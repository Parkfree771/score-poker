import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:score_poker/l10n/app_localizations.dart';
import 'package:score_poker/ui/game_screen.dart';
import 'package:score_poker/ui/widgets/board_view.dart';
import 'package:score_poker/ui/widgets/card_face.dart';

Widget _app() => MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: ThemeData(brightness: Brightness.dark, useMaterial3: true),
      home: const GameScreen(seed: 1),
    );

/// 비동기 연출/AI 타이머를 충분히 흘려보낸다(고정 스텝 펌프).
Future<void> _settleAll(WidgetTester tester) async {
  for (var i = 0; i < 90; i++) {
    await tester.pump(const Duration(milliseconds: 300));
  }
}

/// 오프닝: 딜링 완료 → 내 카드 1장 탭 → 쇼다운/결과 자동 진행 → 보드로 진입(+상대 선공 시 AI).
Future<void> _passReveal(WidgetTester tester) async {
  await tester.pump(); // 첫 프레임
  await tester.pump(const Duration(milliseconds: 2000)); // 딜링 완료 → 선택 단계
  await tester.tap(find.byType(CardFace).first); // 내 카드 선택
  await _settleAll(tester); // 쇼다운/결과/보드 진입/AI 정리
}

void main() {
  testWidgets('선공 화면이 먼저 뜨고, 진행하면 보드가 나온다 (세로)', (tester) async {
    tester.view.physicalSize = const Size(400, 850);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_app());
    await tester.pump(); // 오프닝(딜링) 표시
    expect(find.byType(BoardView), findsNothing); // 아직 보드 아님

    await _passReveal(tester);
    expect(find.byType(BoardView), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('가로에서도 오류 없이 보드가 나온다', (tester) async {
    tester.view.physicalSize = const Size(900, 450);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_app());
    await _passReveal(tester);
    expect(find.byType(BoardView), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('보드에서 폴드가 오류 없이 동작', (tester) async {
    tester.view.physicalSize = const Size(400, 850);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_app());
    await _passReveal(tester);

    await tester.tap(find.byIcon(Icons.flag_rounded));
    await _settleAll(tester); // 폴드 후 AI가 끝까지 자동 진행
    expect(tester.takeException(), isNull);
  });
}
