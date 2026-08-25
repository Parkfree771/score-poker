import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:score_poker/l10n/app_localizations.dart';
import 'package:score_poker/l10n/app_localizations_ko.dart';
import 'package:score_poker/ui/game_screen.dart';
import 'package:score_poker/ui/widgets/veil_chip.dart';

/// 부스트 판을 화면에서 실제로 눌러 본다: 칩 4개, 스왑 버튼 → 손패 6장이 전부 새로 온다,
/// 스왑 뒤엔 버튼이 사라진다. 카드를 한 장 놓은 뒤에는 스왑이 없다.
void main() {
  final l10n = AppLocalizationsKo();

  Finder labeled(String label) => find.byWidgetPredicate(
      (w) => w.key is GlobalKey && w.key.toString().contains(label));

  Future<void> pumpFor(WidgetTester tester, Duration total,
      {Duration step = const Duration(milliseconds: 250)}) async {
    for (var t = Duration.zero; t < total; t += step) {
      await tester.pump(step);
    }
  }

  /// 판이 끝날 때까지 타이머·AI 예약을 전부 흘려보낸다(남은 타이머가 있으면 테스트가 깨진다).
  Future<void> drain(WidgetTester tester) => pumpFor(
      tester, const Duration(seconds: 420), step: const Duration(milliseconds: 500));

  Future<void> waitFor(WidgetTester tester, Finder f) async {
    for (var t = 0; t < 40; t++) {
      if (f.evaluate().isNotEmpty) return;
      await tester.pump(const Duration(milliseconds: 250));
    }
    expect(f, findsWidgets);
  }

  testWidgets('부스트 판: 칩 4개 + 스왑 1회', (tester) async {
    tester.view.physicalSize = const Size(430, 930);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MaterialApp(
      locale: Locale('ko'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: GameScreen(seed: 9, boosted: true),
    ));
    await tester.pump();
    await pumpFor(tester, const Duration(seconds: 3));
    await waitFor(tester, find.text(l10n.swapButton));

    // 내 레일에 칩 4개(파랑 링), 상대는 3개.
    final mine = tester
        .widgetList<VeilChip>(find.byType(VeilChip))
        .where((c) => c.filled)
        .length;
    expect(mine, greaterThanOrEqualTo(7), reason: '내 4 + 상대 3 = 채워진 칩 7개');

    expect(labeled('hand-'), findsNWidgets(6));
    await tester.tap(find.text(l10n.swapButton));
    await tester.pump();
    await pumpFor(tester, const Duration(seconds: 3));
    expect(labeled('hand-'), findsNWidgets(6), reason: '스왑 뒤에도 손패는 6장');
    expect(tester.takeException(), isNull);

    // 스왑은 판에 한 번 — 버튼이 사라진다(투명 + 무시).
    final btn = tester.widget<AnimatedOpacity>(find.ancestor(
        of: find.text(l10n.swapButton), matching: find.byType(AnimatedOpacity)).first);
    expect(btn.opacity, 0);

    await drain(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('카드를 한 장 놓으면 스왑 버튼이 사라진다', (tester) async {
    tester.view.physicalSize = const Size(430, 930);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MaterialApp(
      locale: Locale('ko'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: GameScreen(seed: 9, boosted: true),
    ));
    await tester.pump();
    await pumpFor(tester, const Duration(seconds: 3));
    await waitFor(tester, find.text(l10n.swapButton));
    await tester.tap(labeled('hand-0'));
    await tester.pump();
    await tester.tap(labeled('cell-p0-0-0'), warnIfMissed: false);
    await pumpFor(tester, const Duration(milliseconds: 800));
    final btn = tester.widget<AnimatedOpacity>(find.ancestor(
        of: find.text(l10n.swapButton), matching: find.byType(AnimatedOpacity)).first);
    expect(btn.opacity, 0);
    await drain(tester);
    expect(tester.takeException(), isNull);
  });
}
