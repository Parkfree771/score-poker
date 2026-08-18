import 'package:flutter_test/flutter_test.dart';
import 'package:score_poker/domain/card.dart';
import 'package:score_poker/domain/deck.dart';
import 'package:score_poker/domain/game.dart';

/// 유료 토큰의 **규칙**을 고정한다.
///
/// 여기가 깨지면 돈으로 산 이득의 크기가 달라진다 — 이 게임이 pay-to-win이 아니라고
/// 말할 수 있는 근거가 전부 "판당 1회"라는 상한 하나이므로, 그 상한은 UI가 아니라
/// 도메인이 지켜야 하고 그걸 검증하는 게 이 파일이다.

GameState _state({
  GameRules p0 = GameRules.standard,
  GameRules p1 = GameRules.none,
}) =>
    GameState.custom(
      Deck.shuffled(seed: 1),
      rules: {PlayerId.p0: p0, PlayerId.p1: p1},
    );

void _put(GameState s, PlayerId p, int row, int col, PlayingCard card) {
  s.fields[p]![row][col] = PlacedCard(card, p);
}

MoveError _errorOf(void Function() action) {
  try {
    action();
  } on IllegalMove catch (e) {
    return e.error;
  }
  fail('IllegalMove가 던져지지 않았습니다');
}

