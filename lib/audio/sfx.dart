import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 게임 효과음. 음원은 `assets/sfx/*.wav` — 전부 `tool/gen_sfx.py`로 합성한
/// 자체 제작이라 라이선스 문제가 없다.
enum Sfx {
  cardPlace('card_place'),
  attack('attack'),
  shield('shield'),
  token('token'),
  win('win'),
  lose('lose');

  const Sfx(this.fileName);
  final String fileName;

  String get assetPath => 'sfx/$fileName.wav'; // AssetSource 기준(assets/ 접두 자동)
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

  final Map<Sfx, AudioPlayer> _players = {};
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

  Future<void> _play(Sfx sfx) async {
    final p = _players.putIfAbsent(sfx, () {
      final player = AudioPlayer();
      player.setPlayerMode(PlayerMode.lowLatency).catchError((Object _) {});
      return player;
    });
    await p.stop(); // 겹치면 재시작
    await p.play(AssetSource(sfx.assetPath));
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
