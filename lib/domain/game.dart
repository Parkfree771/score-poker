import 'board.dart';
import 'card.dart';
import 'deck.dart';
import 'scoring.dart';

export 'board.dart';

/// 스코어 포커 규칙 엔진 v4 "스트라이크" (순수 Dart). UI/네트워크와 분리.
///
/// 판은 3줄 × 5칸 vs 3줄 × 5칸. 같은 번호 줄끼리 족보로 겨루고 **2줄을 이기면 승리**한다.
/// v3(동시 라운드·공개)에서 **교대 턴 + 공격** 구조로 전면 개편:
///
/// - R1) **턴제 드로**: 시작 손패 [startHand]장. 매 턴 시작에 덱에서 1장 **비공개로**
///       뽑는다(교대 턴). 내 손이 계속 5장으로 유지된다.
/// - R2) **순서 배치**: 카드는 자기 줄의 **왼쪽부터 차례로** 놓인다(1번 칸을 채워야
///       2번 칸). 기본은 **앞면**(상대에게 공개), **뒷면 배치 = 칩 1**.
/// - R3) **공격(스트라이크)**: 손패의 랭크 = 상대 필드의 **보이는** 카드 랭크면 그 카드를
///       지목해 **두 장 모두 제거**한다(오른쪽 카드가 왼쪽으로 당겨진다). 공격자는 보충
///       1장을 뽑는데 이것이 **방어막 카드**다(R4).
/// - R4) **방어막**: 공격 보충 카드는 공격에 못 쓰고 공격받지도 않지만, **양쪽 필드
///       아무 유효 칸**에 놓을 수 있다 — 내 빈칸을 채우거나 상대 줄에 낮은 카드를 꽂아
///       족보를 방해한다.
/// - R5) **칩 [veilsPerMatch]개**(판 전체, 겸용): 뒷면 배치, 또는 **훔쳐보기**(상대 뒷면
///       1장을 나만 확인 — 이후 내가 공격할 수 있다. 턴 소모 없음).
/// - R6) **조커 [jokers]장**: 내 빈 칸에 원하는 카드로 놓는 **와일드**([placeWild],
///       뒷면 가능). 조커로 공격할 수는 없다.
/// - R7) 양쪽 필드 완성 또는 덱 소진 시 전 카드 공개 → 3줄 2승(동수면 총점) 정산.
///
/// **부스트**(상점 상품, 판당 1개 — [ScoreGame.deal]의 `boostFor`): 칩 +1(4→5),
/// **손패 스왑** 1회(내 턴에 손 전체를 새로 받는다. 한 수라도 뒀으면 못 쓴다).
///
/// 수치 근거: 시작 패 4장·칩 4개는 52장 덱 시뮬(strike_sim.py)로 확정 —
/// 공격 4.3회/판, 패 6장은 덱 소진 종료 55%로 탈락. 자세한 표는 docs/RULES.md §시뮬.
class ScoreGame {
  ScoreGame._(this._deck);

  static const int rowsN = kRows;
  static const int colsN = kCols;
  static const int startHand = 4;
  static const int veilsPerMatch = 4;
  static const int jokers = 2;

  /// 덱(52+조커)으로 시작, 각자 [startHand]장 딜, 선턴(p0)이 첫 드로까지 받는다.
  factory ScoreGame.deal({int? seed, PlayerId? boostFor, int jokers = ScoreGame.jokers}) {
    final g = ScoreGame._(Deck.shuffled(seed: seed, jokers: jokers));
    if (boostFor != null) {
      g.veilLeft[boostFor] = veilsPerMatch + 1;
      g.swapLeft[boostFor] = 1;
      g._boosted[boostFor] = true;
    }
    for (final p in PlayerId.values) {
      g.hands[p]!.addAll(g._deck.draw(startHand));
    }
    g._beginTurn();
    return g;
  }

  /// [p]의 판 전체 칩 최대치(부스트면 5). 레일의 칩 소켓 수.
  int veilsMax(PlayerId p) => _boosted[p]! ? veilsPerMatch + 1 : veilsPerMatch;

  bool isBoosted(PlayerId p) => _boosted[p]!;

  /// 남은 손패 스왑 횟수(부스트 판만 1, 아니면 0).
  late final Map<PlayerId, int> swapLeft = {
    for (final p in PlayerId.values) p: 0,
  };
  late final Map<PlayerId, bool> _boosted = {
    for (final p in PlayerId.values) p: false,
  };

  /// [p]가 이 판에서 카드를 한 장이라도 놓거나 공격했는가(스왑·부스트 환불 판단용).
  late final Map<PlayerId, bool> acted = {
    for (final p in PlayerId.values) p: false,
  };

