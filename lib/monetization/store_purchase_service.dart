import 'dart:async';
import 'dart:io';

import 'package:in_app_purchase/in_app_purchase.dart' as iap;
import 'package:in_app_purchase_android/in_app_purchase_android.dart';

import 'products.dart';
import 'purchase_service.dart';

/// 실제 스토어(Google Play / App Store) 결제.
///
/// **소비성 상품에서 가장 흔한 두 가지 사고를 여기서 막는다:**
///
/// 1. **`autoConsume: false`로 산다.** 기본값(true)이면 토큰을 지급하기 *전에* 소비
///    처리가 끝난다. 그 사이 앱이 죽으면 스토어는 "이미 처리된 구매"로 보고 다시
///    배달하지 않는다 → 돈만 받고 토큰을 못 준다. 우리가 지급을 마친 뒤에
///    [complete]에서 직접 소비한다.
/// 2. **소비를 빠뜨리지 않는다.** 안드로이드에서 소비 처리를 안 하면 그 상품을
///    **다시 살 수 없다.** (Play는 3일 안에 소비/승인되지 않은 구매를 자동 환불한다)
class StorePurchaseService implements PurchaseService {
  StorePurchaseService({iap.InAppPurchase? store})
      : _store = store ?? iap.InAppPurchase.instance;

  final iap.InAppPurchase _store;

  final _delivered = StreamController<PendingPurchase>.broadcast();
  StreamSubscription<List<iap.PurchaseDetails>>? _sub;

  /// 완료 처리를 하려면 원본 [iap.PurchaseDetails]가 필요하다. 우리 [PendingPurchase]는
  /// 도메인 쪽 타입이라 SDK 객체를 들고 있지 않으므로 여기서 짝을 보관한다.
  final _pendingDetails = <String, iap.PurchaseDetails>{};

  bool _available = false;

  @override
  bool get isSupported => Platform.isAndroid || Platform.isIOS;

  @override
  Future<void> initialize() async {
    // 스트림 구독이 먼저다 — 연결 직후 밀려 있던 구매가 즉시 흘러온다.
    _sub = _store.purchaseStream.listen(
      _onPurchases,
      onError: (Object _) {}, // 스트림 오류로 앱이 죽지 않게
    );

    _available = await _store.isAvailable();
    if (!_available) return;

    // 안드로이드: 지급 전에 앱이 죽어 **소비되지 않은 채 남은 구매**를 다시 꺼내온다.
    // (iOS는 미완료 트랜잭션을 StoreKit이 알아서 스트림에 다시 흘려보내므로 부르지
    //  않는다 — 부르면 App Store 로그인 창이 뜰 수 있다.)
    if (Platform.isAndroid) {
      try {
        await _store.restorePurchases();
      } on Object {
        // 복구 실패는 치명적이지 않다. 다음 실행에 다시 시도된다.
      }
    }
  }

  @override
  Future<List<ProductOffer>> loadOffers() async {
    if (!_available) return const [];
    final response =
        await _store.queryProductDetails({for (final p in Products.all) p.id});

    // notFoundIDs는 대개 **스토어 콘솔에 상품이 없거나 아직 활성화 전**이라는 뜻이다.
    // 조용히 비어 보이면 원인을 못 찾으므로 로그 대신 목록에서 빠지는 것으로 드러난다.
    return [
      for (final d in response.productDetails)
        if (Products.byId(d.id) case final product?)
          ProductOffer(
            product: product,
            title: d.title,
            description: d.description,
            formattedPrice: d.price, // 스토어가 만든 지역화 문자열 — 그대로 쓴다
            rawPrice: d.rawPrice,
            currencyCode: d.currencyCode,
          ),
    ];
  }

  @override
  Future<PurchaseResult> buy(Product product) async {
    if (!_available) {
      return const PurchaseResult(PurchaseStatus.notSupported);
    }
    final response = await _store.queryProductDetails({product.id});
    if (response.productDetails.isEmpty) {
      return const PurchaseResult(PurchaseStatus.error,
          message: 'product not found in store');
    }

    try {
      // 반환값은 "결제창을 띄웠는가"일 뿐이다. 실제 결과(구매/취소/오류)는
      // purchaseStream으로 온다 — 여기서 성공을 단정하면 안 된다.
      final launched = await _store.buyConsumable(
        purchaseParam:
            iap.PurchaseParam(productDetails: response.productDetails.first),
        autoConsume: false, // ★ 지급을 마친 뒤 우리가 직접 소비한다 (클래스 문서 참고)
      );
      return launched
          ? const PurchaseResult(PurchaseStatus.purchased)
          : const PurchaseResult(PurchaseStatus.cancelled);
    } on Object catch (e) {
      return PurchaseResult(PurchaseStatus.error, message: '$e');
    }
  }

  void _onPurchases(List<iap.PurchaseDetails> purchases) {
    for (final details in purchases) {
      switch (details.status) {
        case iap.PurchaseStatus.purchased:
        case iap.PurchaseStatus.restored:
          final product = Products.byId(details.productID);
          if (product == null) {
            // 우리가 모르는 상품 — 그냥 종료 처리해서 재배달을 끊는다.
            unawaited(_finish(details));
            break;
          }
          // purchaseID가 없는 경우(일부 플랫폼)에는 상품id+토큰으로 대체 키를 만든다.
          // 이 키가 중복 지급 방지의 전부이므로 절대 비워 두면 안 된다.
          final id = details.purchaseID ??
              '${details.productID}:'
                  '${details.verificationData.serverVerificationData.hashCode}';
          _pendingDetails[id] = details;
          _delivered.add(PendingPurchase(purchaseId: id, product: product));

        case iap.PurchaseStatus.pending:
          // 승인 대기(부모 승인·계좌이체). **여기서 지급하면 안 된다.**
          break;

        case iap.PurchaseStatus.error:
        case iap.PurchaseStatus.canceled:
          // 실패해도 완료 처리는 해야 트랜잭션이 정리된다.
          unawaited(_finish(details));
      }
    }
  }

  @override
  Future<void> complete(PendingPurchase purchase) async {
    final details = _pendingDetails.remove(purchase.purchaseId);
    if (details == null) return;
    await _finish(details);
  }

  /// 트랜잭션 종료.
  ///
  /// 안드로이드에서는 **소비(consume)** 가 곧 완료다 — 소비하면 Play의 보유 목록에서
  /// 빠져 재구매가 가능해지고, 승인(acknowledge)도 함께 처리된다.
  /// iOS는 [iap.InAppPurchase.completePurchase]로 트랜잭션을 끝낸다.
  Future<void> _finish(iap.PurchaseDetails details) async {
    try {
      if (Platform.isAndroid) {
        final android = _store
            .getPlatformAddition<InAppPurchaseAndroidPlatformAddition>();
        await android.consumePurchase(details);
      } else if (details.pendingCompletePurchase) {
        await _store.completePurchase(details);
      }
    } on Object {
      // 완료 처리에 실패하면 스토어가 다시 배달한다. 지갑이 중복 지급을 막으므로
      // 다음 기회에 다시 시도되는 것이 옳은 동작이다.
    }
  }

  @override
  Stream<PendingPurchase> get delivered => _delivered.stream;

  @override
  Future<void> dispose() async {
    await _sub?.cancel();
    await _delivered.close();
  }
}
