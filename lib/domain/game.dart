import 'card.dart';
import 'deck.dart';
import 'scoring.dart';

/// 게임 규칙 엔진 (순수 Dart). UI/네트워크와 분리되어 테스트로 검증 가능.
///
/// 규칙 v2 (GAME_DESIGN.md):
/// - A1) **매 턴 보충**: 턴 시작에 손패가 [kHandSize]장이 되도록 덱에서 뽑는다.
///       (v1의 "시작 5장 소진 후 드로우" 방식은 손패가 1장으로 고정돼 선택지가 없었다)
/// - A2) **공격 카드**: 처음 받은 손패에만 공격 표식([PlayingCard.isAttacker])이 붙는다.
///       상대 카드를 빼앗는 공격은 그 카드(또는 조커)로만 가능 → 공격 횟수가 자연히 제한된다.
///       공격 카드를 그냥 배치하면 공격력을 잃는다(아껴 둘수록 배치 선택지가 줄어드는 상충).
/// - A3) **공격 = 빼앗기**: 같은 숫자로 상대 카드를 뽑아 **내 필드 빈 칸에 놓고 쉴드로 고정**한다.
///       내 필드에 빈 칸이 없으면 공격할 수 없다. 사용한 공격 카드는 버려진다.
///       · 일반 공격 카드(rank R): 상대의 **일반 카드 중 rank R** 만.
///       · 조커: 상대의 **모든 카드**(쉴드/조커 배치 포함).
///       · 빼앗아 온 카드는 쉴드가 되어 되빼앗기지 않는다(무한 되뺏기 방지).
/// - A4) **보상**: 공격에 성공하면 그 턴에 **배치를 한 번 더** 할 수 있다([pendingBonus]).
///       보너스로는 공격할 수 없다(연쇄 금지). 놓을 곳이 없으면 자동으로 넘어간다.
/// - A5) 조커 배치는 **자기 필드에만**(숫자+슈트 지정). 쉴드는 자기/상대 필드 모두 가능.
/// - A6) 종료: 양측 폴드 / 30칸 가득 / 활성 플레이어 모두 둘 수 없음.
/// - A7) 폴드: 폴드한 쪽은 더 이상 턴을 받지 않음. 상대는 계속 진행.
/// - A8) **토큰 행동**([declareShield]/[markAttacker]): 상점에서 파는 아이템의 규칙적 실체.
///       턴을 소모하지 않지만 **판당 사용 횟수 상한**([GameRules])이 도메인에서 강제된다.
///       상한을 UI에만 두면 뚫린다 — 온라인 대전에서는 서버가 이 엔진으로 판정한다.

enum PlayerId { p0, p1 }

extension PlayerIdX on PlayerId {
  PlayerId get other => this == PlayerId.p0 ? PlayerId.p1 : PlayerId.p0;
}

enum GamePhase { awaitingReveal, playing, finished }

/// 규칙 위반의 종류. **도메인은 사용자 문구를 갖지 않는다** — 화면에 보일 문장은
/// UI 레이어에서 현재 로케일로 번역한다(`lib/ui/move_error_text.dart`).
enum MoveError {
  notPlaying, // 플레이 단계가 아님
  playerFolded, // 폴드한 플레이어
  alreadyRevealed, // 선공이 이미 결정됨
  badHandIndex, // 손패 인덱스 범위 밖
  badCell, // 칸 좌표 범위 밖
  cellOccupied, // 이미 카드가 있는 칸
  jokerOwnFieldOnly, // 조커는 자기 필드에만
  jokerNeedsDesignation, // 조커는 숫자+슈트 지정 필요
  normalOwnFieldOnly, // 일반 카드는 자기 필드에만
  attackOncePerTurn, // 보너스 배치 중에는 공격 불가
  shieldCannotAttack, // 쉴드 카드로는 공격 불가
  attackerCardRequired, // 공격 표식/조커가 아님
  noTargetCard, // 빼앗을 카드가 없음
  needJokerToTakeShield, // 쉴드/조커 카드는 조커로만
  rankMismatch, // 같은 숫자가 아님
  needEmptyCellForSteal, // 빼앗은 카드를 놓을 빈 칸 없음
  notBonusTurn, // 보너스 배치 차례가 아님
  tokenExhausted, // 이 판의 토큰 사용 횟수를 다 씀
  tokenNoCardHere, // 토큰을 쓸 칸에 카드가 없음
  shieldTargetNotEligible, // 이미 빼앗기지 않는 카드(쉴드/조커)
  attackMarkNotEligible, // 이미 공격할 수 있는 카드(또는 쉴드 카드)
}

