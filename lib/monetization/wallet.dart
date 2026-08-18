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
/// - 환영 지급 3세트: **써 보지 않은 아이템은 사지 않는다.** 첫 판부터 효과를 경험시킨다.
/// - 데일리 1세트: 하루 한 판을 부스트할 수 있다. 하루 1~2판 하는 라이트 유저는 사실상
///   전부 무료로 덮이고(어차피 결제하지 않을 층이다), 하루 5판 이상 하는 층에게만
///   "부족하다"는 감각이 생긴다. 이 층이 결제 모수다.
class TokenGrantPolicy {
  const TokenGrantPolicy({
    this.welcome = const {TokenKind.shield: 3, TokenKind.attack: 3},
    this.daily = const {TokenKind.shield: 1, TokenKind.attack: 1},
  });

  /// 첫 실행 1회 지급.
  final TokenBundle welcome;

  /// 하루 1회 지급.
  final TokenBundle daily;
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
