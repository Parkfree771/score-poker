import 'dart:math';

import 'card.dart';
import 'game.dart';
import 'hand.dart';
import 'scoring.dart';

/// AI가 결정한 한 수.
sealed class AiMove {
  const AiMove();
}

class PlaceMove extends AiMove {
  const PlaceMove(this.handIndex, this.target, this.row, this.col, {this.jokerRank, this.jokerSuit});
  final int handIndex;
  final PlayerId target;
  final int row, col;
  final int? jokerRank;
  final Suit? jokerSuit;
}

/// 공격(빼앗기): [row]/[col]의 상대 카드를 뽑아 내 [myRow]/[myCol] 빈 칸에 놓는다.
class AttackMove extends AiMove {
  const AttackMove(this.handIndex, this.row, this.col, this.myRow, this.myCol);
  final int handIndex;
  final int row, col;
  final int myRow, myCol;
}

class FoldMove extends AiMove {
  const FoldMove();
}

/// 페르소나별 기풍 파라미터.
class AiStyle {
  const AiStyle({
    required this.aggression, // 제거(공격) 성향 0~1
    required this.jokerPatience, // 조커를 아끼는 정도 0~1 (높을수록 늦게 씀)
    required this.shieldSabotage, // 쉴드를 상대 줄에 꽂는 변칙 성향
  });

  final double aggression;
  final double jokerPatience;
  final bool shieldSabotage;

  static const clode = AiStyle(aggression: 0.35, jokerPatience: 0.8, shieldSabotage: false);
  static const het = AiStyle(aggression: 0.9, jokerPatience: 0.2, shieldSabotage: false);
  static const jenna = AiStyle(aggression: 0.55, jokerPatience: 0.5, shieldSabotage: true);
}

/// 휴리스틱 AI: 후보 수를 전부 점수화해 가장 좋은 수를 고른다.
/// 반환하는 수는 항상 게임 규칙상 합법이다(둘 곳이 전혀 없으면 폴드).
class HeuristicAi {
  HeuristicAi(this.style, {int seed = 0}) : _rng = Random(seed);

  final AiStyle style;
  final Random _rng;

  AiMove decide(GameState s, PlayerId me) {
    final hand = s.hands[me]!;
    if (hand.isEmpty) return const FoldMove();
    final opp = me.other;
    // 보너스 배치 차례에는 배치만 가능 — 공격 후보는 만들지 않는다.
    if (s.pendingBonus) return _fallback(s, me, opp) ?? const FoldMove();

    double bestScore = double.negativeInfinity;
    AiMove? best;
    void consider(double score, AiMove move) {
      score += _rng.nextDouble() * 2; // 동점 흔들기(기풍 유지, 수는 다양하게)
      if (score > bestScore) {
        bestScore = score;
        best = move;
      }
    }

    for (var i = 0; i < hand.length; i++) {
      final c = hand[i];
      if (c.isJoker) {
        _considerJoker(s, me, opp, i, consider);
      } else if (c.isShield) {
        _considerShield(s, me, opp, i, c, consider);
      } else {
        _considerNormal(s, me, opp, i, c, consider);
      }
    }

    return best ?? _fallback(s, me, opp) ?? const FoldMove();
  }

  // ---- 후보 생성 ----

  void _considerNormal(
      GameState s, PlayerId me, PlayerId opp, int i, PlayingCard c, void Function(double, AiMove) consider) {
    // 자기 줄 배치: 족보 점수 상승 + 접전 줄 뒤집기 보너스
    for (var r = 0; r < kRows; r++) {
      final col = _firstEmpty(s, me, r);
      if (col == null) continue;
      final gain = _placeGain(s, me, opp, r, c);
      consider(gain, PlaceMove(i, me, r, col));
    }
    // 공격(빼앗기)은 **처음 받은 카드**로만 — 공격 성향으로 가중
    if (!c.canAttack) return;
    for (var r = 0; r < kRows; r++) {
      for (var col = 0; col < kCols; col++) {
        final cell = s.fields[opp]![r][col];
        if (cell == null || !cell.removableByNormal || cell.card.rank != c.rank) continue;
        final dest = _bestDest(s, me, opp, cell.card);
        if (dest == null) continue; // 내 필드가 꽉 차면 빼앗을 수 없다
        final dmg = _removeDamage(s, opp, r, cell.card);
        // 상대 피해 + 빼앗은 카드가 내 줄에 붙는 이득 + 추가 배치(보너스) 가치
        final value = dmg + dest.gain + 8;
        consider(value * (0.35 + style.aggression * 0.8),
            AttackMove(i, r, col, dest.row, dest.col));
      }
    }
  }

  /// 빼앗은 카드를 놓기 가장 좋은 내 빈 칸.
  ({int row, int col, double gain})? _bestDest(
      GameState s, PlayerId me, PlayerId opp, PlayingCard stolen) {
    ({int row, int col, double gain})? best;
    for (var r = 0; r < kRows; r++) {
      final col = _firstEmpty(s, me, r);
      if (col == null) continue;
      final gain = _placeGain(s, me, opp, r, stolen.asShield());
      if (best == null || gain > best.gain) best = (row: r, col: col, gain: gain);
    }
    return best;
  }

