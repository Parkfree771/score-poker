import 'dart:math';

import 'card.dart';

/// 52장 덱: 13랭크 × 4슈트. (조커 없음 — 가림 룰은 와일드를 쓰지 않는다)
class Deck {
  Deck(this._cards);

  final List<PlayingCard> _cards;

  int get remaining => _cards.length;
  bool get isEmpty => _cards.isEmpty;

  /// 표준 52장 덱(+ 조커 [jokers]장)을 생성한다(셔플 전).
  factory Deck.standard({int jokers = 0}) {
    final cards = <PlayingCard>[];
    for (final suit in Suit.values) {
      for (final rank in Ranks.all) {
        cards.add(PlayingCard(rank, suit));
      }
    }
    for (var i = 0; i < jokers; i++) {
      cards.add(const PlayingCard.joker());
    }
    return Deck(cards);
  }

  /// 셔플된 표준 덱. 테스트 재현성을 위해 [seed] 주입 가능.
  factory Deck.shuffled({int? seed, int jokers = 0}) {
    return Deck.standard(jokers: jokers)..shuffle(Random(seed));
  }

  void shuffle([Random? random]) {
    _cards.shuffle(random);
  }

  /// 맨 위에서 [count]장을 뽑는다. 남은 카드가 모자라면 있는 만큼만 반환.
  List<PlayingCard> draw(int count) {
    final n = count.clamp(0, _cards.length).toInt();
    final drawn = _cards.sublist(0, n);
    _cards.removeRange(0, n);
    return drawn;
  }

  /// 한 장 뽑기. 비어 있으면 null.
  PlayingCard? drawOne() => _cards.isEmpty ? null : _cards.removeAt(0);
}
