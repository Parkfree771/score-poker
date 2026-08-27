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
/// - R6) **조커 [jokers]장**(덱에 섞여 손에 들어온다). 두 가지 쓰임:
///       ① **와일드** — 내 빈 칸에 원하는 랭크·무늬로 놓는다([placeWild], 3장 배치의 하나,
///          뒷면·숨기기 가능). ② **강타** — 상대 판의 **이미 놓인 카드**(공개·비공개 무관)를
///          내가 정한 카드로 **바꿔치기**한다([declareStrike]). 강타는 3장 배치와 **별도 행동**이며
///          공개 때 기본 3장이 뒤집힌 뒤 발동한다([resolveStrikes]). 바뀐 카드는 앞면이 된다.
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
  static const int jokers = 2;

  /// 52장 덱으로 시작, 각자 [startHand]장 딜. [boostFor]가 있으면 그 쪽만 부스트 판이다.
  factory ScoreGame.deal({int? seed, PlayerId? boostFor, int jokers = ScoreGame.jokers}) {
    final g = ScoreGame._(Deck.shuffled(seed: seed, jokers: jokers));
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
  /// 라운드당 정확히 [perRound]장까지. 조커는 [placeWild]로만 놓는다.
  void place(PlayerId p, int handIndex, int row, int col) {
    if (hands[p]![handIndex].isJoker) throw StateError('조커는 카드를 정해서 놓는다');
    _placeSlot(p, handIndex, row, col, hands[p]![handIndex], wild: false);
  }

  /// 조커를 내 빈 칸에 [as] 카드로 놓는다(와일드). 3장 배치의 하나로 센다.
  void placeWild(PlayerId p, int handIndex, int row, int col, PlayingCard as) {
    if (!hands[p]![handIndex].isJoker) throw StateError('조커가 아니다');
    if (as.isJoker) throw StateError('조커를 조커로 지정할 수 없다');
    _placeSlot(p, handIndex, row, col, as, wild: true);
  }

  void _placeSlot(PlayerId p, int handIndex, int row, int col, PlayingCard card,
      {required bool wild}) {
    if (revealDone) throw StateError('공개 후에는 배치할 수 없다');
    if (leftToPlace(p) <= 0) throw StateError('이번 라운드 배치는 $perRound장까지다');
    if (fields[p]![row][col] != null) throw StateError('빈 칸이 아니다');
    hands[p]!.removeAt(handIndex);
    fields[p]![row][col] = VeiledSlot(card, round: round, wild: wild);
  }

  /// 이번 라운드에 예고된 강타(공개 때 발동). 위치는 상대에게 실시간으로 보인다 —
  /// 뒷면 배치와 같은 원칙(어디에 두는지는 노출, 무엇으로 바꾸는지는 비공개).
  final Map<PlayerId, List<JokerStrike>> pendingStrikes = {
    PlayerId.p0: [],
    PlayerId.p1: [],
  };

  /// 마지막 [reveal]/[resolveStrikes]에서 실제로 발동한 강타(연출용).
  List<JokerStrike> lastStrikes = const [];

  /// [p]가 손패의 조커 [handIndex]로 상대 카드 ([row],[col])를 [as]로 바꾸겠다고 예고한다.
  /// 표적은 **이미 놓인 카드**(빈 칸 불가, 공개·비공개 무관). 3장 배치와 별도 행동.
  void declareStrike(PlayerId p, int handIndex, int row, int col, PlayingCard as) {
    if (revealDone) throw StateError('공개 후에는 강타할 수 없다');
    if (!hands[p]![handIndex].isJoker) throw StateError('조커가 아니다');
    if (as.isJoker) throw StateError('조커를 조커로 지정할 수 없다');
    if (fields[p.other]![row][col] == null) throw StateError('빈 칸은 강타할 수 없다');
    if (pendingStrikes[p]!.any((s) => s.row == row && s.col == col)) {
      throw StateError('이미 강타를 예고한 카드다');
    }
    hands[p]!.removeAt(handIndex);
    pendingStrikes[p]!.add(JokerStrike(by: p, row: row, col: col, card: as));
  }

  /// 예고한 강타를 물린다 — 조커가 손으로 돌아온다(공개 전까지 자유).
  void cancelStrike(PlayerId p, int row, int col) {
    final list = pendingStrikes[p]!;
    final i = list.indexWhere((s) => s.row == row && s.col == col);
    if (i < 0) throw StateError('예고한 강타가 없다');
    list.removeAt(i);
    hands[p]!.add(const PlayingCard.joker());
  }

  /// 예고된 강타를 발동한다: 표적 카드가 지정 카드로 바뀌고 **앞면**이 된다
  /// (숨겨져 있었어도 드러난다 — 원래 카드는 사라진다). 발동 목록을 돌려준다.
  List<JokerStrike> resolveStrikes() {
    final done = <JokerStrike>[];
    for (final p in PlayerId.values) {
      for (final s in List.of(pendingStrikes[p]!)) {
        done.add(resolveStrike(p, s.row, s.col));
      }
    }
    lastStrikes = done;
    return done;
  }

  /// 예고된 강타 하나를 발동한다(UI가 한 방씩 연출할 때).
  JokerStrike resolveStrike(PlayerId by, int row, int col) {
    final list = pendingStrikes[by]!;
    final i = list.indexWhere((s) => s.row == row && s.col == col);
    if (i < 0) throw StateError('예고한 강타가 없다');
    final s = list.removeAt(i);
    final old = fields[by.other]![row][col]!;
    fields[by.other]![row][col] = VeiledSlot(s.card, round: old.round, faceUp: true, strikeBy: by);
    return s;
  }

  /// 동시 공개: 이번 라운드에 놓인 카드 중 [hidden]에 지정된 것만 빼고 뒤집는다.
  /// 숨긴 장수만큼 비공개권이 깎인다. 그 다음 예고된 강타가 발동한다 —
  /// UI가 연출을 사이에 끼우려면 [deferStrikes]로 미루고 [resolveStrikes]를 직접 부른다.
  void reveal(Map<PlayerId, Set<(int, int)>> hidden, {bool deferStrikes = false}) {
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
    if (!deferStrikes) resolveStrikes();
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
/// [wild]는 주인이 조커로 지정해 놓은 카드, [strikeBy]는 상대의 강타로 바뀐 카드.
class VeiledSlot {
  VeiledSlot(this.card,
      {required this.round, this.faceUp = false, this.wild = false, this.strikeBy});
  final PlayingCard card;
  final int round;
  bool faceUp;
  final bool wild;
  final PlayerId? strikeBy;

  /// 조커가 관여한 칸(와일드·강타) — 카드 위에 조커 배지가 붙는다.
  bool get jokered => wild || strikeBy != null;
}

/// 예고된 조커 강타: [by]가 상대 판 ([row],[col])의 카드를 [card]로 바꾼다.
class JokerStrike {
  const JokerStrike({required this.by, required this.row, required this.col, required this.card});
  final PlayerId by;
  final int row;
  final int col;
  final PlayingCard card;
}
