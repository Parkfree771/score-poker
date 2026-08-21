import 'package:flutter_test/flutter_test.dart';
import 'package:score_poker/domain/card.dart';
import 'package:score_poker/domain/deck.dart';

void main() {
  group('덱', () {
    test('표준 덱은 52장 (조커 없음)', () {
      expect(Deck.standard().remaining, 52);
    });

    test('각 랭크는 4장씩', () {
      final all = Deck.standard().draw(100); // 52장 전부
      expect(all.length, 52);
      for (final rank in Ranks.all) {
        expect(all.where((c) => c.rank == rank).length, 4, reason: 'rank $rank');
      }
    });

    test('draw는 요청 수만큼 빼고 남은 수를 줄인다', () {
      final deck = Deck.standard();
      final hand = deck.draw(6);
      expect(hand.length, 6);
      expect(deck.remaining, 46);
    });

    test('같은 seed면 셔플 결과가 재현된다', () {
      final a = Deck.shuffled(seed: 42).draw(52);
      final b = Deck.shuffled(seed: 42).draw(52);
      expect(a, b);
    });

    test('덱이 비면 draw는 있는 만큼만 반환', () {
      final deck = Deck.standard();
      deck.draw(52);
      expect(deck.isEmpty, isTrue);
      expect(deck.draw(5), isEmpty);
    });
  });
}
