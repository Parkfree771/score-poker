import 'package:flutter_test/flutter_test.dart';
import 'package:score_poker/domain/tribattle.dart';

TriCard w(int v) => TriCard(v, TriElement.water);
TriCard f(int v) => TriCard(v, TriElement.fire);
TriCard t(int v) => TriCard(v, TriElement.forest);

void main() {
  group('합체 — 값은 합, 이기는 원소가 남는다', () {
    test('5물 + 6불 = 11물 (물이 불을 끈다)', () {
      final m = w(5).mergeWith(f(6));
      expect(m.value, 11);
      expect(m.elem, TriElement.water);
    });
    test('순서 무관 — 6불 위에 5물을 얹어도 물', () {
      expect(f(6).mergeWith(w(5)).elem, TriElement.water);
    });
    test('불+숲=불, 숲+물=숲, 같은 원소는 유지', () {
      expect(f(3).mergeWith(t(9)).elem, TriElement.fire);
      expect(t(2).mergeWith(w(8)).elem, TriElement.forest);
      expect(t(4).mergeWith(t(4)), isA<TriCard>()
          .having((c) => c.value, 'value', 8)
          .having((c) => c.elem, 'elem', TriElement.forest));
    });
  });

  group('행 족보 — 5개 누적값의 조합 × 배율', () {
    TriRowEval ev(List<TriCard?> r) => evalRow(r);
    test('원페어 ×2 / 투페어 ×2.5 / 트리플 ×3', () {
      expect(ev([w(3), f(3), w(4), t(5), f(9)]).combo, TriCombo.pair);
      expect(ev([w(3), f(3), w(4), t(4), f(9)]).combo, TriCombo.twoPair);
      expect(ev([w(3), f(3), t(3), t(4), f(9)]).combo, TriCombo.trips);
      expect(ev([w(3), f(3), w(4), t(5), f(9)]).score, 24 * 2);
    });
    test('스트레이트 ×4 — 합체값(10~14)도 연속이면 인정', () {
      expect(ev([w(10), f(11), t(12), w(13), f(14)]).combo, TriCombo.straight);
    });
    test('플러시 ×5 / 풀하우스 ×6 / 포카드 ×8 / 파이브 ×10', () {
      expect(ev([w(2), w(5), w(7), w(8), w(9)]).combo, TriCombo.flush);
      expect(ev([w(3), f(3), t(3), w(9), f(9)]).combo, TriCombo.fullHouse);
      expect(ev([w(6), f(6), t(6), w(6), f(9)]).combo, TriCombo.quad);
      expect(ev([w(6), f(6), t(6), w(6), f(6)]).combo, TriCombo.five);
      expect(ev([w(6), f(6), t(6), w(6), f(6)]).score, 30 * 10);
    });
    test('스트레이트 플러시 ×12', () {
      final e = ev([w(4), w(5), w(6), w(7), w(8)]);
      expect(e.combo, TriCombo.straightFlush);
      expect(e.score, 30 * 12);
    });
    test('페어여도 원소가 통일이면 플러시로 흡수된다 (×5)', () {
      final e = ev([w(3), w(3), w(5), w(8), w(9)]);
      expect(e.combo, TriCombo.flush);
      expect(e.flush, isTrue);
      expect(e.score, 28 * 5);
    });
    test('플러시보다 센 족보엔 보정이 없다 (물 파이브 = ×10 그대로)', () {
      final e = ev([w(6), w(6), w(6), w(6), w(6)]);
      expect(e.combo, TriCombo.five);
      expect(e.score, 30 * 10);
    });
    test('미완성 행은 채운 값 그대로(족보·플러시 없음)', () {
      final e = ev([w(3), w(4), null, null, null]);
      expect(e.combo, TriCombo.high);
      expect(e.flush, isFalse);
      expect(e.score, 7);
    });
  });

  group('열 대결 — 유효값 = 값 × 상성 1.5', () {
    test('같은 값이라도 상성이 이긴다: 물10 vs 불10', () {
      final d = colDuel(0, w(10), f(10));
      expect(d.dmgToB, 5); // 물 유효 15 vs 불 10
      expect(d.dmgToA, 0);
      expect(d.winnerElem, TriElement.water);
    });
    test('상성을 값으로 뒤집는다: 불20 vs 물10', () {
      final d = colDuel(0, f(20), w(10));
      expect(d.dmgToB, 5); // 불 20 vs 물 유효 15
      expect(d.winnerElem, TriElement.fire);
    });
    test('완전 동률이면 무승부', () {
      final d = colDuel(0, w(7), w(7));
      expect(d.dmgToA + d.dmgToB, 0);
      expect(d.winnerElem, isNull);
    });
  });

  group('게임 진행', () {
    test('라운드: 각자 5열을 정확히 1번씩 채우면 정산이 준비된다', () {
      final g = TriGame(seed: 1);
      const bot = TriGreedyBot();
      while (g.pendingResult == null) {
        final (i, c) = bot.choose(g)!;
        g.pickAndPlace(i, c);
      }
      expect(g.rowA.whereType<TriCard>().length, 5);
      expect(g.rowB.whereType<TriCard>().length, 5);
      expect(g.pendingResult!.duels.length, 5);
      expect(g.turnOwner, isNull, reason: '정산 대기 중엔 픽 불가');
      final hp0 = g.hpA + g.hpB;
      g.applyPendingResult();
      expect(g.hpA + g.hpB, lessThan(hp0), reason: '누군가는 맞았다');
      expect(g.round, 1);
      expect(g.market.length, TriRules.marketSize, reason: '다음 라운드 마켓');
    });
    test('2라운드부터는 배치가 합체다', () {
      final g = TriGame(seed: 2);
      const bot = TriGreedyBot();
      while (g.pendingResult == null) {
        final (i, c) = bot.choose(g)!;
        expect(g.pickAndPlace(i, c), isFalse, reason: '1라운드는 빈 열');
      }
      g.applyPendingResult();
      final (i, c) = bot.choose(g)!;
      final before = g.rowOf(g.leaderIsA)[c]!.value;
      final card = g.market[i]!.value;
      expect(g.pickAndPlace(i, c), isTrue, reason: '2라운드는 합체');
      expect(g.rowOf(!g.turnOwner! ? g.leaderIsA : !g.leaderIsA), anything);
      // 방금 얹은 열의 값 = 기존 + 새 카드.
      final rowJustPlaced =
          g.leaderIsA ? g.rowA : g.rowB; // 2라운드 첫 픽은 선픽자
      expect(rowJustPlaced[c]!.value, before + card);
    });
    test('HP가 다 달면 끝나고 승자가 나온다 (덱 한도 7라운드 안)', () {
      final g = TriGame(seed: 3);
      const bot = TriGreedyBot();
      while (!g.over) {
        if (g.pendingResult != null) {
          g.applyPendingResult();
          continue;
        }
        final (i, c) = bot.choose(g)!;
        g.pickAndPlace(i, c);
      }
      expect(g.winner, isNotNull);
      expect(g.round, lessThanOrEqualTo(TriRules.maxRounds));
    });
    test('같은 시드는 같은 게임을 재현한다', () {
      double run(int seed) {
        final g = TriGame(seed: seed);
        const bot = TriGreedyBot();
        while (!g.over) {
          if (g.pendingResult != null) {
            g.applyPendingResult();
            continue;
          }
          final (i, c) = bot.choose(g)!;
          g.pickAndPlace(i, c);
        }
        return g.hpA - g.hpB;
      }

      expect(run(42), run(42));
    });
    test('덜 맞은 쪽이 다음 라운드 선픽', () {
      final g = TriGame(seed: 5);
      const bot = TriGreedyBot();
      while (g.pendingResult == null) {
        final (i, c) = bot.choose(g)!;
        g.pickAndPlace(i, c);
      }
      final r = g.pendingResult!;
      final aWon = r.totalToA < r.totalToB;
      g.applyPendingResult();
      if (r.totalToA != r.totalToB) {
        expect(g.leaderIsA, aWon);
      }
    });
  });
}
