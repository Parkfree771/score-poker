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

/// 가림 룰 AI.
///
/// 손패에서 **이번 라운드에 낼 카드**(남은 배치 수만큼)를 고른다: (카드 × 줄) 배정을
/// 한꺼번에 탐색해 **판 전체 값어치**([_boardValue] — 상대의 공개 카드를 보고 "두 줄을
/// 이길 확률")가 가장 높은 조합을 택한다. 기풍 계수는 그 위에 얹힌다. 반환된 handIndex는
/// **현재 손패 기준**이므로, 실행할 때는 인덱스가 밀리지 않게 내림차순으로 배치해야 한다.
class VeiledAi {
  VeiledAi(this.style, {int? seed}) : _rng = Random(seed);

  final AiStyle style;
  final Random _rng;

  AiProfile get profile => AiProfile.byStyle[style]!;

  List<({int handIndex, int row, int col})> plan(ScoreGame g, PlayerId p) {
    final rows = g.allRows(p);
    // 상대는 **공개된 카드만** 안다 — 숨긴 카드는 "한 장 더 있다"로만 친다.
    final opp = [
      for (var r = 0; r < ScoreGame.rowsN; r++) g.publicRow(p.other, r),
    ];
    final oppHidden = [
      for (var r = 0; r < ScoreGame.rowsN; r++)
        g.allRows(p.other)[r].length - opp[r].length,
    ];
    final free = [
      for (var r = 0; r < ScoreGame.rowsN; r++) ScoreGame.colsN - rows[r].length,
    ];
    final hand = g.hands[p]!;
    final n = min(g.leftToPlace(p), hand.length);
    if (n == 0) return const [];

    // (카드, 줄) 배정 n개를 **한꺼번에** 탐색한다 — 손패의 페어·같은 무늬가 한 줄에
    // 모이려면 한 장씩 탐욕으로 고르면 안 된다. 6장·3배치면 ~3천 가지, 충분히 싸다.
    var bestValue = -1e18;
    List<(int, int)> best = const [];
    final assign = <(int, int)>[];
    final used = <int>{};

    void search(int k) {
      if (k == n) {
        var v = _boardValue(rows, opp, oppHidden, free);
        v += profile.noise * _rng.nextDouble() * 0.6;
        if (v > bestValue) {
          bestValue = v;
          best = List.of(assign);
        }
        return;
      }
      for (var i = 0; i < hand.length; i++) {
        if (used.contains(i)) continue;
        // 카드 순서 중복만 잘라낸다: 인덱스 오름차순으로만 고른다.
        if (assign.isNotEmpty && i < assign.last.$1) continue;
        for (var r = 0; r < ScoreGame.rowsN; r++) {
          if (free[r] <= 0) continue;
          used.add(i);
          assign.add((i, r));
          rows[r].add(hand[i]);
          free[r]--;
          search(k + 1);
          free[r]++;
          rows[r].removeLast();
          assign.removeLast();
          used.remove(i);
        }
      }
    }

    search(0);

    final plan = <({int handIndex, int row, int col})>[];
    for (final (i, r) in best) {
      var col = 0;
      while (g.fields[p]![r][col] != null ||
          plan.any((m) => m.row == r && m.col == col)) {
        col++;
      }
      plan.add((handIndex: i, row: r, col: col));
    }
    return plan;
  }

  /// 판 전체의 값어치 — "세 줄 중 두 줄을 이길 확률"에 가깝게.
  ///
  /// 줄마다 내 세기 − 상대 세기(공개분 + 숨긴 장수만큼의 잠재력)를 승률로 바꾼 뒤,
  /// 상위 두 줄을 크게, 세 번째 줄은 기풍(sacrificeWeakRow)만큼 작게 센다.
  /// 이미 굳은 줄(확실히 이김/짐)에 카드를 더 부어도 값이 오르지 않는다 —
  /// 시그모이드라 자연히 접전인 줄로 카드가 간다.
  double _boardValue(List<List<PlayingCard>> mine, List<List<PlayingCard>> opp,
      List<int> oppHidden, List<int> free) {
    final ps = <double>[];
    var evenness = 0.0;
    for (var r = 0; r < mine.length; r++) {
      final my = _strength(mine[r]) + free[r] * 14; // 빈 칸 = 아직 오를 여지
      final theirs = _strength(opp[r]) +
          oppHidden[r] * 22 + // 숨긴 카드는 보통 값어치가 있는 카드다
          (ScoreGame.colsN - opp[r].length - oppHidden[r]) * 14;
      final margin = my - theirs;
      ps.add(1 / (1 + exp(-margin / 55)));
      evenness += free[r] == 0 ? 0 : 1;
    }
    ps.sort((a, b) => b.compareTo(a));
    final weakWeight = 0.55 - 0.45 * profile.sacrificeWeakRow;
    var v = ps[0] + ps[1] + weakWeight * ps[2];
    // 두 줄이 모두 반반이면 몰아주기가 낫다: 둘 다 이길 확률(곱)도 조금 센다.
    v += 0.5 * ps[0] * ps[1];
    v += profile.balance * 0.04 * evenness;
    return v;
  }

  /// 줄의 세기: 등급 ×100 + 점수.
  double _strength(List<PlayingCard> cards) {
    if (cards.isEmpty) return 0;
    final h = evaluateHand(cards);
    return h.category.index * 100.0 + h.score;
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
