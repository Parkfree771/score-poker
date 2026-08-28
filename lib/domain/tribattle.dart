/// 트라이 배틀 도메인 — 룰의 정본은 `docs/TRIBATTLE.md`.
///
/// UI·연출을 모른다. 시뮬레이션(tribattle_sim3.py)에서 검증한 수치를 그대로 옮겼고,
/// 숫자를 바꿀 때는 문서의 §7(시뮬 근거)도 함께 갱신할 것.
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

/// 보드 위의 카드. [value]는 합성으로 9를 넘을 수 있다(3+3→12, 12+12→48).
class TriCard {
  const TriCard(this.value, this.elem);
  final int value;
  final TriElement elem;

  /// 합성 — 같은 숫자만 겹칠 수 있다. 값 = 합 × 2,
  /// 원소는 **이기는 쪽이 남는다**(같으면 유지). 상성 삼각형이 곧 합성 규칙이다.
  TriCard merge(TriCard other) {
    assert(value == other.value, '합성은 같은 숫자만');
    final e = elem == other.elem
        ? elem
        : (elem.beats(other.elem) ? elem : other.elem);
    return TriCard((value + other.value) * TriRules.mergeMult, e);
  }

  @override
  String toString() => '${elem.name[0]}$value';
}

/// 확정 수치 모음 — 튜닝은 여기서만 한다.
abstract final class TriRules {
  static const rows = 3, cols = 5;
  static const ranks = 9; // 1~9
  static const copies = 3; // 원소당 3벌 = 81장
  static const rounds = 3;
  static const marketSize = 11; // 10픽 + 1소각
  static const hp = 60;
  static const mergeMult = 2;

  /// 픽 순서 — (선픽자인가, 몇 장). 스네이크 1-2-2-2-2-1.
  static const pickOrder = [
    (true, 1), (false, 2), (true, 2), (false, 2), (true, 2), (false, 1),
  ];

  // 데미지 상한 — 몰빵의 초과분을 낭비로 만든다. 잭팟 행만 이를 뚫는다.
  static const colCap = 10.0;
  static const rowCap = 20.0;
  static const quadRowCap = 60.0; // 포카드 행 = 상한 ×3
  static const duelMult = 1.5; // 열 대결 상성 배율

  // 순수(단일 원소) 배율 — 줄이 가득 찼을 때만.
  static const colPure = 1.25; // 열 3장 전부
  static const rowPure4 = 1.25; // 행 5장 중 4장
  static const rowPure5 = 1.5; // 행 5장 전부
}

/// 조합 배율 — 행(5칸)과 열(3칸)이 다르다(열이 짧아 상한도 배율도 따로 튜닝).
class _Mults {
  const _Mults(
      {required this.pair,
      required this.trips,
      required this.straight3,
      this.straight5 = 1,
      this.quad = 1,
      this.five = 1});
  final double pair, trips, straight3, straight5, quad, five;
}

const _rowMults =
    _Mults(pair: 2, trips: 3, straight3: 3, straight5: 5, quad: 5, five: 8);
const _colMults = _Mults(pair: 2.5, trips: 5, straight3: 4);

/// 한 줄(행 또는 열)의 점수 — 조합은 **숫자만** 만들고, 원소는 배율만 만든다.
double lineScore(List<TriCard?> line, {required bool isRow}) {
  final cs = line.whereType<TriCard>().toList();
  if (cs.isEmpty) return 0;
  final m = isRow ? _rowMults : _colMults;
  final vals = cs.map((c) => c.value).toList()..sort();
  final counts = <int, int>{};
  for (final v in vals) {
    counts[v] = (counts[v] ?? 0) + 1;
  }
  final top = counts.values.reduce(max);
  final distinct = counts.length == vals.length;
  final straight =
      vals.length >= 3 && distinct && vals.last - vals.first == vals.length - 1;
  double mult;
  if (top >= 5) {
    mult = m.five;
  } else if (top == 4) {
    mult = m.quad;
  } else if (straight && vals.length == 5) {
    mult = m.straight5;
  } else if (top == 3) {
    mult = m.trips;
  } else if (straight && vals.length == 3) {
    mult = m.straight3;
  } else if (top == 2) {
    mult = m.pair;
  } else {
    mult = 1;
  }
  final total = vals.fold<int>(0, (a, b) => a + b);
  return total * mult * _purity(cs, line.length, isRow: isRow);
}

/// 순수 배율 — **줄이 가득 찼을 때만** 준다(중간엔 "진행 중인 약속").
double _purity(List<TriCard> cs, int slots, {required bool isRow}) {
  if (cs.length < slots) return 1;
  final counts = <TriElement, int>{};
  for (final c in cs) {
    counts[c.elem] = (counts[c.elem] ?? 0) + 1;
  }
  final top = counts.values.reduce(max);
  if (isRow) {
    if (top == 5) return TriRules.rowPure5;
    if (top == 4) return TriRules.rowPure4;
    return 1;
  }
  return top == 3 ? TriRules.colPure : 1;
}

