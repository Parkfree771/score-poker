/// 스트라이크 모드 도메인 — 룰 정본은 `docs/STRIKE.md`.
///
/// 본편(스코어 포커)의 카드·족보·판정 위에 새 규칙을 얹은 실험 모드:
///  - 3줄×5칸, 각 줄은 **왼쪽부터 순서대로** 채운다
///  - 시작 손패 4장, 매 턴 덱에서 1장 **비공개 드로** (교대 턴)
///  - 배치: 앞면 무료 / **뒷면 = 칩 1** (뒷면은 상대에게 안 보이고 공격받지 않는다)
///  - 공격: 손패 랭크 == 상대 필드의 **보이는** 카드 랭크 → 두 장 모두 제거(왼쪽으로 당겨짐),
///    공격자는 보충 1장을 뽑는데 이것이 **방어막 카드**(공격 불가·피격 불가) —
///    양쪽 필드 아무 유효 칸에 놓을 수 있다(낮은 카드로 상대 족보 방해)
///  - 훔쳐보기: 칩 1로 상대 뒷면 1장을 나만 확인(턴 소모 없음)
///  - 종료: 양쪽 필드 완성 또는 덱 소진 → 본편 판정(3줄 중 2줄 승 / 총점차)
///
/// 수치는 시뮬(세션 스크래치 `strike_sim.py`, 52장 덱)로 검증:
/// 공격 4.3회/판, 뒷면 5~7회, 덱 소진 종료 17%.
///
/// UI·연출을 모른다.
library;

import 'dart:math';

import 'card.dart';
import 'hand.dart';
import 'scoring.dart';

/// 확정 수치 모음 — 튜닝은 여기서만 한다.
abstract final class StrikeRules {
  static const rows = 3, slots = 5;
  static const startHand = 4;
  static const chips = 4; // 판당 고정(보충 없음) — 본편 비공개권 감각
  static const costHide = 1;
  static const costPeek = 1;
}

/// 필드 위의 카드 + 상태.
class StrikeCard {
  StrikeCard(this.card);
  final PlayingCard card;

  /// 뒷면 배치(칩 1) — 주인이 아닌 쪽에겐 안 보이고, 공격 표적이 안 된다.
  bool faceDown = false;

  /// 상대가 칩으로 훔쳐봄 — 훔쳐본 쪽에겐 공개 취급(공격 가능해진다).
  bool peeked = false;

  /// 방어막(공격 보충 카드) — 공격에 못 쓰고, 공격받지도 않는다.
  bool shield = false;

  @override
  String toString() => '${card.label}${shield ? '*' : (faceDown ? '?' : '')}';
}

/// 지금 게임이 기다리는 행동.
enum StrikePhase {
  /// 현재 플레이어의 본 행동(배치/공격/버리기) 대기. 훔쳐보기는 덤 행동.
  action,

  /// 공격 성공 → 방어막 배치 대기(양쪽 필드 아무 유효 칸).
  shield,

  /// 판 종료.
  finished,
}

/// 한 판의 상태 기계. 플레이어 0 = 나, 1 = 상대.
///
/// 턴 흐름: 턴 시작에 자동 드로 → [phase]에 맞춰 [place]/[attack]/[discard]
/// ([peek]는 턴 소모 없음) → 공격이면 [placeShield]까지가 한 턴.
class StrikeGame {
  StrikeGame({required int seed, this.current = 0}) {
    final rng = Random(seed);
    _deck = [
      for (final r in Ranks.all)
        for (final s in Suit.values) PlayingCard(r, s),
    ]..shuffle(rng);
    for (var i = 0; i < StrikeRules.startHand; i++) {
      for (final h in hands) {
        h.add(_deck.removeLast());
      }
    }
    _beginTurn();
  }

  late final List<PlayingCard> _deck;

  /// [player][row] — 각 줄은 왼쪽부터 채워진 카드 목록.
  final fields = [
    List.generate(StrikeRules.rows, (_) => <StrikeCard>[]),
    List.generate(StrikeRules.rows, (_) => <StrikeCard>[]),
  ];
  final hands = [<PlayingCard>[], <PlayingCard>[]];
  final chips = [StrikeRules.chips, StrikeRules.chips];

  int current;
  StrikePhase phase = StrikePhase.action;

  /// 공격 직후 배치 대기 중인 방어막.
  StrikeCard? pendingShield;

  /// 이번 턴에 방금 뽑은 카드(연출용 — 손패의 마지막 장).
  PlayingCard? lastDrawn;

  int get deckLeft => _deck.length;
  bool get finished => phase == StrikePhase.finished;

  bool isFull(int player) =>
      fields[player].every((r) => r.length >= StrikeRules.slots);

  /// [player]의 아직 안 찬 줄들.
  List<int> openRows(int player) => [
        for (var r = 0; r < StrikeRules.rows; r++)
          if (fields[player][r].length < StrikeRules.slots) r
      ];

  void _beginTurn() {
    if ((isFull(0) && isFull(1)) || _deck.isEmpty) {
      _finish();
      return;
    }
    lastDrawn = _deck.removeLast();
    hands[current].add(lastDrawn!);
    phase = StrikePhase.action;
  }

