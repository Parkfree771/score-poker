/// 트라이 배틀 도메인 v2 — 룰 정본은 `docs/TRIBATTLE.md`.
///
/// **한 줄 5열 누적 전장**: 라운드마다 각 열에 1장씩 얹고(2라운드부터는 기존
/// 카드와 **합체** — 값은 합, 원소는 이기는 쪽), 다 채우면 열 대결 5번 + 행(족보)
/// 대결 1번으로 진 쪽 HP를 깎는다. HP가 다 달 때까지. 3줄도, 최종전도 없다.
///
/// UI·연출을 모른다. 수치는 자가대전 시뮬(tribattle_sim4.py)로 검증:
/// HP 250 = 중앙값 4라운드, 데미지는 라운드마다 자연 상승(30→257), 선픽 50%.
library;

import 'dart:math';

/// 원소. 상성: 물은 불을 끄고, 불은 숲을 태우고, 숲은 물을 마신다.
enum TriElement {
  water,
  fire,
  forest;

  /// 내가 이기는 원소.
  TriElement get prey => switch (this) {
        TriElement.water => TriElement.fire,
        TriElement.fire => TriElement.forest,
        TriElement.forest => TriElement.water,
      };

  bool beats(TriElement other) => prey == other;
}

/// 열 위의 카드(누적 스택의 현재 상태). [value]는 합체로 계속 자란다.
class TriCard {
  const TriCard(this.value, this.elem);
  final int value;
  final TriElement elem;

  /// **합체** — 새 카드가 얹히면 값은 합, 원소는 이기는 쪽이 남는다(같으면 유지).
  /// 예: 5물 + 6불 = 11물 (물이 불을 끈다). 상성 삼각형이 곧 합체 규칙이다.
  TriCard mergeWith(TriCard incoming) {
    final e = elem == incoming.elem
        ? elem
        : (elem.beats(incoming.elem) ? elem : incoming.elem);
    return TriCard(value + incoming.value, e);
  }

  @override
  String toString() => '${elem.name[0]}$value';
}

/// 확정 수치 — 튜닝은 여기서만.
abstract final class TriRules {
  static const cols = 5;
  static const ranks = 9; // 덱 랭크 1~9
  static const copies = 3; // 원소당 3벌 = 81장
  static const marketSize = 10; // 가운데 5×2로 깔리고 전부 소진된다(소각 없음)
  static const maxRounds = 8; // 81 ÷ 10
  static const hp = 250.0;
  static const duelMult = 1.5; // 열 대결 상성 배율

  /// 픽 순서 — (선픽자인가, 몇 장). 스네이크 1-2-2-2-2-1.
  static const pickOrder = [
    (true, 1), (false, 2), (true, 2), (false, 2), (true, 2), (false, 1),
  ];
}

/// 행 족보 — 5개 누적값의 조합. 배율은 시뮬과 1:1.
enum TriCombo {
  high('하이', 1),
  pair('원페어', 2),
  twoPair('투페어', 2.5),
  trips('트리플', 3),
  straight('스트레이트', 4),
  flush('플러시', 5),
  fullHouse('풀하우스', 6),
  quad('포카드', 8),
  five('파이브', 10),
  straightFlush('스트레이트 플러시', 12);

  const TriCombo(this.label, this.mult);
  final String label;
  final double mult;
}

/// 행 평가 결과.
class TriRowEval {
  const TriRowEval(this.score, this.combo, this.flush);
  final double score;
  final TriCombo combo;

  /// 5열이 한 원소로 통일됐는가 — 족보 서열의 플러시 이상으로 이미 반영돼 있다.
  final bool flush;
}

