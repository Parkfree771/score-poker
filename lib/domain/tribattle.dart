/// 트라이 배틀 도메인 v3 — 룰의 정본은 `docs/TRIBATTLE.md`.
///
/// v3 "비공개 드로 배틀": 매 턴 덱에서 1장 비공개 드로 →
/// 배치(앞면 무료 / 뒷면 코인1) 또는 공격(랭크 매칭). 공격하면 두 장이 소멸하고
/// 보충 1장 = 방어막(공격 불가·피격 불가, 양쪽 필드 아무 유효 칸).
/// 수치는 전부 시뮬(tribattle_v3_sim3.py, 세션 스크래치)로 검증한 값.
///
/// UI·연출을 모른다.
library;

import 'dart:math';

/// 원소. 족보(플러시)에만 관여 — 공격 매칭은 랭크만 본다.
enum TriElement {
  water,
  fire,
  forest;

  /// 내가 이기는 원소 (v1 유산 — v3 코어에선 안 쓰지만 연출·확장용으로 유지).
  TriElement get prey => switch (this) {
        TriElement.water => TriElement.fire,
        TriElement.fire => TriElement.forest,
        TriElement.forest => TriElement.water,
      };

  bool beats(TriElement other) => prey == other;
}

/// 카드. 상태 플래그는 게임이 진행하며 바뀐다.
class TriCard {
  TriCard(this.rank, this.elem);
  final int rank;
  final TriElement elem;

  /// 뒷면 배치(코인1) — 주인이 아닌 쪽에겐 안 보이고, 공격 표적이 안 된다.
  bool faceDown = false;

  /// 상대가 코인으로 훔쳐봄 — 훔쳐본 쪽에겐 공개 취급(공격 가능해진다).
  bool peeked = false;

  /// 방어막(공격 성공 보충 카드) — 공격에 못 쓰고, 공격받지도 않는다.
  bool shield = false;

  @override
  String toString() => '${elem.name[0]}$rank${shield ? '*' : ''}';
}

/// 확정 수치 모음 — 튜닝은 여기서만 한다.
abstract final class TriRules {
  static const cols = 3, rows = 5; // 열 3개 × 높이 5 (아래부터 채움)
  static const ranks = 9; // 1~9
  static const copies = 3; // 원소당 3벌 = 81장
  static const startHand = 2;
  static const startCoins = 5;
  static const coinEveryMyTurns = 3; // 내 턴 3번마다 +1
  static const costFaceDown = 1;
  static const costPeek = 1;
  static const hp = 250;

  /// 열(5칸) 조합 배율 — 시뮬 달성률(희귀도)에 비례.
  static const colFive = 10.0,
      colStraight5 = 7.0,
      colQuad = 6.0,
      colFull = 5.0,
      colTrips = 3.0,
      colStraight3 = 2.5,
      colPair = 2.0;

  /// 행(3칸) 조합 배율.
  static const rowTrips = 5.0, rowStraight3 = 3.5, rowPair = 2.0;

  /// 플러시(원소 통일, 줄이 가득 찼을 때만) — 열은 11판에 1번꼴 레어라 크게.
  static const flushCol = 2.0, flushRow = 1.3;
}

/// 줄 조합 — 연출·라벨용. 배율은 [colScore]/[rowScore]가 안다.
enum TriCombo {
  none('—'),
  pair('페어'),
  straight3('3연속'),
  trips('트리플'),
  fullHouse('풀하우스'),
  straight5('5연속'),
  quad('포카드'),
  five('파이브');

  const TriCombo(this.label);
  final String label;
}