  void _finish() {
    phase = StrikePhase.finished;
    for (final f in fields) {
      for (final row in f) {
        for (final c in row) {
          c.faceDown = false; // 정산 — 전부 공개
        }
      }
    }
  }

  void _endTurn() {
    current = 1 - current;
    _beginTurn();
  }

  // ---- 조회 ----

  /// [owner]의 카드 [c]가 [viewer] 눈에 공개인가 — 주인은 항상 보고,
  /// 남은 앞면이거나 훔쳐봤을 때만 본다.
  bool visibleTo(int viewer, int owner, StrikeCard c) =>
      viewer == owner || !c.faceDown || c.peeked;

  /// [player]가 [rank]로 때릴 수 있는 상대 카드 위치들 (row, index).
  List<(int, int)> attackTargets(int player, int rank) {
    final opp = fields[1 - player];
    return [
      for (var r = 0; r < StrikeRules.rows; r++)
        for (var i = 0; i < opp[r].length; i++)
          if (!opp[r][i].shield &&
              visibleTo(player, 1 - player, opp[r][i]) &&
              opp[r][i].card.rank == rank)
            (r, i),
    ];
  }

  // ---- 행동 ----

  /// 배치 — [row]의 다음 칸(왼쪽부터). [hidden]이면 칩 1 소모.
  void place(int handIdx, int row, {bool hidden = false}) {
    assert(phase == StrikePhase.action);
    assert(fields[current][row].length < StrikeRules.slots);
    final card = StrikeCard(hands[current].removeAt(handIdx));
    if (hidden) {
      assert(chips[current] >= StrikeRules.costHide);
      chips[current] -= StrikeRules.costHide;
      card.faceDown = true;
    }
    fields[current][row].add(card);
    _endTurn();
  }

  /// 공격 — 손패 [handIdx]와 상대 (row, idx) 카드의 랭크가 같아야 한다.
  /// 두 장 소멸(오른쪽 카드는 왼쪽으로 당겨짐) → 덱이 남았으면 방어막 드로.
  void attack(int handIdx, int row, int idx) {
    assert(phase == StrikePhase.action);
    final target = fields[1 - current][row][idx];
    assert(!target.shield && visibleTo(current, 1 - current, target));
    assert(hands[current][handIdx].rank == target.card.rank);
    hands[current].removeAt(handIdx);
    fields[1 - current][row].removeAt(idx);
    if (_deck.isEmpty) {
      _endTurn();
      return;
    }
    pendingShield = StrikeCard(_deck.removeLast())..shield = true;
    phase = StrikePhase.shield;
  }

  /// 방어막 배치 가능한 (내 필드인가, 줄) 목록.
  List<(bool own, int row)> shieldSlots() => [
        for (final r in openRows(current)) (true, r),
        for (final r in openRows(1 - current)) (false, r),
      ];

  /// 방어막 배치. 양쪽 다 만석이면 소각된다.
  void placeShield(bool ownField, int row) {
    assert(phase == StrikePhase.shield);
    final field = fields[ownField ? current : 1 - current];
    if (field[row].length < StrikeRules.slots) {
      field[row].add(pendingShield!);
    }
    pendingShield = null;
    _endTurn();
  }

  /// 훔쳐보기(턴 소모 없음, 칩 1) — 상대 뒷면 카드를 나에게만 공개.
  void peek(int row, int idx) {
    assert(phase == StrikePhase.action);
    assert(chips[current] >= StrikeRules.costPeek);
    final c = fields[1 - current][row][idx];
    assert(c.faceDown && !c.peeked && !c.shield);
    chips[current] -= StrikeRules.costPeek;
    c.peeked = true;
  }

  /// 버리기 — 내 필드가 만석일 때만(공격은 의무가 아니다).
  void discard(int handIdx) {
    assert(phase == StrikePhase.action);
    assert(openRows(current).isEmpty);
    hands[current].removeAt(handIdx);
    _endTurn();
  }

  // ---- 판정 ----

  List<List<PlayingCard>> rowsOf(int player) =>
      [for (final r in fields[player]) [for (final c in r) c.card]];

  /// 본편 판정(3줄 중 2줄 승 / 총점차). 나(0) 기준.
  MatchResult judge() => judgeMatch(rowsOf(0), rowsOf(1));
}

// ---- 봇 ------------------------------------------------------------------

/// 봇의 다음 수 — 화면이 한 스텝씩 실행·연출한다.
sealed class StrikeMove {
  const StrikeMove();
}

class MoveAttack extends StrikeMove {
  const MoveAttack(this.handIdx, this.row, this.idx);
  final int handIdx, row, idx;
}

class MovePlace extends StrikeMove {
  const MovePlace(this.handIdx, this.row, {required this.hidden});
  final int handIdx, row;
  final bool hidden;
}

class MovePeek extends StrikeMove {
  const MovePeek(this.row, this.idx);
  final int row, idx;
}

class MoveShield extends StrikeMove {
  const MoveShield(this.ownField, this.row);
  final bool ownField;
  final int row;
}

