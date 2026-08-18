import 'package:flutter_test/flutter_test.dart';
import 'package:score_poker/domain/card.dart';
import 'package:score_poker/domain/scoring.dart';

PlayingCard c(int rank, [Suit suit = Suit.clubs]) => PlayingCard(rank, suit);

void main() {
  group('줄 비교', () {
    test('등급이 높으면 숫자 합이 낮아도 이긴다 (스트레이트 > 트리플)', () {
      final straight = [c(5, Suit.clubs), c(6, Suit.hearts), c(7, Suit.spades), c(8, Suit.diamonds), c(9, Suit.clubs)];
      final trips = [c(Ranks.king, Suit.clubs), c(Ranks.king, Suit.hearts), c(Ranks.king, Suit.spades), c(Ranks.queen, Suit.diamonds), c(Ranks.jack, Suit.clubs)];
      expect(compareLine(straight, trips), LineOutcome.win);
    });

    test('같은 등급이면 숫자값이 높은 쪽이 이긴다', () {
      final pairK = [c(Ranks.king, Suit.clubs), c(Ranks.king, Suit.hearts), c(2), c(3), c(4)];
      final pair5 = [c(5, Suit.clubs), c(5, Suit.hearts), c(9), c(8), c(7)];
      expect(compareLine(pairK, pair5), LineOutcome.win);
    });

    test('완전히 같으면 무승부', () {
      final a = [c(7, Suit.clubs), c(7, Suit.hearts)];
      final b = [c(7, Suit.spades), c(7, Suit.diamonds)];
      expect(compareLine(a, b), LineOutcome.tie);
    });
  });

  group('매치 판정', () {
    List<PlayingCard> pair(int r) => [c(r, Suit.clubs), c(r, Suit.hearts)];
    List<PlayingCard> high(int r) => [c(r, Suit.clubs), c(r == 2 ? 3 : 2, Suit.hearts)];

    test('3줄 중 2줄 이기면 승리', () {
      final mine = [pair(Ranks.king), pair(Ranks.queen), high(2)];
      final opp = [high(5), high(6), pair(10)];
      final r = judgeMatch(mine, opp);
      expect(r.lineOutcomes, [LineOutcome.win, LineOutcome.win, LineOutcome.lose]);
      expect(r.outcome, MatchOutcome.win);
    });

    test('1승 1패 1무 → 총점차로 승부', () {
      final mine = [pair(Ranks.ace), high(9), pair(5)]; // 42, 17, 15
      final opp = [high(2), pair(Ranks.ace), pair(5)]; // 5, 42, 15
      final r = judgeMatch(mine, opp);
      expect(r.lineOutcomes, [LineOutcome.win, LineOutcome.lose, LineOutcome.tie]);
      expect(r.myTotal, greaterThan(r.opponentTotal));
      expect(r.outcome, MatchOutcome.win);
    });

    test('모든 줄 비기고 총점 같으면 무승부', () {
      final mine = [pair(5), pair(6), pair(7)];
      final opp = [pair(5), pair(6), pair(7)];
      final r = judgeMatch(mine, opp);
      expect(r.lineOutcomes.every((o) => o == LineOutcome.tie), isTrue);
      expect(r.outcome, MatchOutcome.draw);
    });
  });
}
