import 'dart:math';

import 'card.dart';
import 'deck.dart';
import 'scoring.dart';

/// 게임 규칙 엔진 (순수 Dart). UI/네트워크와 분리되어 테스트로 검증 가능.
///
/// 구현 가정 (GAME_DESIGN.md 기준, 애매한 부분은 합리적 기본값 — 추후 조정 가능):
/// - A1) 제거(일반/조커) 보상 = **새 쉴드 카드 1장을 손패로 드로우**(덱 소모 없음). 제거 즉시 손패로
///       들어오고 턴은 종료된다. 이후 일반 손패처럼 자유롭게 배치. 쉴드는 조커 외에는 제거 불가.
/// - A2) 드로우 단계: 양측이 **시작 카드 5장(쉴드 보상 제외)** 을 모두 소진하면 시작.
///       이후 각 플레이어는 자기 턴 시작에 덱에서 1장 드로우.
/// - A3) 조커 배치는 **자기 필드에만**(숫자+슈트 지정). 쉴드는 자기/상대 필드 모두 가능.
/// - A4) 제거 규칙:
///       · 일반 카드(rank R): 상대의 **일반 카드 중 rank R** 만 제거.
///       · 조커: 상대의 **모든 카드(일반/쉴드/조커 배치)** 제거 가능.
///       · 쉴드/조커 배치 카드: 일반 카드로는 제거 불가(조커만).
/// - A5) 종료: 양측 폴드 / 30칸 가득 / 활성 플레이어 모두 둘 수 없음.
/// - A6) 폴드: 폴드한 쪽은 더 이상 턴을 받지 않음(드로우/배치 없음). 상대는 계속 진행.

enum PlayerId { p0, p1 }

extension PlayerIdX on PlayerId {
  PlayerId get other => this == PlayerId.p0 ? PlayerId.p1 : PlayerId.p0;
}

enum GamePhase { awaitingReveal, playing, finished }

/// 예외: 규칙 위반 행동.
class IllegalMove implements Exception {
  IllegalMove(this.message);
  final String message;
  @override
  String toString() => 'IllegalMove: $message';
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
const int kStartingHand = 5; // 6장 받고 1장 오픈 후 남는 수

class GameState {
  GameState._(this._deck, this._random);

  final Deck _deck;
  final Random _random;

  final Map<PlayerId, List<PlayingCard>> hands = {
    PlayerId.p0: <PlayingCard>[],
    PlayerId.p1: <PlayingCard>[],
  };
  final Map<PlayerId, List<List<PlacedCard?>>> fields = {
    PlayerId.p0: _emptyField(),
    PlayerId.p1: _emptyField(),
  };
  final Map<PlayerId, bool> folded = {PlayerId.p0: false, PlayerId.p1: false};
  final Map<PlayerId, int> startingLeft = {
    PlayerId.p0: kStartingHand,
    PlayerId.p1: kStartingHand,
  };

  PlayerId current = PlayerId.p0;
  GamePhase phase = GamePhase.awaitingReveal;
  bool drawPhase = false;

  static List<List<PlacedCard?>> _emptyField() =>
      List.generate(kRows, (_) => List<PlacedCard?>.filled(kCols, null));

  int get deckRemaining => _deck.remaining;
  bool get isFinished => phase == GamePhase.finished;

  // ---- 셋업 ----

  /// 셔플된 덱에서 각자 6장씩 받는다. 이후 [revealForFirstTurn] 호출 필요.
  factory GameState.deal({int? seed}) {
    final deck = Deck.shuffled(seed: seed);
    final s = GameState._(deck, Random(seed));
    for (final p in PlayerId.values) {
      s.hands[p]!.addAll(deck.draw(6));
    }
    return s;
  }

  /// 테스트/시나리오용: 덱만 주입하고 손패·필드·상태는 직접 구성한다. (기본 phase=playing)
  factory GameState.custom(Deck deck, {Random? random}) {
    final s = GameState._(deck, random ?? Random(0));
    s.phase = GamePhase.playing;
    return s;
  }

  /// 각자 손패에서 1장씩 오픈(인덱스). 높은 숫자가 선공, 동점이면 슈트 순서(♠>♥>♦>♣).
  /// 오픈한 카드는 버려진다 → 손패 5장. 선공이 정해지면 플레이 시작.
  void revealForFirstTurn(int index0, int index1) {
    if (phase != GamePhase.awaitingReveal) {
      throw IllegalMove('이미 선공이 결정되었습니다');
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
      if (target != current) throw IllegalMove('조커는 자기 필드에만 놓을 수 있습니다');
      if (jokerRank == null || jokerSuit == null) {
        throw IllegalMove('조커는 숫자와 슈트를 지정해야 합니다');
      }
    } else {
      if (target != current) throw IllegalMove('일반 카드는 자기 필드에만 놓을 수 있습니다');
    }
    _checkCell(row, col);
    if (fields[target]![row][col] != null) throw IllegalMove('이미 카드가 있는 칸입니다');

    final placedModel = card.isJoker ? card.designate(jokerRank!, jokerSuit!) : card;
    fields[target]![row][col] = PlacedCard(placedModel, current);
    hand.removeAt(handIndex);
    _consumeStarting(card);
    _afterAction();
  }