/// 예외: 규칙 위반 행동. [error]로 종류를 구분한다.
class IllegalMove implements Exception {
  IllegalMove(this.error);
  final MoveError error;
  @override
  String toString() => 'IllegalMove(${error.name})';
}

/// 한 판에서 **토큰으로 얻을 수 있는 이득의 상한**.
///
/// 상한을 여기(도메인)에 두는 이유: UI에서만 막으면 뚫린다. 온라인 대전에서는
/// 서버가 이 엔진을 그대로 돌려 판정하므로, 상한이 규칙 엔진 안에 있어야 클라이언트를
/// 조작해도 소용이 없다.
///
/// **이 값은 "가진 개수"가 아니라 "한 판에 쓸 수 있는 횟수"다.** 실제 보유량은
/// 지갑(`TokenWallet`)이 따로 관리한다 — 도메인은 결제를 몰라야 하기 때문이다.
/// 즉 사용하려면 **둘 다** 통과해야 한다: 판당 상한(여기) + 보유량(지갑).
class GameRules {
  const GameRules({this.shieldDeclarations = 0, this.attackMarks = 0});

  /// 토큰을 전혀 쓸 수 없는 판(기본값). AI 상대는 언제나 이것을 받는다.
  static const none = GameRules();

  /// 상점에서 파는 기본 구성: 종류별 판당 1회.
  ///
  /// **이 숫자를 올리지 말 것.** 100개를 산 사람도 한 판의 이득이 1개 쓴 사람과 같다는
  /// 것이 이 게임이 pay-to-win이 아닌 유일한 근거다.
  static const standard = GameRules(shieldDeclarations: 1, attackMarks: 1);

  /// 내 필드의 카드를 쉴드로 만들 수 있는 횟수.
  final int shieldDeclarations;

  /// 손패 카드에 공격 표식을 붙일 수 있는 횟수.
  final int attackMarks;
}

/// 필드에 놓인 카드. [placedBy]는 놓은 주체(조커 면역/보상 판정용).
class PlacedCard {
  PlacedCard(this.card, this.placedBy);
  final PlayingCard card;
  final PlayerId placedBy;

  bool get isShield => card.isShield;
  bool get isJoker => card.isJoker;

  /// 일반 카드(같은 숫자)로 제거 가능한가? 쉴드/조커 배치는 불가.
  bool get removableByNormal => !isShield && !isJoker;
}

const int kRows = 3;
const int kCols = 5;
const int kHandSize = 5; // 유지 손패 크기 (6장 받고 1장 오픈 → 5장으로 시작)

class GameState {
  GameState._(this._deck, this._rules);

  final Deck _deck;

  /// 플레이어별 토큰 사용 상한. 없는 플레이어는 [GameRules.none].
  final Map<PlayerId, GameRules> _rules;

  GameRules rulesFor(PlayerId p) => _rules[p] ?? GameRules.none;

  final Map<PlayerId, int> _shieldDeclarationsUsed = {PlayerId.p0: 0, PlayerId.p1: 0};
  final Map<PlayerId, int> _attackMarksUsed = {PlayerId.p0: 0, PlayerId.p1: 0};

  /// 이 판에서 [p]가 아직 쓸 수 있는 쉴드 선언 횟수.
  int shieldDeclarationsLeft(PlayerId p) =>
      rulesFor(p).shieldDeclarations - _shieldDeclarationsUsed[p]!;

  /// 이 판에서 [p]가 아직 쓸 수 있는 표식 부여 횟수.
  int attackMarksLeft(PlayerId p) => rulesFor(p).attackMarks - _attackMarksUsed[p]!;

  final Map<PlayerId, List<PlayingCard>> hands = {
    PlayerId.p0: <PlayingCard>[],
    PlayerId.p1: <PlayingCard>[],
  };
  final Map<PlayerId, List<List<PlacedCard?>>> fields = {
    PlayerId.p0: _emptyField(),
    PlayerId.p1: _emptyField(),
  };
  final Map<PlayerId, bool> folded = {PlayerId.p0: false, PlayerId.p1: false};

  PlayerId current = PlayerId.p0;
  GamePhase phase = GamePhase.awaitingReveal;

  /// 공격에 성공해 **배치를 한 번 더** 할 수 있는 상태. 이 동안 턴은 넘어가지 않고,
  /// 배치(또는 [passBonus])로 소비된다. 보너스로 다시 공격할 수는 없다.
  bool pendingBonus = false;

