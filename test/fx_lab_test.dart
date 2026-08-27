import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:score_poker/l10n/app_localizations.dart';
import 'package:score_poker/ui/fx_lab.dart';
import 'package:score_poker/ui/game_screen.dart';
import 'package:score_poker/ui/theme.dart';

/// 연출 실험실 — 버튼마다 연출이 예외 없이 끝까지 돌고, 다음 버튼은 같은 출발점에서 다시 돈다.
void main() {
  Widget app() => MaterialApp(
        theme: buildAppTheme(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('ko'),
        home: GameScreen(initialGame: fxLabState(), fxLab: true),
      );

  testWidgets('강타·칩 버튼이 연출을 끝까지 돌린다', (tester) async {
    tester.view.physicalSize = const Size(430, 930);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(app());
    await tester.pump(const Duration(milliseconds: 600));
    for (final label in ['강타 나→상대', '강타 상대→나', '강타 둘 다', '칩 나→상대', '칩 상대→나']) {
      expect(find.text(label), findsOneWidget, reason: label);
      await tester.tap(find.text(label));
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 150));
      }
      expect(tester.takeException(), isNull, reason: label);
    }
  });
}