TriCombo _combo(List<int> ranks, {required bool isCol}) {
  if (ranks.length < 2) return TriCombo.none;
  final counts = <int, int>{};
  for (final r in ranks) {
    counts[r] = (counts[r] ?? 0) + 1;
  }
  final tops = counts.values.toList()..sort((a, b) => b.compareTo(a));
  final top = tops[0];
  final second = tops.length > 1 ? tops[1] : 0;
  final uniq = counts.keys.toList()..sort();
  var run = 1, bestRun = 1;
  for (var i = 1; i < uniq.length; i++) {
    run = uniq[i] - uniq[i - 1] == 1 ? run + 1 : 1;
    bestRun = max(bestRun, run);
  }
  if (isCol) {
    if (top >= 5) return TriCombo.five;
    if (top == 4) return TriCombo.quad;
    if (bestRun >= 5) return TriCombo.straight5;
    if (top == 3 && second >= 2) return TriCombo.fullHouse;
    if (top == 3) return TriCombo.trips;
    if (bestRun >= 3) return TriCombo.straight3;
    if (top == 2) return TriCombo.pair;
    return TriCombo.none;
  }
  if (top >= 3) return TriCombo.trips;
  if (bestRun >= 3) return TriCombo.straight3;
  if (top == 2) return TriCombo.pair;
  return TriCombo.none;
}

TriCombo colCombo(List<TriCard> cards) =>
    _combo([for (final c in cards) c.rank], isCol: true);

TriCombo rowCombo(List<TriCard> cards) =>
    _combo([for (final c in cards) c.rank], isCol: false);

double _mult(TriCombo c, {required bool isCol}) => isCol
    ? switch (c) {
        TriCombo.five => TriRules.colFive,
        TriCombo.quad => TriRules.colQuad,
        TriCombo.straight5 => TriRules.colStraight5,
        TriCombo.fullHouse => TriRules.colFull,
        TriCombo.trips => TriRules.colTrips,
        TriCombo.straight3 => TriRules.colStraight3,
        TriCombo.pair => TriRules.colPair,
        TriCombo.none => 1.0,
      }
    : switch (c) {
        TriCombo.trips => TriRules.rowTrips,
        TriCombo.straight3 => TriRules.rowStraight3,
        TriCombo.pair => TriRules.rowPair,
        _ => 1.0,
      };

/// 줄 점수 = 랭크 합 × 조합 배율 × (가득 찬 플러시면 플러시 배율).
double _lineScore(List<TriCard> cards, {required bool isCol}) {
  if (cards.isEmpty) return 0;
  final sum = cards.fold<int>(0, (a, c) => a + c.rank);
  var s = sum * _mult(_combo([for (final c in cards) c.rank], isCol: isCol),
      isCol: isCol);
  final slots = isCol ? TriRules.rows : TriRules.cols;
  if (cards.length == slots &&
      cards.map((c) => c.elem).toSet().length == 1) {
    s *= isCol ? TriRules.flushCol : TriRules.flushRow;
  }
  return s;
}

double colScore(List<TriCard> cards) => _lineScore(cards, isCol: true);
double rowScore(List<TriCard> cards) => _lineScore(cards, isCol: false);

/// 한 사람의 전장 — 열 3개, 각 열은 아래부터 쌓이는 스택(중력).
class TriBoard {
  final List<List<TriCard>> cols =
      List.generate(TriRules.cols, (_) => <TriCard>[]);

  bool get isFull => cols.every((c) => c.length >= TriRules.rows);

  bool canPlace(int c) => cols[c].length < TriRules.rows;

  List<int> get openCols =>
      [for (var c = 0; c < TriRules.cols; c++) if (canPlace(c)) c];

  /// 높이 [r]의 행(놓인 카드만).
  List<TriCard> row(int r) =>
      [for (final col in cols) if (col.length > r) col[r]];

  double get score {
    var s = cols.fold<double>(0, (a, c) => a + colScore(c));
    for (var r = 0; r < TriRules.rows; r++) {
      s += rowScore(row(r));
    }
    return s;
  }

  /// 카드 제거 — 위 카드는 아래로 떨어진다(리스트라 자동).
  TriCard removeAt(int c, int r) => cols[c].removeAt(r);
}

/// 지금 게임이 기다리는 행동.
enum TriPhase {
  /// 현재 플레이어의 본 행동(배치/공격/버리기) 대기. 훔쳐보기는 덤 행동.
  action,

  /// 공격 성공 → 방어막 배치 대기(양쪽 필드 아무 유효 칸).
  shield,

  /// 판 종료(양 보드 완성 또는 덱 소진).
  finished,
}

