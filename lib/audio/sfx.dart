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
  cardPlace('card_place', variants: 4, jitter: true, gain: 0.65),
  cardSlide('card_slide', variants: 4, jitter: true),
  deal('deal'),
  shuffle('shuffle'),
  attackHit('attack_hit', variants: 2, jitter: true),

  /// "두-둥" — 동시 공개·판정 세리머니의 예고 스팅.
  sting('sting'),
  shield('shield'),
  token('token', variants: 3, jitter: true),

  /// "팅" — 칩이 레일에서 튀어 오르는 순간(열어보기 출발).
  chipPing('chip_ping', variants: 2, jitter: true),

  /// "착" — 날아간 칩이 뒷면을 쳐내는 순간.
  chipFlick('chip_flick', variants: 2, jitter: true),

  /// "탁-슈욱" — 칩을 쏘는 순간. Sonniss GDC 발췌 리믹스(휘익 저역 밴드 + 출발 클릭).
  /// 파일이 이미 피크 -11dB인데 실기기에서 여전히 충돌을 눌러서 gain으로 -7dB 더 —
  /// 밸런스를 파일에 다시 굽지 않고 여기 숫자로 조절한다(OTA 패치로 튜닝 가능).
  chipShot('chip_shot', variants: 2, gain: 0.45),

  /// "탁!" — 칩이 카드에 맞는 순간. Sonniss GDC 발췌 리믹스(기어 클릭 + 저역 썸프,
  /// 새추레이션으로 RMS를 올려 시퀀스에서 가장 크게 들린다).
  /// jitter 없음: 변형 2종의 피치가 이미 달라서(썸프 105/118Hz) 지터까지 얹으면
  /// "내가 칠 때와 상대가 칠 때 소리가 다르다"고 들린다 — 실기기 청취 피드백.
  chipTing('chip_ting', variants: 2),

  /// "틱" — 되튄 칩이 테이블에 다시 닿는 작은 소리(`tool/gen_chip_sfx.py`).
  chipTick('chip_tick', variants: 2, jitter: true),
  win('win'),
  lose('lose');

  const Sfx(this.baseName, {this.variants = 1, this.jitter = false, this.gain = 1});
  final String baseName;
  final int variants;
  final bool jitter;

  /// 재생 음량(0~1). 소리 간 상대 밸런스는 파일에 굽는 대신 여기서 조절한다 —
  /// wav 재생성 없이 코드(OTA 패치)만으로 튜닝하기 위해서다.
  final double gain;

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

  /// (소리, 변형) → **캐시 앵커** 플레이어. 직접 재생하지 않고 소스만 물려 둔다 —
  /// 네이티브 SoundPool 캐시를 붙잡아, 재생마다 새로 만드는 플레이어([_play])의
  /// 로드가 항상 캐시 히트가 되게 한다(재생 시점 로드는 소리가 늦게 난다).
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
      p.setVolume(sfx.gain).catchError((Object _) {});
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
  ///
  /// [variant]를 지정하면 그 변형을 지터 없이 재생한다 — 딜링처럼 같은 소리가
  /// 같은 리듬으로 "착착착" 반복돼야 하는 자리용(무작위 변형은 리듬을 부순다).
  void play(Sfx sfx, {int? variant}) {
    if (!_enabled) return;
    // fire-and-forget: 게임 루프를 오디오에 붙들지 않는다.
    _play(sfx, variant: variant).catchError((Object _) {});
  }

  /// **재생마다 새 플레이어를 만들어 쏘고 버린다.** 안드로이드 lowLatency 모드는
  /// 재생 완료 신호가 오지 않아 같은 플레이어의 두 번째 재생부터 조용히 무시되는
  /// 버그가 있다(bluefireteam/audioplayers#1489). stop→resume도, play() 재호출도
  /// 실기기에서 2~3번째부터 죽는 것이 확인됐다 — 플레이어를 재사용하는 한 못
  /// 피한다. 대신 [_players]의 앵커들이 소스를 물고 있어 네이티브 SoundPool
  /// 캐시가 유지되므로, 새 플레이어의 로드는 캐시 히트라 지연이 없다.
  /// 다 쓴 플레이어는 완료 이벤트가 안 오므로 타이머로 정리한다.
  Future<void> _play(Sfx sfx, {int? variant}) async {
    final v = variant ?? _rng.nextInt(sfx.variants);
    _player(sfx, v); // 앵커 보장 — 최초 재생 전에 캐시를 채운다.
    final p = AudioPlayer();
    unawaited(p.setPlayerMode(PlayerMode.lowLatency).catchError((Object _) {}));
    unawaited(p.setVolume(sfx.gain).catchError((Object _) {}));
    if (sfx.jitter && variant == null) {
      // 미지원 플랫폼에서 실패해도 원속으로 재생되면 그만이다.
      unawaited(p
          .setPlaybackRate(0.94 + _rng.nextDouble() * 0.12)
          .catchError((Object _) {}));
    }
    try {
      await p.play(AssetSource(sfx.assetPath(v)));
    } finally {
      unawaited(Future<void>.delayed(const Duration(seconds: 4))
          .then((_) => p.dispose())
          .catchError((Object _) {}));
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
