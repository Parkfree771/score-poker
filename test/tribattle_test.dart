import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:score_poker/domain/tribattle.dart';

TriCard w(int v) => TriCard(v, TriElement.water);
TriCard f(int v) => TriCard(v, TriElement.fire);
TriCard t(int v) => TriCard(v, TriElement.forest);

void main() {
  group('합성 — 이기는 원소가 남는다', () {
    test('같은 원소는 유지', () {
      final m = w(3).merge(w(3));
      expect(m.value, 12); // (3+3)×2
      expect(m.elem, TriElement.water);
    });
    test('물은 불을 끈다', () {
      expect(w(3).merge(f(3)).elem, TriElement.water);
      expect(f(3).merge(w(3)).elem, TriElement.water);
    });
    test('불은 숲을 태운다 / 숲은 물을 마신다', () {
      expect(f(5).merge(t(5)).elem, TriElement.fire);
      expect(t(7).merge(w(7)).elem, TriElement.forest);
    });
  });

  group('조합 점수 = 랭크 합 × 배율', () {
    test('행 페어 ×2 (미완성 줄 — 순수 배율 없음)', () {
      expect(lineScore([w(3), f(3), w(4), w(5), null], isRow: true),
          (3 + 3 + 4 + 5) * 2);
    });
    test('행이 가득 차면 순수 4장 배율이 함께 붙는다', () {
      // 물4+불1 페어: 30 × 순수4장 1.25 = 37.5 아님 — 페어 ×2 먼저: 24×2×1.25.
      expect(lineScore([w(3), f(3), w(4), w(5), w(9)], isRow: true),
          (3 + 3 + 4 + 5 + 9) * 2 * 1.25);
    });
    test('열 트리플 ×5', () {
      expect(lineScore([w(4), f(4), t(4)], isRow: false), 12 * 5);
    });
    test('행 5스트레이트 ×5', () {
      expect(lineScore([w(1), f(2), w(3), t(4), w(5)], isRow: true), 15 * 5);
    });
    test('합성값도 스트레이트에 낀다 (10,11,12)', () {
      // 값만 본다 — 합성으로 만든 10~12도 연속이면 스트레이트.
      expect(lineScore([w(10), f(11), w(12)], isRow: false), 33 * 4);
    });
    test('파이브 ×8', () {
      expect(lineScore([w(9), f(9), t(9), w(9), f(9)], isRow: true), 45 * 8);
    });
  });

  group('순수 배율 — 줄이 가득 찼을 때만', () {
    test('열 3장 전부 물 ×1.25', () {
      expect(lineScore([w(2), w(5), w(8)], isRow: false), (15) * 1 * 1.25);
    });
    test('열 2장 물은 아직 0 보너스', () {
      expect(lineScore([w(2), w(5), null], isRow: false), 7);
    });
    test('행 4장 순수 ×1.25, 5장 순수 ×1.5', () {
      expect(lineScore([w(1), w(3), w(5), w(7), f(8)], isRow: true),
          24 * 1.25);
      expect(lineScore([w(1), w(3), w(5), w(7), w(8)], isRow: true),
          closeTo(24 * 1.5, 1e-9));
    });
  });

  group('전선 정산', () {
    test('열 상한 10 — 압승 초과분은 낭비', () {
      final a = TriBoard()..put(0, 0, w(9))..put(1, 0, f(9))..put(2, 0, t(9));
      final b = TriBoard()..put(0, 0, w(1));
      final r = resolve(a, b);
      // 열0: 트리플 135 vs 1 → 상한 10. 행 기여: 행0 9−1=8, 행1·행2 각 9.
      expect(r.dmgA, TriRules.colCap + 8 + 9 + 9);
    });
    test('포카드 행은 상한 60, 파이브 행은 무제한', () {
      TriBoard quadRow() => TriBoard()
        ..put(0, 0, w(9))
        ..put(0, 1, f(9))
        ..put(0, 2, t(9))
        ..put(0, 3, w(9))
        ..put(0, 4, f(8));
      final a = quadRow();
      final r = resolve(a, TriBoard());
      // 행 데미지는 quadRowCap을 넘지 못하지만 일반 상한(20)은 넘는다.
      // 열 기여: 단일 카드 9,9,9,9,8 = 44 (상한 10 미달). 행 = 포카드 220 → 상한 60.
      final rowDmg = r.dmgA - (9 + 9 + 9 + 9 + 8);
      expect(rowDmg, greaterThan(TriRules.rowCap));
      expect(rowDmg, TriRules.quadRowCap);

      final five = TriBoard()
        ..put(0, 0, w(9))
        ..put(0, 1, f(9))
        ..put(0, 2, t(9))
        ..put(0, 3, w(9))
        ..put(0, 4, f(9));
      final r2 = resolve(five, TriBoard());
      expect(r2.jackpotRowsA, [0]);
      // 파이브 행 점수 45×8×?(순수 아님) = 360 — 상한 없이 그대로.
      expect(r2.dmgA, greaterThan(300));
    });
    test('진 쪽 포카드는 상한을 열어주지 않는다', () {
      final a = TriBoard() // 강한 일반 행
        ..put(0, 0, w(9))
        ..put(0, 1, w(8))
        ..put(0, 2, w(7))
        ..put(0, 3, w(6))
        ..put(0, 4, w(5)); // 스트레이트+순수
      final b = TriBoard() // 약한 포카드 행 (1×4)
        ..put(0, 0, w(1))
        ..put(0, 1, f(1))
        ..put(0, 2, t(1))
        ..put(0, 3, w(1));
      final r = resolve(a, b);
      // a가 이긴다 — 이긴 쪽(a)는 포카드가 아니므로 행 상한은 20.
      final rowDmg = r.dmgA - TriRules.colCap * 5;
      expect(rowDmg, lessThanOrEqualTo(TriRules.rowCap));
    });
    test('열 대결 상성 ×1.5 — 물 열이 불 열을 잡는다', () {
      final a = TriBoard()..put(0, 0, w(5))..put(1, 0, w(5)); // 물 페어 25
      final b = TriBoard()..put(0, 0, f(5))..put(1, 0, f(5)); // 불 페어 25
      final r = resolve(a, b);
      expect(r.winner, 0); // 동점이지만 상성으로 물이 이긴다
    });
  });

  group('판 진행(TriGame)', () {
    test('픽 순서 1-2-2-2-2-1, 라운드마다 마켓 11장, 3라운드 뒤 종료', () {
      final g = TriGame(seed: 1);
      var picksA = 0, picksB = 0;
      const bot = TriGreedyBot();
      while (!g.finished) {
        expect(g.market.length, lessThanOrEqualTo(TriRules.marketSize));
        final owner = g.turnOwner!;
        final (i, r, c) = bot.choose(g)!;
        g.pickAndPlace(i, r, c);
        owner ? picksA++ : picksB++;
      }
      expect(picksA, 15);
      expect(picksB, 15);
      expect(g.turnOwner, isNull);
    });
    test('같은 시드는 같은 판을 재현한다', () {
      String run(int seed) {
        final g = TriGame(seed: seed);
        const bot = TriGreedyBot();
        while (!g.finished) {
          final (i, r, c) = bot.choose(g)!;
          g.pickAndPlace(i, r, c);
        }
        final r = resolve(g.boardA, g.boardB);
        return '${r.dmgA}/${r.dmgB}';
      }

      expect(run(42), run(42));
      expect(run(42) == run(43), isFalse);
    });
    test('HP 매치 — 진 쪽만 순수차만큼 깎이고 0이면 끝난다', () {
      final m = TriMatch();
      final rng = Random(5);
      var guard = 0;
      while (!m.over && guard++ < 12) {
        final g = TriGame(seed: rng.nextInt(1 << 30));
        const bot = TriGreedyBot();
        while (!g.finished) {
          final (i, r, c) = bot.choose(g)!;
          g.pickAndPlace(i, r, c);
        }
        m.applyGame(resolve(g.boardA, g.boardB));
      }
      expect(m.over, isTrue, reason: '12판 안에 승부가 나야 한다(시뮬 중앙값 3판)');
      expect(m.winner, isNotNull);
    });
  });
}
