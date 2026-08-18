import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:score_poker/domain/card.dart';
import 'package:score_poker/domain/deck.dart';
import 'package:score_poker/domain/game.dart';
import 'package:score_poker/ui/theme.dart';
import 'package:score_poker/ui/widgets/board_view.dart';
import 'package:score_poker/ui/widgets/card_face.dart';

void main() {
  testWidgets('GOLDEN: 카드 비주얼', (tester) async {
    final cards = <PlayingCard>[
      const PlayingCard(Ranks.ace, Suit.hearts),
      const PlayingCard(10, Suit.diamonds),
      const PlayingCard(Ranks.king, Suit.clubs),
      const PlayingCard(7, Suit.spades),
      const PlayingCard(5, Suit.hearts, isShield: true),
      PlayingCard.undesignatedJoker(),
    ];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        backgroundColor: AppColors.bgBottom,
        body: Center(
          child: Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [for (final c in cards) CardFace(card: c, size: 90)],
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    await expectLater(find.byType(Wrap), matchesGoldenFile('goldens/cards.png'));
  });

  testWidgets('GOLDEN: 보드 레이아웃', (tester) async {
    tester.view.physicalSize = const Size(900, 620);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final g = GameState.custom(Deck(<PlayingCard>[]));
    // 라인1: 내가 우세, 라인2: 비슷, 라인3: 상대 우세 (중앙부터 채움 = col0,1..)
    void put(PlayerId p, int row, int col, PlayingCard c) =>
        g.fields[p]![row][col] = PlacedCard(c, p);
    put(PlayerId.p0, 0, 0, const PlayingCard(Ranks.king, Suit.hearts));
    put(PlayerId.p0, 0, 1, const PlayingCard(Ranks.king, Suit.spades));
    put(PlayerId.p1, 0, 0, const PlayingCard(3, Suit.clubs));
    put(PlayerId.p0, 1, 0, const PlayingCard(9, Suit.diamonds));
    put(PlayerId.p1, 1, 0, const PlayingCard(9, Suit.clubs));
    put(PlayerId.p1, 1, 1, PlayingCard.undesignatedJoker());
    put(PlayerId.p1, 2, 0, const PlayingCard(10, Suit.hearts));
    put(PlayerId.p1, 2, 1, const PlayingCard(8, Suit.spades, isShield: true));
    put(PlayerId.p0, 2, 0, const PlayingCard(2, Suit.clubs));

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        backgroundColor: AppColors.bgBottom,
        body: BoardView(state: g, viewer: PlayerId.p0, onCellTap: (_, __, ___) {}),
      ),
    ));
    await tester.pumpAndSettle();
    await expectLater(find.byType(BoardView), matchesGoldenFile('goldens/board.png'));
  });
}