  /// 스왑 가능? 부스트가 남아 있고, 내 턴이고, 아직 **한 수도 안 뒀고**, 덱이 넉넉할 때.
  bool canSwap(PlayerId p) =>
      swapLeft[p]! > 0 &&
      turn == p &&
      phase == TurnPhase.action &&
      !acted[p]! &&
      _deck.remaining >= hands[p]!.length;

  /// 손패 **전부**를 새로 받는다. 새 카드 목록을 돌려준다.
  List<PlayingCard> swap(PlayerId p) {
    if (!canSwap(p)) throw StateError('지금은 스왑할 수 없다');
    final old = List.of(hands[p]!);
    hands[p]!.clear();
    final fresh = _deck.draw(old.length);
    hands[p]!.addAll(fresh);
    swapLeft[p] = swapLeft[p]! - 1;
    return fresh;
  }

  final Deck _deck;
  int get deckRemaining => _deck.remaining;

  /// 손패(시작 4장 + 매 턴 1장 드로, 쓰면 빠진다).
  final Map<PlayerId, List<PlayingCard>> hands = {
    PlayerId.p0: [],
    PlayerId.p1: [],
  };

  /// fields[p][row][col] — null이면 빈 칸.
  final Map<PlayerId, List<List<VeiledSlot?>>> fields = {
    for (final p in PlayerId.values)
      p: [
        for (var r = 0; r < rowsN; r++) List<VeiledSlot?>.filled(colsN, null),
      ],
  };

  /// 남은 칩(뒷면 배치/훔쳐보기 겸용). 부스트 판은 5로 시작한다.
  final Map<PlayerId, int> veilLeft = {
    PlayerId.p0: veilsPerMatch,
    PlayerId.p1: veilsPerMatch,
  };

  /// 지금 누구의 턴인가.
  PlayerId turn = PlayerId.p0;

  /// 턴이 기다리는 행동.
  TurnPhase phase = TurnPhase.action;

  /// 공격 직후 배치를 기다리는 방어막 카드(공격자가 놓는다).
  PlayingCard? pendingShield;

  /// 이번 턴 시작에 뽑은 카드(연출용 — 손패의 마지막 장).
  PlayingCard? lastDrawn;

  bool get isFinished => phase == TurnPhase.finished;

  // ---- 턴 회전 ----

  void _beginTurn() {
    if ((fieldFull(PlayerId.p0) && fieldFull(PlayerId.p1)) || _deck.isEmpty) {
      phase = TurnPhase.finished;
      return;
    }
    lastDrawn = _deck.drawOne();
    hands[turn]!.add(lastDrawn!);
    phase = TurnPhase.action;
  }

  void _endTurn() {
    turn = turn.other;
    _beginTurn();
  }

  // ---- 조회 ----

  bool fieldFull(PlayerId p) =>
      fields[p]!.every((row) => row.every((s) => s != null));

  /// [p]의 [row]에서 다음에 채워질 칸(왼쪽부터). 꽉 찼으면 -1.
  int nextCol(PlayerId p, int row) {
    for (var c = 0; c < colsN; c++) {
      if (fields[p]![row][c] == null) return c;
    }
    return -1;
  }

  /// [p]의 아직 안 찬 줄들.
  List<int> openRows(PlayerId p) =>
      [for (var r = 0; r < rowsN; r++) if (nextCol(p, r) >= 0) r];

  /// [owner]의 칸 [s]가 [viewer] 눈에 보이는가 —
  /// 주인은 항상, 남은 앞면이거나 훔쳐봤을 때만.
  bool visibleTo(PlayerId viewer, PlayerId owner, VeiledSlot s) =>
      viewer == owner || s.faceUp || s.peeked;

  /// [p]가 [rank]로 때릴 수 있는 상대 카드 위치들.
  /// 방어막은 못 때리고, 뒷면은 훔쳐봤을 때만 보인다.
  List<(int, int)> attackTargets(PlayerId p, int rank) {
    final opp = p.other;
    return [
      for (var r = 0; r < rowsN; r++)
        for (var c = 0; c < colsN; c++)
          if (fields[opp]![r][c] case final s?
              when !s.shield && visibleTo(p, opp, s) && s.card.rank == rank)
            (r, c),
    ];
  }

  // ---- 행동 (전부 [turn]의 플레이어만) ----

  void _checkAction(PlayerId p) {
    if (phase != TurnPhase.action) throw StateError('지금은 본 행동 차례가 아니다');
    if (turn != p) throw StateError('내 턴이 아니다');
  }

