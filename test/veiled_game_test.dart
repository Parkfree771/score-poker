import 'package:flutter_test/flutter_test.dart';
import 'package:score_poker/domain/game.dart' show PlayerId;
import 'package:score_poker/domain/scoring.dart';
import 'package:score_poker/domain/veiled_game.dart';

void main() {
  group('딜과 배치', () {
    test('조커 없는 52장, 시작 6장 + 라운드마다 3장 보충', () {
      final g = VeiledGame.deal(seed: 1);
      expect(g.hands[PlayerId.p0]!.length, 6);
      expect(g.hands[PlayerId.p1]!.length, 6);
      expect(g.deckRemaining, 52 - 12);
      expect(g.hands[PlayerId.p0]!.any((c) => c.isJoker), isFalse);
    });

    test('라운드당 3장까지만 놓을 수 있다', () {
      final g = VeiledGame.deal(seed: 1);
      for (var i = 0; i < 3; i++) {
        g.place(PlayerId.p0, 0, 0, i);
      }
      expect(g.hands[PlayerId.p0]!.length, 3);
      expect(() => g.place(PlayerId.p0, 0, 1, 0), throwsStateError);
    });

    test('배치는 뒷면, 빈 칸에만', () {
      final g = VeiledGame.deal(seed: 1);
      g.place(PlayerId.p0, 0, 0, 0);
      expect(g.fields[PlayerId.p0]![0][0]!.faceUp, isFalse);
      expect(() => g.place(PlayerId.p0, 0, 0, 0), throwsStateError);
    });
  });

  group('공개·비공개권', () {
    VeiledGame placedAll({int seed = 2}) {
      final g = VeiledGame.deal(seed: seed);
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
      final g = VeiledGame.deal(seed: 7);
      while (true) {
        for (final p in PlayerId.values) {
          final plan = veiledAiPlan(g, p)
            ..sort((a, b) => b.handIndex.compareTo(a.handIndex));
          for (final m in plan) {
            g.place(p, m.handIndex, m.row, m.col);
          }
        }
        g.reveal({
          for (final p in PlayerId.values) p: veiledAiHides(g, p),
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
        final g = VeiledGame.deal(seed: seed);
        var guard = 0;
        while (!g.isFinished && ++guard < 20) {
          for (final p in PlayerId.values) {
            final plan = veiledAiPlan(g, p)
              ..sort((a, b) => b.handIndex.compareTo(a.handIndex));
            for (final m in plan) {
              g.place(p, m.handIndex, m.row, m.col);
            }
          }
          g.reveal({
            for (final p in PlayerId.values) p: veiledAiHides(g, p),
          });
          final peek = veiledAiPeek(g, PlayerId.p1);
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
}