/// 한 판의 상태 기계. 플레이어 0 = 나(A), 1 = 상대(B).
///
/// 턴 흐름: [_beginTurn]이 드로+코인 지급 → 호출자는 [phase]에 맞춰
/// [place]/[attack]/[discard]([peek]는 덤) → 공격이면 [placeShield]까지.
class TriGame {
  TriGame({required int seed, this.current = 0}) : _rng = Random(seed) {
    _deck = [
      for (var copy = 0; copy < TriRules.copies; copy++)
        for (final e in TriElement.values)
          for (var v = 1; v <= TriRules.ranks; v++) TriCard(v, e),
    ]..shuffle(_rng);
    for (var i = 0; i < TriRules.startHand; i++) {
      for (final h in hands) {
        h.add(_deck.removeLast());
      }
    }
    _beginTurn();
  }

  final Random _rng;
  late final List<TriCard> _deck;
  final boards = [TriBoard(), TriBoard()];
  final hands = [<TriCard>[], <TriCard>[]];
  final coins = [TriRules.startCoins, TriRules.startCoins];
  final myTurns = [0, 0]; // 코인 수입 계산용

  int current;
  TriPhase phase = TriPhase.action;

  /// 공격 직후 배치 대기 중인 방어막.
  TriCard? pendingShield;

  int get deckLeft => _deck.length;
  bool get finished => phase == TriPhase.finished;

  TriBoard get myBoard => boards[current];
  TriBoard get oppBoard => boards[1 - current];

  void _beginTurn() {
    if (boards[0].isFull && boards[1].isFull) {
      _finish();
      return;
    }
    if (_deck.isEmpty) {
      _finish();
      return;
    }
    myTurns[current]++;
    if (myTurns[current] % TriRules.coinEveryMyTurns == 0) coins[current]++;
    hands[current].add(_deck.removeLast());
    phase = TriPhase.action;
  }

  void _finish() {
    phase = TriPhase.finished;
    // 판이 끝나면 전부 공개.
    for (final b in boards) {
      for (final col in b.cols) {
        for (final c in col) {
          c.faceDown = false;
        }
      }
    }
  }

  void _endTurn() {
    current = 1 - current;
    _beginTurn();
  }

  // ---- 조회 ----

  /// [player] 눈에 보이는 상대 카드인가(뒷면이면 훔쳐봤을 때만).
  bool visibleTo(int player, TriCard c) => !c.faceDown || c.peeked;

  /// [player]가 [rank]로 때릴 수 있는 상대 카드 위치들.
  List<(int col, int row)> attackTargets(int player, int rank) {
    final opp = boards[1 - player];
    return [
      for (var c = 0; c < TriRules.cols; c++)
        for (var r = 0; r < opp.cols[c].length; r++)
          if (!opp.cols[c][r].shield &&
              visibleTo(player, opp.cols[c][r]) &&
              opp.cols[c][r].rank == rank)
            (c, r),
    ];
  }

  /// 본 행동이 하나라도 있나(없으면 버리기만 가능).
  bool get hasAction {
    if (boards[current].openCols.isNotEmpty) return true;
    for (final h in hands[current]) {
      if (attackTargets(current, h.rank).isNotEmpty) return true;
    }
    return false;
  }

  // ---- 행동 ----

  /// 배치. [faceDown]이면 코인 1 소모.
  void place(int handIdx, int col, {bool faceDown = false}) {
    assert(phase == TriPhase.action);
    assert(boards[current].canPlace(col));
    final card = hands[current].removeAt(handIdx);
    if (faceDown) {
      assert(coins[current] >= TriRules.costFaceDown);
      coins[current] -= TriRules.costFaceDown;
      card.faceDown = true;
    }
    boards[current].cols[col].add(card);
    _endTurn();
  }

  /// 공격 — 내 [handIdx] 카드와 상대 (col,row) 카드의 랭크가 같아야 한다.
  /// 두 장 소멸 → 덱이 남았으면 방어막 드로([phase]가 [TriPhase.shield]로).
  void attack(int handIdx, int col, int row) {
    assert(phase == TriPhase.action);
    final target = boards[1 - current].cols[col][row];
    assert(!target.shield && visibleTo(current, target));
    assert(hands[current][handIdx].rank == target.rank);
    hands[current].removeAt(handIdx);
    boards[1 - current].removeAt(col, row);
    if (_deck.isEmpty) {
      _endTurn();
      return;
    }
    pendingShield = _deck.removeLast()..shield = true;
    phase = TriPhase.shield;
  }

