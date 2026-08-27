import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:score_poker/domain/card.dart';
import 'package:score_poker/domain/game.dart';
import 'package:score_poker/l10n/app_localizations.dart';
import 'package:score_poker/l10n/app_localizations_ko.dart';
import 'package:score_poker/ui/game_screen.dart';
import 'package:score_poker/ui/widgets/joker_card.dart';

/// 조커를 **화면에서** 써 본다 — 손패 탭 → 칸 탭 → 시트에서 숫자 입력·무늬 선택 → 확정.
/// 정지 모드(initialGame)라 타이머·AI는 돌지 않고, 주입한 [ScoreGame] 인스턴스가
/// 그대로 바뀌므로 규칙 적용을 객체에서 바로 확인한다.
void main() {
  final l10n = AppLocalizationsKo();

  Finder labeled(String label) => find.byWidgetPredicate(
      (w) => w.key is GlobalKey && w.key.toString().contains(label));

  ScoreGame state() {
    final g = ScoreGame.deal(seed: 5, jokers: 0);
    // 상대 판에 카드 셋(하나는 숨김), 내 판은 비어 있다.
    g.fields[PlayerId.p1]![0][0] = VeiledSlot(const PlayingCard(13, Suit.spades), round: 0, faceUp: true);
    g.fields[PlayerId.p1]![0][1] = VeiledSlot(const PlayingCard(13, Suit.hearts), round: 0, faceUp: true);
    g.fields[PlayerId.p1]![1][0] = VeiledSlot(const PlayingCard(9, Suit.clubs), round: 0);
    g.round = 1;
    g.hands[PlayerId.p0]!
      ..clear()
      ..addAll([
        const PlayingCard.joker(),
        const PlayingCard.joker(),
        const PlayingCard(5, Suit.clubs),
        const PlayingCard(8, Suit.diamonds),
        const PlayingCard(4, Suit.hearts),
        const PlayingCard(11, Suit.spades),
      ]);
    return g;
  }

  Future<ScoreGame> pumpGame(WidgetTester tester) async {
    tester.view.physicalSize = const Size(430, 930);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final g = state();
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('ko'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: GameScreen(initialGame: g),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    return g;
  }

  Future<void> settle(WidgetTester tester, [int ms = 700]) async {
    for (var t = 0; t < ms; t += 100) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('와일드: 조커를 K♥로 내 판에 놓는다(뒷면·조커 카드 표시)', (tester) async {
    final g = await pumpGame(tester);
    expect(find.byType(JokerFace), findsNWidgets(2), reason: '손패의 조커 두 장');

    await tester.tap(labeled('hand-0'));
    await tester.pump();
    expect(find.text(l10n.jokerHandTip.replaceFirst('\n', ' · ')), findsWidgets);
    await tester.tap(labeled('cell-p0-2-0'), warnIfMissed: false);
    await settle(tester);
    expect(find.text(l10n.jokerPickWildTitle), findsOneWidget, reason: '선택 시트');
    // 숫자를 정하기 전엔 확정할 수 없다.
    expect(tester.widget<FilledButton>(find.byKey(const ValueKey('joker-confirm'))).onPressed, isNull);

    await tester.enterText(find.byKey(const ValueKey('joker-rank')), 'K');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('joker-suit-hearts')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('joker-confirm')));
    await settle(tester, 1200);

    final slot = g.fields[PlayerId.p0]![2][0];
    expect(slot, isNotNull);
    expect(slot!.card, const PlayingCard(13, Suit.hearts));
    expect(slot.wild, isTrue);
    expect(slot.faceUp, isFalse, reason: '와일드도 뒷면으로 놓인다');
    expect(g.leftToPlace(PlayerId.p0), 2, reason: '3장 배치의 하나');
    // 손패의 조커 1장 + 판 위 와일드 칸(K♥를 든 조커 카드) = 2.
    final faces = tester.widgetList<JokerFace>(find.byType(JokerFace)).toList();
    expect(faces.where((f) => f.as == null).length, 1, reason: '조커 한 장 남음');
    expect(faces.where((f) => f.as == const PlayingCard(13, Suit.hearts)).length, 1,
        reason: '와일드 칸은 K♥ 모서리를 단 조커 카드');
  });

  testWidgets('강타: 상대 숨긴 카드를 2♣로 예고하고, 다시 탭하면 물린다', (tester) async {
    final g = await pumpGame(tester);
    await tester.tap(labeled('hand-0'));
    await tester.pump();
    await tester.tap(labeled('cell-p1-1-0'), warnIfMissed: false);
    await settle(tester);
    expect(find.text(l10n.jokerPickStrikeTitle), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('joker-rank')), '2');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('joker-suit-clubs')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('joker-confirm')));
    await settle(tester, 1200);

    expect(g.pendingStrikes[PlayerId.p0]!.length, 1, reason: '강타 예고');
    expect(g.leftToPlace(PlayerId.p0), 3, reason: '강타는 배치 수를 안 먹는다');
    expect(g.fields[PlayerId.p1]![1][0]!.faceUp, isFalse, reason: '발동 전엔 그대로');
    final faces = tester.widgetList<JokerFace>(find.byType(JokerFace)).toList();
    expect(faces.where((f) => f.as == null).length, 1, reason: '조커 한 장은 상대 카드 위로 갔다');
    expect(faces.where((f) => f.as == const PlayingCard(2, Suit.clubs)).length, 1,
        reason: '예고된 칸은 2♣ 모서리를 단 조커 카드');

    // 물리기.
    await tester.tap(labeled('cell-p1-1-0'), warnIfMissed: false);
    await settle(tester);
    expect(g.pendingStrikes[PlayerId.p0], isEmpty);
    expect(find.byType(JokerFace), findsNWidgets(2), reason: '조커가 손으로 돌아왔다');

    // 발동: 공개 후 resolve — 숨긴 카드가 2♣ 앞면이 된다.
    g.declareStrike(PlayerId.p0, 0, 1, 0, const PlayingCard(2, Suit.clubs));
    g.resolveStrikes();
    final struck = g.fields[PlayerId.p1]![1][0]!;
    expect(struck.card, const PlayingCard(2, Suit.clubs));
    expect(struck.faceUp, isTrue);
    expect(struck.strikeBy, PlayerId.p0);
  });

  testWidgets('빈 칸엔 강타할 수 없다 — 시트가 열리지 않는다', (tester) async {
    await pumpGame(tester);
    await tester.tap(labeled('hand-0'));
    await tester.pump();
    await tester.tap(labeled('cell-p1-2-3'), warnIfMissed: false);
    await settle(tester);
    expect(find.text(l10n.jokerPickStrikeTitle), findsNothing);
  });
}