  void _considerShield(
      GameState s, PlayerId me, PlayerId opp, int i, PlayingCard c, void Function(double, AiMove) consider) {
    // 자기 줄 배치(소극적 — 쉴드는 제거 불가라 방어 가치 +6)
    for (var r = 0; r < kRows; r++) {
      final col = _firstEmpty(s, me, r);
      if (col == null) continue;
      consider(_placeGain(s, me, opp, r, c) * 0.7 + 6, PlaceMove(i, me, r, col));
    }
    // 변칙: 상대 줄 빈칸에 꽂아 족보를 망친다(망친 만큼 + 방해 보너스)
    if (style.shieldSabotage) {
      for (var r = 0; r < kRows; r++) {
        final cards = _rowCards(s, opp, r);
        if (cards.length < 2 || cards.length >= kCols) continue;
        final col = _firstEmpty(s, opp, r);
        if (col == null) continue;
        final before = evaluateHand(cards).score;
        final after = evaluateHand([...cards, c]).score;
        final damage = before - after; // 낮아질수록(음수 gain) 좋은 방해
        if (damage > -5) consider(damage + 14, PlaceMove(i, opp, r, col));
      }
    }
  }

  void _considerJoker(
      GameState s, PlayerId me, PlayerId opp, int i, void Function(double, AiMove) consider) {
    final reserve = 18 * style.jokerPatience; // 아껴두는 가치
    // 배치: 숫자/슈트를 전수 탐색해 가장 좋은 지정을 찾는다
    for (var r = 0; r < kRows; r++) {
      final col = _firstEmpty(s, me, r);
      if (col == null) continue;
      final cards = _rowCards(s, me, r);
      if (cards.length >= kCols) continue;
      final before = evaluateHand(cards).score;
      var bestGain = double.negativeInfinity;
      int bestRank = Ranks.all.last;
      Suit bestSuit = Suit.spades;
      for (final rank in Ranks.all) {
        for (final suit in Suit.values) {
          final gain =
              evaluateHand([...cards, PlayingCard(rank, suit)]).score - before.toDouble();
          if (gain > bestGain) {
            bestGain = gain;
            bestRank = rank;
            bestSuit = suit;
          }
        }
      }
      consider(bestGain - reserve, PlaceMove(i, me, r, col, jokerRank: bestRank, jokerSuit: bestSuit));
    }
    // 공격: 무엇이든(쉴드 포함) 빼앗을 수 있다 — 상대의 가장 아픈 카드를 노린다
    for (var r = 0; r < kRows; r++) {
      for (var col = 0; col < kCols; col++) {
        final cell = s.fields[opp]![r][col];
        if (cell == null) continue;
        final dest = _bestDest(s, me, opp, cell.card);
        if (dest == null) continue;
        final dmg = _removeDamage(s, opp, r, cell.card);
        consider((dmg + dest.gain + 8) * (0.4 + style.aggression * 0.6) - reserve,
            AttackMove(i, r, col, dest.row, dest.col));
      }
    }
  }

  /// 아무 후보도 점수화되지 않았을 때의 합법 수 탐색(폴드 직전 안전망).
  AiMove? _fallback(GameState s, PlayerId me, PlayerId opp) {
    final hand = s.hands[me]!;
    for (var i = 0; i < hand.length; i++) {
      final c = hand[i];
      for (var r = 0; r < kRows; r++) {
        final col = _firstEmpty(s, me, r);
        if (col == null) continue;
        if (c.isJoker) return PlaceMove(i, me, r, col, jokerRank: Ranks.all.last, jokerSuit: Suit.spades);
        return PlaceMove(i, me, r, col);
      }
      if (c.isShield) {
        for (var r = 0; r < kRows; r++) {
          final col = _firstEmpty(s, opp, r);
          if (col != null) return PlaceMove(i, opp, r, col);
        }
      }
    }
    return null;
  }

  // ---- 점수 계산 ----

  double _placeGain(GameState s, PlayerId me, PlayerId opp, int row, PlayingCard c) {
    final cards = _rowCards(s, me, row);
    if (cards.length >= kCols) return double.negativeInfinity;
    final before = evaluateHand(cards).score;
    final after = evaluateHand([...cards, c]).score;
    var gain = (after - before).toDouble();
    // 접전 줄 가중: 지고 있는 줄을 뒤집으면 보너스
    final oppCards = _rowCards(s, opp, row);
    final wasLosing = compareLine(cards, oppCards) == LineOutcome.lose;
    final nowWinning = compareLine([...cards, c], oppCards) == LineOutcome.win;
    if (wasLosing && nowWinning) gain += 25;
    return gain;
  }

  double _removeDamage(GameState s, PlayerId owner, int row, PlayingCard victim) {
    final cards = _rowCards(s, owner, row);
    final without = [...cards]..remove(victim);
    return (evaluateHand(cards).score - evaluateHand(without).score).toDouble();
  }

  List<PlayingCard> _rowCards(GameState s, PlayerId p, int row) =>
      [for (final c in s.fields[p]![row]) if (c != null) c.card];

  int? _firstEmpty(GameState s, PlayerId p, int row) {
    for (var col = 0; col < kCols; col++) {
      if (s.fields[p]![row][col] == null) return col;
    }
    return null;
  }
}
