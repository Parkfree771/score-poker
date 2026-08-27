import 'package:flutter_test/flutter_test.dart';
import 'package:score_poker/domain/ai.dart';
import 'package:score_poker/domain/card.dart';
import 'package:score_poker/domain/game.dart';
import 'package:score_poker/domain/hand.dart';
import 'package:score_poker/domain/scoring.dart';

/// 테스트용 AI 한 벌(플레이어마다 다른 기풍 — 편향된 한 성격만 도는 것을 막는다).
final _ais = {
  PlayerId.p0: VeiledAi(AiStyle.clode, seed: 1),
  PlayerId.p1: VeiledAi(AiStyle.het, seed: 2),
};
VeiledAi ai(PlayerId p) => _ais[p]!;

void main() {
  group('딜과 배치', () {
    test('52장 덱, 시작 6장 + 라운드마다 3장 보충', () {
      final g = ScoreGame.deal(seed: 1, jokers: 0);
      expect(g.hands[PlayerId.p0]!.length, 6);
      expect(g.hands[PlayerId.p1]!.length, 6);
      expect(g.deckRemaining, 52 - 12);
    });

    test('라운드당 3장까지만 놓을 수 있다', () {
      final g = ScoreGame.deal(seed: 1, jokers: 0);
      for (var i = 0; i < 3; i++) {
        g.place(PlayerId.p0, 0, 0, i);
      }
      expect(g.hands[PlayerId.p0]!.length, 3);
      expect(() => g.place(PlayerId.p0, 0, 1, 0), throwsStateError);
    });

    test('배치는 뒷면, 빈 칸에만', () {
      final g = ScoreGame.deal(seed: 1, jokers: 0);
      g.place(PlayerId.p0, 0, 0, 0);
      expect(g.fields[PlayerId.p0]![0][0]!.faceUp, isFalse);
      expect(() => g.place(PlayerId.p0, 0, 0, 0), throwsStateError);
    });
  });

  group('공개·비공개권', () {
    ScoreGame placedAll({int seed = 2}) {
      final g = ScoreGame.deal(seed: seed, jokers: 0);
      for (final p in PlayerId.values) {
        for (var i = 2; i >= 0; i--) {
          g.place(p, i, i % 3, g.round); // 라운드마다 다른 열
        }
      }
      return g;
    }

    test('공개하면 이번 라운드 카드가 뒤집힌다', () {
      final g = placedAll();
      g.reveal(const {});
      for (final (r, c) in [(0, 0), (1, 0), (2, 0)]) {
        expect(g.fields[PlayerId.p0]![r][c]!.faceUp, isTrue);
      }
      expect(g.revealDone, isTrue);
    });

    test('숨긴 카드는 안 뒤집히고 비공개권이 깎인다', () {
      final g = placedAll();
      g.reveal({
        PlayerId.p0: {(0, 0)},
      });
      expect(g.fields[PlayerId.p0]![0][0]!.faceUp, isFalse);
      expect(g.fields[PlayerId.p0]![1][0]!.faceUp, isTrue);
      expect(g.veilLeft[PlayerId.p0], 2);
      expect(g.veilLeft[PlayerId.p1], 3);
    });

    test('비공개권보다 많이 숨길 수 없다', () {
      final g = placedAll();
      g.veilLeft[PlayerId.p0] = 0;
      expect(() => g.reveal({PlayerId.p0: {(0, 0)}}), throwsStateError);
    });

    test('peek은 상대 숨김 카드를 공개하고 비공개권을 쓴다', () {
      final g = placedAll();
      g.reveal({
        PlayerId.p1: {(0, 0)},
      });
      g.peek(PlayerId.p0, 0, 0);
      expect(g.fields[PlayerId.p1]![0][0]!.faceUp, isTrue);
      expect(g.veilLeft[PlayerId.p0], 2);
      // 이미 공개된 카드는 peek 불가
      expect(() => g.peek(PlayerId.p0, 0, 0), throwsStateError);
    });

    test('공개된 카드만으로 계산하는 publicLine은 숨긴 정보를 새지 않는다', () {
      final g = placedAll();
      g.reveal({
        PlayerId.p1: {(0, 0)},
      });
      expect(g.publicRow(PlayerId.p1, 0), isEmpty);
      g.publicLine(PlayerId.p0, 0); // 계산만 되면 된다(크래시 없음)
    });
  });

  group('전체 흐름', () {
    test('5라운드 채우면 15칸, 최후 공개 후 기존 규칙으로 정산', () {
      final g = ScoreGame.deal(seed: 7, jokers: 0);
      while (true) {
        for (final p in PlayerId.values) {
          final plan = ai(p).plan(g, p)
            ..sort((a, b) => b.handIndex.compareTo(a.handIndex));
          for (final m in plan) {
            g.place(p, m.handIndex, m.row, m.col);
          }
        }
        g.reveal({
          for (final p in PlayerId.values) p: ai(p).hides(g, p),
        });
        if (g.isFinished) break;
        g.nextRound();
      }
      for (final p in PlayerId.values) {
        var n = 0;
        for (final row in g.fields[p]!) {
          n += row.where((s) => s != null).length;
        }
        expect(n, 15);
      }
      g.revealAll();
      for (final p in PlayerId.values) {
        expect(g.hiddenOf(p), isEmpty);
      }
      final res = g.judge();
      expect(res.outcome, isIn(MatchOutcome.values));
      expect(res.lineOutcomes.length, 3);
    });

    test('AI 50판 무교착·정상 종료', () {
      for (var seed = 0; seed < 50; seed++) {
        final g = ScoreGame.deal(seed: seed, jokers: 0);
        var guard = 0;
        while (!g.isFinished && ++guard < 20) {
          for (final p in PlayerId.values) {
            final plan = ai(p).plan(g, p)
              ..sort((a, b) => b.handIndex.compareTo(a.handIndex));
            for (final m in plan) {
              g.place(p, m.handIndex, m.row, m.col);
            }
          }
          g.reveal({
            for (final p in PlayerId.values) p: ai(p).hides(g, p),
          });
          final peek = ai(PlayerId.p1).peek(g, PlayerId.p1);
          if (peek != null && g.hiddenOf(PlayerId.p0).isNotEmpty) {
            g.peek(PlayerId.p1, peek.$1, peek.$2);
          }
          if (!g.isFinished) g.nextRound();
        }
        expect(g.isFinished, isTrue, reason: 'seed $seed 미종료');
        g.revealAll();
        g.judge();
      }
    });
  });

  group('부스트(칩 +1 · 스왑 1회)', () {
    test('부스트 판은 그쪽만 칩 4개, 상대는 3개', () {
      final g = ScoreGame.deal(seed: 1, jokers: 0, boostFor: PlayerId.p0);
      expect(g.veilLeft[PlayerId.p0], 4);
      expect(g.veilsMax(PlayerId.p0), 4);
      expect(g.veilLeft[PlayerId.p1], 3);
      expect(g.veilsMax(PlayerId.p1), 3);
      expect(g.isBoosted(PlayerId.p0), isTrue);
      expect(g.canSwap(PlayerId.p1), isFalse, reason: '부스트 없는 쪽은 스왑 없음');
    });

    test('스왑은 받은 카드 전부를 새로 받고, 판에 한 번뿐', () {
      final g = ScoreGame.deal(seed: 2, jokers: 0, boostFor: PlayerId.p0);
      final before = List.of(g.hands[PlayerId.p0]!);
      expect(g.canSwap(PlayerId.p0), isTrue);
      final fresh = g.swap(PlayerId.p0);
      expect(fresh.length, ScoreGame.startHand, reason: '첫 라운드는 받은 6장 전부');
      expect(g.hands[PlayerId.p0]!.length, ScoreGame.startHand);
      expect(g.hands[PlayerId.p0]!.any(before.contains), isFalse, reason: '옛 카드가 남으면 안 된다');
      expect(g.canSwap(PlayerId.p0), isFalse, reason: '한 판에 1회');
      expect(() => g.swap(PlayerId.p0), throwsStateError);
    });

    test('받은 카드를 한 장이라도 놓으면 스왑 불가', () {
      final g = ScoreGame.deal(seed: 3, jokers: 0, boostFor: PlayerId.p0);
      g.place(PlayerId.p0, 0, 0, 0);
      expect(g.canSwap(PlayerId.p0), isFalse);
    });

    test('다음 라운드엔 보충 3장이 스왑 대상', () {
      final g = ScoreGame.deal(seed: 4, jokers: 0, boostFor: PlayerId.p0);
      for (final p in PlayerId.values) {
        for (var i = 0; i < 3; i++) {
          g.place(p, 0, i, 0);
        }
      }
      g.reveal(const {});
      g.nextRound();
      expect(g.drawnThisRound(PlayerId.p0).length, ScoreGame.refill);
      final kept = g.hands[PlayerId.p0]!.sublist(0, 3);
      g.swap(PlayerId.p0);
      expect(g.hands[PlayerId.p0]!.sublist(0, 3), kept, reason: '지난 라운드 카드는 그대로');
    });
  });
  group('조커', () {
    /// [p] 손패 맨 앞에 조커를 끼워 넣는다(덱 순서와 무관하게 재현).
    int giveJoker(ScoreGame g, PlayerId p) {
      g.hands[p]!.insert(0, const PlayingCard.joker());
      return 0;
    }

    test('덱은 52장 + 조커 2장', () {
      final g = ScoreGame.deal(seed: 1);
      expect(g.deckRemaining, 54 - 12);
    });

    test('와일드: 조커를 원하는 카드로 내 빈 칸에 놓는다(3장 배치의 하나)', () {
      final g = ScoreGame.deal(seed: 1);
      final i = giveJoker(g, PlayerId.p0);
      expect(() => g.place(PlayerId.p0, i, 0, 0), throwsStateError);
      g.placeWild(PlayerId.p0, i, 0, 0, const PlayingCard(14, Suit.spades));
      final slot = g.fields[PlayerId.p0]![0][0]!;
      expect(slot.card, const PlayingCard(14, Suit.spades));
      expect(slot.wild, isTrue);
      expect(slot.faceUp, isFalse);
      expect(g.leftToPlace(PlayerId.p0), 2);
    });

    test('강타: 별도 행동, 빈 칸 불가, 공개 뒤 발동해 앞면으로 바뀐다', () {
      final g = ScoreGame.deal(seed: 2, jokers: 0);
      // 1라운드: p1이 (0,0)에 놓고 숨긴다.
      g.place(PlayerId.p1, 0, 0, 0);
      g.place(PlayerId.p1, 0, 1, 0);
      g.place(PlayerId.p1, 0, 2, 0);
      g.place(PlayerId.p0, 0, 0, 0);
      g.place(PlayerId.p0, 0, 1, 0);
      g.place(PlayerId.p0, 0, 2, 0);
      g.reveal({PlayerId.p1: {(0, 0)}});
      g.nextRound();
      expect(g.fields[PlayerId.p1]![0][0]!.faceUp, isFalse);

      final i = giveJoker(g, PlayerId.p0);
      final handBefore = g.hands[PlayerId.p0]!.length;
      expect(() => g.declareStrike(PlayerId.p0, i, 0, 4, const PlayingCard(2, Suit.clubs)),
          throwsStateError, reason: '빈 칸');
      g.declareStrike(PlayerId.p0, i, 0, 0, const PlayingCard(2, Suit.clubs));
      expect(g.hands[PlayerId.p0]!.length, handBefore - 1);
      expect(g.leftToPlace(PlayerId.p0), 3, reason: '강타는 배치 수를 안 먹는다');
      expect(g.pendingStrikes[PlayerId.p0]!.length, 1);
      // 발동 전엔 원래 카드 그대로(숨긴 채).
      expect(g.fields[PlayerId.p1]![0][0]!.faceUp, isFalse);

      for (var k = 0; k < 3; k++) {
        g.place(PlayerId.p0, 0, k, 1);
        g.place(PlayerId.p1, 0, k, 1);
      }
      g.reveal(const {}, deferStrikes: true);
      expect(g.fields[PlayerId.p1]![0][0]!.faceUp, isFalse, reason: '미룬 강타는 아직');
      final done = g.resolveStrikes();
      expect(done.length, 1);
      final struck = g.fields[PlayerId.p1]![0][0]!;
      expect(struck.card, const PlayingCard(2, Suit.clubs));
      expect(struck.faceUp, isTrue);
      expect(struck.strikeBy, PlayerId.p0);
      expect(struck.jokered, isTrue);
      expect(g.pendingStrikes[PlayerId.p0], isEmpty);
    });

    test('강타 취소: 조커가 손으로 돌아온다', () {
      final g = ScoreGame.deal(seed: 3, jokers: 0);
      g.place(PlayerId.p1, 0, 0, 0);
      final i = giveJoker(g, PlayerId.p0);
      g.declareStrike(PlayerId.p0, i, 0, 0, const PlayingCard(3, Suit.hearts));
      expect(g.hands[PlayerId.p0]!.any((c) => c.isJoker), isFalse);
      g.cancelStrike(PlayerId.p0, 0, 0);
      expect(g.hands[PlayerId.p0]!.any((c) => c.isJoker), isTrue);
      expect(g.pendingStrikes[PlayerId.p0], isEmpty);
    });

    test('강타로 바뀐 카드는 그 줄 족보에 그대로 들어간다(붕괴)', () {
      final g = ScoreGame.deal(seed: 4);
      // p1 0번 줄에 K K K를 강제로 깔아 두고 하나를 2로 바꾼다.
      for (var c = 0; c < 3; c++) {
        g.fields[PlayerId.p1]![0][c] = VeiledSlot(PlayingCard(13, Suit.values[c]), round: 0, faceUp: true);
      }
      final i = giveJoker(g, PlayerId.p0);
      g.declareStrike(PlayerId.p0, i, 0, 1, const PlayingCard(2, Suit.clubs));
      g.resolveStrikes();
      expect(evaluateHand(g.allRows(PlayerId.p1)[0]).category, HandCategory.onePair);
    });
  });
}
