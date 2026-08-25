import 'dart:async';
import 'dart:math';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 게임 효과음.
///
/// 카드 소리는 실제 녹음(Kenney Casino Audio, CC0 — `tool/import_sfx.py`),
/// 나머지는 `tool/gen_sfx.py`로 합성한 자체 제작이라 라이선스 문제가 없다.
///
/// [variants]가 2 이상이면 파일이 `<이름>_1..N.wav`로 여러 개 있고, 재생할 때마다
/// 무작위로 하나를 고른다. [jitter]는 재생 속도를 ±6% 흔든다 — 같은 소리의 반복은
/// 몇 번만 들어도 "게임 소리"처럼 들리는데, 샘플·피치 변형 두 가지가 그걸 없앤다.
enum Sfx {
  cardPlace('card_place', variants: 4, jitter: true),
  cardSlide('card_slide', variants: 4, jitter: true),
  deal('deal'),
  shuffle('shuffle'),
  attackHit('attack_hit', variants: 2, jitter: true),

  /// "두-둥" — 동시 공개·판정 세리머니의 예고 스팅.
  sting('sting'),
  shield('shield'),
  token('token'),

  /// "팅" — 칩이 레일에서 튀어 오르는 순간(열어보기 출발).
  chipPing('chip_ping'),

  /// "착" — 날아간 칩이 뒷면을 쳐내는 순간.
  chipFlick('chip_flick'),
  win('win'),
  lose('lose');

  const Sfx(this.baseName, {this.variants = 1, this.jitter = false});
  final String baseName;
  final int variants;
  final bool jitter;

  /// AssetSource 기준(assets/ 접두 자동).
  String assetPath(int variant) =>
      variants == 1 ? 'sfx/$baseName.wav' : 'sfx/${baseName}_${variant + 1}.wav';
}

/// 효과음 재생기.
///
/// - **어떤 실패도 게임을 막지 않는다** — 재생 실패(웹 자동재생 정책, 플러그인 없음)는
///   조용히 삼킨다. 소리는 부가 기능이다.
/// - on/off는 여기서 저장까지 책임진다(설정 화면은 [enabled]만 토글).
/// - 소리 종류마다 플레이어를 하나씩 두고 재사용한다 — 같은 소리가 겹치면 재시작되지만,
///   카드 게임의 효과음 빈도에서는 들리는 차이가 없고 리소스가 안전하게 고정된다.
class SfxService extends ChangeNotifier {
  SfxService();

  static const _kEnabled = 'settings.sfx.v1';

  /// (소리, 변형) → 미리 로드된 플레이어. **재생 시점 로드는 소리가 늦게 난다** —
  /// 특히 웹은 매번 네트워크 fetch가 끼어 카드 안착보다 "탁"이 늦었다.
  final Map<(Sfx, int), AudioPlayer> _players = {};
  final Random _rng = Random();
  bool _enabled = true;
  bool get enabled => _enabled;

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _enabled = prefs.getBool(_kEnabled) ?? true;
      notifyListeners();
    } on Object {
      // 저장소를 못 읽어도 기본값(켜짐)으로 동작한다.
    }
    _preloadAll();
  }

  /// 모든 음원을 미리 로드한다. 실패한 파일은 재생 시점에 다시 시도된다.
  void _preloadAll() {
    // guarded zone: AudioPlayer 생성자 **내부의** 비동기 채널 오류(플러그인 없는
    // 테스트 환경 등)는 밖에서 catch할 수 없고 엉뚱한 곳에 unhandled로 떨어진다.
    // 소리는 부가 기능 — 초기화 실패는 어디서 왔든 조용히 삼킨다.
    runZonedGuarded(() {
      for (final sfx in Sfx.values) {
        for (var v = 0; v < sfx.variants; v++) {
          _player(sfx, v);
        }
      }
    }, (_, __) {});
  }

  AudioPlayer _player(Sfx sfx, int variant) {
    return _players.putIfAbsent((sfx, variant), () {
      final p = AudioPlayer();
      p.setPlayerMode(PlayerMode.lowLatency).catchError((Object _) {});
      // stop() 후에도 소스를 놓지 않는다(기본 release는 다음 재생 때 다시 로드한다).
      p.setReleaseMode(ReleaseMode.stop).catchError((Object _) {});
      p.setSource(AssetSource(sfx.assetPath(variant))).catchError((Object _) {});
      return p;
    });
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

  /// 효과음 재생. 끈 상태거나 재생이 불가능한 환경이면 아무 일도 하지 않는다.
  void play(Sfx sfx) {
    if (!_enabled) return;
    // fire-and-forget: 게임 루프를 오디오에 붙들지 않는다.
    _play(sfx).catchError((Object _) {});
  }

  /// **재생 호출을 await로 줄줄이 엮지 않는다.** stop → setRate → resume을 차례로
  /// 기다리면 플랫폼 채널을 세 번 왕복하는 동안 소리가 밀린다(카드가 손에 닿고 나서
  /// "착"이 난다). 같은 플레이어에 건 호출은 순서가 유지되므로 걸어만 두고 넘어간다.
  Future<void> _play(Sfx sfx) async {
    final p = _player(sfx, _rng.nextInt(sfx.variants));
    unawaited(p.stop().catchError((Object _) {})); // 겹치면 재시작
    if (sfx.jitter) {
      // 미지원 플랫폼에서 실패해도 원속으로 재생되면 그만이다.
      unawaited(p
          .setPlaybackRate(0.94 + _rng.nextDouble() * 0.12)
          .catchError((Object _) {}));
    }
    // 소스가 이미 물려 있으므로 resume이 즉시 난다. 프리로드가 실패했던
    // 파일이면 여기서 다시 세팅된다.
    try {
      await p.resume();
    } on Object {
      await p.play(AssetSource(sfx.assetPath(_rng.nextInt(sfx.variants))));
    }
  }

  @override
  void dispose() {
    for (final p in _players.values) {
      p.dispose();
    }
    super.dispose();
  }
}

/// 위젯 트리에 [SfxService]를 내려보낸다.
///
/// **`MaterialApp`보다 위에 둘 것**(다른 스코프들과 같은 이유 — `Navigator.push`로 연
/// 화면이 스코프 밖으로 나가면 안 된다). 스코프가 없는 환경(위젯 테스트·스크린샷)에서는
/// [maybeOf]가 null을 주고, 호출부는 소리 없이 동작한다.
class SfxScope extends InheritedNotifier<SfxService> {
  const SfxScope({super.key, required SfxService service, required super.child})
      : super(notifier: service);

  static SfxService? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SfxScope>()?.notifier;

  static SfxService of(BuildContext context) {
    final s = maybeOf(context);
    assert(s != null, 'SfxScope가 위에 없습니다');
    return s!;
  }
}
