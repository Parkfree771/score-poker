import '../domain/card.dart';
import '../domain/game.dart';

/// 연출 실험실(디버그 전용) — 조커 강타·비공개권 칩 튕김을 **버튼으로 바로** 쏘기 위한
/// 고정 판. 실제 게임에서는 두 연출이 드물게 나와 디테일을 잡기 어렵다.
/// `GameScreen(initialGame: fxLabState(), fxLab: true)`로 연다. 홈 앱바의 플라스크 아이콘.
///
/// 배치:
///  - 내 (1,1) 숨김 10♦ / 상대 (1,1) 숨김 9♥, (2,0) 숨김 3♣ → 칩 열어보기 표적
///  - 상대 (1,0) 9♠에 내 강타(A♥) 예고 / 내 (1,0) 10♣에 상대 강타(2♣) 예고
ScoreGame fxLabState() {
  final g = ScoreGame.deal(seed: 7);
  const h = Suit.hearts, sp = Suit.spades, d = Suit.diamonds, c = Suit.clubs;
  void place(PlayerId p, int row, List<PlayingCard> cards, {Set<int> hidden = const {}}) {
    for (var i = 0; i < cards.length; i++) {
      g.fields[p]![row][i] = VeiledSlot(cards[i], round: i, faceUp: !hidden.contains(i));
    }
  }

  place(PlayerId.p0, 0, [const PlayingCard(14, sp), const PlayingCard(14, h)]);
  place(PlayerId.p0, 1, [const PlayingCard(10, c), const PlayingCard(10, d), const PlayingCard(10, sp)],
      hidden: {1}); // 이번 라운드(2) 카드는 열어볼 수 없다 — 지난 라운드 카드를 숨긴다.
  place(PlayerId.p0, 2, [const PlayingCard(7, h)]);
  place(PlayerId.p1, 0, [const PlayingCard(13, d), const PlayingCard(12, d)]);
  place(PlayerId.p1, 1, [const PlayingCard(9, sp), const PlayingCard(9, h)], hidden: {1});
  place(PlayerId.p1, 2, [const PlayingCard(3, c)], hidden: {0});
  g.round = 2;
  g.veilLeft[PlayerId.p0] = 2;
  g.veilLeft[PlayerId.p1] = 1;
  g.hands[PlayerId.p0]!
    ..clear()
    ..addAll([
      const PlayingCard.joker(),
      const PlayingCard(5, c),
      const PlayingCard(13, sp),
      const PlayingCard(4, h),
      const PlayingCard(8, d),
    ]);
  g.hands[PlayerId.p1]!
    ..clear()
    ..addAll([for (var i = 0; i < 4; i++) const PlayingCard(2, sp)]);
  g.pendingStrikes[PlayerId.p0]!.add(const JokerStrike(
      by: PlayerId.p0, row: 1, col: 0, card: PlayingCard(14, Suit.hearts)));
  g.pendingStrikes[PlayerId.p1]!.add(const JokerStrike(
      by: PlayerId.p1, row: 1, col: 0, card: PlayingCard(2, Suit.clubs)));
  return g;
}
