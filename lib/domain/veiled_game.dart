import 'card.dart';
import 'deck.dart';
import 'game.dart' show PlayerId, PlayerIdX;
import 'hand.dart';
import 'scoring.dart';

/// 가림 룰 (기존 판 위의 새 규칙, 프로토타입).
///
/// 판은 기존 그대로 — 3줄×5칸 vs 3줄×5칸, 같은 번호 줄끼리 대결, 2줄 이기면 승리.
/// 바뀌는 것은 **정보 공개 방식**뿐이다:
/// - 배치는 **뒷면**. 상대가 어디에 두는지는 실시간으로 보이지만 내용은 안 보인다
///   → 배치 위치·순서 자체가 심리전.
/// - **라운드**: 시작 손패 6장, 매 라운드 3장 보충. 타이머 안에 **손에서 3장을 골라**
///   배치 → **이번에 놓은 카드 동시 공개**. 공개된 카드는 계속 공개.
///   5라운드 × 3장 = 15칸. (손이 배치 수보다 크므로 "어떤 3장을 낼까"가 매 라운드의 선택)
/// - **비공개권 3개**(판 전체): 공개 때 내 카드를 숨기는 데 쓰거나,
///   아껴서 **상대가 숨긴 카드를 열어보는 데** 쓴다.
/// - 공격/조커/토큰 없음(코어 검증). 마지막에 전부 공개하고 기존 규칙으로 정산.
///
/// 타이머는 UI 관심사 — 도메인은 배치·공개·비공개권의 회계만 책임진다.
class VeiledGame {
  VeiledGame._(this._deck);

  static const int rowsN = 3;
  static const int colsN = 5;
  static const int perRound = 3;
  static const int totalRounds = 5; // 5 × 3장 = 15칸
  static const int startHand = 6;
  static const int refill = 3;

