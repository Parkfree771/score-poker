import 'package:flutter_test/flutter_test.dart';
import 'package:score_poker/domain/card.dart';
import 'package:score_poker/domain/deck.dart';
import 'package:score_poker/domain/hand.dart';

/// `docs/RULES.md`에 적힌 예시와 단언을 그대로 검증한다.
/// 규칙서와 엔진이 어긋나면 여기서 깨진다 — 규칙서는 외부(다른 AI 등)에 배포되므로
/// 문서가 틀리는 것이 코드가 틀리는 것만큼 위험하다.
void main() {
  PlayingCard c(int rank, [Suit s = Suit.clubs]) => PlayingCard(rank, s);

  group('RULES.md §2.1 덱 구성', () {
    test('58장 = 14랭크 × 4슈트 + 조커 2', () {
      final deck = Deck.standard();
      expect(deck.remaining, 58);
      final all = deck.draw(58);
      expect(all.where((x) => x.isJoker).length, 2);
      expect(all.where((x) => !x.isJoker).length, 56);
    });

    test('모든 랭크가 정확히 4장씩', () {
      final all = Deck.standard().draw(58).where((x) => !x.isJoker);
      for (final rank in Ranks.all) {
        expect(all.where((x) => x.rank == rank).length, 4, reason: 'rank $rank');
      }
      expect(Ranks.all.length, 14);
    });

    test('숫자값: 1~10 그대로, J=11 Q=12 K=13 A=14', () {
      expect(c(1).value, 1);
      expect(c(10).value, 10);
      expect(c(Ranks.jack).value, 11);
      expect(c(Ranks.queen).value, 12);
      expect(c(Ranks.king).value, 13);
      expect(c(Ranks.ace).value, 14);
    });

    test('슈트 순위 ♠ > ♥ > ♦ > ♣', () {
      expect(Suit.spades.order > Suit.hearts.order, isTrue);
      expect(Suit.hearts.order > Suit.diamonds.order, isTrue);
      expect(Suit.diamonds.order > Suit.clubs.order, isTrue);
    });
  });

  group('RULES.md §8.3 숫자값 예시', () {
    test('A A (2장) = 42', () {
      expect(evaluateHand([c(14, Suit.spades), c(14, Suit.hearts)]).score, 42);
    });

    test('3 3 3 (3장) = 15', () {
      expect(
          evaluateHand([c(3, Suit.spades), c(3, Suit.hearts), c(3, Suit.diamonds)]).score, 15);
    });

    test('2♠ 5♥ 9♦ J♣ K♠ = 40 (하이카드)', () {
      final line = [
        c(2, Suit.spades),
        c(5, Suit.hearts),
        c(9, Suit.diamonds),
        c(Ranks.jack, Suit.clubs),
        c(Ranks.king, Suit.spades),
      ];
      final r = evaluateHand(line);
      expect(r.score, 40);
      expect(r.category, HandCategory.highCard);
    });

    test('K K K Q Q (풀하우스) = 101', () {
      final line = [
        c(13, Suit.spades),
        c(13, Suit.hearts),
        c(13, Suit.diamonds),
        c(12, Suit.clubs),
        c(12, Suit.spades),
      ];
      final r = evaluateHand(line);
      expect(r.category, HandCategory.fullHouse);
      expect(r.score, 101);
    });

    test('7 7 7 7 (4장) = 49, 트리플로 판정', () {
      final line = [
        c(7, Suit.spades),
        c(7, Suit.hearts),
        c(7, Suit.diamonds),
        c(7, Suit.clubs),
      ];
      final r = evaluateHand(line);
      expect(r.score, 49);
      expect(r.category, HandCategory.threeOfAKind, reason: '5칸이 안 찼으면 포카드 미성립');
    });
  });

  group('RULES.md §8.2 족보 성립 조건', () {
    test('스트레이트: 1 2 3 4 5 / A 1 2 3 4 / 10 J Q K A 모두 성립', () {
      for (final ranks in [
        [1, 2, 3, 4, 5],
        [Ranks.ace, 1, 2, 3, 4],
        [10, Ranks.jack, Ranks.queen, Ranks.king, Ranks.ace],
      ]) {
        final line = [
          for (var i = 0; i < 5; i++) c(ranks[i], Suit.values[i % 4]),
        ];
        expect(evaluateHand(line).category, HandCategory.straight, reason: '$ranks');
      }
    });

    test('숫자가 중복되면 스트레이트 아님', () {
      final line = [c(3), c(3, Suit.hearts), c(4), c(5), c(6)];
      expect(evaluateHand(line).category, isNot(HandCategory.straight));
    });

    test('4장짜리 같은 슈트는 플러쉬가 아니다', () {
      final line = [
        c(2, Suit.hearts),
        c(5, Suit.hearts),
        c(9, Suit.hearts),
        c(13, Suit.hearts),
      ];
      expect(evaluateHand(line).category, HandCategory.highCard);
    });

    test('5장 같은 슈트는 플러쉬', () {
      final line = [
        c(2, Suit.hearts),
        c(5, Suit.hearts),
        c(9, Suit.hearts),
        c(13, Suit.hearts),
        c(7, Suit.hearts),
      ];
      expect(evaluateHand(line).category, HandCategory.flush);
    });

    test('족보 등급 순서가 정통 포커와 같다', () {
      const expected = [
        HandCategory.highCard,
        HandCategory.onePair,
        HandCategory.twoPair,
        HandCategory.threeOfAKind,
        HandCategory.straight,
        HandCategory.flush,
        HandCategory.fullHouse,
        HandCategory.fourOfAKind,
        HandCategory.straightFlush,
        HandCategory.fiveOfAKind,
      ];
      expect(HandCategory.values, expected);
    });
  });
}
