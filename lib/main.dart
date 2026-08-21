import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'audio/sfx.dart';
import 'data/app_settings.dart';
import 'feedback/haptics.dart';
import 'l10n/app_localizations.dart';
import 'monetization/monetization.dart';
import 'ui/home_screen.dart';
import 'ui/theme.dart';

void main() => runApp(const ScorePokerApp());

class ScorePokerApp extends StatefulWidget {
  const ScorePokerApp(
      {super.key, this.monetization, this.settings, this.sfx, this.haptics});

  /// 테스트에서 주입용. 비우면 기본(플랫폼에 맞는) 구성을 쓴다.
  final Monetization? monetization;
  final AppSettings? settings;
  final SfxService? sfx;
  final HapticService? haptics;

  @override
  State<ScorePokerApp> createState() => _ScorePokerAppState();
}

class _ScorePokerAppState extends State<ScorePokerApp> {
  late final Monetization _monetization = widget.monetization ?? Monetization();
  late final AppSettings _settings = widget.settings ?? AppSettings();
  late final SfxService _sfx = widget.sfx ?? SfxService();
  late final HapticService _haptics = widget.haptics ?? HapticService();

  @override
  void initState() {
    super.initState();
    // 언어 설정은 첫 프레임에 필요하지만 저장소 읽기가 비동기라 잠깐 늦는다.
    // 그동안은 **기기 언어**로 그려지므로(=locale null) 깜빡임이 사실상 없다.
    // 저장소를 못 읽는 환경(테스트 등)에서도 앱은 떠야 한다 — 실패하면 기본값으로 간다.
    _guard(_settings.load());
    _guard(_sfx.load());
    _guard(_haptics.load());
    // 결제 초기화는 네트워크를 타서 수백 ms가 걸린다. main()에서 await하면
    // 그동안 흰 화면이 뜨므로 **첫 프레임이 그려진 뒤에** 시작한다.
    SchedulerBinding.instance
        .addPostFrameCallback((_) => _guard(_monetization.startAsync()));
  }

  /// 시작 단계의 비동기 실패로 앱이 죽지 않게 한다(설정·결제 둘 다 선택적 기능이다).
  void _guard(Future<void> f) => f.catchError((Object _) {});

  @override
  void dispose() {
    _monetization.dispose();
    _settings.dispose();
    _sfx.dispose();
    _haptics.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 두 스코프 모두 **MaterialApp 위**에 둔다. 아래에 두면 Navigator.push로 연
    // 화면(상점·설정)이 스코프 밖으로 나가 즉시 죽는다.
    return AppSettingsScope(
      settings: _settings,
      child: SfxScope(
        service: _sfx,
        child: HapticScope(
          service: _haptics,
          child: MonetizationScope(
            monetization: _monetization,
            child: AnimatedBuilder(
              animation: _settings,
              builder: (context, _) => MaterialApp(
                onGenerateTitle: (ctx) => AppLocalizations.of(ctx).appTitle,
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                supportedLocales: AppLocalizations.supportedLocales,
                // null이면 기기 언어를 따른다(지원하지 않는 언어는 아래 콜백이 영어로 보낸다).
                locale: _settings.locale,
                localeListResolutionCallback: _resolveLocale,
                theme: buildAppTheme(),
                home: const HomeScreen(),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 기기 언어 자동 감지.
  ///
  /// 기기의 **선호 언어 목록을 순서대로** 훑어 지원하는 것을 고른다(예: 프랑스어 우선,
  /// 한국어 차선인 기기는 한국어로 뜬다). 하나도 안 맞으면 **영어**로 떨어진다 —
  /// 지원하지 않는 언어권 사용자에게 한국어를 보여주면 아무것도 할 수 없다.
  Locale? _resolveLocale(
      List<Locale>? deviceLocales, Iterable<Locale> supported) {
    for (final device in deviceLocales ?? const <Locale>[]) {
      for (final s in supported) {
        if (s.languageCode == device.languageCode) return s;
      }
    }
    return const Locale('en');
  }
}
