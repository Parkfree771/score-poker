import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:score_poker/audio/sfx.dart';
import 'package:score_poker/data/app_settings.dart';
import 'package:score_poker/feedback/haptics.dart';
import 'package:score_poker/l10n/app_localizations.dart';
import 'package:score_poker/ui/settings_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('HapticService', () {
    test('기본값은 켜짐', () async {
      SharedPreferences.setMockInitialValues({});
      final h = HapticService();
      await h.load();
      expect(h.enabled, isTrue);
    });

    test('끄면 저장되고 재로드해도 유지된다', () async {
      SharedPreferences.setMockInitialValues({});
      final h = HapticService();
      await h.load();
      await h.setEnabled(false);

      final h2 = HapticService();
      await h2.load();
      expect(h2.enabled, isFalse);
    });

    test('play는 플러그인이 없어도 크래시하지 않는다', () async {
      SharedPreferences.setMockInitialValues({});
      final h = HapticService();
      for (final e in Haptic.values) {
        h.play(e); // 테스트 환경엔 진동 채널이 없다 — 조용히 무시되면 통과
      }
      await h.setEnabled(false);
      h.play(Haptic.impact);
    });

    test('모바일에서만 지원된다', () {
      final h = HapticService();
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      expect(h.supported, isTrue);
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      expect(h.supported, isTrue);
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      expect(h.supported, isFalse);
      debugDefaultTargetPlatformOverride = null;
    });
  });

  group('설정 화면 햅틱 토글', () {
    Widget app({required SfxService sfx, HapticService? haptics}) {
      Widget child = const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: Locale('ko'),
        home: SettingsScreen(),
      );
      if (haptics != null) child = HapticScope(service: haptics, child: child);
      return AppSettingsScope(
        settings: AppSettings(),
        child: SfxScope(service: sfx, child: child),
      );
    }

    testWidgets('토글하면 서비스가 꺼진다', (tester) async {
      SharedPreferences.setMockInitialValues({});
      // 플랫폼 오버라이드는 테스트 본문 안에서 복원해야 한다(바인딩 불변식 검사).
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        final sfx = SfxService();
        final haptics = HapticService();
        await haptics.load();

        await tester.pumpWidget(app(sfx: sfx, haptics: haptics));
        await tester.pumpAndSettle();

        expect(find.text('진동 (햅틱)'), findsOneWidget);
        await tester.tap(find.byType(SwitchListTile).last);
        await tester.pumpAndSettle();
        expect(haptics.enabled, isFalse);
        expect(sfx.enabled, isTrue); // 효과음 토글은 그대로
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('스코프가 없으면 햅틱 줄이 없다 (효과음 줄만)', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(app(sfx: SfxService()));
      await tester.pumpAndSettle();
      expect(find.byType(SwitchListTile), findsOneWidget);
      expect(find.text('진동 (햅틱)'), findsNothing);
    });
  });
}
