import 'package:flutter_test/flutter_test.dart';
import 'package:score_poker/domain/ai.dart';
import 'package:score_poker/domain/card.dart';
import 'package:score_poker/domain/game.dart';
import 'package:score_poker/domain/scoring.dart';

/// 봇으로 판을 끝까지 굴린다. [onMove]가 true를 돌려주면 그 시점에 멈춘다.
bool runWithBot(ScoreGame g, {int seed = 0, bool Function(TurnMove m)? onMove}) {
  final bots = {
    PlayerId.p0: VeiledAi(AiStyle.clode, level: 4, seed: seed),
    PlayerId.p1: VeiledAi(AiStyle.het, level: 4, seed: seed + 1),
  };
  var guard = 0;
  while (!g.isFinished && guard++ < 500) {
    final p = g.turn;
    final m = bots[p]!.chooseTurn(g, p);
    if (onMove != null && onMove(m)) return true;
    switch (m) {
      case MovePlace(:final handIndex, :final row, :final hidden, :final wildAs):
        if (wildAs != null) {
          g.placeWild(p, handIndex, row, wildAs, hidden: hidden);
        } else {
          g.place(p, handIndex, row, hidden: hidden);
        }
      case MoveAttack(:final handIndex, :final row, :final col):
        g.attack(p, handIndex, row, col);
      case MovePeek(:final row, :final col):
        g.peek(p, row, col);
      case MoveShield(:final ownField, :final row):
        g.placeShield(p, ownField, row);
      case MoveBurnShield():
        g.burnShield(p);
      case MoveDiscard(:final handIndex):
        g.discard(p, handIndex);
    }
  }
  return false;
}

