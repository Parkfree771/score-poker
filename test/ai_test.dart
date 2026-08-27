import 'package:flutter_test/flutter_test.dart';
import 'package:score_poker/domain/ai.dart';
import 'package:score_poker/domain/card.dart';
import 'package:score_poker/domain/game.dart';
import 'package:score_poker/domain/scoring.dart';

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
  group('레벨', () {
    /// 한 판을 끝까지 둔다(숨기기·열어보기 포함). p0 기준 결과.
    MatchOutcome play(VeiledAi a, VeiledAi b, int seed) {
      final g = ScoreGame.deal(seed: seed);
      while (!g.isFinished) {
        for (final (p, ai) in [(PlayerId.p0, a), (PlayerId.p1, b)]) {
          final j = ai.jokerMove(g, p);
          if (j == null) continue;
          if (j.strike) {
            g.declareStrike(p, j.handIndex, j.row, j.col, j.card);
          } else {
            g.placeWild(p, j.handIndex, j.row, j.col, j.card);
          }
        }
        placeRound(g, PlayerId.p0, a);
        placeRound(g, PlayerId.p1, b);
        g.reveal({PlayerId.p0: a.hides(g, PlayerId.p0), PlayerId.p1: b.hides(g, PlayerId.p1)});
        for (final (p, ai) in [(PlayerId.p0, a), (PlayerId.p1, b)]) {
          final t = ai.peek(g, p);
          if (t != null) g.peek(p, t.$1, t.$2);
        }
        if (!g.isFinished) g.nextRound();
      }
      g.revealAll();
      return g.judge().outcome;
    }

    test('5레벨이 1레벨을 확실히 더 많이 이긴다(자리 바꿔 40판)', () {
      var hi = 0, lo = 0;
      for (var seed = 0; seed < 40; seed++) {
        final style = AiStyle.values[seed % AiStyle.values.length];
        final swap = seed.isOdd;
        final a = VeiledAi(style, level: swap ? 1 : 5, seed: seed);
        final b = VeiledAi(style, level: swap ? 5 : 1, seed: seed + 7);
        final o = play(a, b, seed);
        if (o == (swap ? MatchOutcome.lose : MatchOutcome.win)) hi++;
        if (o == (swap ? MatchOutcome.win : MatchOutcome.lose)) lo++;
      }
      expect(hi, greaterThan(lo + 6), reason: '5레벨 $hi승 / 1레벨 $lo승');
    });

    test('5레벨이어도 기풍은 남는다 — 헷이 크로드보다 편중', () {
      var clodeSpread = 0, hetSpread = 0;
      for (var seed = 0; seed < 12; seed++) {
        for (final style in [AiStyle.clode, AiStyle.het]) {
          final g = ScoreGame.deal(seed: seed);
          final ai = VeiledAi(style, level: 5, seed: seed);
          for (var r = 0; r < 3; r++) {
            placeRound(g, PlayerId.p0, ai);
            placeRound(g, PlayerId.p1, VeiledAi(AiStyle.clode, level: 2, seed: 99));
            g.reveal(const {});
            g.nextRound();
          }
          final counts = [
            for (final row in g.fields[PlayerId.p0]!) row.where((s) => s != null).length,
          ]..sort();
          if (style == AiStyle.clode) {
            clodeSpread += counts.last - counts.first;
          } else {
            hetSpread += counts.last - counts.first;
          }
        }
      }
      expect(hetSpread, greaterThan(clodeSpread),
          reason: '헷($hetSpread)이 크로드($clodeSpread)보다 편중돼야 한다');
    });

    test('높은 레벨은 굳은 줄엔 비공개권을 안 쓴다(승패 갈리는 줄만 연다)', () {
      // 4레벨: smartPeek. 숨긴 카드가 있어도 그 줄 승률이 한쪽으로 기울면 null.
      final g = ScoreGame.deal(seed: 3);
      final filler = VeiledAi(AiStyle.clode, level: 2, seed: 3);
      placeRound(g, PlayerId.p0, filler);
      placeRound(g, PlayerId.p1, filler);
      final hidden = g.placedThisRound(PlayerId.p1).first;
      g.reveal({PlayerId.p1: {hidden}});
      g.nextRound();
      final ai = VeiledAi(AiStyle.grok, level: 4, seed: 1); // 그록: peekChance 1.0
      final t = ai.peek(g, PlayerId.p0);
      // 결과는 판에 따라 null(굳은 줄)이거나 숨긴 카드 자체여야 한다 — 다른 칸을 열진 않는다.
      expect(t == null || t == hidden, isTrue);
    });
  });
  group('조커', () {
    test('낮은 레벨은 조커를 받자마자 와일드로, 높은 레벨은 이득이 커야 쓴다', () {
      final g = ScoreGame.deal(seed: 11);
      g.hands[PlayerId.p0]!.insert(0, const PlayingCard.joker());
      final low = VeiledAi(AiStyle.clode, level: 1, seed: 1).jokerMove(g, PlayerId.p0);
      expect(low, isNotNull);
      expect(low!.strike, isFalse);
      expect(low.card.isJoker, isFalse);
      // 판이 비어 있으면 강타할 표적이 없고 와일드 이득도 작다 — 5레벨은 아낀다.
      final high = VeiledAi(AiStyle.clode, level: 5, seed: 1).jokerMove(g, PlayerId.p0);
      expect(high == null || !high.strike, isTrue);
    });

    test('5레벨은 상대의 완성된 줄을 강타해 붕괴시킨다', () {
      final g = ScoreGame.deal(seed: 12);
      for (var c = 0; c < 5; c++) {
        g.fields[PlayerId.p1]![0][c] = VeiledSlot(
            PlayingCard(c < 4 ? 13 : 9, Suit.values[c % 4]), round: 0, faceUp: true);
      }
      g.hands[PlayerId.p0]!.insert(0, const PlayingCard.joker());
      final m = VeiledAi(AiStyle.dipsy, level: 5, seed: 1).jokerMove(g, PlayerId.p0);
      expect(m, isNotNull);
      expect(m!.strike, isTrue);
      expect(m.row, 0);
      expect(m.card.rank, lessThan(13));
    });

    test('배치 계획은 조커를 건너뛴다', () {
      final g = ScoreGame.deal(seed: 13);
      g.hands[PlayerId.p0]!.insert(0, const PlayingCard.joker());
      final plan = VeiledAi(AiStyle.het, level: 3, seed: 1).plan(g, PlayerId.p0);
      expect(plan.length, 3);
      expect(plan.any((m) => g.hands[PlayerId.p0]![m.handIndex].isJoker), isFalse);
    });
  });
}
