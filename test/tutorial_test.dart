import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:score_poker/l10n/app_localizations.dart';
import 'package:score_poker/main.dart';
import 'package:score_poker/monetization/monetization.dart';
import 'package:score_poker/ui/home_screen.dart';
import 'package:score_poker/ui/how_to_play_screen.dart';
import 'package:score_poker/ui/rules_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 첫 실행 튜토리얼이 뜨는 조건을 고정한다.
///
/// 두 방향으로 다 틀릴 수 있다: 안 뜨면 규칙을 모른 채 첫 판을 두게 되고,
/// 매번 뜨면 성가셔서 앱을 지운다.

Future<void> _pumpApp(WidgetTester tester, {Map<String, Object> prefs = const {}}) async {
  // 테스트 기본 로케일은 en_US다 — 한국어 문구를 확인하려면 명시해야 한다.
  tester.platformDispatcher.localesTestValue = [const Locale('ko')];
  addTearDown(tester.platformDispatcher.clearLocalesTestValue);
  SharedPreferences.setMockInitialValues(prefs);
  final monetization = Monetization(purchases: StubPurchaseService());
  addTearDown(monetization.dispose);

  await tester.pumpWidget(ScorePokerApp(monetization: monetization));
  // 설정 로드(비동기) → 알림 → 포스트프레임에서 튜토리얼 push → 전환 애니메이션
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 120));
  }
}

void main() {
  testWidgets('첫 실행이면 튜토리얼이 자동으로 뜬다', (tester) async {
    await _pumpApp(tester);
    expect(find.byType(HowToPlayScreen), findsOneWidget);
  });

  testWidgets('이미 본 뒤에는 다시 뜨지 않는다', (tester) async {
    await _pumpApp(tester, prefs: {'settings.seenHowToPlay.v1': true});
    expect(find.byType(HowToPlayScreen), findsNothing);
    expect(find.byType(HomeScreen), findsOneWidget);
  });

  testWidgets('한 번 뜨면 봤다고 저장된다 — 다음 실행에는 안 뜬다', (tester) async {
    await _pumpApp(tester);
    expect(find.byType(HowToPlayScreen), findsOneWidget);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('settings.seenHowToPlay.v1'), isTrue);
  });

  testWidgets('홈의 "게임 방법"으로 언제든 다시 열 수 있다', (tester) async {
    tester.view.physicalSize = const Size(430, 930);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _pumpApp(tester, prefs: {'settings.seenHowToPlay.v1': true});
    expect(find.byType(HowToPlayScreen), findsNothing);

    await tester.tap(find.text('게임 방법'));
    await tester.pumpAndSettle();
    expect(find.byType(HowToPlayScreen), findsOneWidget);
  });

  testWidgets('튜토리얼에서 규칙 전문으로 넘어갈 수 있다', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      locale: Locale('ko'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: HowToPlayScreen(),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('규칙 전체 보기'));
    await tester.pumpAndSettle();
    expect(find.byType(RulesScreen), findsOneWidget);
  });

  testWidgets('설정 스코프가 없으면 자동으로 뜨지 않는다 (스크린샷·위젯 테스트 보호)', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      locale: Locale('ko'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: HomeScreen(),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(HowToPlayScreen), findsNothing);
  });
}
