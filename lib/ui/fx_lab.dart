import '../domain/card.dart';
import '../domain/game.dart';

/// 연출 실험실(디버그 전용) — 공격(스트라이크)·칩 훔쳐보기·방어막 연출을 **버튼으로
/// 바로** 쏘기 위한 고정 판. 실제 게임에서는 원하는 상황이 드물게 나와 디테일을 잡기
/// 어렵다. `GameScreen(initialGame: fxLabState(), fxLab: true)`로 연다(홈 제목 꾹).
///
/// 배치(스트라이크 룰 v4):
///  - 내 줄0: A♠ A♥ (페어, 앞면) — 상대의 공격 데모 표적(상대 손에 A♣)
///  - 내 줄1: 10♣(앞) 10♦(뒷면) — 상대 칩 훔쳐보기 표적
///  - 상대 줄0: K♦ Q♦ (앞면)
///  - 상대 줄1: 9♠(앞) 9♥(뒷면) — 내 공격(손의 9♦)·훔쳐보기 표적
///  - 상대 줄2: 3♣(뒷면)
ScoreGame fxLabState() {
  final g = ScoreGame.deal(seed: 7);
  const h = Suit.hearts, sp = Suit.spades, d = Suit.diamonds, c = Suit.clubs;
  void put(PlayerId p, int row, List<PlayingCard> cards, {Set<int> hidden = const {}}) {
    for (var i = 0; i < cards.length; i++) {
      g.fields[p]![row][i] = VeiledSlot(cards[i], faceUp: !hidden.contains(i));
    }
  }

  put(PlayerId.p0, 0, [const PlayingCard(14, sp), const PlayingCard(14, h)]);
  put(PlayerId.p0, 1, [const PlayingCard(10, c), const PlayingCard(10, d)],
      hidden: {1});
  put(PlayerId.p0, 2, [const PlayingCard(7, h)]);
  put(PlayerId.p1, 0, [const PlayingCard(13, d), const PlayingCard(12, d)]);
  put(PlayerId.p1, 1, [const PlayingCard(9, sp), const PlayingCard(9, h)], hidden: {1});
  put(PlayerId.p1, 2, [const PlayingCard(3, c)], hidden: {0});
  g.veilLeft[PlayerId.p0] = 2;
  g.veilLeft[PlayerId.p1] = 1;
  g.hands[PlayerId.p0]!
    ..clear()
    ..addAll([
      const PlayingCard(9, d), // 상대 9♠를 쳐낼 수 있다 — 공격 데모
      const PlayingCard.joker(),
      const PlayingCard(13, sp),
      const PlayingCard(4, h),
      const PlayingCard(8, d),
    ]);
  g.hands[PlayerId.p1]!
    ..clear()
    ..addAll([
      const PlayingCard(14, c), // 내 A♠를 쳐낼 수 있다 — 피격 데모
      const PlayingCard(2, sp),
      const PlayingCard(2, h),
      const PlayingCard(6, c),
    ]);
  g.turn = PlayerId.p0;
  g.phase = TurnPhase.action;
  return g;
}
