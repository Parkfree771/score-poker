import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:score_poker/domain/card.dart';
import 'package:score_poker/l10n/app_localizations.dart';
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
      const PlayingCard(5, Suit.hearts),
      const PlayingCard(2, Suit.diamonds),
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

    // 라인1: 내가 우세, 라인2: 비슷, 라인3: 상대 우세 (왼쪽부터 채움 = col0,1..)
    final g = ScoreGame.deal(seed: 3);
    void put(PlayerId p, int row, int col, PlayingCard c) =>
        g.fields[p]![row][col] = VeiledSlot(c, round: 0, faceUp: true);
    put(PlayerId.p0, 0, 0, const PlayingCard(Ranks.king, Suit.hearts));
    put(PlayerId.p0, 0, 1, const PlayingCard(Ranks.king, Suit.spades));
    put(PlayerId.p1, 0, 0, const PlayingCard(3, Suit.clubs));
    put(PlayerId.p0, 1, 0, const PlayingCard(9, Suit.diamonds));
    put(PlayerId.p1, 1, 0, const PlayingCard(9, Suit.clubs));
    put(PlayerId.p1, 1, 1, const PlayingCard(Ranks.queen, Suit.diamonds));
    put(PlayerId.p1, 2, 0, const PlayingCard(10, Suit.hearts));
    put(PlayerId.p1, 2, 1, const PlayingCard(8, Suit.spades));
    put(PlayerId.p0, 2, 0, const PlayingCard(2, Suit.clubs));
    // 가림 룰의 상태 3종을 한 컷에: 상대 뒷면 / 내 홀카드 / 봉인.
    g.fields[PlayerId.p1]![0][1] = VeiledSlot(const PlayingCard(7, Suit.hearts), round: 1);
    g.fields[PlayerId.p0]![1][1] = VeiledSlot(const PlayingCard(4, Suit.spades), round: 1);
    g.fields[PlayerId.p0]![2][1] = VeiledSlot(const PlayingCard(Ranks.ace, Suit.clubs), round: 1);

    await tester.pumpWidget(MaterialApp(
      // 점수 알약이 족보 이름을 쓰므로 실제 앱과 같은 로컬라이제이션을 물린다.
      locale: const Locale('ko'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        backgroundColor: AppColors.bgBottom,
        body: BoardView(
          cellAt: g.cellAt,
          viewer: PlayerId.p0,
          onCellTap: (_, __, ___) {},
          lookOf: (owner, row, col) {
            final slot = g.fields[owner]![row][col];
            if (slot == null || slot.faceUp) return CellLook.face;
            if (owner != PlayerId.p0) return CellLook.backVeiled;
            return col == 1 && row == 2 ? CellLook.sealed : CellLook.peek;
          },
          lineCardsOf: (p, line) => g.publicRow(p, line),
        ),
      ),
    ));
    // 덮인 카드의 일렁거림은 계속 돌기 때문에 pumpAndSettle이 끝나지 않는다 — 고정 펌프.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    await expectLater(find.byType(BoardView), matchesGoldenFile('goldens/board.png'));
  });
}
