import 'dart:math';

import 'card.dart';

/// 54장 덱(표준 포커 + 조커): 13랭크 × 4슈트(52장) + 조커 2장.
class Deck {
  Deck(this._cards);

  final List<PlayingCard> _cards;

  int get remaining => _cards.length;
  bool get isEmpty => _cards.isEmpty;

  /// 표준 54장 덱을 생성한다(셔플 전). 조커는 미지정 상태로 2장 포함.
  factory Deck.standard() {
    final cards = <PlayingCard>[];
    for (final suit in Suit.values) {
      for (final rank in Ranks.all) {
        cards.add(PlayingCard(rank, suit));
      }
    }
    cards.add(PlayingCard.undesignatedJoker());
    cards.add(PlayingCard.undesignatedJoker());
    return Deck(cards);
  }

  /// 셔플된 표준 덱. 테스트 재현성을 위해 [seed] 주입 가능.
  factory Deck.shuffled({int? seed}) {
    return Deck.standard()..shuffle(Random(seed));
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
