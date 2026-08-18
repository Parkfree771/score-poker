import 'package:flutter_test/flutter_test.dart';
import 'package:score_poker/domain/card.dart';
import 'package:score_poker/domain/deck.dart';
import 'package:score_poker/domain/game.dart';

PlayingCard card(int rank, [Suit suit = Suit.clubs]) => PlayingCard(rank, suit);
PlayingCard shield(int rank, [Suit suit = Suit.clubs]) =>
    PlayingCard(rank, suit, isShield: true);
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

  group('제거 + 보상 드로우', () {
    test('제거 → 보상 쉴드가 손패로 들어오고 턴 종료', () {
      final g = GameState.custom(fillerDeck());
      g.hands[PlayerId.p0]!.add(card(6, Suit.hearts));
      g.hands[PlayerId.p1]!.add(card(3));
      g.fields[PlayerId.p1]![0][0] = PlacedCard(card(6, Suit.spades), PlayerId.p1);
      g.current = PlayerId.p0;

      final before = g.hands[PlayerId.p0]!.length;
      g.removeOpponentCard(0, 0, 0);
      expect(g.fields[PlayerId.p1]![0][0], isNull); // 제거됨
      expect(g.hands[PlayerId.p0]!.length, before); // 무기 나가고 보상 들어옴(순증 0)
      expect(g.hands[PlayerId.p0]!.last.isShield, isTrue); // 보상은 쉴드
      expect(g.lastReward, isNotNull);
      expect(g.current, PlayerId.p1); // 턴 종료
    });

    test('다른 숫자로는 제거 불가', () {
      final g = GameState.custom(fillerDeck());
      g.hands[PlayerId.p0]!.add(card(5));
      g.fields[PlayerId.p1]![0][0] = PlacedCard(card(6), PlayerId.p1);
      g.current = PlayerId.p0;
      expect(() => g.removeOpponentCard(0, 0, 0), throwsA(isA<IllegalMove>()));
    });

    test('쉴드 카드는 일반 카드로 제거 불가, 조커로는 가능', () {
      final g = GameState.custom(fillerDeck());
      g.hands[PlayerId.p0]!.addAll([card(6), joker()]);
      g.fields[PlayerId.p1]![0][0] = PlacedCard(shield(6), PlayerId.p1);
      g.current = PlayerId.p0;

      expect(() => g.removeOpponentCard(0, 0, 0), throwsA(isA<IllegalMove>()));
      g.removeOpponentCard(1, 0, 0); // 조커는 쉴드도 제거
      expect(g.fields[PlayerId.p1]![0][0], isNull);
      expect(g.hands[PlayerId.p0]!.last.isShield, isTrue); // 보상 쉴드가 손패로
      expect(g.current, PlayerId.p1); // 턴 종료
    });

    test('조커로 놓은 카드는 일반 카드로 제거 불가', () {
      final g = GameState.custom(fillerDeck());
      g.hands[PlayerId.p0]!.add(card(9));
      g.fields[PlayerId.p1]![0][0] =
          PlacedCard(card(9, Suit.spades).copyWith(isJoker: true), PlayerId.p1);
      g.current = PlayerId.p0;
      expect(() => g.removeOpponentCard(0, 0, 0), throwsA(isA<IllegalMove>()));
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

  group('드로우 단계', () {
    test('양측 시작 카드 소진 후 턴 시작에 1장 드로우', () {
      final g = GameState.custom(fillerDeck());
      g.hands[PlayerId.p0]!.add(card(5)); // 마지막 시작 카드
      g.hands[PlayerId.p1]!.add(card(8));
      g.startingLeft[PlayerId.p0] = 1;
      g.startingLeft[PlayerId.p1] = 0; // p1은 이미 소진
      g.current = PlayerId.p0;

      g.placeCard(0, PlayerId.p0, 0, 0); // p0 마지막 시작 카드 소진 → drawPhase on
      expect(g.drawPhase, isTrue);
      // 턴이 p1로 넘어가며 1장 드로우 → 손패 2장
      expect(g.current, PlayerId.p1);
      expect(g.hands[PlayerId.p1]!.length, 2);
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
