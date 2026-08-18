import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:score_poker/data/app_settings.dart';
import 'package:score_poker/l10n/app_localizations.dart';
import 'package:score_poker/main.dart';
import 'package:score_poker/monetization/monetization.dart';
import 'package:score_poker/ui/settings_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 언어 규칙을 고정한다.
///
/// 여기가 깨지면 **외국인 사용자가 한국어 화면을 보게 되거나**, 언어를 골라도 다음
/// 실행에 되돌아간다. 둘 다 앱을 못 쓰게 만드는 수준의 문제인데 조용히 깨진다.

Future<void> _pumpApp(WidgetTester tester, {required List<Locale> deviceLocales}) async {
  tester.platformDispatcher.localesTestValue = deviceLocales;
  addTearDown(tester.platformDispatcher.clearLocalesTestValue);

  SharedPreferences.setMockInitialValues({});
  final monetization = Monetization(purchases: StubPurchaseService());
  addTearDown(monetization.dispose);

  await tester.pumpWidget(ScorePokerApp(monetization: monetization));
  await tester.pump();
  await tester.pump();
}

void main() {
  group('기기 언어 자동 감지', () {
    testWidgets('한국어 기기 → 한국어', (tester) async {
      await _pumpApp(tester, deviceLocales: [const Locale('ko')]);
      expect(find.text('온라인 대전'), findsOneWidget);
    });

    testWidgets('영어 기기 → 영어', (tester) async {
      await _pumpApp(tester, deviceLocales: [const Locale('en')]);
      expect(find.text('Online Match'), findsOneWidget);
    });

    testWidgets('지원하지 않는 언어(프랑스어) → 한국어가 아니라 영어로 떨어진다', (tester) async {
      await _pumpApp(tester, deviceLocales: [const Locale('fr')]);
      expect(find.text('Online Match'), findsOneWidget,
          reason: '지원 목록 첫 항목을 그냥 쓰면 프랑스 사용자가 한국어를 보게 된다');
    });

    testWidgets('선호 언어 목록을 순서대로 훑는다 (프랑스어 우선, 한국어 차선 → 한국어)', (tester) async {
      await _pumpApp(tester, deviceLocales: [const Locale('fr'), const Locale('ko')]);
      expect(find.text('온라인 대전'), findsOneWidget);
    });
  });

  group('AppSettings', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('기본값은 "고르지 않음" — 기기 언어를 따른다', () async {
      final s = AppSettings();
      await s.load();
      expect(s.locale, isNull);
      expect(s.followsSystem, isTrue);
    });

    test('고른 언어는 다음 실행에 살아난다', () async {
      final a = AppSettings();
      await a.load();
      await a.setLocale(const Locale('en'));

      final b = AppSettings();
      await b.load();
      expect(b.locale, const Locale('en'));
      expect(b.followsSystem, isFalse);
    });

    test('시스템으로 되돌리면 저장값이 지워진다', () async {
      final a = AppSettings();
      await a.load();
      await a.setLocale(const Locale('ko'));
      await a.setLocale(null);

      final b = AppSettings();
      await b.load();
      expect(b.locale, isNull);
    });

    test('같은 값으로 다시 설정하면 알림을 쏘지 않는다', () async {
      final s = AppSettings();
      await s.load();
      var notifications = 0;
      s.addListener(() => notifications++);
      await s.setLocale(const Locale('en'));
      await s.setLocale(const Locale('en'));
      expect(notifications, 1);
    });
  });

  group('설정 화면', () {
    testWidgets('언어를 고르면 화면 전체가 그 언어로 바뀐다', (tester) async {
      tester.platformDispatcher.localesTestValue = [const Locale('ko')];
      addTearDown(tester.platformDispatcher.clearLocalesTestValue);
      SharedPreferences.setMockInitialValues({});

      final settings = AppSettings();
      await settings.load();
      addTearDown(settings.dispose);

      await tester.pumpWidget(AppSettingsScope(
        settings: settings,
        child: AnimatedBuilder(
          animation: settings,
          builder: (context, _) => MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: settings.locale,
            home: const SettingsScreen(),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text('설정'), findsOneWidget);

      await tester.tap(find.text('English'));
      await tester.pumpAndSettle();

      expect(settings.locale, const Locale('en'));
      expect(find.text('Settings'), findsOneWidget, reason: '고른 즉시 화면이 바뀌어야 한다');
    });

    testWidgets('언어 이름은 번역하지 않는다 — 한국어 화면에서도 English로 보인다', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final settings = AppSettings();
      await settings.load();
      addTearDown(settings.dispose);

      await tester.pumpWidget(AppSettingsScope(
        settings: settings,
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: Locale('ko'),
          home: SettingsScreen(),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('English'), findsOneWidget,
          reason: '"영어"라고 써 두면 영어 사용자가 자기 언어를 못 찾는다');
      expect(find.text('한국어'), findsOneWidget);
    });
  });
}
