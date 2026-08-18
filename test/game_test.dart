import 'package:flutter_test/flutter_test.dart';
import 'package:score_poker/domain/card.dart';
import 'package:score_poker/domain/deck.dart';
import 'package:score_poker/domain/game.dart';

PlayingCard card(int rank, [Suit suit = Suit.clubs]) => PlayingCard(rank, suit);
PlayingCard shield(int rank, [Suit suit = Suit.clubs]) =>
    PlayingCard(rank, suit, isShield: true);
/// 공격 표식이 붙은 카드(처음 받은 손패에 해당).
PlayingCard atk(int rank, [Suit suit = Suit.clubs]) =>
    PlayingCard(rank, suit, isAttacker: true);
PlayingCard joker() => PlayingCard.undesignatedJoker();

/// 필러 카드로 채운 덱(보상 드로우/조기 종료 방지용).
Deck fillerDeck([int n = 20]) =>
    Deck(List.generate(n, (_) => card(2, Suit.clubs)));

void main() {
  group('셋업 / 선공', () {
    test('6장 받고 오픈하면 손패 5장, phase=playing', () {
      final g = GameState.deal(seed: 1);
      expect(g.hands[PlayerId.p0]!.length, 6);
      g.revealForFirstTurn(0, 0);
      expect(g.hands[PlayerId.p0]!.length, 5);
      expect(g.hands[PlayerId.p1]!.length, 5);
      expect(g.phase, GamePhase.playing);
    });

    test('높은 숫자가 선공 (동점이면 슈트 ♠>♥>♦>♣)', () {
      final g = GameState.deal(seed: 7);
      final c0 = g.hands[PlayerId.p0]![0];
      final c1 = g.hands[PlayerId.p1]![0];
      var cmp = c0.rank.compareTo(c1.rank);
      if (cmp == 0) cmp = c0.suit.order.compareTo(c1.suit.order);
      final expected = cmp >= 0 ? PlayerId.p0 : PlayerId.p1;
      g.revealForFirstTurn(0, 0);
      expect(g.current, expected);
    });
  });

  group('카드 배치', () {
    test('일반 카드는 자기 필드에 배치되고 턴이 넘어간다', () {
      final g = GameState.custom(fillerDeck());
      g.hands[PlayerId.p0]!.addAll([card(5), card(6)]);
      g.hands[PlayerId.p1]!.addAll([card(8), card(9)]);
      g.current = PlayerId.p0;

      g.placeCard(0, PlayerId.p0, 0, 0);
      expect(g.fields[PlayerId.p0]![0][0]!.card.rank, 5);
      expect(g.hands[PlayerId.p0]!.length, 1);
      expect(g.current, PlayerId.p1);
    });

    test('일반 카드를 상대 필드에 놓으면 IllegalMove', () {
      final g = GameState.custom(fillerDeck());
      g.hands[PlayerId.p0]!.add(card(5));
      g.current = PlayerId.p0;
      expect(
        () => g.placeCard(0, PlayerId.p1, 0, 0),
        throwsA(isA<IllegalMove>()),
      );
    });

    test('쉴드 카드는 상대 필드에도 놓을 수 있다', () {
      final g = GameState.custom(fillerDeck());
      g.hands[PlayerId.p0]!.add(shield(7));
      g.hands[PlayerId.p1]!.add(card(2));
      g.current = PlayerId.p0;
      g.placeCard(0, PlayerId.p1, 1, 2);
      final placed = g.fields[PlayerId.p1]![1][2]!;
      expect(placed.isShield, isTrue);
      expect(placed.placedBy, PlayerId.p0);
    });

    test('조커는 숫자+슈트를 지정해 자기 필드에 배치', () {
      final g = GameState.custom(fillerDeck());
      g.hands[PlayerId.p0]!.add(joker());
      g.hands[PlayerId.p1]!.add(card(2));
      g.current = PlayerId.p0;
      g.placeCard(0, PlayerId.p0, 0, 0, jokerRank: Ranks.king, jokerSuit: Suit.hearts);
      final placed = g.fields[PlayerId.p0]![0][0]!;
      expect(placed.isJoker, isTrue);
      expect(placed.card.rank, Ranks.king);
      expect(placed.card.suit, Suit.hearts);
    });
  });

  group('빼앗기(공격)', () {
    test('같은 숫자로 빼앗으면 내 칸에 쉴드로 박히고, 보너스 배치가 열린다', () {
      final g = GameState.custom(fillerDeck());
      g.hands[PlayerId.p0]!.addAll([atk(6, Suit.hearts), card(4)]);
      g.hands[PlayerId.p1]!.add(card(3));
      g.fields[PlayerId.p1]![0][0] = PlacedCard(card(6, Suit.spades), PlayerId.p1);
      g.current = PlayerId.p0;

      g.attack(0, 0, 0, 1, 0);
      expect(g.fields[PlayerId.p1]![0][0], isNull); // 상대 칸이 비고
      final stolen = g.fields[PlayerId.p0]![1][0]!; // 내 칸에 들어옴
      expect(stolen.card.rank, 6);
      expect(stolen.card.suit, Suit.spades);
      expect(stolen.isShield, isTrue); // 쉴드로 고정 → 되빼앗기 불가
      expect(g.lastStolen, isNotNull);
      expect(g.pendingBonus, isTrue);
      expect(g.current, PlayerId.p0); // 턴은 아직 내 것
    });

    test('보너스로 한 번 더 놓으면 턴이 넘어간다', () {
      final g = GameState.custom(fillerDeck());
      g.hands[PlayerId.p0]!.addAll([atk(6), card(4)]);
      g.hands[PlayerId.p1]!.add(card(3));
      g.fields[PlayerId.p1]![0][0] = PlacedCard(card(6, Suit.spades), PlayerId.p1);
      g.current = PlayerId.p0;

      g.attack(0, 0, 0, 1, 0);
      g.placeCard(0, PlayerId.p0, 2, 0); // 보너스 배치
      expect(g.pendingBonus, isFalse);
      expect(g.current, PlayerId.p1);
    });

    test('보너스는 포기할 수 있고, 보너스 중에는 다시 공격 못 한다', () {
      final g = GameState.custom(fillerDeck());
      g.hands[PlayerId.p0]!.addAll([atk(6), atk(7)]);
      g.hands[PlayerId.p1]!.add(card(3));
      g.fields[PlayerId.p1]![0][0] = PlacedCard(card(6, Suit.spades), PlayerId.p1);
      g.fields[PlayerId.p1]![0][1] = PlacedCard(card(7, Suit.spades), PlayerId.p1);
      g.current = PlayerId.p0;

      g.attack(0, 0, 0, 1, 0);
      expect(() => g.attack(0, 0, 1, 1, 1), throwsA(isA<IllegalMove>()));
      g.passBonus();
      expect(g.pendingBonus, isFalse);
      expect(g.current, PlayerId.p1);
    });

    test('처음 받은 카드가 아니면 공격 불가 (조커는 예외)', () {
      final g = GameState.custom(fillerDeck());
      g.hands[PlayerId.p0]!.addAll([card(6), joker()]); // 표식 없는 6 + 조커
      g.fields[PlayerId.p1]![0][0] = PlacedCard(card(6, Suit.spades), PlayerId.p1);
      g.current = PlayerId.p0;

      expect(() => g.attack(0, 0, 0, 0, 0), throwsA(isA<IllegalMove>()));
      g.attack(1, 0, 0, 0, 0); // 조커는 표식 없이도 가능
      expect(g.fields[PlayerId.p1]![0][0], isNull);
    });

    test('다른 숫자로는 빼앗을 수 없다', () {
      final g = GameState.custom(fillerDeck());
      g.hands[PlayerId.p0]!.add(atk(5));
      g.fields[PlayerId.p1]![0][0] = PlacedCard(card(6), PlayerId.p1);
      g.current = PlayerId.p0;
      expect(() => g.attack(0, 0, 0, 0, 0), throwsA(isA<IllegalMove>()));
    });

    test('쉴드는 일반 카드로 못 빼앗고 조커로는 가능', () {
      final g = GameState.custom(fillerDeck());
      g.hands[PlayerId.p0]!.addAll([atk(6), joker()]);
      g.fields[PlayerId.p1]![0][0] = PlacedCard(shield(6), PlayerId.p1);
      g.current = PlayerId.p0;

      expect(() => g.attack(0, 0, 0, 0, 0), throwsA(isA<IllegalMove>()));
      g.attack(1, 0, 0, 0, 0);
      expect(g.fields[PlayerId.p1]![0][0], isNull);
      expect(g.fields[PlayerId.p0]![0][0]!.isShield, isTrue);
    });

    test('조커로 놓은 카드는 일반 카드로 빼앗을 수 없다', () {
      final g = GameState.custom(fillerDeck());
      g.hands[PlayerId.p0]!.add(atk(9));
      g.fields[PlayerId.p1]![0][0] =
          PlacedCard(card(9, Suit.spades).copyWith(isJoker: true), PlayerId.p1);
      g.current = PlayerId.p0;
      expect(() => g.attack(0, 0, 0, 0, 0), throwsA(isA<IllegalMove>()));
    });

    test('빼앗은 카드를 놓을 빈 칸이 없으면 공격 불가', () {
      final g = GameState.custom(fillerDeck());
      g.hands[PlayerId.p0]!.add(atk(6));
      for (var r = 0; r < kRows; r++) {
        for (var c = 0; c < kCols; c++) {
          g.fields[PlayerId.p0]![r][c] = PlacedCard(card(2), PlayerId.p0);
        }
      }
      g.fields[PlayerId.p1]![0][0] = PlacedCard(card(6, Suit.spades), PlayerId.p1);
      g.current = PlayerId.p0;
      expect(() => g.attack(0, 0, 0, 0, 0), throwsA(isA<IllegalMove>()));
    });
  });

  group('폴드', () {
    test('한 명 폴드해도 게임은 계속, 상대가 진행', () {
      final g = GameState.custom(fillerDeck());
      g.hands[PlayerId.p0]!.add(card(5));
      g.hands[PlayerId.p1]!.add(card(8));
      g.current = PlayerId.p0;
      g.fold();
      expect(g.folded[PlayerId.p0], isTrue);
      expect(g.isFinished, isFalse);
      expect(g.current, PlayerId.p1);
    });

    test('양쪽 폴드하면 종료', () {
      final g = GameState.custom(fillerDeck());
      g.hands[PlayerId.p0]!.add(card(5));
      g.hands[PlayerId.p1]!.add(card(8));
      g.current = PlayerId.p0;
      g.fold();
      g.fold(); // 이제 current=p1
      expect(g.isFinished, isTrue);
    });
  });

  group('매 턴 보충', () {
    test('턴 시작에 손패가 kHandSize장이 되도록 채워진다', () {
      final g = GameState.custom(fillerDeck());
      g.hands[PlayerId.p0]!.add(card(5));
      g.hands[PlayerId.p1]!.add(card(8));
      g.current = PlayerId.p0;

      g.placeCard(0, PlayerId.p0, 0, 0);
      expect(g.current, PlayerId.p1);
      expect(g.hands[PlayerId.p1]!.length, kHandSize); // 1장 → 5장으로 보충
    });

    test('보충으로 뽑은 카드에는 공격 표식이 없다', () {
      final g = GameState.deal(seed: 3);
      expect(g.hands[PlayerId.p0]!.every((c) => c.isAttacker), isTrue); // 처음 6장
      g.revealForFirstTurn(0, 0);
      final first = g.current;
      g.placeCard(0, first, 0, 0); // 5 → 4
      g.placeCard(0, first.other, 0, 0); // 상대도 두면 내 턴 시작에 1장 보충된다
      expect(g.hands[first]!.length, kHandSize);
      expect(g.hands[first]!.last.isAttacker, isFalse);
    });

    test('덱이 마르면 더 이상 보충되지 않는다', () {
      final g = GameState.custom(Deck(<PlayingCard>[]));
      g.hands[PlayerId.p0]!.addAll([card(5), card(6)]);
      g.hands[PlayerId.p1]!.add(card(8));
      g.current = PlayerId.p0;
      g.placeCard(0, PlayerId.p0, 0, 0);
      expect(g.hands[PlayerId.p1]!.length, 1);
    });
  });

  group('종료 후 결과', () {
    test('보드가 한쪽 우세로 끝나면 그쪽 승리', () {
      final g = GameState.custom(Deck(<PlayingCard>[]));
      // p0: 세 줄 모두 강한 카드, p1: 약한 카드 (각 줄 1장씩만)
      for (var r = 0; r < kRows; r++) {
        g.fields[PlayerId.p0]![r][0] = PlacedCard(card(Ranks.king), PlayerId.p0);
        g.fields[PlayerId.p1]![r][0] = PlacedCard(card(2), PlayerId.p1);
      }
      final res = g.result();
      expect(res.outcome.name, 'win');
    });
  });
}