/// 행(5개 누적값) 족보 점수 = 값 합 × 배율. 빈 칸은 0값·플러시 불인정으로 취급.
TriRowEval evalRow(List<TriCard?> row) {
  final cards = row.whereType<TriCard>().toList();
  final vals = [for (final c in row) c?.value ?? 0];
  final full = cards.length == TriRules.cols;
  final flush =
      full && cards.map((c) => c.elem).toSet().length == 1;
  final counts = <int, int>{};
  for (final c in cards) {
    counts[c.value] = (counts[c.value] ?? 0) + 1;
  }
  final sorted = counts.values.toList()..sort((a, b) => b.compareTo(a));
  final top = sorted.isEmpty ? 0 : sorted[0];
  final second = sorted.length > 1 ? sorted[1] : 0;
  final distinct = counts.length == cards.length;
  final sv = cards.map((c) => c.value).toList()..sort();
  final straight = full &&
      distinct &&
      sv.last - sv.first == TriRules.cols - 1;

  TriCombo combo;
  if (top >= 5) {
    combo = TriCombo.five;
  } else if (straight && flush) {
    combo = TriCombo.straightFlush;
  } else if (top == 4) {
    combo = TriCombo.quad;
  } else if (top == 3 && second >= 2) {
    combo = TriCombo.fullHouse;
  } else if (flush) {
    combo = TriCombo.flush;
  } else if (straight) {
    combo = TriCombo.straight;
  } else if (top == 3) {
    combo = TriCombo.trips;
  } else if (top == 2 && second == 2) {
    combo = TriCombo.twoPair;
  } else if (top == 2) {
    combo = TriCombo.pair;
  } else {
    combo = TriCombo.high;
  }
  // 플러시는 족보 서열에 이미 들어 있다(페어+원소통일 → 그냥 플러시 ×5).
  final total = vals.fold<int>(0, (a, b) => a + b);
  return TriRowEval(total * combo.mult, combo, flush);
}

/// 열 하나의 대결 — 유효값 = 값 × (상성이면 1.5). 진 쪽이 차이만큼 맞는다.
class TriColDuel {
  const TriColDuel(this.col, this.dmgToA, this.dmgToB, this.winnerElem);
  final int col;
  final double dmgToA, dmgToB;

  /// 이긴 쪽 원소(공격 모션 색). 무승부면 null.
  final TriElement? winnerElem;
}

TriColDuel colDuel(int c, TriCard a, TriCard b) {
  final ea = a.value * (a.elem.beats(b.elem) ? TriRules.duelMult : 1.0);
  final eb = b.value * (b.elem.beats(a.elem) ? TriRules.duelMult : 1.0);
  if (ea > eb) return TriColDuel(c, 0, ea - eb, a.elem);
  if (eb > ea) return TriColDuel(c, eb - ea, 0, b.elem);
  return TriColDuel(c, 0, 0, null);
}

/// 라운드 정산 전체 — 연출이 이 순서대로 재생한다(열 5개 → 행 1개).
class TriRoundResult {
  const TriRoundResult({
    required this.round,
    required this.duels,
    required this.rowA,
    required this.rowB,
    required this.rowDmgToA,
    required this.rowDmgToB,
  });

  final int round;
  final List<TriColDuel> duels;
  final TriRowEval rowA, rowB;
  final double rowDmgToA, rowDmgToB;

  double get totalToA =>
      duels.fold(rowDmgToA, (s, d) => s + d.dmgToA);
  double get totalToB =>
      duels.fold(rowDmgToB, (s, d) => s + d.dmgToB);
}

/// 81장 덱(시드 재현 가능).
List<TriCard> makeDeck(Random rng) {
  final deck = [
    for (var copy = 0; copy < TriRules.copies; copy++)
      for (final e in TriElement.values)
        for (var v = 1; v <= TriRules.ranks; v++) TriCard(v, e),
  ];
  deck.shuffle(rng);
  return deck;
}

/// 한 게임(HP 소진까지)의 상태 기계.
///
/// 흐름: 라운드마다 마켓 11장 → `pickOrder`대로 픽 즉시 배치(각자 각 열 1장씩,
/// 열이 차면 합체) → 다 채우면 [pendingResult]에 정산이 준비된다. UI가 연출을
/// 끝내고 [applyPendingResult]를 부르면 HP가 깎이고 다음 라운드가 열린다.
/// (정산 준비와 적용을 나눈 이유: 열 공격 연출이 하나씩 재생될 시간을 UI에 준다.)
class TriGame {
  TriGame({required int seed, this.leaderIsA = true}) : _rng = Random(seed) {
    _deck = makeDeck(_rng);
    _openMarket();
  }

  final Random _rng;
  late List<TriCard> _deck;
  final rowA = List<TriCard?>.filled(TriRules.cols, null);
  final rowB = List<TriCard?>.filled(TriRules.cols, null);

  /// 마켓 — **고정 슬롯 10칸** (5×2 판). 픽하면 그 칸이 null(빈 자리)이 된다.
  /// 리스트를 줄이지 않는 이유: 칸이 밀리면 화면에서 카드들이 재배열돼 혼란스럽다.
  final market = List<TriCard?>.filled(TriRules.marketSize, null);

  double hpA = TriRules.hp;
  double hpB = TriRules.hp;

  bool leaderIsA;
  int round = 0; // 0-base. 완료된 라운드 수이기도 하다.
  int _step = 0;
  int _taken = 0;

