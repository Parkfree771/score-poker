import 'card.dart';
import 'hand.dart';

/// 한 줄 대결 결과(나 기준).
enum LineOutcome { win, lose, tie }

/// 매치 최종 결과(나 기준).
enum MatchOutcome { win, lose, draw }

/// 한 줄(나/상대 각 최대 5장)을 비교한다.
LineOutcome compareLine(List<PlayingCard> mine, List<PlayingCard> opponent) {
  final cmp = evaluateHand(mine).compareTo(evaluateHand(opponent));
  if (cmp > 0) return LineOutcome.win;
  if (cmp < 0) return LineOutcome.lose;
  return LineOutcome.tie;
}

/// 한 줄의 숫자값(총점차 계산용).
int lineScore(List<PlayingCard> cards) => evaluateHand(cards).score;

/// 3줄 보드의 매치 판정 결과.
class MatchResult {
  const MatchResult({
    required this.outcome,
    required this.lineOutcomes,
    required this.myTotal,
    required this.opponentTotal,
  });

  final MatchOutcome outcome;
  final List<LineOutcome> lineOutcomes; // 길이 3
  final int myTotal;
  final int opponentTotal;

  @override
  String toString() =>
      'MatchResult($outcome, lines=$lineOutcomes, $myTotal vs $opponentTotal)';
}

/// 매치 판정(나 기준). [myRows]/[opponentRows]는 각각 길이 3의 줄 목록.
///
/// 규칙(GAME_DESIGN.md §5.4):
/// 1. 3줄 중 2줄 이상 이기면 승리.
/// 2. 2줄에 못 미치면 양측 총점차(전 줄 숫자값 합)로 판정.
/// 3. 총점차도 같으면 무승부.
MatchResult judgeMatch(
  List<List<PlayingCard>> myRows,
  List<List<PlayingCard>> opponentRows,
) {
  assert(myRows.length == 3 && opponentRows.length == 3);

  final lineOutcomes = <LineOutcome>[];
  var myWins = 0;
  var oppWins = 0;
  var myTotal = 0;
  var oppTotal = 0;

  for (var i = 0; i < 3; i++) {
    final outcome = compareLine(myRows[i], opponentRows[i]);
    lineOutcomes.add(outcome);
    if (outcome == LineOutcome.win) myWins++;
    if (outcome == LineOutcome.lose) oppWins++;
    myTotal += lineScore(myRows[i]);
    oppTotal += lineScore(opponentRows[i]);
  }

  final MatchOutcome outcome;
  if (myWins >= 2) {
    outcome = MatchOutcome.win;
  } else if (oppWins >= 2) {
    outcome = MatchOutcome.lose;
  } else if (myTotal > oppTotal) {
    outcome = MatchOutcome.win;
  } else if (myTotal < oppTotal) {
    outcome = MatchOutcome.lose;
  } else {
    outcome = MatchOutcome.draw;
  }

  return MatchResult(
    outcome: outcome,
    lineOutcomes: lineOutcomes,
    myTotal: myTotal,
    opponentTotal: oppTotal,
  );
}
