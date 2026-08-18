import 'dart:async';

import 'products.dart';

enum PurchaseStatus {
  /// 스토어가 구매를 확정했다. 토큰 지급은 [PurchaseService.delivered] 스트림으로 온다.
  purchased,

  /// 사용자가 취소.
  cancelled,

  /// 결제 승인 대기(부모 승인, 계좌이체 등). **여기서 토큰을 주면 안 된다.**
  pending,

  error,

  /// 이 플랫폼에서는 결제를 지원하지 않는다(웹·데스크톱).
  notSupported,
}

class PurchaseResult {
  const PurchaseResult(this.status, {this.message});
  final PurchaseStatus status;
  final String? message;

  bool get isSuccess => status == PurchaseStatus.purchased;
}

/// 아직 토큰으로 바꿔주지 않은 구매.
///
/// 처리 순서를 지켜야 한다: **지급 → 저장 → [PurchaseService.complete]**.
/// 완료 처리를 먼저 하면, 그 직후 앱이 죽었을 때 돈만 받고 토큰은 못 준 상태가 된다.
/// 반대로 하면 최악의 경우 중복 배달이 오는데, 그건 [purchaseId]로 막는다.
class PendingPurchase {
  const PendingPurchase({required this.purchaseId, required this.product});

  /// 스토어 거래 id. 중복 지급 방지 키다.
  final String purchaseId;
  final Product product;

  @override
  String toString() => 'PendingPurchase($purchaseId, ${product.id})';
}

/// 결제 창구. 실제 구현은 `in_app_purchase`를 감싸고, 개발/웹에서는 [StubPurchaseService].
///
/// 규칙:
/// - **도메인(`lib/domain`)은 이 계층을 몰라야 한다.** 게임 규칙이 결제에 의존하면
///   테스트가 어려워지고 pay-to-win으로 흘러가기 쉽다. 토큰의 효과는 `GameRules`라는
///   순수한 값으로만 도메인에 들어간다.
/// - **소비성 상품은 반드시 소비 처리해야 한다.** 안드로이드에서 `consumePurchase`를
///   빼먹으면 그 상품을 **다시 살 수 없다** — 가장 흔한 결제 버그다. [complete]가 담당한다.
/// - 구매 성공 응답만 믿지 말고 [delivered] 스트림으로 지급한다(앱 재시작·지연 승인).
abstract class PurchaseService {
  bool get isSupported;

  /// 스토어 연결. 첫 프레임 이후에 호출한다.
  Future<void> initialize();

  /// 가격 표시용 상품 정보. **가격을 앱에 하드코딩하지 말 것**(지역·환율·세금·가격 포인트).
  Future<List<ProductOffer>> loadOffers();

  Future<PurchaseResult> buy(Product product);

  /// 토큰으로 바꿔줘야 할 구매가 흘러온다. 앱 시작 직후 밀린 구매도 여기로 온다.
  Stream<PendingPurchase> get delivered;

  /// 지급을 끝냈다고 스토어에 알린다(iOS finishTransaction / Android consume).
  Future<void> complete(PendingPurchase purchase);

  Future<void> dispose();
}

/// 스토어 SDK 없이 도는 스텁 — 웹/데스크톱 개발용.
///
/// [autoGrant]를 켜면 구매가 즉시 성공한 것처럼 처리되어 상점·인게임 UI를 확인할 수 있다.
/// 실제 결제는 일어나지 않는다.
class StubPurchaseService implements PurchaseService {
  StubPurchaseService({this.autoGrant = false});

  final bool autoGrant;

  final _delivered = StreamController<PendingPurchase>.broadcast();
  int _seq = 0;

  @override
  bool get isSupported => false;

  @override
  Future<void> initialize() async {}

  /// 스텁에서는 상품 정의의 **참고가**를 보여준다.
  /// 실기기에서는 이 값을 절대 쓰지 않는다(스토어가 준 가격으로 덮인다).
  @override
  Future<List<ProductOffer>> loadOffers() async => [
        for (final p in Products.all)
          ProductOffer(
            product: p,
            title: p.id,
            description: '',
            formattedPrice: '₩${_comma(p.referencePriceKrw)}',
            rawPrice: p.referencePriceKrw.toDouble(),
            currencyCode: 'KRW',
          ),
      ];

  @override
  Future<PurchaseResult> buy(Product product) async {
    if (!autoGrant) {
      // 사용자에게 보일 문장은 UI가 l10n으로 만든다(여기서 한국어를 박으면 영어 빌드에 샌다).
      return const PurchaseResult(PurchaseStatus.notSupported);
    }
    _delivered.add(PendingPurchase(
      purchaseId: 'stub-${product.id}-${_seq++}',
      product: product,
    ));
    return const PurchaseResult(PurchaseStatus.purchased);
  }

  @override
  Stream<PendingPurchase> get delivered => _delivered.stream;

  @override
  Future<void> complete(PendingPurchase purchase) async {}

  @override
  Future<void> dispose() async => _delivered.close();

  static String _comma(int n) {
    final s = '$n';
    final b = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
      b.write(s[i]);
    }
    return b.toString();
  }
}