  /// 배치 — [row]의 다음 칸(왼쪽부터). [hidden]이면 칩 1 소모(뒷면).
  void place(PlayerId p, int handIndex, int row, {bool hidden = false}) {
    if (hands[p]![handIndex].isJoker) throw StateError('조커는 카드를 정해서 놓는다');
    _placeSlot(p, handIndex, row, hands[p]![handIndex], wild: false, hidden: hidden);
  }

  /// 조커를 내 줄에 [as] 카드로 놓는다(와일드).
  void placeWild(PlayerId p, int handIndex, int row, PlayingCard as,
      {bool hidden = false}) {
    if (!hands[p]![handIndex].isJoker) throw StateError('조커가 아니다');
    if (as.isJoker) throw StateError('조커를 조커로 지정할 수 없다');
    _placeSlot(p, handIndex, row, as, wild: true, hidden: hidden);
  }

  void _placeSlot(PlayerId p, int handIndex, int row, PlayingCard card,
      {required bool wild, required bool hidden}) {
    _checkAction(p);
    final col = nextCol(p, row);
    if (col < 0) throw StateError('그 줄은 가득 찼다');
    if (hidden) {
      if (veilLeft[p]! <= 0) throw StateError('칩이 없다');
      veilLeft[p] = veilLeft[p]! - 1;
    }
    hands[p]!.removeAt(handIndex);
    fields[p]![row][col] = VeiledSlot(card, faceUp: !hidden, wild: wild);
    acted[p] = true;
    _endTurn();
  }

  /// 공격 — 손패 [handIndex]와 상대 ([row],[col]) 카드의 랭크가 같아야 한다.
  /// 두 장 모두 제거(오른쪽 카드는 왼쪽으로 당겨짐) → 덱이 남았으면 방어막 드로.
  /// 제거된 상대 카드를 돌려준다(연출용).
  PlayingCard attack(PlayerId p, int handIndex, int row, int col) {
    _checkAction(p);
    final atk = hands[p]![handIndex];
    if (atk.isJoker) throw StateError('조커로는 공격할 수 없다');
    final target = fields[p.other]![row][col];
    if (target == null) throw StateError('빈 칸이다');
    if (target.shield) throw StateError('방어막은 공격할 수 없다');
    if (!visibleTo(p, p.other, target)) throw StateError('안 보이는 카드다');
    if (target.card.rank != atk.rank) throw StateError('랭크가 다르다');
    hands[p]!.removeAt(handIndex);
    _collapse(p.other, row, col);
    acted[p] = true;
    final shield = _deck.drawOne();
    if (shield == null) {
      _endTurn();
    } else {
      pendingShield = shield;
      phase = TurnPhase.shield;
    }
    return target.card;
  }

  /// [row]에서 [col]을 제거하고 오른쪽 카드들을 한 칸씩 왼쪽으로 당긴다.
  void _collapse(PlayerId p, int row, int col) {
    final cells = fields[p]![row];
    for (var c = col; c < colsN - 1; c++) {
      cells[c] = cells[c + 1];
    }
    cells[colsN - 1] = null;
  }

  /// 방어막 배치 가능한 (내 필드인가, 줄) 목록. 비어 있으면 소각뿐이다.
  List<(bool own, int row)> shieldSlots() => [
        for (final r in openRows(turn)) (true, r),
        for (final r in openRows(turn.other)) (false, r),
      ];

  /// 방어막 배치 — 양쪽 필드 아무 유효 줄. 양쪽 다 만석이면 [burnShield]로 소각한다.
  /// 방어막은 항상 **앞면**이고(정보로서 공정), 공격받지 않는다.
  void placeShield(PlayerId p, bool ownField, int row) {
    if (phase != TurnPhase.shield || turn != p) throw StateError('방어막 차례가 아니다');
    final owner = ownField ? p : p.other;
    final col = nextCol(owner, row);
    if (col < 0) throw StateError('그 줄은 가득 찼다');
    fields[owner]![row][col] = VeiledSlot(pendingShield!, faceUp: true, shield: true);
    pendingShield = null;
    _endTurn();
  }

  /// 놓을 곳이 아예 없을 때 방어막을 소각한다.
  void burnShield(PlayerId p) {
    if (phase != TurnPhase.shield || turn != p) throw StateError('방어막 차례가 아니다');
    if (shieldSlots().isNotEmpty) throw StateError('놓을 곳이 있으면 소각할 수 없다');
    pendingShield = null;
    _endTurn();
  }