class MoveDiscard extends StrikeMove {
  const MoveDiscard(this.handIdx);
  final int handIdx;
}

/// 족보 스칼라 — 카테고리가 지배하고 동급은 점수로 가른다(시뮬과 동일).
int _scalar(List<PlayingCard> cards) {
  final h = evaluateHand(cards);
  return h.category.index * 1000 + h.score;
}

/// 줄의 낙관적 잠재력(그룹 위주 근사) — 방어막 투기 판단용.
int _rowPotential(List<PlayingCard> cards) {
  final free = StrikeRules.slots - cards.length;
  final counts = <int, int>{};
  for (final c in cards) {
    counts[c.rank] = (counts[c.rank] ?? 0) + 1;
  }
  final top = counts.values.fold(0, max);
  final ach = min(4, top + free);
  final cat = ach >= 4
      ? HandCategory.fourOfAKind
      : ach == 3
          ? HandCategory.threeOfAKind
          : ach == 2
              ? HandCategory.onePair
              : HandCategory.highCard;
  return cat.index * 1000 + cards.fold(0, (a, c) => a + c.value);
}

/// 시뮬의 '가치 공격' 봇: 족보를 부수는 공격만 하고, 방어막은 내 이득과
/// 상대 잠재력 파괴를 비교해 놓고, 페어 코어·고랭크는 칩으로 숨긴다.
class StrikeBot {
  const StrikeBot({this.rng});

  final Random? rng;

  StrikeMove choose(StrikeGame g) {
    final p = g.current;
    if (g.phase == StrikePhase.shield) return _chooseShield(g);
    final opp = g.fields[1 - p];
    // 1) 가치 공격 — 상대 줄의 족보 등급을 실제로 깎는 표적만.
    (int, int, int, int)? best;
    for (var h = 0; h < g.hands[p].length; h++) {
      for (final (r, i) in g.attackTargets(p, g.hands[p][h].rank)) {
        final row = [for (final c in opp[r]) c.card];
        final before = _scalar(row);
        row.removeAt(i);
        final worth = before - _scalar(row);
        if (worth >= 900 && (best == null || worth > best.$1)) {
          best = (worth, h, r, i);
        }
      }
    }
    if (best != null) return MoveAttack(best.$2, best.$3, best.$4);
    // 2) 훔쳐보기 — 때릴 게 없고 칩 여유가 있으면 정보 수집.
    if (g.chips[p] > 2) {
      final hidden = [
        for (var r = 0; r < StrikeRules.rows; r++)
          for (var i = 0; i < opp[r].length; i++)
            if (opp[r][i].faceDown && !opp[r][i].peeked && !opp[r][i].shield)
              (r, i),
      ];
      if (hidden.isNotEmpty) {
        final (r, i) = hidden[(rng ?? Random()).nextInt(hidden.length)];
        return MovePeek(r, i);
      }
    }
    // 3) 배치 — 즉시 족보 + 잠재력 증가가 최대인 (카드, 줄).
    final mine = g.fields[p];
    (double, int, int)? bestPlace;
    for (var h = 0; h < g.hands[p].length; h++) {
      final card = g.hands[p][h];
      for (final r in g.openRows(p)) {
        final row = [for (final c in mine[r]) c.card];
        final gain = (_scalar([...row, card]) - _scalar(row)) +
            0.3 * (_rowPotential([...row, card]) - _rowPotential(row));
        if (bestPlace == null || gain > bestPlace.$1) {
          bestPlace = (gain, h, r);
        }
      }
    }
    if (bestPlace != null) {
      final card = g.hands[p][bestPlace.$2];
      final core = g.fields[p]
          .any((row) => row.any((x) => x.card.rank == card.rank));
      final hide = g.chips[p] >= StrikeRules.costHide &&
          (core || card.rank >= Ranks.jack);
      return MovePlace(bestPlace.$2, bestPlace.$3, hidden: hide);
    }
    return const MoveDiscard(0);
  }

  StrikeMove _chooseShield(StrikeGame g) {
    final p = g.current;
    final s = g.pendingShield!.card;
    (int, int)? bestSelf;
    for (final r in g.openRows(p)) {
      final row = [for (final c in g.fields[p][r]) c.card];
      final d = _scalar([...row, s]) - _scalar(row);
      if (bestSelf == null || d > bestSelf.$1) bestSelf = (d, r);
    }
    (int, int)? bestHarass;
    for (final r in g.openRows(1 - p)) {
      final row = [for (final c in g.fields[1 - p][r]) c.card];
      final cut = _rowPotential(row) - _rowPotential([...row, s]);
      if (bestHarass == null || cut > bestHarass.$1) bestHarass = (cut, r);
    }
    if (bestHarass != null &&
        (bestSelf == null || bestHarass.$1 > bestSelf.$1)) {
      return MoveShield(false, bestHarass.$2);
    }
    if (bestSelf != null) return MoveShield(true, bestSelf.$2);
    return const MoveShield(true, 0); // 양쪽 만석 — 소각
  }
}
