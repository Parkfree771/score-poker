import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:score_poker/l10n/app_localizations.dart';
import 'package:score_poker/l10n/app_localizations_en.dart';
import 'package:score_poker/ui/game_screen.dart';
import 'package:score_poker/ui/widgets/board_view.dart';

Widget _app() => MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: ThemeData(brightness: Brightness.dark, useMaterial3: true),
      home: const GameScreen(seed: 1),
    );

/// 디버그 라벨이 붙은 GlobalKey로 위젯을 찾는다(칸: `cell-p0-0-0`, 손패: `hand-0`).
Finder _labeled(String label) => find.byWidgetPredicate(
    (w) => w.key is GlobalKey && w.key.toString().contains(label));

/// 딜링 연출(12장이 한 장씩 날아온다)을 끝까지 흘려보낸다 → 배치 단계.
Future<void> _finishDealing(WidgetTester tester) async {
  await tester.pump();
  for (var i = 0; i < 30; i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }
}

/// 판이 끝날 때까지(5라운드 × 60초 타이머 + 연출) 가짜 시간을 흘린다.
///
/// 화면은 라운드 타이머와 AI 예약을 계속 돌리므로, **끝까지 돌리지 않으면**
/// 테스트 종료 시 살아 있는 타이머 때문에 실패한다.
Future<void> _playToEnd(WidgetTester tester) async {
  for (var i = 0; i < 900; i++) {
    await tester.pump(const Duration(milliseconds: 500));
  }
}

void main() {
  testWidgets('딜링이 끝나면 보드와 손패 6장이 보인다 (세로)', (tester) async {
    tester.view.physicalSize = const Size(400, 850);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_app());
    await _finishDealing(tester);

    expect(find.byType(BoardView), findsOneWidget);
    expect(_labeled('hand-'), findsNWidgets(6)); // 시작 손패 6장
    expect(tester.takeException(), isNull);

    await _playToEnd(tester);
  });

  testWidgets('가로에서도 오류 없이 보드가 나온다', (tester) async {
    tester.view.physicalSize = const Size(900, 450);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_app());
    await _finishDealing(tester);
    expect(find.byType(BoardView), findsOneWidget);
    expect(tester.takeException(), isNull);

    await _playToEnd(tester);
  });

  testWidgets('손패를 골라 칸을 탭하면 손에서 빠진다', (tester) async {
    tester.view.physicalSize = const Size(400, 850);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_app());
    await _finishDealing(tester);

    await tester.tap(_labeled('hand-0'));
    await tester.pump();
    await tester.tap(_labeled('cell-p0-0-0'), warnIfMissed: false);
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 150));
    }
    expect(_labeled('hand-'), findsNWidgets(5));
    expect(tester.takeException(), isNull);

    await _playToEnd(tester);
  });

  testWidgets('끝까지 돌리면 결과가 뜬다 (배치는 자동으로 채워진다)', (tester) async {
    tester.view.physicalSize = const Size(400, 850);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_app());
    await _finishDealing(tester);
    await _playToEnd(tester);

    final l10n = AppLocalizationsEn();
    expect(
        find.byWidgetPredicate((w) =>
            w is Text &&
            [l10n.matchWin, l10n.matchLose, l10n.matchDraw].contains(w.data)),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
