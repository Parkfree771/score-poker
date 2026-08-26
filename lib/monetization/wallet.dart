import 'package:flutter/foundation.dart';

import 'products.dart';
import 'tokens.dart';
import 'wallet_store.dart';

/// 무료 지급 정책.
///
/// **숫자를 여기 한 곳에만 둔다.** 무료 지급량은 매출과 이탈을 동시에 결정하는 값이라
/// 출시 후에도 계속 조정하게 된다 — 코드 여기저기 흩어져 있으면 못 만진다.
///
/// 기본값의 근거:
/// - 환영 지급 3판: **써 보지 않은 아이템은 사지 않는다.** 첫 판부터 효과를 경험시킨다.
/// - 데일리 없음: 10판이 ₩1,000(한 판 100원)이라 무료 데일리를 주면 살 이유가 사라진다.
///   (정책 자체는 남겨 둔다 — 이벤트로 켤 수 있다.)
/// - 광고 보상 1판 · 하루 2회: 안 살 사람에게서도 매출이 나오는 길이되, **무제한이면
///   데일리와 똑같이 판매를 죽인다.** 팩(10판)보다 귀찮아야 "귀찮으면 사라"가 성립한다.
class TokenGrantPolicy {
  const TokenGrantPolicy({
    this.welcome = const {TokenKind.boost: 3},
    this.daily = const {},
    this.adReward = const {TokenKind.boost: 1},
    this.adDailyCap = 2,
  });

  /// 첫 실행 1회 지급.
  final TokenBundle welcome;

  /// 하루 1회 지급.
  final TokenBundle daily;

  /// 보상형 광고 1회 완주당 지급.
  final TokenBundle adReward;

  /// 하루에 광고 보상을 받을 수 있는 횟수. 0이면 광고 보상 없음.
  final int adDailyCap;
}

/// 내가 가진 토큰.
///
/// **경고 — 소비성 잔량은 복원되지 않는다.**
/// 스토어의 "구매 복원"은 비소비성·구독만 대상으로 한다. 소비성 토큰의 잔량은 서버가
/// 없으면 이 기기에만 존재하고, 앱을 지우거나 기기를 바꾸면 사라진다. 서버(계정 연동)를
/// 붙이기 전까지는 상점에 이 사실을 반드시 표시해야 한다 — 안 그러면 환불 문의로 돌아온다.
///
/// **경고 2 — 로컬 잔량은 위조 가능하다.** 루팅 기기에서 저장값을 고치면 토큰을 늘릴 수
/// 있다. 싱글 대전에서는 자기 손해라 무시할 수 있지만, **온라인 대전에서는 토큰 사용을
/// 서버가 판정해야 한다.** 클라이언트 잔량을 믿고 PvP를 열면 안 된다.
class TokenWallet extends ChangeNotifier {
  TokenWallet({
    WalletStore? store,
    this.policy = const TokenGrantPolicy(),
  }) : _store = store ?? const WalletStore();

  final WalletStore _store;
  final TokenGrantPolicy policy;

  WalletData _data = const WalletData();
  bool _loaded = false;

  bool get isLoading => !_loaded;

  int balanceOf(TokenKind kind) => _data.balances[kind] ?? 0;

  bool has(TokenKind kind) => balanceOf(kind) > 0;

  /// 저장된 잔량을 읽고, 첫 실행이면 환영 지급을 한다.
  Future<void> load() async {
    _data = await _store.load();
    _loaded = true;
    if (!_data.welcomed) {
      _data = _data.copyWith(
        balances: _data.balances.plus(policy.welcome),
        welcomed: true,
      );
      await _store.save(_data);
    }
    notifyListeners();
  }

  /// 오늘 무료 지급을 받을 수 있는가.
  bool canClaimDaily({DateTime? now}) =>
      _loaded && _data.lastDailyYmd != _ymd(now ?? DateTime.now());

  /// 하루 1회 무료 지급. 실제로 준 토큰을 돌려준다(이미 받았으면 빈 묶음).
  Future<TokenBundle> claimDaily({DateTime? now}) async {
    final today = _ymd(now ?? DateTime.now());
    if (!_loaded || _data.lastDailyYmd == today) return const {};
    _data = _data.copyWith(
      balances: _data.balances.plus(policy.daily),
      lastDailyYmd: today,
    );
    await _store.save(_data);
    notifyListeners();
    return policy.daily;
  }

  /// 오늘 받은 광고 보상 횟수(기기 로컬 날짜 기준).
  int adRewardsToday({DateTime? now}) =>
      _data.adYmd == _ymd(now ?? DateTime.now()) ? _data.adCount : 0;

  /// 오늘 더 받을 수 있는 광고 보상 횟수.
  int adRewardsLeftToday({DateTime? now}) =>
      !_loaded ? 0 : (policy.adDailyCap - adRewardsToday(now: now)).clamp(0, policy.adDailyCap);

  /// 광고 보상 지급 — **광고를 끝까지 본 뒤에만** 부른다.
  ///
  /// 이 메서드는 "봤는가"를 판단하지 않는다. 그건 `RewardedAdService.show()`의 몫이고,
  /// 여기는 (1) 일일 캡, (2) 같은 [rewardId] 중복 지급만 막는다. 하나라도 걸리면 false.
  Future<bool> grantAdReward({required String rewardId, DateTime? now}) async {
    if (!_loaded) await load();
    final today = _ymd(now ?? DateTime.now());
    if (_data.deliveredAdRewardIds.contains(rewardId)) return false;
    final count = _data.adYmd == today ? _data.adCount : 0;
    if (count >= policy.adDailyCap) return false;
    _data = _data.copyWith(
      balances: _data.balances.plus(policy.adReward),
      adYmd: today,
      adCount: count + 1,
      deliveredAdRewardIds: [..._data.deliveredAdRewardIds, rewardId],
    );
    await _store.save(_data);
    notifyListeners();
    return true;
  }

  /// 토큰 1개를 쓴다. 잔량이 없으면 false(호출한 쪽이 상점으로 유도한다).
  Future<bool> spend(TokenKind kind) async {
    final left = balanceOf(kind);
    if (left <= 0) return false;
    final next = {..._data.balances}..[kind] = left - 1;
    _data = _data.copyWith(balances: next);
    await _store.save(_data);
    notifyListeners();
    return true;
  }

  /// 구매를 토큰으로 바꿔준다.
  ///
  /// **[purchaseId]로 중복 지급을 막는다.** 스토어는 `completePurchase`를 부르기 전까지
  /// 같은 구매를 계속 다시 배달하므로, 이 방어가 없으면 앱이 한 번 죽을 때마다 토큰이
  /// 다시 들어온다. 이미 지급한 구매면 false를 돌려준다(그래도 완료 처리는 해야 한다).
  Future<bool> grant(Product product, {required String purchaseId}) async {
    if (!_loaded) await load();
    if (_data.deliveredPurchaseIds.contains(purchaseId)) return false;
    _data = _data.copyWith(
      balances: _data.balances.plus(product.grants),
      deliveredPurchaseIds: [..._data.deliveredPurchaseIds, purchaseId],
    );
    await _store.save(_data);
    notifyListeners();
    return true;
  }

  @visibleForTesting
  TokenBundle get balances => Map.unmodifiable(_data.balances);

  static int _ymd(DateTime t) => t.year * 10000 + t.month * 100 + t.day;
}
