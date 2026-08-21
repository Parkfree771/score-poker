/// 판매 상품 정의.
///
/// **2026-08-21 현재 이 상품들은 진열되지 않는다.** 가림 룰(v3)로 바뀌면서 토큰을 쓰던
/// 규칙이 사라졌고, 상점 화면은 "준비 중"만 보여준다. 정의를 남겨 두는 이유는 결제
/// 배관(구매 복원·지급·지갑)이 이 형태 위에서 검증돼 있기 때문이다 — 새 규칙에 맞는
/// 상품이 정해지면 여기만 갈아 끼우면 된다.
///
/// 파는 것은 **인게임 토큰 두 종류뿐**이다(광고는 팔지 않는다 — 애초에 광고가 없다).
///
/// **왜 이게 pay-to-win이 아닌가**
/// 토큰은 한 판에 **각 종류 1개까지만** 쓸 수 있다(`GameRules`). 100개를 사도 한 판에서
/// 얻는 이득은 1개 쓴 사람과 똑같다. 즉 돈은 "이득의 크기"가 아니라 "이득을 쓸 수 있는
/// 판의 수"만 늘린다. 게다가 쉴드는 조커로 깨지고(덱에 2장), 공격 표식은 같은 숫자 규칙과
/// 빈 칸 조건을 그대로 받는다 — 규칙 안에서 이미 카운터가 존재한다.
library;

import 'tokens.dart';

/// 이 게임의 상품은 전부 소비성이다(쓰면 없어진다).
///
/// 소비성이라 **스토어 "구매 복원"의 대상이 아니다.** 잔량은 기기에 남는다
/// (`TokenWallet` 문서의 경고 참고).
enum ProductKind { consumable }

class Product {
  const Product({
    required this.id,
    required this.grants,
    required this.referencePriceKrw,
    this.kind = ProductKind.consumable,
  });

  /// 스토어 콘솔에 등록할 상품 ID. **콘솔과 글자 하나까지 같아야 한다.**
  final String id;

  /// 구매 시 지급할 토큰.
  final TokenBundle grants;

  /// 개발/스텁 표시용 **참고가**. 실제 결제 금액이 아니다.
  ///
  /// 실제로 보여줄 가격은 언제나 스토어가 준 [ProductOffer.formattedPrice]다
  /// (지역·환율·세금·가격 포인트가 나라마다 다르다).
  final int referencePriceKrw;

  final ProductKind kind;

  /// 이 상품이 주는 토큰 총 개수(개당 단가 계산용).
  int get tokenCount => grants.total;

  @override
  bool operator ==(Object other) => other is Product && other.id == id;
  @override
  int get hashCode => id.hashCode;
  @override
  String toString() => 'Product($id)';
}

class Products {
  Products._();

  /// 쉴드 토큰 10개.
  static const shield10 = Product(
    id: 'token_shield_10',
    grants: {TokenKind.shield: 10},
    referencePriceKrw: 3300,
  );

  /// 공격 토큰 10개. **쉴드와 같은 가격** — 둘의 강도가 대칭이라 가격도 대칭이다.
  static const attack10 = Product(
    id: 'token_attack_10',
    grants: {TokenKind.attack: 10},
    referencePriceKrw: 3300,
  );

  /// 세트 20개(각 10개). 낱개 두 개(₩6,600)보다 싸다 — 실질적으로 이걸 사게 된다.
  static const set20 = Product(
    id: 'token_set_20',
    grants: {TokenKind.shield: 10, TokenKind.attack: 10},
    referencePriceKrw: 4990,
  );

  /// 상점 표시 순서. 세트를 맨 위에 둔다(가장 유리한 선택을 먼저 보여준다).
  static const all = <Product>[set20, shield10, attack10];

  static Product? byId(String id) {
    for (final p in all) {
      if (p.id == id) return p;
    }
    return null;
  }
}

/// 스토어에서 받아온 상품 정보.
///
/// **가격 문자열을 앱에서 만들지 말 것.** 통화 기호·자릿수·세금 포함 여부가 나라마다
/// 다르고, 애플·구글의 가격 포인트가 달라 같은 상품도 플랫폼마다 금액이 다를 수 있다.
class ProductOffer {
  const ProductOffer({
    required this.product,
    required this.title,
    required this.description,
    required this.formattedPrice,
    this.rawPrice,
    this.currencyCode,
  });

  final Product product;
  final String title;
  final String description;

  /// 스토어가 준 지역화된 가격 문자열(예: "₩4,990"). 그대로 표시할 것.
  final String formattedPrice;

  /// 숫자 가격. 할인율·개당 단가를 **실제 지역 가격으로** 계산하기 위해 필요하다.
  /// (하드코딩한 "24% 할인"은 다른 나라에서 거짓말이 된다)
  final double? rawPrice;

  final String? currencyCode;

  /// 토큰 1개당 가격. 가격 정보가 없으면 null.
  double? get pricePerToken {
    final p = rawPrice;
    if (p == null || product.tokenCount == 0) return null;
    return p / product.tokenCount;
  }
}

/// 낱개 상품 대비 세트가 몇 % 싼지 — **스토어가 준 실제 가격으로** 계산한다.
///
/// 가격 정보가 없거나 더 싸지 않으면 null을 돌려준다(배지를 아예 숨긴다).
int? discountPercent(ProductOffer set, Iterable<ProductOffer> singles) {
  final setPrice = set.rawPrice;
  if (setPrice == null || setPrice <= 0) return null;
  var reference = 0.0;
  for (final s in singles) {
    final p = s.rawPrice;
    if (p == null) return null;
    reference += p;
  }
  if (reference <= setPrice) return null;
  return (((reference - setPrice) / reference) * 100).round();
}