void main() {
  group('판당 상한 (pay-to-win 방지의 핵심)', () {
    test('기본값은 0 — 아무것도 안 주면 토큰을 쓸 수 없다', () {
      final s = GameState.custom(Deck.shuffled(seed: 1));
      _put(s, PlayerId.p0, 0, 0, const PlayingCard(7, Suit.hearts));
      s.hands[PlayerId.p0]!.add(const PlayingCard(3, Suit.clubs));

      expect(_errorOf(() => s.declareShield(0, 0)), MoveError.tokenExhausted);
      expect(_errorOf(() => s.markAttacker(0)), MoveError.tokenExhausted);
    });

    test('쉴드 선언은 판당 1회 — 두 번째는 거부된다', () {
      final s = _state();
      _put(s, PlayerId.p0, 0, 0, const PlayingCard(7, Suit.hearts));
      _put(s, PlayerId.p0, 0, 1, const PlayingCard(8, Suit.spades));

      expect(s.shieldDeclarationsLeft(PlayerId.p0), 1);
      s.declareShield(0, 0);
      expect(s.shieldDeclarationsLeft(PlayerId.p0), 0);

      expect(_errorOf(() => s.declareShield(0, 1)), MoveError.tokenExhausted,
          reason: '많이 사도 한 판의 이득이 같다는 것이 이 게임의 유일한 방어선이다');
    });

    test('표식 부여도 판당 1회', () {
      final s = _state();
      s.hands[PlayerId.p0]!
        ..add(const PlayingCard(3, Suit.clubs))
        ..add(const PlayingCard(4, Suit.clubs));

      s.markAttacker(0);
      expect(s.attackMarksLeft(PlayerId.p0), 0);
      expect(_errorOf(() => s.markAttacker(1)), MoveError.tokenExhausted);
    });

    test('두 종류의 상한은 서로 독립이다', () {
      final s = _state();
      _put(s, PlayerId.p0, 0, 0, const PlayingCard(7, Suit.hearts));
      s.hands[PlayerId.p0]!.add(const PlayingCard(3, Suit.clubs));

      s.declareShield(0, 0);
      expect(s.attackMarksLeft(PlayerId.p0), 1, reason: '쉴드를 썼다고 공격 표식이 줄면 안 된다');
      s.markAttacker(0);
      expect(s.attackMarksLeft(PlayerId.p0), 0);
    });

    test('상한은 플레이어별로 따로 관리된다 (싱글에서 AI는 못 쓴다)', () {
      final s = _state();
      expect(s.shieldDeclarationsLeft(PlayerId.p0), 1);
      expect(s.shieldDeclarationsLeft(PlayerId.p1), 0);

      s.current = PlayerId.p1;
      _put(s, PlayerId.p1, 0, 0, const PlayingCard(7, Suit.hearts));
      expect(_errorOf(() => s.declareShield(0, 0)), MoveError.tokenExhausted);
    });
  });

  group('쉴드 선언', () {
    test('선언한 카드는 일반 공격 카드로 빼앗을 수 없다', () {
      final s = _state();
      _put(s, PlayerId.p0, 0, 0, const PlayingCard(7, Suit.hearts));
      s.declareShield(0, 0);
      expect(s.fields[PlayerId.p0]![0][0]!.card.isShield, isTrue);

      // 상대가 같은 숫자(7) 공격 카드로 친다 → 쉴드라서 막힌다
      s.current = PlayerId.p1;
      s.hands[PlayerId.p1]!.add(const PlayingCard(7, Suit.spades, isAttacker: true));
      expect(_errorOf(() => s.attack(0, 0, 0, 0, 0)),
          MoveError.needJokerToTakeShield);
    });

    test('조커로는 여전히 깨진다 — 이게 이 아이템의 카운터다', () {
      final s = _state();
      _put(s, PlayerId.p0, 0, 0, const PlayingCard(7, Suit.hearts));
      s.declareShield(0, 0);

      s.current = PlayerId.p1;
      s.hands[PlayerId.p1]!.add(PlayingCard.undesignatedJoker());
      s.attack(0, 0, 0, 0, 0);

      expect(s.fields[PlayerId.p0]![0][0], isNull, reason: '조커에게는 쉴드가 통하지 않는다');
      expect(s.fields[PlayerId.p1]![0][0]!.card.rank, 7);
    });

    test('점수는 그대로 — 쉴드는 "안 빼앗긴다"는 성질만 추가한다', () {
      final s = _state();
      _put(s, PlayerId.p0, 0, 0, const PlayingCard(7, Suit.hearts));
      s.declareShield(0, 0);
      final card = s.fields[PlayerId.p0]![0][0]!.card;
      expect(card.rank, 7);
      expect(card.suit, Suit.hearts);
    });

    test('이미 쉴드이거나 조커로 놓은 카드는 대상이 아니다 (토큰 낭비 방지)', () {
      final s = _state();
      _put(s, PlayerId.p0, 0, 0, const PlayingCard(7, Suit.hearts, isShield: true));
      _put(s, PlayerId.p0, 0, 1, const PlayingCard(9, Suit.clubs, isJoker: true));

      expect(_errorOf(() => s.declareShield(0, 0)), MoveError.shieldTargetNotEligible);
      expect(_errorOf(() => s.declareShield(0, 1)), MoveError.shieldTargetNotEligible);
      expect(s.shieldDeclarationsLeft(PlayerId.p0), 1, reason: '거부된 시도는 횟수를 먹지 않는다');
    });

    test('빈 칸과 보드 밖은 거부된다', () {
      final s = _state();
      expect(_errorOf(() => s.declareShield(0, 0)), MoveError.tokenNoCardHere);
      expect(_errorOf(() => s.declareShield(9, 9)), MoveError.badCell);
    });

    test('상대 필드는 건드릴 수 없다 — 좌표는 언제나 내 필드다', () {
      final s = _state();
      _put(s, PlayerId.p1, 0, 0, const PlayingCard(7, Suit.hearts));
      expect(_errorOf(() => s.declareShield(0, 0)), MoveError.tokenNoCardHere,
          reason: '내 필드 (0,0)은 비어 있다');
      expect(s.fields[PlayerId.p1]![0][0]!.card.isShield, isFalse);
    });
  });

  group('표식 부여', () {
    test('덱에서 뽑은 카드로 공격할 수 있게 된다', () {
      final s = _state();
      s.hands[PlayerId.p0]!.add(const PlayingCard(7, Suit.clubs)); // 표식 없음
      _put(s, PlayerId.p1, 0, 0, const PlayingCard(7, Suit.hearts));

      expect(_errorOf(() => s.attack(0, 0, 0, 0, 0)), MoveError.attackerCardRequired);

      s.markAttacker(0);
      s.attack(0, 0, 0, 0, 0);
      expect(s.fields[PlayerId.p1]![0][0], isNull);
      expect(s.fields[PlayerId.p0]![0][0]!.card.isShield, isTrue, reason: '빼앗은 카드는 쉴드가 된다');
    });

    test('표식을 붙여도 나머지 조건은 그대로다 (같은 숫자여야 한다)', () {
      final s = _state();
      s.hands[PlayerId.p0]!.add(const PlayingCard(3, Suit.clubs));
      _put(s, PlayerId.p1, 0, 0, const PlayingCard(7, Suit.hearts));

      s.markAttacker(0);
      expect(_errorOf(() => s.attack(0, 0, 0, 0, 0)), MoveError.rankMismatch,
          reason: '표식은 "공격 자격"만 주지 "무조건 성공"을 주지 않는다');
    });

    test('이미 공격 가능한 카드와 쉴드 카드는 대상이 아니다', () {
      final s = _state();
      s.hands[PlayerId.p0]!
        ..add(const PlayingCard(3, Suit.clubs, isAttacker: true))
        ..add(PlayingCard.undesignatedJoker())
        ..add(const PlayingCard(5, Suit.clubs, isShield: true));

      expect(_errorOf(() => s.markAttacker(0)), MoveError.attackMarkNotEligible);
      expect(_errorOf(() => s.markAttacker(1)), MoveError.attackMarkNotEligible);
      expect(_errorOf(() => s.markAttacker(2)), MoveError.attackMarkNotEligible,
          reason: '쉴드는 표식을 붙여도 공격에 못 쓴다 — 토큰만 버리게 된다');
      expect(s.attackMarksLeft(PlayerId.p0), 1);
    });

    test('손패에 없는 인덱스는 거부된다', () {
      final s = _state();
      expect(_errorOf(() => s.markAttacker(0)), MoveError.badHandIndex);
    });
  });

  group('턴과의 관계', () {
    test('토큰 행동은 턴을 소모하지 않는다 — 쓰고 나서 그 턴의 수를 그대로 둔다', () {
      final s = _state();
      _put(s, PlayerId.p0, 0, 0, const PlayingCard(7, Suit.hearts));
      s.hands[PlayerId.p0]!.add(const PlayingCard(3, Suit.clubs));

      s.declareShield(0, 0);
      expect(s.current, PlayerId.p0, reason: '토큰의 비용은 토큰이지 한 턴이 아니다');

      s.markAttacker(0);
      expect(s.current, PlayerId.p0);

      s.placeCard(0, PlayerId.p0, 1, 0);
      expect(s.current, PlayerId.p1, reason: '진짜 행동을 해야 턴이 넘어간다');
    });

    test('게임이 끝난 뒤에는 쓸 수 없다', () {
      final s = _state();
      _put(s, PlayerId.p0, 0, 0, const PlayingCard(7, Suit.hearts));
      s.phase = GamePhase.finished;
      expect(_errorOf(() => s.declareShield(0, 0)), MoveError.notPlaying);
    });

    test('폴드한 뒤에는 쓸 수 없다', () {
      final s = _state();
      _put(s, PlayerId.p0, 0, 0, const PlayingCard(7, Suit.hearts));
      s.folded[PlayerId.p0] = true;
      expect(_errorOf(() => s.declareShield(0, 0)), MoveError.playerFolded);
    });
  });
}
