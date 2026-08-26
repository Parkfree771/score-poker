import 'package:flutter_test/flutter_test.dart';
import 'package:score_poker/domain/ai.dart';
import 'package:score_poker/domain/game.dart';

/// 페르소나 AI는 **같은 룰을 다르게 둔다**. 여기서 지키는 것은 "누가 더 세냐"가 아니라
/// 기풍이 실제 행동으로 나타나는가다 — 성격이 안 드러나면 상대 셋이 다 같은 상대다.
void main() {
  /// [p]가 이번 라운드 3장을 계획대로 놓는다.
  void placeRound(ScoreGame g, PlayerId p, VeiledAi ai) {
    final plan = ai.plan(g, p)
      ..sort((a, b) => b.handIndex.compareTo(a.handIndex));
    for (final m in plan) {
      g.place(p, m.handIndex, m.row, m.col);
    }
  }

  group('기풍별 배치', () {
    test('크로드는 세 줄을 고르게, 헷은 두 줄에 몰아준다', () {
      var clodeSpread = 0, hetSpread = 0;
      for (var seed = 0; seed < 20; seed++) {
        for (final style in [AiStyle.clode, AiStyle.het]) {
          final g = ScoreGame.deal(seed: seed);
          final ai = VeiledAi(style, seed: seed);
          // 3라운드까지만 — 15칸이 다 차면 어떤 기풍이든 결국 같아진다.
          for (var r = 0; r < 3; r++) {
            placeRound(g, PlayerId.p0, ai);
            placeRound(g, PlayerId.p1, VeiledAi(AiStyle.clode, seed: 99));
            g.reveal(const {});
            g.nextRound();
          }
          final counts = [
            for (final row in g.fields[PlayerId.p0]!)
              row.where((s) => s != null).length,
          ]..sort();
          // 가장 많이 채운 줄과 가장 적게 채운 줄의 차 = 편중도.
          final spread = counts.last - counts.first;
          if (style == AiStyle.clode) {
            clodeSpread += spread;
          } else {
            hetSpread += spread;
          }
        }
      }
      expect(hetSpread, greaterThan(clodeSpread),
          reason: '헷($hetSpread)이 크로드($clodeSpread)보다 편중돼야 한다');
    });
  });

  group('기풍별 비공개권 운용', () {
    /// [round]라운드까지 진행한 판을 만든다(공개 전 상태).
    ScoreGame upTo(int round, {int seed = 5}) {
      final g = ScoreGame.deal(seed: seed);
      final filler = VeiledAi(AiStyle.clode, seed: seed);
      for (var r = 0; r < round; r++) {
        placeRound(g, PlayerId.p0, filler);
        placeRound(g, PlayerId.p1, filler);
        g.reveal(const {});
        g.nextRound();
      }
      placeRound(g, PlayerId.p0, filler);
      placeRound(g, PlayerId.p1, filler);
      return g;
    }

    test('크로드는 초반에 숨기지 않는다', () {
      for (var round = 0; round < 2; round++) {
        final g = upTo(round);
        expect(VeiledAi(AiStyle.clode, seed: 3).hides(g, PlayerId.p1), isEmpty,
            reason: '$round라운드');
      }
    });

    test('크로드는 열어보기용으로 비공개권을 남긴다', () {
      final g = upTo(4);
      g.veilLeft[PlayerId.p1] = 1; // 마지막 한 개
      expect(VeiledAi(AiStyle.clode, seed: 3).hides(g, PlayerId.p1), isEmpty);
    });

    test('헷은 첫 라운드부터 숨기고, 남기지 않는다', () {
      var hid = 0;
      for (var seed = 0; seed < 12; seed++) {
        final g = upTo(0, seed: seed);
        if (VeiledAi(AiStyle.het, seed: seed).hides(g, PlayerId.p1).isNotEmpty) {
          hid++;
        }
      }
      expect(hid, greaterThan(0), reason: '헷이 초반에 한 번도 안 숨겼다');
    });

    test('제나는 값어치 없는 카드도 숨긴다(허세)', () {
      // 크로드 기준으로는 숨길 이유가 없는 판들에서 제나만 숨기는 경우가 있어야 한다.
      var bluffs = 0;
      for (var seed = 0; seed < 25; seed++) {
        final g = upTo(2, seed: seed);
        final calm = VeiledAi(AiStyle.clode, seed: seed).hides(g, PlayerId.p1);
        final tricky = VeiledAi(AiStyle.jenna, seed: seed).hides(g, PlayerId.p1);
        if (calm.isEmpty && tricky.isNotEmpty) bluffs++;
      }
      expect(bluffs, greaterThan(0));
    });

    test('숨기기는 이번 라운드에 놓은 카드만 고른다', () {
      final g = upTo(3);
      for (final style in AiStyle.values) {
        final hides = VeiledAi(style, seed: 11).hides(g, PlayerId.p1);
        for (final pos in hides) {
          expect(g.fields[PlayerId.p1]![pos.$1][pos.$2]!.round, g.round);
        }
      }
    });
  });

  group('기풍별 열어보기', () {
    test('크로드는 헷보다 늦게 연다', () {
      expect(AiProfile.byStyle[AiStyle.clode]!.peekFromRound,
          greaterThan(AiProfile.byStyle[AiStyle.het]!.peekFromRound));
    });

    test('열어볼 대상은 언제나 상대의 지난 라운드 숨김 카드', () {
      final g = ScoreGame.deal(seed: 9);
      final filler = VeiledAi(AiStyle.clode, seed: 9);
      // 1라운드: p0가 한 장 숨긴다.
      placeRound(g, PlayerId.p0, filler);
      placeRound(g, PlayerId.p1, filler);
      final mine = g.placedThisRound(PlayerId.p0).first;
      g.reveal({
        PlayerId.p0: {mine},
      });
      g.nextRound();
      placeRound(g, PlayerId.p0, filler);
      placeRound(g, PlayerId.p1, filler);

      final target = VeiledAi(AiStyle.het, seed: 1).peek(g, PlayerId.p1);
      expect(target, mine);
      g.peek(PlayerId.p1, target!.$1, target.$2);
      expect(g.fields[PlayerId.p0]![mine.$1][mine.$2]!.faceUp, isTrue);
      expect(g.veilLeft[PlayerId.p1], 2);
    });
  });

  test('모든 기풍이 100판을 교착 없이 끝낸다', () {
    final n = AiStyle.values.length;
    for (var seed = 0; seed < 100; seed++) {
      final a = VeiledAi(AiStyle.values[seed % n], seed: seed);
      final b = VeiledAi(AiStyle.values[(seed + 1) % n], seed: seed + 1);
      final g = ScoreGame.deal(seed: seed);
      var guard = 0;
      while (!g.isFinished && ++guard < 20) {
        placeRound(g, PlayerId.p0, a);
        placeRound(g, PlayerId.p1, b);
        g.reveal({
          PlayerId.p0: a.hides(g, PlayerId.p0),
          PlayerId.p1: b.hides(g, PlayerId.p1),
        });
        for (final (p, ai) in [(PlayerId.p0, a), (PlayerId.p1, b)]) {
          final t = ai.peek(g, p);
          if (t != null) g.peek(p, t.$1, t.$2);
        }
        if (!g.isFinished) g.nextRound();
      }
      expect(g.isFinished, isTrue, reason: 'seed $seed 미종료');
      g.revealAll();
      g.judge();
    }
  });
}