  static List<List<PlacedCard?>> _emptyField() =>
      List.generate(kRows, (_) => List<PlacedCard?>.filled(kCols, null));

  int get deckRemaining => _deck.remaining;
  bool get isFinished => phase == GamePhase.finished;

  // ---- 셋업 ----

  /// 셔플된 덱에서 각자 6장씩 받는다. 이후 [revealForFirstTurn] 호출 필요.
  factory GameState.deal({int? seed, Map<PlayerId, GameRules> rules = const {}}) {
    final deck = Deck.shuffled(seed: seed);
    final s = GameState._(deck, rules);
    for (final p in PlayerId.values) {
      // 처음 받은 카드에만 공격 표식 — 이후 뽑는 카드는 배치 전용이다.
      s.hands[p]!.addAll(deck.draw(6).map((c) => c.asAttacker()));
    }
    return s;
  }

  /// 테스트/시나리오용: 덱만 주입하고 손패·필드·상태는 직접 구성한다. (기본 phase=playing)
  factory GameState.custom(Deck deck, {Map<PlayerId, GameRules> rules = const {}}) {
    final s = GameState._(deck, rules);
    s.phase = GamePhase.playing;
    return s;
  }

  /// 각자 손패에서 1장씩 오픈(인덱스). 높은 숫자가 선공, 동점이면 슈트 순서(♠>♥>♦>♣).
  /// 오픈한 카드는 버려진다 → 손패 5장. 선공이 정해지면 플레이 시작.
  void revealForFirstTurn(int index0, int index1) {
    if (phase != GamePhase.awaitingReveal) {
      throw IllegalMove(MoveError.alreadyRevealed);
    }
    final c0 = _takeFromHand(PlayerId.p0, index0);
    final c1 = _takeFromHand(PlayerId.p1, index1);
    var cmp = c0.rank.compareTo(c1.rank);
    if (cmp == 0) cmp = c0.suit.order.compareTo(c1.suit.order);
    current = cmp >= 0 ? PlayerId.p0 : PlayerId.p1;
    phase = GamePhase.playing;
    _beginTurn();
  }

  // ---- 행동 ----

  /// 손패의 카드를 필드에 배치한다.
  /// - 일반/조커: [target]은 자기 자신. 조커는 [jokerRank]/[jokerSuit] 지정 필요.
  /// - 쉴드: [target]은 자기 또는 상대.
  void placeCard(
    int handIndex,
    PlayerId target,
    int row,
    int col, {
    int? jokerRank,
    Suit? jokerSuit,
  }) {
    _ensureTurn();
    final hand = hands[current]!;
    _checkIndex(hand, handIndex);
    final card = hand[handIndex];

    if (card.isShield) {
      // 자기/상대 모두 허용
    } else if (card.isJoker) {
      if (target != current) throw IllegalMove(MoveError.jokerOwnFieldOnly);
      if (jokerRank == null || jokerSuit == null) {
        throw IllegalMove(MoveError.jokerNeedsDesignation);
      }
    } else {
      if (target != current) throw IllegalMove(MoveError.normalOwnFieldOnly);
    }
    _checkCell(row, col);
    if (fields[target]![row][col] != null) throw IllegalMove(MoveError.cellOccupied);

    final placedModel = card.isJoker ? card.designate(jokerRank!, jokerSuit!) : card;
    fields[target]![row][col] = PlacedCard(placedModel, current);
    hand.removeAt(handIndex);
    _afterAction(); // 보너스 배치였다면 여기서 소비되고 턴이 넘어간다
  }

