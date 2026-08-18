import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 앱 전역 설정. 지금은 언어 하나뿐이지만 설정 화면이 늘어날 자리다.
///
/// **언어의 기본값은 "고르지 않음"이다.** 저장된 값이 없으면 [locale]이 null이고,
/// 그러면 `MaterialApp`이 **기기 언어를 보고 자동으로** 고른다
/// (지원: 한국어/영어, 그 외 언어는 영어로 떨어진다).
/// 기본값을 특정 언어로 박아두면 외국인 사용자가 첫 실행부터 한국어를 보게 된다.
class AppSettings extends ChangeNotifier {
  AppSettings({SettingsStore? store}) : _store = store ?? const SettingsStore();

  final SettingsStore _store;

  Locale? _locale;
  bool _seenHowToPlay = false;
  bool _loaded = false;

  /// 사용자가 직접 고른 언어. **null이면 기기 설정을 따른다.**
  Locale? get locale => _locale;

  bool get isLoading => !_loaded;

  /// 화면에 "시스템 설정 따름"이 선택된 상태로 보여야 하는가.
  bool get followsSystem => _locale == null;

  /// 첫 실행 튜토리얼을 이미 봤는가. **로드 전에는 true로 본다** —
  /// 아직 모르는 상태에서 띄우면 이미 본 사람에게 매번 다시 뜬다.
  bool get seenHowToPlay => !_loaded || _seenHowToPlay;

  Future<void> load() async {
    _locale = await _store.loadLocale();
    _seenHowToPlay = await _store.loadSeenHowToPlay();
    _loaded = true;
    notifyListeners();
  }

  Future<void> markHowToPlaySeen() async {
    if (_seenHowToPlay) return;
    _seenHowToPlay = true;
    await _store.saveSeenHowToPlay(true);
    notifyListeners();
  }

  /// [locale]에 null을 주면 다시 기기 설정을 따른다.
  Future<void> setLocale(Locale? locale) async {
    if (_locale == locale) return;
    _locale = locale;
    await _store.saveLocale(locale);
    notifyListeners();
  }
}

class SettingsStore {
  const SettingsStore();

  static const _kLocale = 'settings.locale.v1';
  static const _kSeenHowToPlay = 'settings.seenHowToPlay.v1';

  Future<Locale?> loadLocale() async {
    // 저장소를 못 읽으면 "고르지 않음"으로 본다 → 기기 언어를 따라간다.
    try {
      final prefs = await SharedPreferences.getInstance();
      final code = prefs.getString(_kLocale);
      if (code == null || code.isEmpty) return null;
      return Locale(code);
    } on Object {
      return null;
    }
  }

  Future<bool> loadSeenHowToPlay() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_kSeenHowToPlay) ?? false;
    } on Object {
      // 못 읽으면 "봤다"고 친다 — 매번 다시 띄우는 쪽이 더 나쁘다.
      return true;
    }
  }

  Future<void> saveSeenHowToPlay(bool seen) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kSeenHowToPlay, seen);
    } on Object {
      // 무시
    }
  }

  Future<void> saveLocale(Locale? locale) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (locale == null) {
        await prefs.remove(_kLocale);
      } else {
        await prefs.setString(_kLocale, locale.languageCode);
      }
    } on Object {
      // 저장 실패해도 이번 실행에는 선택이 반영된다.
    }
  }
}

/// 위젯 트리에 [AppSettings]를 내려보낸다.
///
/// **`MaterialApp`보다 위에 둘 것.** 아래에 두면 `Navigator.push`로 연 설정 화면이
/// 스코프 밖으로 나간다(결제 스코프에서 겪은 것과 같은 문제).
class AppSettingsScope extends InheritedNotifier<AppSettings> {
  const AppSettingsScope({super.key, required AppSettings settings, required super.child})
      : super(notifier: settings);

  static AppSettings of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppSettingsScope>();
    assert(scope != null, 'AppSettingsScope가 위에 없습니다');
    return scope!.notifier!;
  }

  static AppSettings? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppSettingsScope>()?.notifier;
}
