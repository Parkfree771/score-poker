import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:score_poker/audio/sfx.dart';
import 'package:score_poker/l10n/app_localizations.dart';
import 'package:score_poker/data/app_settings.dart';
import 'package:score_poker/ui/settings_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SfxService', () {
    test('기본값은 켜짐', () async {
      SharedPreferences.setMockInitialValues({});
      final s = SfxService();
      await s.load();
      expect(s.enabled, isTrue);
    });

    test('끄면 저장되고 재로드해도 유지된다', () async {
      SharedPreferences.setMockInitialValues({});
      final s = SfxService();
      await s.load();
      await s.setEnabled(false);

      final s2 = SfxService();
      await s2.load();
      expect(s2.enabled, isFalse);
    });

    test('꺼진 상태의 play는 아무 일도 하지 않는다 (플러그인 없어도 안전)', () async {
      SharedPreferences.setMockInitialValues({});
      final s = SfxService();
      await s.setEnabled(false);
      s.play(Sfx.cardPlace); // 크래시 없으면 통과
    });
  });

  group('설정 화면 효과음 토글', () {
    Widget app(SfxService sfx) => AppSettingsScope(
          settings: AppSettings(),
          child: SfxScope(
            service: sfx,
            child: const MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              locale: Locale('ko'),
              home: SettingsScreen(),
            ),
          ),
        );

    testWidgets('토글하면 서비스가 꺼진다', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final sfx = SfxService();
      await sfx.load();

      await tester.pumpWidget(app(sfx));
      await tester.pumpAndSettle();

      expect(find.text('효과음'), findsOneWidget);
      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();
      expect(sfx.enabled, isFalse);
    });

    testWidgets('스코프가 없으면 효과음 섹션이 아예 없다', (tester) async {
      await tester.pumpWidget(AppSettingsScope(
        settings: AppSettings(),
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: Locale('ko'),
          home: SettingsScreen(),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.byType(SwitchListTile), findsNothing);
    });
  });
}