/// 줄의 주원소(다수결). 동률이면 null — 상성 계산에서 빠진다.
TriElement? lineElem(List<TriCard?> line) {
  final counts = <TriElement, int>{};
  for (final c in line.whereType<TriCard>()) {
    counts[c.elem] = (counts[c.elem] ?? 0) + 1;
  }
  if (counts.isEmpty) return null;
  final sorted = counts.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  if (sorted.length > 1 && sorted[0].value == sorted[1].value) return null;
  return sorted[0].key;
}

/// 행 잭팟 판정: 포카드(같은 값 4장) / 파이브(5장).
enum RowTier { none, quad, five }

RowTier rowTier(List<TriCard?> row) {
  final vals = row.whereType<TriCard>().map((c) => c.value).toList();
  if (vals.length < 4) return RowTier.none;
  final counts = <int, int>{};
  for (final v in vals) {
    counts[v] = (counts[v] ?? 0) + 1;
  }
  final top = counts.values.reduce(max);
  if (top >= 5) return RowTier.five;
  if (top == 4) return RowTier.quad;
  return RowTier.none;
}

/// 한 사람의 3×5 격자.
class TriBoard {
  final List<List<TriCard?>> g =
      List.generate(TriRules.rows, (_) => List.filled(TriRules.cols, null));
  int merges = 0;

  List<TriCard?> row(int r) => g[r];
  List<TriCard?> col(int c) => [for (var r = 0; r < TriRules.rows; r++) g[r][c]];

  bool get isFull =>
      g.every((row) => row.every((c) => c != null));

  /// [card]를 놓을 수 있는 칸 — 빈 칸 + 같은 숫자(합성).
  List<(int, int)> places(TriCard card) => [
        for (var r = 0; r < TriRules.rows; r++)
          for (var c = 0; c < TriRules.cols; c++)
            if (g[r][c] == null || g[r][c]!.value == card.value) (r, c),
      ];

  /// 배치(빈 칸) 또는 합성(같은 숫자). 규칙 위반이면 assert.
  void put(int r, int c, TriCard card) {
    final cur = g[r][c];
    if (cur == null) {
      g[r][c] = card;
    } else {
      g[r][c] = cur.merge(card);
      merges++;
    }
  }
}

/// 전선 정산 결과.
class TriResolution {
  const TriResolution(this.dmgA, this.dmgB, this.jackpotRowsA, this.jackpotRowsB);
  final double dmgA, dmgB;

  /// 포카드 이상을 완성한 행 번호(연출용).
  final List<int> jackpotRowsA, jackpotRowsB;

  /// 진 쪽만 순수차만큼 깎는다 — 접전 판은 찔끔, 압승 판은 뭉텅.
  double get net => (dmgA - dmgB).abs();
  int get winner => dmgA > dmgB ? 0 : (dmgB > dmgA ? 1 : -1);
}

/// 8전선(열5 + 행3) 정산 — 전선별 점수차를 상한으로 잘라 합산한다.
TriResolution resolve(TriBoard a, TriBoard b) {
  var dmgA = 0.0, dmgB = 0.0;
  final jackA = <int>[], jackB = <int>[];
  for (var i = 0; i < TriRules.cols; i++) {
    var sa = lineScore(a.col(i), isRow: false);
    var sb = lineScore(b.col(i), isRow: false);
    final ea = lineElem(a.col(i)), eb = lineElem(b.col(i));
    if (ea != null && eb != null) {
      if (ea.beats(eb)) sa *= TriRules.duelMult;
      if (eb.beats(ea)) sb *= TriRules.duelMult;
    }
    final d = sa - sb;
    final dd = min(d.abs(), TriRules.colCap);
    d > 0 ? dmgA += dd : dmgB += dd;
  }
  for (var i = 0; i < TriRules.rows; i++) {
    var sa = lineScore(a.row(i), isRow: true);
    var sb = lineScore(b.row(i), isRow: true);
    final ea = lineElem(a.row(i)), eb = lineElem(b.row(i));
    if (ea != null && eb != null) {
      if (ea.beats(eb)) sa *= TriRules.duelMult;
      if (eb.beats(ea)) sb *= TriRules.duelMult;
    }
    final ta = rowTier(a.row(i)), tb = rowTier(b.row(i));
    if (ta != RowTier.none) jackA.add(i);
    if (tb != RowTier.none) jackB.add(i);
    final d = sa - sb;
    // 잭팟 상한은 **이긴 쪽의 행**이 기준 — 진 쪽 포카드가 상한을 열어주면 안 된다.
    final tier = d > 0 ? ta : tb;
    final cap = switch (tier) {
      RowTier.five => double.infinity,
      RowTier.quad => TriRules.quadRowCap,
      RowTier.none => TriRules.rowCap,
    };
    final dd = min(d.abs(), cap);
    d > 0 ? dmgA += dd : dmgB += dd;
  }
  return TriResolution(dmgA, dmgB, jackA, jackB);
}

