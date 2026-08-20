import 'package:flutter_test/flutter_test.dart';
import 'package:score_poker/domain/card.dart';
import 'package:score_poker/domain/hand.dart';

/// 테스트 헬퍼: 슈트는 기본 ♣(플러쉬 오판 방지용으로 섞어 씀).
PlayingCard c(int rank, [Suit suit = Suit.clubs]) => PlayingCard(rank, suit);

void main() {
  group('족보 등급 판정', () {
    test('하이카드', () {
      final h = evaluateHand([
        c(2, Suit.clubs),
        c(5, Suit.hearts),
        c(7, Suit.spades),
        c(9, Suit.diamonds),
        c(Ranks.jack, Suit.clubs),
      ]);
      expect(h.category, HandCategory.highCard);
    });

    test('원페어', () {
      final h = evaluateHand([
        c(10, Suit.clubs),
        c(10, Suit.hearts),
        c(3, Suit.spades),
        c(6, Suit.diamonds),
        c(9, Suit.clubs),
      ]);
      expect(h.category, HandCategory.onePair);
    });

    test('투페어', () {
      final h = evaluateHand([
        c(8, Suit.clubs),
        c(8, Suit.hearts),
        c(5, Suit.spades),
        c(5, Suit.diamonds),
        c(2, Suit.clubs),
      ]);
      expect(h.category, HandCategory.twoPair);
    });

    test('트리플', () {
      final h = evaluateHand([
        c(7, Suit.clubs),
        c(7, Suit.hearts),
        c(7, Suit.spades),
        c(2, Suit.diamonds),
        c(5, Suit.clubs),
      ]);
      expect(h.category, HandCategory.threeOfAKind);
    });

    test('스트레이트 (일반)', () {
      final h = evaluateHand([
        c(5, Suit.clubs),
        c(6, Suit.hearts),
        c(7, Suit.spades),
        c(8, Suit.diamonds),
        c(9, Suit.clubs),
      ]);
      expect(h.category, HandCategory.straight);
    });

    test('스트레이트 (A를 14로: 10-J-Q-K-A)', () {
      final h = evaluateHand([
        c(10, Suit.clubs),
        c(Ranks.jack, Suit.hearts),
        c(Ranks.queen, Suit.spades),
        c(Ranks.king, Suit.diamonds),
        c(Ranks.ace, Suit.clubs),
      ]);
      expect(h.category, HandCategory.straight);
    });

    test('스트레이트 (A를 1로: A-2-3-4-5, 휠)', () {
      final h = evaluateHand([
        c(Ranks.ace, Suit.clubs),
        c(2, Suit.hearts),
        c(3, Suit.spades),
        c(4, Suit.diamonds),
        c(5, Suit.clubs),
      ]);
      expect(h.category, HandCategory.straight);
    });

    test('A-3-4-5-6 은 스트레이트 아님 (2가 빠짐)', () {
      final h = evaluateHand([
        c(Ranks.ace, Suit.clubs),
        c(3, Suit.hearts),
        c(4, Suit.spades),
        c(5, Suit.diamonds),
        c(6, Suit.clubs),
      ]);
      expect(h.category, isNot(HandCategory.straight));
    });

    test('플러쉬', () {
      final h = evaluateHand([
        c(2, Suit.spades),
        c(5, Suit.spades),
        c(7, Suit.spades),
        c(9, Suit.spades),
        c(Ranks.jack, Suit.spades),
      ]);
      expect(h.category, HandCategory.flush);
    });

    test('풀하우스', () {
      final h = evaluateHand([
        c(Ranks.king, Suit.clubs),
        c(Ranks.king, Suit.hearts),
        c(Ranks.king, Suit.spades),
        c(Ranks.queen, Suit.diamonds),
        c(Ranks.queen, Suit.clubs),
      ]);
      expect(h.category, HandCategory.fullHouse);
    });

    test('포카드', () {
      final h = evaluateHand([
        c(9, Suit.clubs),
        c(9, Suit.hearts),
        c(9, Suit.spades),
        c(9, Suit.diamonds),
        c(2, Suit.clubs),
      ]);
      expect(h.category, HandCategory.fourOfAKind);
    });

    test('스트레이트 플러쉬', () {
      final h = evaluateHand([
        c(6, Suit.spades),
        c(7, Suit.spades),
        c(8, Suit.spades),
        c(9, Suit.spades),
        c(10, Suit.spades),
      ]);
      expect(h.category, HandCategory.straightFlush);
    });

    test('파이브 카드 (조커 와일드 포함)', () {
      final h = evaluateHand(const [
        PlayingCard(Ranks.king, Suit.clubs),
        PlayingCard(Ranks.king, Suit.hearts),
        PlayingCard(Ranks.king, Suit.spades),
        PlayingCard(Ranks.king, Suit.diamonds),
        PlayingCard(Ranks.king, Suit.spades, isJoker: true), // 조커 → K 지정
      ]);
      expect(h.category, HandCategory.fiveOfAKind);
    });
  });

  group('동급 숫자값(보너스 포함)', () {
    test('AA = 28 + 14 = 42', () {
      final h = evaluateHand([c(Ranks.ace, Suit.clubs), c(Ranks.ace, Suit.hearts)]);
      expect(h.category, HandCategory.onePair);
      expect(h.score, 42);
    });

    test('333 = 9 + 6 = 15', () {
      final h = evaluateHand([
        c(3, Suit.clubs),
        c(3, Suit.hearts),
        c(3, Suit.spades),
      ]);
      expect(h.category, HandCategory.threeOfAKind);
      expect(h.score, 15);
    });
  });

  group('미완성 줄(5장 미만)', () {
    test('4장 같은 랭크는 포카드 아님 → 트리플로 캡', () {
      final h = evaluateHand([
        c(9, Suit.clubs),
        c(9, Suit.hearts),
        c(9, Suit.spades),
        c(9, Suit.diamonds),
      ]);
      expect(h.category, HandCategory.threeOfAKind);
    });

    test('4장 연속이라도 스트레이트 미성립', () {
      final h = evaluateHand([
        c(5, Suit.clubs),
        c(6, Suit.hearts),
        c(7, Suit.spades),
        c(8, Suit.diamonds),
      ]);
      expect(h.category, HandCategory.highCard);
    });
  });
}