  /// 상대 필드의 카드를 제거한다. [handIndex]는 사용할 손패 카드(일반: 같은 숫자 / 조커: 무엇이든).
  void removeOpponentCard(int handIndex, int targetRow, int targetCol) {
    _ensureTurn();
    final hand = hands[current]!;
    _checkIndex(hand, handIndex);
    final weapon = hand[handIndex];
    _checkCell(targetRow, targetCol);
    final cell = fields[current.other]![targetRow][targetCol];
    if (cell == null) throw IllegalMove('제거할 카드가 없습니다');

    if (weapon.isShield) {
      throw IllegalMove('쉴드 카드로는 제거할 수 없습니다');
    } else if (weapon.isJoker) {
      // 무엇이든 제거 가능
    } else {
      if (!cell.removableByNormal) {
        throw IllegalMove('쉴드/조커 카드는 일반 카드로 제거할 수 없습니다');
      }
      if (cell.card.rank != weapon.rank) {
        throw IllegalMove('같은 숫자 카드만 제거할 수 있습니다');
      }
    }

    fields[current.other]![targetRow][targetCol] = null;
    hand.removeAt(handIndex);
    _consumeStarting(weapon);
    // 보상: 새 쉴드 카드를 **손패로 드로우**(즉시 배치가 아니라 이후 자유롭게 사용). 턴 종료.
    lastReward = _randomShieldCard();
    hand.add(lastReward!);
    _afterAction();
  }

  /// 방금 제거 보상으로 손패에 들어온 카드(드로우 연출용). 다음 행동 시 무의미해질 수 있음.
  PlayingCard? lastReward;

  PlayingCard _randomShieldCard() {
    final rank = Ranks.all[_random.nextInt(Ranks.all.length)];
    final suit = Suit.values[_random.nextInt(Suit.values.length)];
    return PlayingCard(rank, suit, isShield: true);
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
    if (phase != GamePhase.playing) throw IllegalMove('플레이 단계가 아닙니다');
    if (folded[current]!) throw IllegalMove('폴드한 플레이어입니다');
  }

  void _checkIndex(List<PlayingCard> hand, int index) {
    if (index < 0 || index >= hand.length) throw IllegalMove('손패 인덱스 오류');
  }

  void _checkCell(int row, int col) {
    if (row < 0 || row >= kRows || col < 0 || col >= kCols) {
      throw IllegalMove('칸 좌표 오류');
    }
  }

  void _consumeStarting(PlayingCard played) {
    // 쉴드 보상은 시작 카드가 아니므로 제외. (드로우 단계 전엔 비쉴드=시작 카드 5장뿐)
    if (!played.isShield && startingLeft[current]! > 0) {
      startingLeft[current] = startingLeft[current]! - 1;
    }
    if (startingLeft[PlayerId.p0]! == 0 && startingLeft[PlayerId.p1]! == 0) {
      drawPhase = true;
    }
  }

  void _afterAction() {
    if (_checkFinished()) {
      phase = GamePhase.finished;
      return;
    }
    _advanceTurn();
  }

  void _advanceTurn() {
    var next = current.other;
    if (folded[next]!) next = current; // 상대가 폴드면 현재가 계속
    current = next;
    _beginTurn();
  }

  void _beginTurn() {
    if (drawPhase && !folded[current]! && !_deck.isEmpty) {
      final c = _deck.drawOne();
      if (c != null) hands[current]!.add(c);
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
    // 드로우로 카드를 얻어 둘 수 있으면 가능
    if (drawPhase && !_deck.isEmpty && _hasEmptyCell(p)) return true;
    final hand = hands[p]!;
    if (hand.isEmpty) return false;
    final hasNormalOrJoker = hand.any((c) => !c.isShield);
    final hasShield = hand.any((c) => c.isShield);
    if (hasNormalOrJoker && _hasEmptyCell(p)) return true; // 자기 필드 배치
    if (hasShield && (_hasEmptyCell(p) || _hasEmptyCell(p.other))) return true;
    // 제거 가능 여부
    final oppHasCard = fields[p.other]!
        .any((row) => row.any((c) => c != null));
    if (oppHasCard && hand.any((c) => !c.isShield)) return true;
    return false;
  }
}