  /// 방어막 배치 가능 칸 — (내 필드인가, 열).
  List<(bool own, int col)> shieldSlots() => [
        for (final c in boards[current].openCols) (true, c),
        for (final c in boards[1 - current].openCols) (false, c),
      ];

  /// 방어막 배치. 양쪽 다 만석이면 [col]에 관계없이 소각된다.
  void placeShield(bool ownField, int col) {
    assert(phase == TriPhase.shield);
    final board = boards[ownField ? current : 1 - current];
    if (board.canPlace(col)) {
      board.cols[col].add(pendingShield!);
    }
    pendingShield = null;
    _endTurn();
  }

  /// 훔쳐보기(덤 행동, 코인 1) — 상대 뒷면 카드를 나에게만 공개.
  void peek(int col, int row) {
    assert(phase == TriPhase.action);
    assert(coins[current] >= TriRules.costPeek);
    final c = boards[1 - current].cols[col][row];
    assert(c.faceDown && !c.peeked && !c.shield);
    coins[current] -= TriRules.costPeek;
    c.peeked = true;
  }

  /// 버리기 — 놓을 곳이 없을 때만(공격은 의무가 아니다).
  void discard(int handIdx) {
    assert(phase == TriPhase.action);
    assert(boards[current].openCols.isEmpty);
    hands[current].removeAt(handIdx);
    _endTurn();
  }

  /// 최종 점수 (0=A, 1=B).
  (double, double) get scores => (boards[0].score, boards[1].score);

  /// 승자: 0/1, 동점 -1. 판이 안 끝났으면 null.
  int? get winner {
    if (!finished) return null;
    final (a, b) = scores;
    return a > b ? 0 : (b > a ? 1 : -1);
  }
}

/// HP 매치 — 판을 반복, 진 쪽이 점수차만큼 깎인다.
class TriMatch {
  double hpA = TriRules.hp.toDouble();
  double hpB = TriRules.hp.toDouble();
  int games = 0;

  bool get over => hpA <= 0 || hpB <= 0;
  int? get matchWinner => !over ? null : (hpA <= 0 ? 1 : 0);

  /// 판 결과 반영 — (판 승자, 데미지) 반환.
  (int, double) applyGame(TriGame g) {
    games++;
    final (a, b) = g.scores;
    final net = (a - b).abs();
    if (a > b) hpB -= net;
    if (b > a) hpA -= net;
    return (g.winner!, net);
  }
}

/// 열의 낙관적 잠재력 — 봇의 방어막 투기 판단용(시뮬과 동일 휴리스틱).
double _colPotential(List<TriCard> cards) {
  final free = TriRules.rows - cards.length;
  final counts = <int, int>{};
  for (final c in cards) {
    counts[c.rank] = (counts[c.rank] ?? 0) + 1;
  }
  var topRank = 9, topN = 0;
  counts.forEach((r, n) {
    if (n > topN || (n == topN && r > topRank)) {
      topRank = r;
      topN = n;
    }
  });
  final ach = topN + free;
  final m = ach >= 5
      ? TriRules.colFive
      : ach == 4
          ? TriRules.colQuad
          : ach == 3
              ? TriRules.colTrips
              : ach == 2
                  ? TriRules.colPair
                  : 1.0;
  final sum = cards.fold<int>(0, (a, c) => a + c.rank);
  return (sum + free * max(topRank, 6)) * m;
}

/// 봇의 다음 수 — 화면이 한 스텝씩 실행·연출한다.
sealed class TriBotMove {
  const TriBotMove();
}

class BotAttack extends TriBotMove {
  const BotAttack(this.handIdx, this.col, this.row);
  final int handIdx, col, row;
}

class BotPlace extends TriBotMove {
  const BotPlace(this.handIdx, this.col, {required this.faceDown});
  final int handIdx, col;
  final bool faceDown;
}

