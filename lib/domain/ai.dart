import 'dart:math';

import 'card.dart';
import 'game.dart';
import 'hand.dart';

/// AI 기풍. 페르소나(크로드/헷/제나)와 1:1로 묶인다.
enum AiStyle {
  /// 크로드 — 침착한 수비형. 세 줄을 고르게 채우고, 비공개권은 확실할 때만 쓴다.
  clode,

  /// 헷 — 공격형. 이길 두 줄에 몰아주고 약한 줄은 버린다. 비공개권을 일찍 태운다.
  het,

  /// 제나 — 변칙형. 배치가 튀고, 값어치 없는 카드도 숨겨 허세를 부린다.
  jenna,
}

/// 기풍별 행동 계수. 룰은 하나지만 **행동이 다르면 다른 상대로 느껴진다**.
class AiProfile {
  const AiProfile({
    required this.sacrificeWeakRow,
    required this.balance,
    required this.noise,
    required this.hideFromRound,
    required this.hideMinGain,
    required this.bluffChance,
    required this.reserveForPeek,
    required this.peekFromRound,
    required this.peekChance,
  });

  /// 가장 약한 줄을 버리고 남은 두 줄에 몰아주는 정도(0~1). 2줄만 이기면 되는 룰이라
  /// 높을수록 공격적이다.
  final double sacrificeWeakRow;

  /// 빈 칸이 많은 줄을 선호하는 정도(0~1) — 높을수록 세 줄이 고르게 찬다.
  final double balance;

  /// 배치 점수에 섞는 무작위성 — 높을수록 수를 읽기 어렵다.
  final double noise;

  /// 이 라운드(0-index)부터 숨기기를 쓴다.
  final int hideFromRound;

  /// 숨길 만한 최소 이득. 100 = "그 카드가 줄의 족보 등급을 올렸을 때만".
  final int hideMinGain;

  /// 이득이 없어도 숨겨서 허세를 부릴 확률.
  final double bluffChance;

  /// 열어보기용으로 남겨 둘 비공개권 수(숨기기에 다 쓰지 않는다).
  final int reserveForPeek;

  /// 이 라운드(0-index)부터 열어보기를 쓴다.
  final int peekFromRound;

  /// 조건이 맞을 때 실제로 열어볼 확률.
  final double peekChance;

  static const Map<AiStyle, AiProfile> byStyle = {
    AiStyle.clode: AiProfile(
      sacrificeWeakRow: 0.0,
      balance: 1.0,
      noise: 0.0,
      hideFromRound: 2,
      hideMinGain: 100,
      bluffChance: 0.0,
      reserveForPeek: 1,
      peekFromRound: 3,
      peekChance: 0.6,
    ),
    AiStyle.het: AiProfile(
      sacrificeWeakRow: 1.0,
      balance: 0.1,
      noise: 0.05,
      hideFromRound: 0,
      hideMinGain: 1,
      bluffChance: 0.15,
      reserveForPeek: 0,
      peekFromRound: 1,
      peekChance: 0.9,
    ),
    AiStyle.jenna: AiProfile(
      sacrificeWeakRow: 0.4,
      balance: 0.5,
      noise: 0.45,
      hideFromRound: 0,
      hideMinGain: 100,
      bluffChance: 0.5,
      reserveForPeek: 1,
      peekFromRound: 2,
      peekChance: 0.7,
    ),
  };
}

/// 가림 룰 AI — 사람 상대용으로 그럴듯하면 된다.
///
/// 손패에서 **이번 라운드에 낼 카드**(남은 배치 수만큼)를 고른다: 매번 (카드 × 줄) 전체
/// 조합에서 기풍 계수를 반영한 점수가 가장 높은 짝을 탐욕으로 뽑는다. 반환된 handIndex는
/// **현재 손패 기준**이므로, 실행할 때는 인덱스가 밀리지 않게 내림차순으로 배치해야 한다.
class VeiledAi {
  VeiledAi(this.style, {int? seed}) : _rng = Random(seed);

  final AiStyle style;
  final Random _rng;

  AiProfile get profile => AiProfile.byStyle[style]!;

