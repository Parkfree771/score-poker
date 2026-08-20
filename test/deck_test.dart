import 'package:flutter_test/flutter_test.dart';
import 'package:score_poker/domain/card.dart';
import 'package:score_poker/domain/deck.dart';

void main() {
  group('덱', () {
    test('표준 덱은 54장 (52 + 조커 2)', () {
      expect(Deck.standard().remaining, 54);
    });

    test('조커는 정확히 2장, 각 랭크는 4장씩', () {
      final all = Deck.standard().draw(100); // 54장 전부
      expect(all.length, 54);
      expect(all.where((c) => c.isJoker).length, 2);

      final nonJoker = all.where((c) => !c.isJoker);
      for (final rank in Ranks.all) {
        expect(nonJoker.where((c) => c.rank == rank).length, 4, reason: 'rank $rank');
      }
    });

    test('draw는 요청 수만큼 빼고 남은 수를 줄인다', () {
      final deck = Deck.standard();
      final hand = deck.draw(6);
      expect(hand.length, 6);
      expect(deck.remaining, 48);
    });

    test('같은 seed면 셔플 결과가 재현된다', () {
      final a = Deck.shuffled(seed: 42).draw(54);
      final b = Deck.shuffled(seed: 42).draw(54);
      expect(a, b);
    });

    test('덱이 비면 draw는 있는 만큼만 반환', () {
      final deck = Deck.standard();
      deck.draw(54);
      expect(deck.isEmpty, isTrue);
      expect(deck.draw(5), isEmpty);
    });
  });
}
