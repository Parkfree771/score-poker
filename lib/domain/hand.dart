import 'card.dart';

/// 포커 족보 등급. index가 클수록 강함 (비교 시 index 사용).
enum HandCategory {
  highCard,
  onePair,
  twoPair,
  threeOfAKind,
  straight,
  flush,
  fullHouse,
  fourOfAKind,
  straightFlush,
}

/// 한 줄(최대 5장) 평가 결과.
///
/// 줄 비교 2단계: 1) [category] 등급 비교, 2) 같은 등급이면 [score](숫자값 합 + 보너스)로 비교.
class HandResult implements Comparable<HandResult> {
  const HandResult(this.category, this.score);

  final HandCategory category;

  /// 동급 비교용 숫자값 = 카드값 합 + (그룹별 (개수-1)×랭크값) 보너스.
  /// 예) AA = 28 + 14 = 42, 333 = 9 + 6 = 15.
  final int score;

  @override
  int compareTo(HandResult other) {
    final c = category.index.compareTo(other.category.index);
    return c != 0 ? c : score.compareTo(other.score);
  }

  @override
  String toString() => '$category(score=$score)';
}

/// 5장(또는 그 이하)의 카드를 평가한다.
///
/// 규칙(GAME_DESIGN.md §5):
/// - 5장이 필요한 족보(스트레이트/플러쉬/풀하우스/포카드/스트레이트 플러쉬/파이브카드)는
///   정확히 5장이 모두 채워졌을 때만 성립. 그 외(1~4장)에서는 페어/투페어/트리플/하이카드만 인정.
/// - 조커는 배치 시 이미 rank/suit가 지정되므로 일반 카드처럼 다룬다.
/// - A(14)는 스트레이트에서 1로도 사용 가능(A-2-3-4-5). 점수 합산에는 항상 14로 계산.
HandResult evaluateHand(List<PlayingCard> cards) {
  assert(cards.length <= 5);
  if (cards.isEmpty) return const HandResult(HandCategory.highCard, 0);

  final full = cards.length == 5;

  // 랭크별 개수
  final counts = <int, int>{};
  for (final c in cards) {
    counts[c.rank] = (counts[c.rank] ?? 0) + 1;
  }
  final groupSizes = counts.values.toList()..sort((a, b) => b - a);
  final maxGroup = groupSizes.first;
  final secondGroup = groupSizes.length > 1 ? groupSizes[1] : 0;

  final isFlush = full && cards.map((c) => c.suit).toSet().length == 1;
  final isStraight = full && _isStraight(counts.keys.toList());

  final HandCategory category;
  if (full && isStraight && isFlush) {
    category = HandCategory.straightFlush;
  } else if (full && maxGroup == 4) {
    category = HandCategory.fourOfAKind;
  } else if (full && maxGroup == 3 && secondGroup == 2) {
    category = HandCategory.fullHouse;
  } else if (isFlush) {
    category = HandCategory.flush;
  } else if (isStraight) {
    category = HandCategory.straight;
  } else if (maxGroup >= 3) {
    // 5장 미만에서 같은 랭크 4개 등은 "5장 필요한 족보" 미성립이므로 트리플로 캡.
    // (추가 동일 랭크 카드는 보너스 점수로 반영됨)
    category = HandCategory.threeOfAKind;
  } else if (maxGroup == 2 && secondGroup == 2) {
    category = HandCategory.twoPair;
  } else if (maxGroup == 2) {
    category = HandCategory.onePair;
  } else {
    category = HandCategory.highCard;
  }

  return HandResult(category, _tiebreakScore(cards, counts));
}

/// 동급 비교용 숫자값: 카드값 합 + 그룹 보너스((개수-1)×랭크값).
int _tiebreakScore(List<PlayingCard> cards, Map<int, int> counts) {
  var total = 0;
  for (final c in cards) {
    total += c.value;
  }
  counts.forEach((rank, count) {
    if (count >= 2) total += (count - 1) * rank; // rank == 점수값 (A=14)
  });
  return total;
}

/// 5개의 서로 다른 랭크가 연속인지. A(14)는 14 또는 1로 시도(A-2-3-4-5).
bool _isStraight(List<int> ranks) {
  if (ranks.length != 5) return false; // 중복 랭크가 있으면 스트레이트 불가
  if (_consecutive(List.of(ranks))) return true;
  if (ranks.contains(Ranks.ace)) {
    final low = ranks.map((r) => r == Ranks.ace ? 1 : r).toList();
    if (low.toSet().length == 5 && _consecutive(low)) return true;
  }
  return false;
}

bool _consecutive(List<int> values) {
  values.sort();
  for (var i = 1; i < values.length; i++) {
    if (values[i] != values[i - 1] + 1) return false;
  }
  return true;
}