  List<({int handIndex, int row, int col})> plan(ScoreGame g, PlayerId p) {
    final plan = <({int handIndex, int row, int col})>[];
    // 시뮬레이션용 줄 구성(자기 카드는 숨김 여부와 무관하게 전부 안다).
    final rows = g.allRows(p);
    final free = [
      for (var r = 0; r < ScoreGame.rowsN; r++) ScoreGame.colsN - rows[r].length,
    ];
    // 버릴 줄: 지금 가장 약한 줄. 기풍에 따라 여기 놓는 것을 꺼린다.
    final sacrifice = _weakestRow(rows);
    final hand = List.of(g.hands[p]!);
    final used = <int>{};
    final n = g.leftToPlace(p);
    for (var k = 0; k < n; k++) {
      var bestI = -1, bestRow = -1;
      var bestScore = -1e18;
      for (var i = 0; i < hand.length; i++) {
        if (used.contains(i)) continue;
        for (var r = 0; r < ScoreGame.rowsN; r++) {
          if (free[r] <= 0) continue;
          final s = _placementScore(rows[r], hand[i], free[r], r == sacrifice);
          if (s > bestScore) {
            bestScore = s;
            bestI = i;
            bestRow = r;
          }
        }
      }
      if (bestI < 0) break; // 빈 칸 없음(정상 흐름에선 없다)
      // 실제 칸: 그 줄의 첫 빈 칸(왼쪽부터 — 기존 게임과 같은 방향).
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

  /// 한 장을 한 줄에 놓았을 때의 값어치.
  /// 족보 등급 상승(×100) + 점수 상승이 뼈대고, 거기에 기풍이 얹힌다.
  double _placementScore(
      List<PlayingCard> row, PlayingCard card, int free, bool isSacrifice) {
    final before = evaluateHand(row);
    final after = evaluateHand([...row, card]);
    final gain = (after.category.index - before.category.index) * 100 +
        (after.score - before.score);
    var s = gain.toDouble();
    s += profile.balance * free * 6; // 고르게 채우기
    if (isSacrifice) s -= profile.sacrificeWeakRow * 120; // 약한 줄은 버린다
    s += profile.noise * _rng.nextDouble() * 90;
    return s;
  }

  int _weakestRow(List<List<PlayingCard>> rows) {
    var weakest = 0;
    var worst = evaluateHand(rows[0]);
    for (var r = 1; r < rows.length; r++) {
      final h = evaluateHand(rows[r]);
      if (h.compareTo(worst) < 0) {
        worst = h;
        weakest = r;
      }
    }
    return weakest;
  }

  /// 공개 직전의 숨기기 선택. 이번 라운드에 놓은 카드 중 한 장까지만 숨긴다
  /// (숨길수록 상대의 열어보기 표적이 늘어난다).
  Set<(int, int)> hides(ScoreGame g, PlayerId p) {
    final budget = g.veilLeft[p]! - profile.reserveForPeek;
    if (budget <= 0 || g.round < profile.hideFromRound) return const {};

    (int, int)? best;
    var bestGain = 0;
    for (final (r, c) in g.placedThisRound(p)) {
      final gain = _cardGain(g, p, r, c);
      if (gain > bestGain) {
        bestGain = gain;
        best = (r, c);
      }
    }
    if (best != null && bestGain >= profile.hideMinGain) return {best};

    // 허세: 값어치 없는 카드를 숨겨 상대의 비공개권을 헛되이 태우게 만든다.
    final placed = g.placedThisRound(p);
    if (placed.isNotEmpty && _rng.nextDouble() < profile.bluffChance) {
      return {placed[_rng.nextInt(placed.length)]};
    }
    return const {};
  }

  /// 그 카드가 자기 줄에 얼마나 기여했는가(등급 상승 ×100 + 점수 상승).
  int _cardGain(ScoreGame g, PlayerId p, int row, int col) {
    final all = <PlayingCard>[];
    final without = <PlayingCard>[];
    for (var c = 0; c < ScoreGame.colsN; c++) {
      final s = g.fields[p]![row][c];
      if (s == null) continue;
      all.add(s.card);
      if (c != col) without.add(s.card);
    }
    final a = evaluateHand(all);
    final b = evaluateHand(without);
    return (a.category.index - b.category.index) * 100 + (a.score - b.score);
  }

  /// 열어보기: 상대가 **지난 라운드에 숨긴** 카드가 있으면 기풍에 따라 하나를 연다.
  /// 표적은 숨김이 몰린 줄 — 상대가 밀어붙이는 줄일 확률이 높다.
  (int, int)? peek(ScoreGame g, PlayerId p) {
    if (g.veilLeft[p]! <= 0 || g.round < profile.peekFromRound) return null;
    if (_rng.nextDouble() >= profile.peekChance) return null;
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
}