  /// 훔쳐보기(턴 소모 없음, 칩 1) — 상대 뒷면 카드를 나만 확인.
  /// 흔적([VeiledSlot.peeked])은 양쪽 다 보인다.
  void peek(PlayerId p, int row, int col) {
    _checkAction(p);
    if (veilLeft[p]! <= 0) throw StateError('칩이 없다');
    final s = fields[p.other]![row][col];
    if (s == null || s.faceUp || s.peeked || s.shield) {
      throw StateError('훔쳐볼 카드가 아니다');
    }
    s.peeked = true;
    veilLeft[p] = veilLeft[p]! - 1;
  }

  /// 버리기 — 내 필드가 만석일 때만(공격은 의무가 아니다).
  void discard(PlayerId p, int handIndex) {
    _checkAction(p);
    if (openRows(p).isNotEmpty) throw StateError('놓을 곳이 있으면 버릴 수 없다');
    hands[p]!.removeAt(handIndex);
    _endTurn();
  }

  // ---- 정산 ----

  /// 최종 정산 전 — 아직 숨겨진 카드 전부 공개. 좌표 목록을 돌려준다.
  List<(PlayerId, int, int)> revealAll() {
    final flipped = <(PlayerId, int, int)>[];
    for (final p in PlayerId.values) {
      for (var r = 0; r < rowsN; r++) {
        for (var c = 0; c < colsN; c++) {
          final s = fields[p]![r][c];
          if (s != null && !s.faceUp) {
            s.faceUp = true;
            flipped.add((p, r, c));
          }
        }
      }
    }
    return flipped;
  }

  /// 3줄 2승(동수면 총점)으로 정산한다. [perspective] 기준.
  MatchResult judge([PlayerId perspective = PlayerId.p0]) => judgeMatch(
        allRows(perspective),
        allRows(perspective.other),
      );

  /// [p]의 세 줄 — 숨김 여부와 무관한 **전체 정보**(최종 정산·자기 판단용).
  List<List<PlayingCard>> allRows(PlayerId p) => [
        for (var r = 0; r < rowsN; r++)
          [
            for (var c = 0; c < colsN; c++)
              if (fields[p]![r][c] != null) fields[p]![r][c]!.card,
          ],
      ];

  /// [viewer] 눈에 보이는 [p]의 줄 — 라이브 점수 표시용(숨긴 정보는 새지 않는다).
  List<PlayingCard> knownRow(PlayerId viewer, PlayerId p, int row) => [
        for (var c = 0; c < colsN; c++)
          if (fields[p]![row][c] case final s? when visibleTo(viewer, p, s))
            s.card,
      ];

  /// **공개된 카드만으로** 본 줄 대결 상태(양쪽 공통 정보).
  LineOutcome publicLine(PlayerId viewer, int row) =>
      compareLine(knownRow(viewer, viewer, row), knownRow(viewer, viewer.other, row));

  List<PlayingCard> publicRow(PlayerId p, int row) => [
        for (var c = 0; c < colsN; c++)
          if (fields[p]![row][c] case final s? when s.faceUp) s.card,
      ];

  /// [p] 필드에서 아직 숨겨져 있는 좌표들.
  List<(int, int)> hiddenOf(PlayerId p) => [
        for (var r = 0; r < rowsN; r++)
          for (var c = 0; c < colsN; c++)
            if (fields[p]![r][c] case final s? when !s.faceUp) (r, c),
      ];

  /// 보드 위젯에 넘길 형태(칸의 카드 + 주인). 빈 칸이면 null.
  PlacedCard? cellAt(PlayerId p, int row, int col) {
    final s = fields[p]![row][col];
    return s == null ? null : PlacedCard(s.card, p);
  }
}

/// 턴이 기다리는 행동.
enum TurnPhase {
  /// 본 행동(배치/공격/버리기) 대기. 훔쳐보기는 턴 소모 없는 덤 행동.
  action,

  /// 공격 성공 → 방어막 배치 대기.
  shield,

  /// 판 종료.
  finished,
}

/// 필드 한 칸: 카드 + 상태.
/// [wild]는 주인이 조커로 지정해 놓은 카드, [shield]는 공격 보충 카드(피격 불가),
/// [peeked]는 상대가 칩으로 훔쳐본 뒷면 카드(훔쳐본 쪽에겐 공개 취급).
class VeiledSlot {
  VeiledSlot(this.card,
      {this.faceUp = false, this.wild = false, this.shield = false});
  final PlayingCard card;
  bool faceUp;
  bool peeked = false;
  final bool wild;
  final bool shield;

  /// 조커가 관여한 칸(와일드) — 카드가 조커 얼굴로 그려진다.
  bool get jokered => wild;
}