void main() {
  group('게임 준비·턴', () {
    test('딜: 손패 4장 + 선턴 드로, 칩 4, 덱 회계', () {
      final g = ScoreGame.deal(seed: 1);
      expect(g.hands[PlayerId.p0]!.length, ScoreGame.startHand + 1,
          reason: '선턴은 드로까지 받는다');
      expect(g.hands[PlayerId.p1]!.length, ScoreGame.startHand);
      expect(g.veilLeft[PlayerId.p0], ScoreGame.veilsPerMatch);
      expect(g.turn, PlayerId.p0);
      expect(g.phase, TurnPhase.action);
      expect(g.deckRemaining,
          52 + ScoreGame.jokers - ScoreGame.startHand * 2 - 1);
    });

    test('배치는 줄 왼쪽부터, 턴이 넘어가고 상대가 드로한다', () {
      final g = ScoreGame.deal(seed: 1);
      final hand = g.hands[PlayerId.p0]!;
      final i = hand.indexWhere((c) => !c.isJoker);
      final card = hand[i];
      g.place(PlayerId.p0, i, 1);
      expect(g.fields[PlayerId.p0]![1][0]!.card, card);
      expect(g.fields[PlayerId.p0]![1][0]!.faceUp, isTrue, reason: '기본은 앞면');
      expect(g.turn, PlayerId.p1);
      expect(g.hands[PlayerId.p1]!.length, ScoreGame.startHand + 1);
      expect(g.nextCol(PlayerId.p0, 1), 1, reason: '다음은 2번 칸');
    });

    test('내 턴이 아니면 못 둔다', () {
      final g = ScoreGame.deal(seed: 1);
      expect(() => g.place(PlayerId.p1, 0, 0), throwsStateError);
    });

    test('뒷면 배치 = 칩 1, 상대에게 안 보인다', () {
      final g = ScoreGame.deal(seed: 1);
      final i = g.hands[PlayerId.p0]!.indexWhere((c) => !c.isJoker);
      g.place(PlayerId.p0, i, 0, hidden: true);
      expect(g.veilLeft[PlayerId.p0], ScoreGame.veilsPerMatch - 1);
      final s = g.fields[PlayerId.p0]![0][0]!;
      expect(s.faceUp, isFalse);
      expect(g.visibleTo(PlayerId.p1, PlayerId.p0, s), isFalse);
      expect(g.visibleTo(PlayerId.p0, PlayerId.p0, s), isTrue);
    });

    test('조커는 와일드로만 — place는 거부, placeWild는 지정 카드로', () {
      // 조커가 손에 올 때까지 시드를 뒤진다.
      for (var seed = 0; seed < 60; seed++) {
        final g = ScoreGame.deal(seed: seed);
        final ji = g.hands[PlayerId.p0]!.indexWhere((c) => c.isJoker);
        if (ji < 0) continue;
        expect(() => g.place(PlayerId.p0, ji, 0), throwsStateError);
        const as = PlayingCard(14, Suit.spades);
        g.placeWild(PlayerId.p0, ji, 0, as);
        final s = g.fields[PlayerId.p0]![0][0]!;
        expect(s.card, as);
        expect(s.wild, isTrue);
        return;
      }
      fail('60개 시드 안에 조커가 안 나옴');
    });
  });

  group('훔쳐보기·공격·방어막', () {
    test('훔쳐보기: 칩 1, 나만 확인(peeked), 턴 유지', () {
      final g = ScoreGame.deal(seed: 1);
      int nonJoker(PlayerId p) =>
          g.hands[p]!.indexWhere((c) => !c.isJoker);
      g.place(PlayerId.p0, nonJoker(PlayerId.p0), 0, hidden: true);
      g.place(PlayerId.p1, nonJoker(PlayerId.p1), 0);
      g.place(PlayerId.p0, nonJoker(PlayerId.p0), 1);
      expect(g.turn, PlayerId.p1);
      final before = g.veilLeft[PlayerId.p1]!;
      g.peek(PlayerId.p1, 0, 0);
      expect(g.veilLeft[PlayerId.p1], before - 1);
      final s = g.fields[PlayerId.p0]![0][0]!;
      expect(s.peeked, isTrue);
      expect(s.faceUp, isFalse, reason: '모두에게 공개되는 건 아니다');
      expect(g.visibleTo(PlayerId.p1, PlayerId.p0, s), isTrue);
      expect(g.turn, PlayerId.p1, reason: '훔쳐보기는 턴을 안 쓴다');
    });

    test('공격: 랭크 일치 → 두 장 소멸(왼쪽 당김) + 방어막 단계', () {
      var attacked = false;
      for (var seed = 0; seed < 40 && !attacked; seed++) {
        final g = ScoreGame.deal(seed: seed);
        attacked = runWithBot(g, seed: seed, onMove: (m) {
          if (m is! MoveAttack) return false;
          final p = g.turn;
          final opp = p.other;
          final row = m.row;
          final filledBefore = [
            for (var c = 0; c < ScoreGame.colsN; c++)
              if (g.fields[opp]![row][c] != null) c
          ].length;
          final handBefore = g.hands[p]!.length;
          g.attack(p, m.handIndex, m.row, m.col);
          final filledAfter = [
            for (var c = 0; c < ScoreGame.colsN; c++)
              if (g.fields[opp]![row][c] != null) c
          ].length;
          expect(filledAfter, filledBefore - 1, reason: '표적 제거');
          // 중력: 빈 칸이 줄 끝에만 있다(가운데 구멍 없음).
          var seenNull = false;
          for (var c = 0; c < ScoreGame.colsN; c++) {
            final isNull = g.fields[opp]![row][c] == null;
            if (seenNull) expect(isNull, isTrue, reason: '왼쪽 당김');
            seenNull = seenNull || isNull;
          }
          expect(g.hands[p]!.length, handBefore - 1);
          expect(g.phase, TurnPhase.shield);
          expect(g.pendingShield, isNotNull);
          return true;
        });
      }
      expect(attacked, isTrue, reason: '40개 시드 안에 공격이 나와야 한다');
    });

    test('방어막은 상대 필드에도 놓을 수 있고, 공격 표적이 아니다', () {
      var harassed = false;
      for (var seed = 0; seed < 80 && !harassed; seed++) {
        final g = ScoreGame.deal(seed: seed);
        harassed = runWithBot(g, seed: seed, onMove: (m) {
          if (m is! MoveShield || m.ownField) return false;
          final by = g.turn;
          final owner = by.other;
          final col = g.nextCol(owner, m.row);
          if (col < 0) return false;
          final shieldCard = g.pendingShield!;
          g.placeShield(by, false, m.row);
          final s = g.fields[owner]![m.row][col]!;
          expect(s.card, shieldCard);
          expect(s.shield, isTrue);
          expect(s.faceUp, isTrue, reason: '방어막은 공정하게 앞면');
          // 공격 표적 목록에 안 뜬다.
          for (final (r, c) in g.attackTargets(owner.other, s.card.rank)) {
            expect(g.fields[owner]![r][c]!.shield, isFalse);
          }
          return true;
        });
      }
      expect(harassed, isTrue, reason: '80개 시드 안에 괴롭히기가 나와야 한다');
    });

    test('뒷면 카드는 공격할 수 없지만 훔쳐본 뒤에는 가능하다', () {
      final g = ScoreGame.deal(seed: 3);
      int nonJoker(PlayerId p) => g.hands[p]!.indexWhere((c) => !c.isJoker);
      // 내가 뒷면으로 놓는다.
      final i = nonJoker(PlayerId.p0);
      final hiddenCard = g.hands[PlayerId.p0]![i];
      g.place(PlayerId.p0, i, 0, hidden: true);
      final s = g.fields[PlayerId.p0]![0][0]!;
      // 상대 눈에는 표적이 아니다.
      expect(g.attackTargets(PlayerId.p1, hiddenCard.rank), isEmpty);
      // 상대가 훔쳐보면 표적이 된다.
      g.peek(PlayerId.p1, 0, 0);
      expect(s.peeked, isTrue);
      expect(g.attackTargets(PlayerId.p1, hiddenCard.rank),
          contains((0, 0)));
    });
  });

  group('종료·정산', () {
    test('판은 반드시 끝나고, 최후 공개 후 본편 판정이 나온다', () {
      for (final seed in [2, 7, 21]) {
        final g = ScoreGame.deal(seed: seed);
        runWithBot(g, seed: seed);
        expect(g.isFinished, isTrue);
        g.revealAll();
        for (final p in PlayerId.values) {
          expect(g.hiddenOf(p), isEmpty);
        }
        final res = g.judge();
        expect(res.lineOutcomes.length, 3);
        expect(res.outcome, isA<MatchOutcome>());
      }
    });

    test('버리기는 내 필드가 만석일 때만', () {
      final g = ScoreGame.deal(seed: 1);
      expect(() => g.discard(PlayerId.p0, 0), throwsStateError,
          reason: '놓을 곳이 있으면 못 버린다');
    });
  });

  group('부스트', () {
    test('부스트 판: 칩 5, 스왑 1회 — 손 전체 교체', () {
      final g = ScoreGame.deal(seed: 1, boostFor: PlayerId.p0);
      expect(g.veilLeft[PlayerId.p0], ScoreGame.veilsPerMatch + 1);
      expect(g.veilsMax(PlayerId.p0), ScoreGame.veilsPerMatch + 1);
      expect(g.canSwap(PlayerId.p0), isTrue);
      final before = List.of(g.hands[PlayerId.p0]!);
      final fresh = g.swap(PlayerId.p0);
      expect(fresh.length, before.length);
      expect(g.swapLeft[PlayerId.p0], 0);
      expect(g.canSwap(PlayerId.p0), isFalse);
    });

    test('한 수라도 뒀으면 스왑 불가', () {
      final g = ScoreGame.deal(seed: 1, boostFor: PlayerId.p0);
      final i = g.hands[PlayerId.p0]!.indexWhere((c) => !c.isJoker);
      g.place(PlayerId.p0, i, 0);
      // 상대 턴을 소비해 내 턴으로 돌아와도 이미 acted.
      final j = g.hands[PlayerId.p1]!.indexWhere((c) => !c.isJoker);
      g.place(PlayerId.p1, j, 0);
      expect(g.turn, PlayerId.p0);
      expect(g.canSwap(PlayerId.p0), isFalse);
    });
  });
}