  /// **공격(빼앗기)**: 손패의 공격 카드로 상대 필드 카드를 뽑아 **내 필드 빈 칸**에 놓는다.
  ///
  /// - [handIndex]: 사용할 공격 카드(공격 표식이 있거나 조커). 사용 후 버려진다.
  /// - [targetRow]/[targetCol]: 빼앗을 상대 칸.
  /// - [myRow]/[myCol]: 빼앗은 카드를 놓을 **내** 빈 칸.
  ///
  /// 빼앗은 카드는 쉴드가 되어 되빼앗기지 않는다. 성공하면 [pendingBonus]가 켜져
  /// 그 턴에 배치를 한 번 더 할 수 있다.
  void attack(int handIndex, int targetRow, int targetCol, int myRow, int myCol) {
    _ensureTurn();
    if (pendingBonus) throw IllegalMove(MoveError.attackOncePerTurn);
    final hand = hands[current]!;
    _checkIndex(hand, handIndex);
    final weapon = hand[handIndex];
    if (!weapon.canAttack) {
      throw IllegalMove(
          weapon.isShield ? MoveError.shieldCannotAttack : MoveError.attackerCardRequired);
    }

    _checkCell(targetRow, targetCol);
    final cell = fields[current.other]![targetRow][targetCol];
    if (cell == null) throw IllegalMove(MoveError.noTargetCard);
    if (!weapon.isJoker) {
      if (!cell.removableByNormal) {
        throw IllegalMove(MoveError.needJokerToTakeShield);
      }
      if (cell.card.rank != weapon.rank) {
        throw IllegalMove(MoveError.rankMismatch);
      }
    }

    _checkCell(myRow, myCol);
    if (fields[current]![myRow][myCol] != null) {
      throw IllegalMove(MoveError.needEmptyCellForSteal);
    }

    // 이동: 상대 칸 → 내 칸(쉴드로 고정). 무기는 버려진다.
    lastStolen = cell.card.asShield();
    fields[current.other]![targetRow][targetCol] = null;
    fields[current]![myRow][myCol] = PlacedCard(lastStolen!, current);
    hand.removeAt(handIndex);
    _afterAction(grantBonus: true);
  }

  /// 방금 빼앗아 온 카드(연출용).
  PlayingCard? lastStolen;

  // ---- 토큰 행동 (상점에서 파는 유료 아이템의 규칙적 실체) ----
  //
  // 둘 다 **턴을 소모하지 않는다.** 비용은 토큰 자체이지 한 턴이 아니다 —
  // 턴까지 먹으면 쓸 이유가 없어져서, 팔아도 아무도 안 쓰는 아이템이 된다.
  // 대신 판당 상한(GameRules)이 이득의 크기를 고정한다.

  /// **쉴드 선언**: 내 필드의 카드 1장을 쉴드로 만든다.
  ///
  /// 쉴드가 된 카드는 일반 공격 카드로 빼앗을 수 없다 — **조커로만 깨진다**(§6).
  /// 덱에 조커가 2장뿐이라는 규칙이 그대로 이 아이템의 카운터가 된다.
  ///
  /// 이미 쉴드이거나 조커로 놓은 카드는 대상이 될 수 없다. 어차피 일반 공격에
  /// 면역이라 토큰만 버리는 셈이기 때문이다(돈 낸 사용자가 헛되이 쓰지 않게 막는다).
  void declareShield(int row, int col) {
    _ensureTurn();
    if (shieldDeclarationsLeft(current) <= 0) {
      throw IllegalMove(MoveError.tokenExhausted);
    }
    _checkCell(row, col);
    final cell = fields[current]![row][col];
    if (cell == null) throw IllegalMove(MoveError.tokenNoCardHere);
    if (!cell.removableByNormal) {
      throw IllegalMove(MoveError.shieldTargetNotEligible);
    }
    fields[current]![row][col] = PlacedCard(cell.card.asShield(), cell.placedBy);
    _shieldDeclarationsUsed[current] = _shieldDeclarationsUsed[current]! + 1;
    // 턴을 넘기지 않는다 — 선언 후 그 턴의 행동을 그대로 이어서 한다.
  }

  /// **표식 부여**: 손패의 카드 1장에 공격 표식을 붙인다.
  ///
  /// 원래 공격 표식은 처음 받은 6장에만 붙는다(§4.1). 이 토큰은 **덱에서 뽑은 카드로도
  /// 공격할 수 있게** 해준다 — 규칙이 걸어둔 "공격 횟수의 자연스러운 상한"을 한 번 푼다.
  ///
  /// 다만 표식이 붙어도 나머지 조건은 그대로다: **같은 숫자**여야 하고, 내 필드에
  /// **빈 칸**이 있어야 하며, 상대의 쉴드는 여전히 못 건드린다. 그래서 표식을 붙였는데도
  /// 칠 곳이 없을 수 있다 — 쓰는 타이밍이 곧 실력이다.
  void markAttacker(int handIndex) {
    _ensureTurn();
    if (attackMarksLeft(current) <= 0) throw IllegalMove(MoveError.tokenExhausted);
    final hand = hands[current]!;
    _checkIndex(hand, handIndex);
    final card = hand[handIndex];
    // 이미 공격 가능한 카드(공격 표식·조커)와 쉴드 카드는 대상이 아니다.
    // 쉴드는 표식을 붙여도 공격에 쓸 수 없다(PlayingCard.canAttack).
    if (card.canAttack || card.isShield) {
      throw IllegalMove(MoveError.attackMarkNotEligible);
    }
    hand[handIndex] = card.asAttacker();
    _attackMarksUsed[current] = _attackMarksUsed[current]! + 1;
  }

