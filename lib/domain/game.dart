import 'board.dart';
import 'card.dart';
import 'deck.dart';
import 'scoring.dart';

export 'board.dart';

/// 스코어 포커 규칙 엔진 (순수 Dart). UI/네트워크와 분리되어 테스트로 검증 가능.
///
/// 판은 3줄 × 5칸 vs 3줄 × 5칸. 같은 번호 줄끼리 족보로 겨루고 **2줄을 이기면 승리**한다.
/// 이 규칙의 핵심은 **정보를 가린다**는 것이다:
///
/// - R1) **뒷면 배치**: 카드는 항상 뒷면으로 놓인다. 상대가 *어디에* 두는지는 실시간으로
///       보이지만 *무엇을* 두는지는 공개 전까지 모른다 → 배치 위치·순서 자체가 심리전이다.
/// - R2) **라운드**: 시작 손패 [startHand]장, 매 라운드 [refill]장 보충. 한 라운드에
///       손에서 [perRound]장을 골라 배치한다. 손이 배치 수보다 크므로 "어떤 3장을 낼까"가
///       매 라운드의 선택이 된다. [totalRounds]라운드 × 3장 = 15칸.
/// - R3) **동시 공개**: 라운드가 끝나면 그 라운드에 놓인 카드가 양쪽 동시에 뒤집힌다.
///       한 번 공개된 카드는 계속 공개 상태다.
/// - R4) **비공개권 [veilsPerMatch]개**(판 전체, 겸용 자원): 공개 때 내 카드를 **숨기거나**,
///       아껴 두었다가 **상대가 숨긴 카드를 열어보는 데** 쓴다. 숨기기와 열어보기가 같은
///       주머니에서 나오므로 "지금 숨길까, 나중에 읽을까"의 상충이 생긴다.
/// - R5) 마지막 라운드까지 끝나면 남은 뒷면 카드를 전부 여는 **최후 공개** 후 정산한다.
///
/// **부스트**(상점 상품, 판당 1개까지 — [ScoreGame.deal]의 `boostFor`): 그 판에서
/// 비공개권 칩이 +1(3→4), **손패 스왑** 1회. 스왑은 이번 라운드에 **받은 카드 전부**를
/// 새로 받는 것이다(선택 교체 아님). 받은 카드 중 한 장이라도 필드에 놓았으면 못 쓴다.
///
/// 타이머는 UI 관심사 — 도메인은 배치·공개·비공개권의 회계만 책임진다.
class ScoreGame {
  ScoreGame._(this._deck);

  static const int rowsN = kRows;
  static const int colsN = kCols;
  static const int perRound = 3;
  static const int totalRounds = 5; // 5 × 3장 = 15칸
  static const int startHand = 6;
  static const int refill = 3;
  static const int veilsPerMatch = 3;

  /// 52장 덱으로 시작, 각자 [startHand]장 딜. [boostFor]가 있으면 그 쪽만 부스트 판이다.
  factory ScoreGame.deal({int? seed, PlayerId? boostFor}) {
    final g = ScoreGame._(Deck.shuffled(seed: seed));
    if (boostFor != null) {
      g.veilLeft[boostFor] = veilsPerMatch + 1;
      g.swapLeft[boostFor] = 1;
      g._boosted[boostFor] = true;
    }
    for (final p in PlayerId.values) {
      final drawn = g._deck.draw(startHand);
      g.hands[p]!.addAll(drawn);
      g._drawnThisRound[p] = List.of(drawn);
    }
    return g;
  }

  /// [p]의 판 전체 비공개권 최대치(부스트면 4). 레일의 칩 소켓 수.
  int veilsMax(PlayerId p) => _boosted[p]! ? veilsPerMatch + 1 : veilsPerMatch;

  bool isBoosted(PlayerId p) => _boosted[p]!;

  /// 남은 손패 스왑 횟수(부스트 판만 1, 아니면 0).
  late final Map<PlayerId, int> swapLeft = {
    for (final p in PlayerId.values) p: 0,
  };
  late final Map<PlayerId, bool> _boosted = {
    for (final p in PlayerId.values) p: false,
  };

  /// 이번 라운드에 **받은** 카드(스왑 대상). 딜/보충 때 채운다.
  final Map<PlayerId, List<PlayingCard>> _drawnThisRound = {
    PlayerId.p0: [],
    PlayerId.p1: [],
  };

  List<PlayingCard> drawnThisRound(PlayerId p) => List.unmodifiable(_drawnThisRound[p]!);

  /// 스왑 가능? 부스트가 남아 있고, 이번 라운드에 아직 **한 장도 놓지 않았고**, 공개 전.
  bool canSwap(PlayerId p) =>
      swapLeft[p]! > 0 &&
      !revealDone &&
      placedThisRound(p).isEmpty &&
      _drawnThisRound[p]!.isNotEmpty &&
      _deck.remaining >= _drawnThisRound[p]!.length;

  /// 이번 라운드에 받은 카드를 **전부** 새로 받는다. 새 카드 목록을 돌려준다.
  List<PlayingCard> swap(PlayerId p) {
    if (!canSwap(p)) throw StateError('지금은 스왑할 수 없다');
    final hand = hands[p]!;
    for (final c in _drawnThisRound[p]!) {
      hand.remove(c);
    }
    final fresh = _deck.draw(_drawnThisRound[p]!.length);
    hand.addAll(fresh);
    _drawnThisRound[p] = List.of(fresh);
    swapLeft[p] = swapLeft[p]! - 1;
    return fresh;
  }