/// 81장 덱 생성(시드 재현 가능).
List<TriCard> makeDeck(Random rng) {
  final deck = [
    for (var copy = 0; copy < TriRules.copies; copy++)
      for (final e in TriElement.values)
        for (var v = 1; v <= TriRules.ranks; v++) TriCard(v, e),
  ];
  deck.shuffle(rng);
  return deck;
}

/// 한 판(격자 완성까지)의 상태 기계.
///
/// 흐름: 라운드마다 마켓 11장 공개 → `pickOrder`대로 픽 즉시 배치 → 1장 소각 →
/// 중간 정산으로 다음 라운드 선픽 결정. 3라운드 뒤 [resolve]가 최종.
/// 누가 픽할 차례인지는 [turnOwner]가 말해준다 — UI와 AI는 이것만 따르면 된다.
class TriGame {
  TriGame({required int seed, this.leaderIsA = true})
      : _rng = Random(seed) {
    _deck = makeDeck(_rng);
    _openMarket();
  }

  final Random _rng;
  late List<TriCard> _deck;
  final boardA = TriBoard();
  final boardB = TriBoard();
  final market = <TriCard>[];

  /// 이번 라운드 선픽이 A인가. 1라운드는 생성자 인자, 이후엔 중간 정산 승자.
  bool leaderIsA;
  int round = 0;
  int _step = 0; // pickOrder 인덱스
  int _taken = 0; // 현재 step에서 픽한 장수

  bool get finished => round >= TriRules.rounds;

  /// 지금 픽할 사람: true=A. 판이 끝났으면 null.
  bool? get turnOwner {
    if (finished) return null;
    final (isLeader, _) = TriRules.pickOrder[_step];
    return isLeader == leaderIsA;
  }

  TriBoard boardOf(bool isA) => isA ? boardA : boardB;

  void _openMarket() {
    market
      ..clear()
      ..addAll([
        for (var i = 0; i < TriRules.marketSize && _deck.isNotEmpty; i++)
          _deck.removeLast(),
      ]);
  }

  /// 마켓 [marketIndex]의 카드를 (r,c)에 배치한다. 호출자는 [turnOwner] 차례여야 한다.
  void pickAndPlace(int marketIndex, int r, int c) {
    assert(!finished, '판이 끝났다');
    final owner = turnOwner!;
    final board = boardOf(owner);
    final card = market.removeAt(marketIndex);
    assert(board.g[r][c] == null || board.g[r][c]!.value == card.value);
    board.put(r, c, card);
    _advance();
  }

  /// 놓을 곳이 전혀 없을 때만 허용되는 픽 포기(카드 소각).
  void pickAndBurn(int marketIndex) {
    final owner = turnOwner!;
    assert(boardOf(owner).places(market[marketIndex]).isEmpty,
        '놓을 곳이 있으면 버릴 수 없다');
    market.removeAt(marketIndex);
    _advance();
  }

  void _advance() {
    _taken++;
    final (_, count) = TriRules.pickOrder[_step];
    if (_taken >= count) {
      _taken = 0;
      _step++;
    }
    if (_step >= TriRules.pickOrder.length) {
      // 라운드 종료 — 남은 마켓 소각, 중간 정산으로 다음 선픽 결정.
      market.clear();
      _step = 0;
      round++;
      final r = resolve(boardA, boardB);
      if (r.winner != -1) leaderIsA = r.winner == 0;
      if (!finished) _openMarket();
    }
  }
}

/// HP 매치 — 판을 반복하며 진 쪽만 순수차만큼 깎는다.
class TriMatch {
  double hpA = TriRules.hp.toDouble();
  double hpB = TriRules.hp.toDouble();
  final games = <TriResolution>[];

  bool get over => hpA <= 0 || hpB <= 0;

  /// 승자: 0=A, 1=B, 아직이면 null.
  int? get winner => !over ? null : (hpA <= 0 ? 1 : 0);

  void applyGame(TriResolution r) {
    games.add(r);
    if (r.winner == 0) hpB -= r.net;
    if (r.winner == 1) hpA -= r.net;
  }
}

/// 최소 그리디 봇 — 프로토타입·테스트용. (전략 AI는 페르소나 단계에서 제대로.)
///
/// 자기 데미지 마진(상한 반영)이 가장 커지는 (카드, 칸)을 고른다.
class TriGreedyBot {
  const TriGreedyBot();

  (int, int, int)? choose(TriGame g) {
    final owner = g.turnOwner;
    if (owner == null) return null;
    final board = g.boardOf(owner);
    final opp = g.boardOf(!owner);
    double best = double.negativeInfinity;
    (int, int, int)? pick;
    for (var i = 0; i < g.market.length; i++) {
      final card = g.market[i];
      for (final (r, c) in board.places(card)) {
        final cur = board.g[r][c];
        final wasMerge = cur != null;
        board.put(r, c, card);
        final res = owner ? resolve(board, opp) : resolve(opp, board);
        final margin = owner ? res.dmgA - res.dmgB : res.dmgB - res.dmgA;
        board.g[r][c] = cur;
        if (wasMerge) board.merges--;
        if (margin > best) {
          best = margin;
          pick = (i, r, c);
        }
      }
    }
    return pick;
  }
}
