import 'dart:async';

import 'package:flutter/widgets.dart';

import 'products.dart';
import 'purchase_service.dart';
import 'purchase_service_factory.dart';
import 'wallet.dart';

export 'products.dart';
export 'purchase_service.dart';
export 'purchase_service_factory.dart';
export 'tokens.dart';
export 'wallet.dart';
export 'wallet_store.dart';

/// 결제와 지갑을 한 곳에서 들고 있는 조립체. 앱은 이것 하나만 알면 된다.
///
/// **시작 순서가 중요하다.** [startAsync]는 `runApp` **이후**, 첫 프레임이 그려진 뒤에
/// 호출한다. 스토어 연결은 네트워크를 타서 수백 ms가 걸리는데, `main()`에서 await하면
/// 그동안 흰 화면이 뜬다.
class Monetization {
  /// [purchases]를 비우면 플랫폼에 맞는 구현이 자동으로 선택된다
  /// (모바일 = 실제 스토어, 웹·데스크톱·테스트 = 스텁).
  Monetization({PurchaseService? purchases, TokenWallet? wallet})
      : purchases = purchases ?? createPurchaseService(),
        wallet = wallet ?? TokenWallet();

  final PurchaseService purchases;
  final TokenWallet wallet;

  /// 스토어에서 받아온 상품 정보. 아직 못 받았으면 비어 있다(상점은 "불러오는 중"을 띄운다).
  final ValueNotifier<List<ProductOffer>> offers = ValueNotifier(const []);

  StreamSubscription<PendingPurchase>? _sub;

  /// 배달된 구매를 **한 번에 하나씩** 처리하기 위한 직렬화 큐.
  /// 두 건이 동시에 지갑을 읽고 쓰면 한 건이 사라진다.
  Future<void> _queue = Future.value();

  bool _started = false;
  bool _disposed = false;

  /// 첫 프레임 이후에 호출한다.
  ///
  /// 1) 지갑을 먼저 읽어 화면이 곧바로 올바른 잔량을 그리게 하고,
  /// 2) 배달 스트림을 **스토어 연결 전에** 구독한다(앱이 죽어 밀려 있던 구매를 놓치지 않게),
  /// 3) 스토어에 연결하고 가격을 받아온다.
  Future<void> startAsync() async {
    if (_started) return;
    _started = true;

    await wallet.load();

    // 구독이 먼저다. initialize()가 밀린 구매를 즉시 흘려보낼 수 있다.
    _sub = purchases.delivered.listen(_enqueueDelivery);

    if (purchases.isSupported) await purchases.initialize();

    // 지원하지 않는 플랫폼에서도 상품 목록은 채운다 — 스텁이 참고가를 돌려주므로
    // 웹/데스크톱에서 상점 화면을 그대로 확인할 수 있다(상점이 "참고가"라고 표시한다).
    await _refreshOffers();
  }

  Future<void> _refreshOffers() async {
    try {
      offers.value = await purchases.loadOffers();
    } on Object {
      // 가격을 못 받아도 앱은 돌아가야 한다. 상점이 "불러오는 중"으로 남는다.
    }
  }

  /// 개발/웹에서 상점 화면을 확인할 수 있도록 스텁의 참고가라도 채워둔다.
  Future<void> loadOffersForPreview() => _refreshOffers();

  void _enqueueDelivery(PendingPurchase p) {
    _queue = _queue.then((_) => _deliver(p)).catchError((Object _) {});
  }

  /// **지급 → 저장 → 완료** 순서를 지킨다(순서를 바꾸면 돈만 받고 토큰을 못 주는 창이 생긴다).
  Future<void> _deliver(PendingPurchase p) async {
    await wallet.grant(p.product, purchaseId: p.purchaseId);
    // 이미 지급된 구매여도 완료 처리는 반드시 한다 —
    // 안 하면 스토어가 영원히 다시 배달하고, 안드로이드에서는 재구매가 막힌다.
    await purchases.complete(p);
  }

  Future<PurchaseResult> buy(Product product) => purchases.buy(product);

  /// **두 번 불려도 안전해야 한다.** 주입해서 쓰는 객체라 소유자가 둘일 수 있다
  /// (앱 위젯의 dispose + 만든 쪽의 정리). 가드가 없으면 이미 dispose된
  /// ValueNotifier/ChangeNotifier를 또 dispose해서 죽는다.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _sub?.cancel();
    await purchases.dispose();
    offers.dispose();
    wallet.dispose();
  }
}

/// 위젯 트리에 [Monetization]을 내려보낸다.
class MonetizationScope extends InheritedWidget {
  const MonetizationScope({super.key, required this.monetization, required super.child});

  final Monetization monetization;

  static Monetization of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<MonetizationScope>();
    assert(scope != null, 'MonetizationScope가 위에 없습니다');
    return scope!.monetization;
  }

  static Monetization? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<MonetizationScope>()?.monetization;

  @override
  bool updateShouldNotify(MonetizationScope old) => old.monetization != monetization;
}