class BotPeek extends TriBotMove {
  const BotPeek(this.col, this.row);
  final int col, row;
}

class BotShield extends TriBotMove {
  const BotShield(this.ownField, this.col);
  final bool ownField;
  final int col;
}

class BotDiscard extends TriBotMove {
  const BotDiscard(this.handIdx);
  final int handIdx;
}

/// 시뮬의 '스마트' 봇 이식 — 가치 공격 + 잠재력 비교 방어막 + 코어 뒷면.
class TriBot {
  const TriBot();

  TriBotMove choose(TriGame g) {
    final p = g.current;
    if (g.phase == TriPhase.shield) return _chooseShield(g);
    final opp = g.boards[1 - p];
    // 1) 가치 공격: 상대 조합 기여가 랭크×2 이상인 표적.
    (double, int, int, int)? best;
    for (var h = 0; h < g.hands[p].length; h++) {
      for (final (c, r) in g.attackTargets(p, g.hands[p][h].rank)) {
        final before = opp.score;
        final card = opp.removeAt(c, r);
        final worth = before - opp.score;
        opp.cols[c].insert(r, card);
        if (worth >= card.rank * 2 && (best == null || worth > best.$1)) {
          best = (worth, h, c, r);
        }
      }
    }
    if (best != null) return BotAttack(best.$2, best.$3, best.$4);
    // 2) 훔쳐보기: 때릴 게 없고 코인 여유가 있으면 정보 수집.
    if (g.coins[p] > 2) {
      final hidden = [
        for (var c = 0; c < TriRules.cols; c++)
          for (var r = 0; r < opp.cols[c].length; r++)
            if (opp.cols[c][r].faceDown &&
                !opp.cols[c][r].peeked &&
                !opp.cols[c][r].shield)
              (c, r),
      ];
      if (hidden.isNotEmpty) {
        final (c, r) = hidden[g._rng.nextInt(hidden.length)];
        return BotPeek(c, r);
      }
    }
    // 3) 배치: 즉시 점수 + 잠재력 증가가 최대인 (카드, 열).
    final mine = g.boards[p];
    (double, int, int)? bestPlace;
    for (var h = 0; h < g.hands[p].length; h++) {
      final card = g.hands[p][h];
      for (final c in mine.openCols) {
        final before = mine.score + 0.3 * _colPotential(mine.cols[c]);
        mine.cols[c].add(card);
        final gain =
            mine.score + 0.3 * _colPotential(mine.cols[c]) - before;
        mine.cols[c].removeLast();
        if (bestPlace == null || gain > bestPlace.$1) {
          bestPlace = (gain, h, c);
        }
      }
    }
    if (bestPlace != null) {
      final card = g.hands[p][bestPlace.$2];
      final core = g.boards[p].cols.any((col) =>
          col.any((x) => x.rank == card.rank));
      final fd = g.coins[p] > TriRules.costFaceDown &&
          (core || card.rank >= 8);
      return BotPlace(bestPlace.$2, bestPlace.$3, faceDown: fd);
    }
    return const BotDiscard(0);
  }

  TriBotMove _chooseShield(TriGame g) {
    final p = g.current;
    final s = g.pendingShield!;
    final mine = g.boards[p], opp = g.boards[1 - p];
    (double, int)? bestSelf;
    for (final c in mine.openCols) {
      final before = mine.score;
      mine.cols[c].add(s);
      final d = mine.score - before;
      mine.cols[c].removeLast();
      if (bestSelf == null || d > bestSelf.$1) bestSelf = (d, c);
    }
    (double, int)? bestHarass;
    for (final c in opp.openCols) {
      final cut = _colPotential(opp.cols[c]) -
          _colPotential([...opp.cols[c], s]);
      if (bestHarass == null || cut > bestHarass.$1) bestHarass = (cut, c);
    }
    if (bestHarass != null &&
        (bestSelf == null || bestHarass.$1 > bestSelf.$1)) {
      return BotShield(false, bestHarass.$2);
    }
    if (bestSelf != null) return BotShield(true, bestSelf.$2);
    // 양쪽 만석 — 소각.
    return const BotShield(true, 0);
  }
}
