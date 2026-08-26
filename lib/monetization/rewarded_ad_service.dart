import 'dart:async';

/// 보상형 광고 1회 노출의 결과.
///
/// **[rewarded]만 지급 근거다.** 나머지는 전부 "지급하지 않는다"의 여러 이유일 뿐이다.
enum AdShowResult {
  /// 사용자가 광고를 **끝까지** 봤다(SDK의 onUserEarnedReward에 해당).
  rewarded,

  /// 끝까지 보지 않고 닫았다. 지급 없음.
  dismissed,

  /// 광고가 아직 준비되지 않았다(로드 중·로드 실패 후). 지급 없음.
  notReady,

  /// 노출 중 오류. 지급 없음.
  failed,

  /// 이 환경은 광고를 지원하지 않는다(테스트 등). 지급 없음.
  notSupported,
}

/// 보상형(리워드) 광고 창구.
///
/// 규칙:
/// - **지급은 여기서 하지 않는다.** 이 계층은 "끝까지 봤는가"만 답한다. 토큰은
///   `Monetization.watchAdForBoost()` → `TokenWallet.grantAdReward()` 한 길로만 들어간다.
/// - [show]는 광고가 닫힌 뒤에 완료된다. SDK 구현은 `onUserEarnedReward`가 불린 경우에만
///   [AdShowResult.rewarded]를 돌려줘야 한다 — 닫힘 콜백(onAdDismissed)은 보상의 근거가 아니다.
/// - 한 번 보여준 광고 객체는 재사용하지 않는다. [show] 뒤에는 [preload]로 다음 것을 미리 받는다.
///
/// 실제 구현(AdMob 등)은 아직 없다 — 지금은 [StubRewardedAdService]가 목 광고 화면을 띄운다.
abstract class RewardedAdService {
  /// 실제 광고 네트워크가 붙어 있는가. false면 상점이 "테스트 광고"라고 표시한다.
  bool get isSupported;

  Future<void> initialize();

  /// 다음 광고를 미리 받아둔다. 실패해도 예외를 던지지 않는다([isReady]가 false로 남는다).
  Future<void> preload();

  /// 지금 바로 보여줄 광고가 있는가.
  bool get isReady;

  /// 전체화면 광고를 보여주고, 닫힌 뒤 결과를 돌려준다.
  Future<AdShowResult> show();

  Future<void> dispose();
}

/// 광고 SDK 없이 도는 스텁 — 웹/데스크톱/테스트용.
///
/// [presenter]가 있으면 그것이 "광고"다(앱에서는 목 광고 화면을 띄우고, 끝까지 봤으면 true).
/// 없으면 [AdShowResult.notSupported] — 테스트에서 [scripted]로 결과를 정해 줄 수도 있다.
class StubRewardedAdService implements RewardedAdService {
  StubRewardedAdService({this.presenter, this.scripted});

  /// 목 광고를 띄우고 "끝까지 봤는가"를 돌려주는 콜백. 앱이 조립 시점에 꽂는다.
  Future<bool> Function()? presenter;

  /// 테스트용: 정해진 결과를 순서대로 돌려준다(비면 [presenter]를 쓴다).
  final List<AdShowResult>? scripted;

  bool _ready = false;
  int shows = 0;

  @override
  bool get isSupported => false;

  @override
  Future<void> initialize() async {}

  @override
  Future<void> preload() async {
    _ready = presenter != null || (scripted?.isNotEmpty ?? false);
  }

  @override
  bool get isReady => _ready;

  @override
  Future<AdShowResult> show() async {
    if (!_ready) return AdShowResult.notReady;
    _ready = false; // 광고 객체는 1회용 — 다음 것은 preload로 다시 받는다.
    shows++;
    final s = scripted;
    if (s != null && s.isNotEmpty) return s.removeAt(0);
    final p = presenter;
    if (p == null) return AdShowResult.notSupported;
    try {
      return await p() ? AdShowResult.rewarded : AdShowResult.dismissed;
    } on Object {
      return AdShowResult.failed;
    }
  }

  @override
  Future<void> dispose() async {}
}
