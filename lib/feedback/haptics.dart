import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vibration/vibration.dart';

/// 게임의 촉각 이벤트. **무엇이 일어났는지**만 말하고, 어떻게 떨릴지는
/// [HapticService]가 플랫폼별로 정한다.
///
/// 진동은 "내가 한 일"과 "내가 당한 일"에만 쓴다 — AI가 자기 필드에 카드를
/// 놓을 때는 울리지 않는다. 전부 울리면 전부 안 울리는 것과 같다.
enum Haptic {
  /// 카드 선택·폴드 같은 가벼운 조작 확인.
  select,

  /// 카드가 필드에 안착.
  place,

  /// 공격 명중(내 공격이든 내가 맞았든). 가장 강한 이중 펄스.
  impact,

  /// 빼앗은 카드가 쉴드로 고정되는 순간.
  shieldLock,

  /// 토큰 사용.
  token,

  /// 승리 — 상승 3연타.
  win,

  /// 패배 — 무겁게 한 번, 여운 한 번.
  lose,
}

/// 햅틱 재생기.
///
/// 플랫폼 전략:
/// - **iOS**: `HapticFeedback`(Taptic Engine). 나이키 런 류의 또렷한 임팩트가
///   바로 이 API다. 패턴은 딜레이 조합으로 만든다.
/// - **Android**: `vibration` 패키지로 진폭 제어 파형(VibrationEffect)을 쓴다.
///   시스템 "터치 피드백" 설정과 무관하게 확실히 울리고, 세기를 단계로 조각할 수 있다.
///   진폭 미지원 기기는 iOS와 같은 `HapticFeedback` 폴백.
/// - 그 외(웹·데스크톱): 아무 것도 하지 않는다.
///
/// 효과음과 같은 원칙 — **어떤 실패도 게임을 막지 않는다.**
class HapticService extends ChangeNotifier {
  HapticService();

  static const _kEnabled = 'settings.haptics.v1';

  bool _enabled = true;
  bool get enabled => _enabled;

  /// Android 진폭 제어 가능 여부. 첫 사용 때 한 번만 물어보고 캐시한다.
  Future<bool>? _amplitudeSupport;

  /// 이 플랫폼에서 햅틱이 의미가 있는가(설정 화면 노출 여부).
  bool get supported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _enabled = prefs.getBool(_kEnabled) ?? true;
      notifyListeners();
    } on Object {
      // 저장소를 못 읽어도 기본값(켜짐)으로 동작한다.
    }
  }

  Future<void> setEnabled(bool value) async {
    if (_enabled == value) return;
    _enabled = value;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kEnabled, value);
    } on Object {
      // 저장 실패해도 이번 실행에는 반영된다.
    }
  }

  /// 촉각 이벤트 재생. 끈 상태·미지원 플랫폼이면 아무 일도 하지 않는다.
  void play(Haptic haptic) {
    if (!_enabled || !supported) return;
    // fire-and-forget: 게임 루프를 진동에 붙들지 않는다.
    _play(haptic).catchError((Object _) {});
  }

  Future<void> _play(Haptic haptic) async {
    if (defaultTargetPlatform == TargetPlatform.android && await _hasAmplitude()) {
      await _playWaveform(haptic);
    } else {
      await _playTaptic(haptic);
    }
  }

  Future<bool> _hasAmplitude() {
    return _amplitudeSupport ??= () async {
      try {
        return await Vibration.hasVibrator() && await Vibration.hasAmplitudeControl();
      } on Object {
        return false; // 플러그인이 없는 환경(테스트 등)
      }
    }();
  }

  /// Android: 진폭 파형. pattern은 [대기, 진동, 대기, 진동…] ms,
  /// intensities는 각 구간의 세기(대기 구간은 0).
  Future<void> _playWaveform(Haptic haptic) async {
    switch (haptic) {
      case Haptic.select:
        await Vibration.vibrate(duration: 12, amplitude: 72);
      case Haptic.place:
        await Vibration.vibrate(duration: 20, amplitude: 170);
      case Haptic.impact:
        // 강타 → 짧은 침묵 → 여진. 이 "쉼"이 두 번째 펄스를 또렷하게 만든다.
        await Vibration.vibrate(
            pattern: [0, 28, 64, 42], intensities: [0, 255, 0, 150]);
      case Haptic.shieldLock:
        await Vibration.vibrate(duration: 35, amplitude: 210);
      case Haptic.token:
        await Vibration.vibrate(
            pattern: [0, 14, 50, 14], intensities: [0, 140, 0, 140]);
      case Haptic.win:
        await Vibration.vibrate(
            pattern: [0, 22, 70, 26, 70, 48], intensities: [0, 110, 0, 180, 0, 255]);
      case Haptic.lose:
        await Vibration.vibrate(
            pattern: [0, 70, 80, 130], intensities: [0, 200, 0, 90]);
    }
  }

  /// iOS(및 Android 폴백): 표준 임팩트를 딜레이로 조합한다.
  Future<void> _playTaptic(Haptic haptic) async {
    switch (haptic) {
      case Haptic.select:
        await HapticFeedback.selectionClick();
      case Haptic.place:
        await HapticFeedback.mediumImpact();
      case Haptic.impact:
        await HapticFeedback.heavyImpact();
        await Future<void>.delayed(const Duration(milliseconds: 70));
        await HapticFeedback.mediumImpact();
      case Haptic.shieldLock:
        await HapticFeedback.mediumImpact();
      case Haptic.token:
        await HapticFeedback.selectionClick();
        await Future<void>.delayed(const Duration(milliseconds: 60));
        await HapticFeedback.selectionClick();
      case Haptic.win:
        await HapticFeedback.lightImpact();
        await Future<void>.delayed(const Duration(milliseconds: 90));
        await HapticFeedback.mediumImpact();
        await Future<void>.delayed(const Duration(milliseconds: 90));
        await HapticFeedback.heavyImpact();
      case Haptic.lose:
        await HapticFeedback.heavyImpact();
        await Future<void>.delayed(const Duration(milliseconds: 150));
        await HapticFeedback.mediumImpact();
    }
  }
}

/// 위젯 트리에 [HapticService]를 내려보낸다. `MaterialApp`보다 위에 둘 것.
/// 스코프가 없는 환경(위젯 테스트·스크린샷)에서는 [maybeOf]가 null을 주고,
/// 호출부는 진동 없이 동작한다.
class HapticScope extends InheritedNotifier<HapticService> {
  const HapticScope(
      {super.key, required HapticService service, required super.child})
      : super(notifier: service);

  static HapticService? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<HapticScope>()?.notifier;
}