  final Deck _deck;
  int get deckRemaining => _deck.remaining;

  /// 손패(시작 6장, 매 라운드 3장 보충). 배치하면 빠진다.
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

  /// 남은 비공개권(숨기기/열어보기 겸용). 부스트 판은 4로 시작한다.
  final Map<PlayerId, int> veilLeft = {
    PlayerId.p0: veilsPerMatch,
    PlayerId.p1: veilsPerMatch,
  };

  int round = 0; // 0..totalRounds-1

  /// 이번 라운드 공개를 마쳤는가. (공개 후 [nextRound] 전까지 true)
  bool revealDone = false;

  bool get isFinished => round >= totalRounds - 1 && revealDone;

  /// [p]가 이번 라운드에 더 놓을 수 있는 장수.
  int leftToPlace(PlayerId p) => perRound - placedThisRound(p).length;

  /// 양쪽 모두 이번 라운드 3장을 다 놓았는가.
  bool get allPlaced =>
      leftToPlace(PlayerId.p0) <= 0 && leftToPlace(PlayerId.p1) <= 0;

  /// [p]의 손패 [handIndex]를 자기 필드 빈 칸에 **뒷면**으로 놓는다.
  /// 라운드당 정확히 [perRound]장까지.
  void place(PlayerId p, int handIndex, int row, int col) {
    if (revealDone) throw StateError('공개 후에는 배치할 수 없다');
    if (leftToPlace(p) <= 0) throw StateError('이번 라운드 배치는 $perRound장까지다');
    if (fields[p]![row][col] != null) throw StateError('빈 칸이 아니다');
    final card = hands[p]!.removeAt(handIndex);
    fields[p]![row][col] = VeiledSlot(card, round: round);
  }

  /// 동시 공개: 이번 라운드에 놓인 카드 중 [hidden]에 지정된 것만 빼고 뒤집는다.
  /// 숨긴 장수만큼 비공개권이 깎인다.
  void reveal(Map<PlayerId, Set<(int, int)>> hidden) {
    if (revealDone) throw StateError('이미 공개했다');
    if (!allPlaced) throw StateError('아직 배치가 끝나지 않았다');
    for (final p in PlayerId.values) {
      final h = hidden[p] ?? const {};
      if (h.length > veilLeft[p]!) throw StateError('비공개권이 모자라다');
      for (final pos in h) {
        final s = fields[p]![pos.$1][pos.$2];
        if (s == null || s.round != round) {
          throw StateError('이번 라운드에 놓은 카드만 숨길 수 있다');
        }
      }
      veilLeft[p] = veilLeft[p]! - h.length;
      for (var r = 0; r < rowsN; r++) {
        for (var c = 0; c < colsN; c++) {
          final s = fields[p]![r][c];
          if (s != null && s.round == round && !h.contains((r, c))) {
            s.faceUp = true;
          }
        }
      }
    }
    revealDone = true;
  }

  /// [p]가 비공개권 1개로 **상대의 숨긴 카드**를 공개시킨다(모두에게 보인다).
  ///
  /// 대상은 **지난 라운드에 숨겨진 카드**뿐이다 — 이번 라운드 뒷면 카드는 어차피
  /// 공개 때 뒤집히므로, 그걸 여는 데 비공개권을 태우는 실수를 규칙이 막아준다.
  void peek(PlayerId p, int row, int col) {
    if (veilLeft[p]! <= 0) throw StateError('비공개권이 없다');
    final s = fields[p.other]![row][col];
    if (s == null || s.faceUp) throw StateError('숨긴 카드가 아니다');
    if (s.round >= round && !revealDone) {
      throw StateError('이번 라운드 카드는 공개 때 뒤집힌다');
    }
    s.faceUp = true;
    veilLeft[p] = veilLeft[p]! - 1;
  }

  /// 다음 라운드로 — [refill]장을 보충한다.
  void nextRound() {
    if (!revealDone) throw StateError('먼저 공개해야 한다');
    if (isFinished) throw StateError('게임이 끝났다');
    round++;
    revealDone = false;
    for (final p in PlayerId.values) {
      final drawn = _deck.draw(refill);
      hands[p]!.addAll(drawn);
      _drawnThisRound[p] = List.of(drawn);
    }
  }

  /// 최종 정산 전 — 아직 숨겨진 카드 전부 공개(최후 공개). 좌표 목록을 돌려준다.
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

  /// **공개된 카드만으로** 본 줄 대결 상태(라이브 표시용 — 숨긴 정보는 새지 않는다).
  LineOutcome publicLine(PlayerId viewer, int row) =>
      compareLine(publicRow(viewer, row), publicRow(viewer.other, row));

  List<PlayingCard> publicRow(PlayerId p, int row) => [
        for (var c = 0; c < colsN; c++)
          if (fields[p]![row][c] case final s? when s.faceUp) s.card,
      ];

  /// [p] 필드에서 이번 라운드에 놓인 좌표들.
  List<(int, int)> placedThisRound(PlayerId p) => [
        for (var r = 0; r < rowsN; r++)
          for (var c = 0; c < colsN; c++)
            if (fields[p]![r][c] case final s? when s.round == round) (r, c),
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

/// 필드 한 칸: 카드 + 공개 여부 + 놓인 라운드.
class VeiledSlot {
  VeiledSlot(this.card, {required this.round, this.faceUp = false});
  final PlayingCard card;
  final int round;
  bool faceUp;
}
