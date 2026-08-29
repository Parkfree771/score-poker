import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:score_poker/domain/card.dart';
import 'package:score_poker/domain/game.dart';
import 'package:score_poker/l10n/app_localizations.dart';
import 'package:score_poker/l10n/app_localizations_ko.dart';
import 'package:score_poker/ui/game_screen.dart';
import 'package:score_poker/ui/widgets/joker_card.dart';

/// 조커(와일드)를 **화면에서** 써 본다 — 손패 탭 → 칸 탭 → 시트에서 숫자·무늬 → 확정.
/// 정지 모드(initialGame)라 타이머·봇은 돌지 않고, 주입한 [ScoreGame]이 그대로
/// 바뀌므로 규칙 적용을 객체에서 바로 확인한다. (v4에서 조커 강타는 없다 —
/// 공격은 일반 카드의 랭크 매칭이다.)
void main() {
  final l10n = AppLocalizationsKo();

  Finder labeled(String label) => find.byWidgetPredicate(
      (w) => w.key is GlobalKey && w.key.toString().contains(label));

  ScoreGame state() {
    final g = ScoreGame.deal(seed: 5, jokers: 0);
    // 상대 판에 카드 셋(하나는 뒷면), 내 판은 비어 있다. 내 턴.
    g.fields[PlayerId.p1]![0][0] =
        VeiledSlot(const PlayingCard(13, Suit.spades), faceUp: true);
    g.fields[PlayerId.p1]![0][1] =
        VeiledSlot(const PlayingCard(13, Suit.hearts), faceUp: true);
    g.fields[PlayerId.p1]![1][0] = VeiledSlot(const PlayingCard(9, Suit.clubs));
    g.hands[PlayerId.p0]!
      ..clear()
      ..addAll([
        const PlayingCard.joker(),
        const PlayingCard.joker(),
        const PlayingCard(5, Suit.clubs),
        const PlayingCard(8, Suit.diamonds),
        const PlayingCard(4, Suit.hearts),
      ]);
    g.turn = PlayerId.p0;
    g.phase = TurnPhase.action;
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

  testWidgets('와일드: 조커를 K♥로 내 판에 놓는다(앞면·조커 카드 표시)', (tester) async {
    final g = await pumpGame(tester);
    expect(find.byType(JokerFace), findsNWidgets(2), reason: '손패의 조커 두 장');

    await tester.tap(labeled('hand-0'));
    await tester.pump();
    await tester.tap(labeled('cell-p0-2-0'), warnIfMissed: false);
    await settle(tester);
    expect(find.text(l10n.jokerPickWildTitle), findsOneWidget, reason: '선택 시트');
    // 숫자를 정하기 전엔 확정할 수 없다.
    expect(
        tester
            .widget<FilledButton>(find.byKey(const ValueKey('joker-confirm')))
            .onPressed,
        isNull);

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
    expect(slot.faceUp, isTrue, reason: 'v4 기본은 앞면(뒷면은 칩 토글)');
    expect(g.turn, PlayerId.p1, reason: '배치는 턴을 쓴다');
    // 손패의 조커 1장 + 판 위 와일드 칸(K♥를 든 조커 카드) = 2.
    final faces = tester.widgetList<JokerFace>(find.byType(JokerFace)).toList();
    expect(faces.where((f) => f.as == null).length, 1, reason: '조커 한 장 남음');
    expect(
        faces.where((f) => f.as == const PlayingCard(13, Suit.hearts)).length, 1,
        reason: '와일드 칸은 K♥ 모서리를 단 조커 카드');
  });

  testWidgets('조커를 든 채 상대 카드를 탭해도 아무 일 없다(강타 없음)', (tester) async {
    final g = await pumpGame(tester);
    await tester.tap(labeled('hand-0'));
    await tester.pump();
    await tester.tap(labeled('cell-p1-0-0'), warnIfMissed: false);
    await settle(tester);
    expect(find.text(l10n.jokerPickWildTitle), findsNothing);
    expect(find.text(l10n.jokerPickStrikeTitle), findsNothing);
    expect(g.hands[PlayerId.p0]!.length, 5, reason: '조커는 그대로 손에 있다');
  });

  testWidgets('일반 카드 랭크 매칭 공격이 화면에서 동작한다', (tester) async {
    final g = await pumpGame(tester);
    // 손에 K를 쥐여 주면 상대 K♠(0,0)가 표적이 된다.
    g.hands[PlayerId.p0]![2] = const PlayingCard(13, Suit.diamonds);
    final st = tester.state(find.byType(GameScreen)) as dynamic;
    // ignore: invalid_use_of_protected_member
    st.setState(() {});
    await tester.pump();

    await tester.tap(labeled('hand-2'));
    await tester.pump();
    await tester.tap(labeled('cell-p1-0-0'), warnIfMissed: false);
    await settle(tester, 2500);

    // 표적 제거 + 왼쪽 당김: (0,0)에 K♥가 온다.
    expect(g.fields[PlayerId.p1]![0][0]!.card, const PlayingCard(13, Suit.hearts));
    expect(g.fields[PlayerId.p1]![0][1], isNull);
    // 방어막 카드가 대기 중이거나 이미 배치됐다(덱이 넉넉하니 대기).
    expect(g.phase, TurnPhase.shield);
    expect(g.pendingShield, isNotNull);

    // 방어막을 상대 줄1(9♣ 옆)에 꽂는다 — 다음 칸(1,1).
    await tester.tap(labeled('cell-p1-1-1'), warnIfMissed: false);
    await settle(tester, 1500);
    expect(g.fields[PlayerId.p1]![1][1], isNotNull);
    expect(g.fields[PlayerId.p1]![1][1]!.shield, isTrue);
    expect(g.turn, PlayerId.p1, reason: '방어막 배치로 턴 종료');
  });
}