  /// 이번 라운드에 아직 안 채운 열.
  final openA = <int>{0, 1, 2, 3, 4};
  final openB = <int>{0, 1, 2, 3, 4};

  /// 라운드가 다 차서 정산 대기 중인 결과. UI 연출 후 [applyPendingResult].
  TriRoundResult? pendingResult;

  bool get over => hpA <= 0 || hpB <= 0 || round >= TriRules.maxRounds;

  /// 승자: 0=A, 1=B, 무=−1. 게임이 안 끝났으면 null.
  int? get winner {
    if (!over) return null;
    if (hpA == hpB) return -1;
    return hpA > hpB ? 0 : 1;
  }

  /// 지금 픽할 사람(true=A). 정산 대기·종료면 null.
  bool? get turnOwner {
    if (over || pendingResult != null) return null;
    final (isLeader, _) = TriRules.pickOrder[_step];
    return isLeader == leaderIsA;
  }

  List<TriCard?> rowOf(bool isA) => isA ? rowA : rowB;
  Set<int> openOf(bool isA) => isA ? openA : openB;

  void _openMarket() {
    for (var i = 0; i < TriRules.marketSize; i++) {
      market[i] = _deck.isNotEmpty ? _deck.removeLast() : null;
    }
  }

  /// 마켓 [marketIndex] 카드를 [col] 열에 얹는다(있으면 합체).
  /// 반환: 합체였는가(연출용).
  bool pickAndPlace(int marketIndex, int col) {
    final owner = turnOwner!;
    final row = rowOf(owner);
    final open = openOf(owner);
    assert(open.contains(col), '이번 라운드에 이미 채운 열');
    final card = market[marketIndex]!;
    market[marketIndex] = null;
    final merging = row[col] != null;
    row[col] = merging ? row[col]!.mergeWith(card) : card;
    open.remove(col);
    _advance();
    return merging;
  }

  void _advance() {
    _taken++;
    final (_, count) = TriRules.pickOrder[_step];
    if (_taken >= count) {
      _taken = 0;
      _step++;
    }
    if (_step >= TriRules.pickOrder.length) {
      market.fillRange(0, market.length, null); // 전부 소진 — 판이 접힌다
      _step = 0;
      _resolveRound();
    }
  }

  void _resolveRound() {
    final duels = [
      for (var c = 0; c < TriRules.cols; c++) colDuel(c, rowA[c]!, rowB[c]!),
    ];
    final ra = evalRow(rowA), rb = evalRow(rowB);
    final d = ra.score - rb.score;
    pendingResult = TriRoundResult(
      round: round + 1,
      duels: duels,
      rowA: ra,
      rowB: rb,
      rowDmgToA: d < 0 ? -d : 0,
      rowDmgToB: d > 0 ? d : 0,
    );
  }

  /// 정산 확정 — HP를 깎고, 덜 맞은 쪽이 다음 라운드 선픽.
  void applyPendingResult() {
    final r = pendingResult!;
    hpA = max(0, hpA - r.totalToA);
    hpB = max(0, hpB - r.totalToB);
    if (r.totalToA != r.totalToB) leaderIsA = r.totalToA < r.totalToB;
    pendingResult = null;
    round++;
    openA.addAll([0, 1, 2, 3, 4]);
    openB.addAll([0, 1, 2, 3, 4]);
    if (!over) _openMarket();
  }
}

/// 그리디 봇 — 행 족보 점수 + 열 유효우위(가중 1.0)를 최대화. 시뮬의 balanced.
class TriGreedyBot {
  const TriGreedyBot();

  (int, int)? choose(TriGame g) {
    final owner = g.turnOwner;
    if (owner == null) return null;
    final row = g.rowOf(owner);
    final oppRow = g.rowOf(!owner);
    final open = g.openOf(owner);
    double best = double.negativeInfinity;
    (int, int)? pick;
    for (var i = 0; i < g.market.length; i++) {
      final card = g.market[i];
      if (card == null) continue; // 이미 픽된 빈 슬롯
      for (final c in open) {
        final prev = row[c];
        row[c] = prev == null ? card : prev.mergeWith(card);
        var v = evalRow(row).score;
        final opp = oppRow[c];
        if (opp != null) {
          // colDuel의 첫 인자를 "나"로 넣으므로 dmgToB가 상대 피해다(주인 무관).
          final duel = colDuel(c, row[c]!, opp);
          v += duel.dmgToB - duel.dmgToA;
        }
        row[c] = prev;
        if (v > best) {
          best = v;
          pick = (i, c);
        }
      }
    }
    return pick;
  }
}
