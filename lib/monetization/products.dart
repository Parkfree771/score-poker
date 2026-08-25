/// 판매 상품 정의.
///
/// 파는 것은 **부스트 팩 하나**다(광고는 팔지 않는다 — 애초에 광고가 없다).
/// 부스트 1개 = 한 판을 부스트해서 시작: 비공개권 칩 +1(3→4), 손패 스왑 1회.
///
/// **왜 이게 pay-to-win이 아닌가**
/// 부스트는 한 판에 **1개까지만** 쓸 수 있다(`ScoreGame.deal(boostFor:)` — 도메인이 강제).
/// 100개를 사도 한 판에서 얻는 이득은 1개 쓴 사람과 똑같다. 돈은 "이득의 크기"가 아니라
/// "이득을 쓸 수 있는 판의 수"만 늘린다. 지금 랭킹은 이 기기 안의 내 기록뿐이라 남에게
/// 피해가 없고, 온라인 대전을 붙일 때 부스트 판의 RP 반영 여부를 다시 정한다.
///
/// **가격(2026-08-25 사용자 결정)**: ₩1,000 = 10판. 애플은 정해진 가격 포인트만 쓸 수 있어
/// ₩990 같은 값이 없으므로 양쪽 스토어 모두 ₩1,000으로 통일했다. 조정은 가격이 아니라
/// **판 수**로 한다(가격 티어·심사 문제가 없다).
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

  /// 부스트 10판. ID는 종류 접두어(`boost_`)를 붙여 나중에 다른 팩을 옆에 두기 쉽게.
  static const boostPack10 = Product(
    id: 'boost_pack_10',
    grants: {TokenKind.boost: 10},
    referencePriceKrw: 1000,
  );

  /// 상점 표시 순서.
  static const all = <Product>[boostPack10];

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

  /// 스토어가 준 지역화된 가격 문자열(예: "₩1,000"). 그대로 표시할 것.
  final String formattedPrice;

  /// 숫자 가격. 개당 단가를 **실제 지역 가격으로** 계산하기 위해 필요하다.
  final double? rawPrice;

  final String? currencyCode;

  /// 토큰(판) 1개당 가격. 가격 정보가 없으면 null.
  double? get pricePerToken {
    final p = rawPrice;
    if (p == null || product.tokenCount == 0) return null;
    return p / product.tokenCount;
  }
}

/// 낱개 상품 대비 세트가 몇 % 싼지 — **스토어가 준 실제 가격으로** 계산한다.
///
/// 가격 정보가 없거나 더 싸지 않으면 null을 돌려준다(배지를 아예 숨긴다).
/// 지금은 상품이 하나라 쓰지 않지만, 큰 팩을 옆에 둘 때 그대로 쓴다.
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