  /// 조커를 뺀 52장 덱으로 시작, 각자 6장 딜.
  factory VeiledGame.deal({int? seed}) {
    final deck = Deck.shuffled(seed: seed);
    final cards = <PlayingCard>[];
    while (!deck.isEmpty) {
      final c = deck.drawOne()!;
      if (!c.isJoker) cards.add(c);
    }
    final g = VeiledGame._(Deck(cards));
    for (final p in PlayerId.values) {
      g.hands[p]!.addAll(g._deck.draw(startHand));
    }
    return g;
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

  /// 남은 비공개권(숨기기/열어보기 겸용).
  final Map<PlayerId, int> veilLeft = {PlayerId.p0: 3, PlayerId.p1: 3};

  int round = 0; // 0..4

  /// 이번 라운드 공개를 마쳤는가. (공개 후 [nextRound] 전까지 true)
  bool revealDone = false;

  bool get isFinished => round >= totalRounds - 1 && revealDone;

  /// [p]가 이번 라운드에 더 놓을 수 있는 장수.
  int leftToPlace(PlayerId p) => perRound - placedThisRound(p).length;

  /// 양쪽 모두 이번 라운드 3장을 다 놓았는가.
  bool get allPlaced =>
      leftToPlace(PlayerId.p0) <= 0 && leftToPlace(PlayerId.p1) <= 0;

  /// [p]의 손패 [handIndex]를 자기 필드 빈 칸에 **뒷면**으로 놓는다.
  /// 라운드당 정확히 3장까지.
  void place(PlayerId p, int handIndex, int row, int col) {
    if (revealDone) throw StateError('공개 후에는 배치할 수 없다');
    if (leftToPlace(p) <= 0) throw StateError('이번 라운드 배치는 3장까지다');
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

  /// 다음 라운드로 — 3장을 보충한다.
  void nextRound() {
    if (!revealDone) throw StateError('먼저 공개해야 한다');
    if (isFinished) throw StateError('게임이 끝났다');
    round++;
    revealDone = false;
    for (final p in PlayerId.values) {
      hands[p]!.addAll(_deck.draw(refill));
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

  /// 기존 규칙 그대로 정산(3줄 2승, 동수면 총점). [perspective] 기준.
  MatchResult judge([PlayerId perspective = PlayerId.p0]) => judgeMatch(
        _allRows(perspective),
        _allRows(perspective.other),
      );

  List<List<PlayingCard>> _allRows(PlayerId p) => [
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
}

/// 필드 한 칸: 카드 + 공개 여부 + 놓인 라운드.
class VeiledSlot {
  VeiledSlot(this.card, {required this.round, this.faceUp = false});
  final PlayingCard card;
  final int round;
  bool faceUp;
}

/// 가림 룰 AI — 사람 상대용 그럴듯한 수준이면 된다.
///
/// 손패에서 **이번 라운드에 낼 카드**(남은 배치 수만큼)를 고른다: 매번 (카드 × 줄)
/// 전체 조합에서 줄 가치를 가장 올리는 짝을 탐욕으로 뽑는다. 반환된 handIndex는
/// **현재 손패 기준**이므로, 실행할 때는 내림차순으로 placeAt해야 인덱스가 안 밀린다.
List<({int handIndex, int row, int col})> veiledAiPlan(VeiledGame g, PlayerId p) {
  final plan = <({int handIndex, int row, int col})>[];
  // 시뮬레이션용 줄 구성(자기 카드는 숨김 여부와 무관하게 전부 안다).
  final rows = [
    for (var r = 0; r < VeiledGame.rowsN; r++)
      [
        for (var c = 0; c < VeiledGame.colsN; c++)
          if (g.fields[p]![r][c] != null) g.fields[p]![r][c]!.card,
      ],
  ];
  final free = [
    for (var r = 0; r < VeiledGame.rowsN; r++)
      VeiledGame.colsN - rows[r].length,
  ];
  final hand = List.of(g.hands[p]!);
  final used = <int>{};
  for (var k = 0; k < g.leftToPlace(p); k++) {
    var bestI = -1, bestRow = -1, bestGain = -1 << 30;
    for (var i = 0; i < hand.length; i++) {
      if (used.contains(i)) continue;
      for (var r = 0; r < VeiledGame.rowsN; r++) {
        if (free[r] <= 0) continue;
        final before = evaluateHand(rows[r]);
        final after = evaluateHand([...rows[r], hand[i]]);
        final gain = (after.category.index - before.category.index) * 100 +
            (after.score - before.score);
        if (gain > bestGain) {
          bestGain = gain;
          bestI = i;
          bestRow = r;
        }
      }
    }
    if (bestI < 0) break; // 빈 칸 없음(정상 흐름에선 없다)
    // 실제 칸: 그 줄의 첫 빈 칸(가운데부터 — col 오름차순이 기존 게임과 같은 방향).
    var col = 0;
    while (g.fields[p]![bestRow][col] != null ||
        plan.any((m) => m.row == bestRow && m.col == col)) {
      col++;
    }
    plan.add((handIndex: bestI, row: bestRow, col: col));
    used.add(bestI);
    rows[bestRow].add(hand[bestI]);
    free[bestRow]--;
  }
  return plan;
}

/// 공개 직전 AI의 숨기기 선택: 이번 라운드 카드 중 **족보 등급을 올린 카드**가 있고
/// 비공개권이 남았으면 가장 가치 있는 1장을 숨긴다(초반 2라운드는 아껴둔다).
Set<(int, int)> veiledAiHides(VeiledGame g, PlayerId p) {
  if (g.veilLeft[p]! <= 0 || g.round < 1) return const {};
  (int, int)? best;
  var bestGain = 0;
  for (final (r, c) in g.placedThisRound(p)) {
    final all = [
      for (var col = 0; col < VeiledGame.colsN; col++)
        if (g.fields[p]![r][col] != null) g.fields[p]![r][col]!.card,
    ];
    final without = [
      for (var col = 0; col < VeiledGame.colsN; col++)
        if (col != c && g.fields[p]![r][col] != null) g.fields[p]![r][col]!.card,
    ];
    final gain = (evaluateHand(all).category.index -
            evaluateHand(without).category.index) *
        100;
    if (gain > bestGain) {
      bestGain = gain;
      best = (r, c);
    }
  }
  return best == null ? const {} : {best};
}

/// AI의 열어보기: 후반(4라운드~)에 비공개권이 남았고 상대가 **지난 라운드에 숨긴**
/// 카드가 있으면, 숨김이 가장 많은 줄의 카드를 하나 연다.
/// (이번 라운드 뒷면 카드는 규칙상 열 수 없다 — peek 가드와 같은 기준)
(int, int)? veiledAiPeek(VeiledGame g, PlayerId p) {
  if (g.veilLeft[p]! <= 0 || g.round < 3) return null;
  final hidden = [
    for (final pos in g.hiddenOf(p.other))
      if (g.fields[p.other]![pos.$1][pos.$2]!.round < g.round || g.revealDone) pos,
  ];
  if (hidden.isEmpty) return null;
  final byRow = <int, int>{};
  for (final (r, _) in hidden) {
    byRow[r] = (byRow[r] ?? 0) + 1;
  }
  final targetRow =
      byRow.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
  return hidden.firstWhere((h) => h.$1 == targetRow);
}