  /// 보너스 배치를 포기하고 턴을 넘긴다.
  void passBonus() {
    _ensureTurn();
    if (!pendingBonus) throw IllegalMove(MoveError.notBonusTurn);
    pendingBonus = false;
    _afterAction();
  }

  /// 폴드: 더 이상 턴을 받지 않는다.
  void fold() {
    _ensureTurn();
    folded[current] = true;
    _afterAction();
  }

  // ---- 결과 ----

  /// 현재 보드 기준 매치 결과([perspective] 기준). 종료 후 호출 권장.
  MatchResult result([PlayerId perspective = PlayerId.p0]) =>
      judgeMatch(_rowsOf(perspective), _rowsOf(perspective.other));

  List<List<PlayingCard>> _rowsOf(PlayerId p) => fields[p]!
      .map((row) => [for (final c in row) if (c != null) c.card])
      .toList();

  // ---- 내부 ----

  PlayingCard _takeFromHand(PlayerId p, int index) {
    final hand = hands[p]!;
    _checkIndex(hand, index);
    return hand.removeAt(index);
  }

  void _ensureTurn() {
    if (phase != GamePhase.playing) throw IllegalMove(MoveError.notPlaying);
    if (folded[current]!) throw IllegalMove(MoveError.playerFolded);
  }

  void _checkIndex(List<PlayingCard> hand, int index) {
    if (index < 0 || index >= hand.length) throw IllegalMove(MoveError.badHandIndex);
  }

  void _checkCell(int row, int col) {
    if (row < 0 || row >= kRows || col < 0 || col >= kCols) {
      throw IllegalMove(MoveError.badCell);
    }
  }

  void _afterAction({bool grantBonus = false}) {
    pendingBonus = grantBonus;
    if (_checkFinished()) {
      phase = GamePhase.finished;
      pendingBonus = false;
      return;
    }
    if (pendingBonus) {
      // 놓을 카드나 빈 칸이 없으면 보너스는 그냥 넘어간다.
      if (_canPlace(current)) return;
      pendingBonus = false;
    }
    _advanceTurn();
  }

  /// 지금 손패로 어딘가에 배치할 수 있는가?
  bool _canPlace(PlayerId p) {
    final hand = hands[p]!;
    if (hand.isEmpty) return false;
    if (_hasEmptyCell(p)) return true;
    return hand.any((c) => c.isShield) && _hasEmptyCell(p.other);
  }

  void _advanceTurn() {
    var next = current.other;
    if (folded[next]!) next = current; // 상대가 폴드면 현재가 계속
    current = next;
    _beginTurn();
  }

  /// 턴 시작 보충: 손패가 [kHandSize]장이 되도록 덱에서 뽑는다.
  /// 여기서 뽑은 카드에는 공격 표식이 없다(배치 전용).
  void _beginTurn() {
    if (folded[current]!) return;
    final hand = hands[current]!;
    while (hand.length < kHandSize && !_deck.isEmpty) {
      final c = _deck.drawOne();
      if (c == null) break;
      hand.add(c);
    }
  }

  bool _checkFinished() {
    if (folded[PlayerId.p0]! && folded[PlayerId.p1]!) return true;
    if (_boardFull()) return true;
    final anyoneCanMove =
        PlayerId.values.any((p) => !folded[p]! && _hasLegalMove(p));
    return !anyoneCanMove;
  }

  bool _boardFull() {
    for (final p in PlayerId.values) {
      for (final row in fields[p]!) {
        for (final cell in row) {
          if (cell == null) return false;
        }
      }
    }
    return true;
  }

  bool _hasEmptyCell(PlayerId p) =>
      fields[p]!.any((row) => row.any((c) => c == null));

  bool _hasLegalMove(PlayerId p) {
    if (!_deck.isEmpty && _hasEmptyCell(p)) return true; // 뽑아서 놓으면 됨
    if (_canPlace(p)) return true;
    // 공격: 공격 카드 + 내 빈 칸 + 상대 카드가 모두 있어야 한다
    final hand = hands[p]!;
    if (hand.any((c) => c.canAttack) &&
        _hasEmptyCell(p) &&
        fields[p.other]!.any((row) => row.any((c) => c != null))) {
      return true;
    }
    return false;
  }
}
