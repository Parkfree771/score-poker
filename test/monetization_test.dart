import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:score_poker/monetization/monetization.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 수익화 계층의 **규칙**을 고정한다. 여기가 깨지면 돈만 받고 토큰을 못 주거나,
/// 반대로 한 번 산 걸 매번 다시 주거나, 안드로이드에서 재구매가 막힌다 —
/// 전부 조용히 망가지고 환불 문의로만 드러나는 것들이다.

class _FakePurchases implements PurchaseService {
  _FakePurchases({this.emitOnInitialize});

  /// 스토어 연결 시점에 밀려 있던 구매를 흘려보낸다(앱이 지급 전에 죽었던 경우).
  final PendingPurchase? emitOnInitialize;

  final _delivered = StreamController<PendingPurchase>.broadcast();
  final completed = <String>[];
  bool initialized = false;
  int offersLoaded = 0;

  @override
  bool get isSupported => true;

  @override
  Future<void> initialize() async {
    initialized = true;
    final pending = emitOnInitialize;
    if (pending != null) _delivered.add(pending);
  }

  @override
  Future<List<ProductOffer>> loadOffers() async {
    offersLoaded++;
    return [
      for (final p in Products.all)
        ProductOffer(
          product: p,
          title: p.id,
          description: '',
          formattedPrice: '₩${p.referencePriceKrw}',
          rawPrice: p.referencePriceKrw.toDouble(),
          currencyCode: 'KRW',
        ),
    ];
  }

  @override
  Future<PurchaseResult> buy(Product product) async {
    _delivered.add(PendingPurchase(purchaseId: 'txn-${product.id}', product: product));
    return const PurchaseResult(PurchaseStatus.purchased);
  }

  void deliver(PendingPurchase p) => _delivered.add(p);

  @override
  Stream<PendingPurchase> get delivered => _delivered.stream;

  @override
  Future<void> complete(PendingPurchase purchase) async =>
      completed.add(purchase.purchaseId);

  @override
  Future<void> dispose() async => _delivered.close();
}

/// 이벤트 루프를 몇 바퀴 돌려 배달 큐가 비워지길 기다린다.
Future<void> settle() async {
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('TokenWallet', () {
    test('첫 실행에 환영 토큰을 주고, 두 번째 실행에는 다시 주지 않는다', () async {
      final a = TokenWallet();
      await a.load();
      expect(a.balanceOf(TokenKind.boost), 3);

      final b = TokenWallet();
      await b.load();
      expect(b.balanceOf(TokenKind.boost), 3, reason: '환영 지급이 실행마다 반복되면 상품이 안 팔린다');
    });

    test('쓰면 줄고, 없으면 못 쓴다', () async {
      final w = TokenWallet(policy: const TokenGrantPolicy(welcome: {TokenKind.boost: 1}));
      await w.load();
      expect(await w.spend(TokenKind.boost), isTrue);
      expect(w.balanceOf(TokenKind.boost), 0);
      expect(await w.spend(TokenKind.boost), isFalse);
      expect(w.balanceOf(TokenKind.boost), 0, reason: '잔량이 음수로 내려가면 안 된다');
    });

    test('잔량은 다음 실행에 살아난다', () async {
      final a = TokenWallet();
      await a.load();
      await a.spend(TokenKind.boost);

      final b = TokenWallet();
      await b.load();
      expect(b.balanceOf(TokenKind.boost), 2);
    });

    test('데일리 무료 지급은 하루 한 번(정책이 켜져 있을 때)', () async {
      final w = TokenWallet(policy: const TokenGrantPolicy(daily: {TokenKind.boost: 1}));
      await w.load();
      final day1 = DateTime(2026, 8, 18, 9);

      expect(w.canClaimDaily(now: day1), isTrue);
      expect(await w.claimDaily(now: day1), isNotEmpty);
      expect(w.balanceOf(TokenKind.boost), 4);

      expect(w.canClaimDaily(now: day1.add(const Duration(hours: 10))), isFalse);
      expect(await w.claimDaily(now: day1.add(const Duration(hours: 10))), isEmpty);
      expect(w.balanceOf(TokenKind.boost), 4, reason: '같은 날 여러 번 받으면 무한 지급이 된다');

      expect(await w.claimDaily(now: DateTime(2026, 8, 19, 0, 1)), isNotEmpty);
      expect(w.balanceOf(TokenKind.boost), 5);
    });

    test('같은 구매 id로는 두 번 지급하지 않는다', () async {
      final w = TokenWallet();
      await w.load();
      final before = w.balanceOf(TokenKind.boost);

      expect(await w.grant(Products.boostPack10, purchaseId: 'txn-1'), isTrue);
      expect(w.balanceOf(TokenKind.boost), before + 10);

      expect(await w.grant(Products.boostPack10, purchaseId: 'txn-1'), isFalse,
          reason: '완료 처리 전에 앱이 죽으면 스토어가 같은 구매를 다시 배달한다');
      expect(w.balanceOf(TokenKind.boost), before + 10);

      expect(await w.grant(Products.boostPack10, purchaseId: 'txn-2'), isTrue);
      expect(w.balanceOf(TokenKind.boost), before + 20);
    });

    test('중복 방지 기록은 앱을 다시 켜도 남는다', () async {
      final a = TokenWallet();
      await a.load();
      await a.grant(Products.boostPack10, purchaseId: 'txn-restart');

      final b = TokenWallet();
      await b.load();
      expect(await b.grant(Products.boostPack10, purchaseId: 'txn-restart'), isFalse);
      expect(b.balanceOf(TokenKind.boost), 13);
    });

    test('저장값이 깨져도 앱은 켜진다', () async {
      SharedPreferences.setMockInitialValues({'wallet.v1': '{잘못된 JSON'});
      final w = TokenWallet();
      await w.load();
      expect(w.isLoading, isFalse);
      expect(w.balanceOf(TokenKind.boost), 3, reason: '깨진 값은 버리고 첫 실행처럼 시작한다');
    });

    test('잔량이 바뀌면 화면에 알린다', () async {
      final w = TokenWallet();
      await w.load();
      var notifications = 0;
      w.addListener(() => notifications++);
      await w.spend(TokenKind.boost);
      await w.grant(Products.boostPack10, purchaseId: 'txn-n');
      expect(notifications, 2);
    });
  });

  group('상품 구성', () {
    test('부스트 팩: ₩1,000에 10판 — 한 판 100원', () {
      expect(Products.boostPack10.referencePriceKrw, 1000);
      expect(Products.boostPack10.tokenCount, 10);
      expect(Products.byId('boost_pack_10'), Products.boostPack10);
    });

    test('개당 단가는 토큰 수로 나눈 값', () {
      const o = ProductOffer(
        product: Products.boostPack10,
        title: '',
        description: '',
        formattedPrice: '₩1,000',
        rawPrice: 1000,
      );
      expect(o.pricePerToken, 100);
    });
  });

  group('Monetization 조립체', () {
    test('구매하면 토큰이 들어오고, 스토어에 완료를 알린다', () async {
      final purchases = _FakePurchases();
      final m = Monetization(purchases: purchases);
      await m.startAsync();
      final before = m.wallet.balanceOf(TokenKind.boost);

      await m.buy(Products.boostPack10);
      await settle();

      expect(m.wallet.balanceOf(TokenKind.boost), before + 10);
      expect(purchases.completed, ['txn-${Products.boostPack10.id}'],
          reason: '소비 처리를 안 하면 안드로이드에서 같은 상품을 다시 살 수 없다');
      await m.dispose();
    });

    test('앱이 죽어 밀려 있던 구매도 시작 직후 지급된다', () async {
      const pending =
          PendingPurchase(purchaseId: 'txn-pending', product: Products.boostPack10);
      final purchases = _FakePurchases(emitOnInitialize: pending);
      final m = Monetization(purchases: purchases);

      await m.startAsync();
      await settle();

      expect(m.wallet.balanceOf(TokenKind.boost), 13,
          reason: '구독을 initialize() 뒤에 하면 이 구매를 영영 놓친다');
      expect(purchases.completed, ['txn-pending']);
      await m.dispose();
    });

    test('이미 지급한 구매가 다시 배달돼도 토큰은 한 번만 — 완료 처리는 다시 한다', () async {
      final purchases = _FakePurchases();
      final m = Monetization(purchases: purchases);
      await m.startAsync();

      const p = PendingPurchase(purchaseId: 'txn-dup', product: Products.boostPack10);
      purchases.deliver(p);
      await settle();
      purchases.deliver(p);
      await settle();

      expect(m.wallet.balanceOf(TokenKind.boost), 13);
      expect(purchases.completed, ['txn-dup', 'txn-dup'],
          reason: '완료를 다시 안 하면 스토어가 영원히 재배달한다');
      await m.dispose();
    });

    test('동시에 배달된 구매가 서로를 덮어쓰지 않는다', () async {
      final purchases = _FakePurchases();
      final m = Monetization(purchases: purchases);
      await m.startAsync();

      purchases.deliver(
          const PendingPurchase(purchaseId: 'a', product: Products.boostPack10));
      purchases.deliver(
          const PendingPurchase(purchaseId: 'b', product: Products.boostPack10));
      await settle();

      expect(m.wallet.balanceOf(TokenKind.boost), 23,
          reason: '직렬화하지 않으면 둘이 같은 잔량을 읽고 한 건이 사라진다');
      await m.dispose();
    });

    test('시작하면 가격을 받아온다', () async {
      final purchases = _FakePurchases();
      final m = Monetization(purchases: purchases);
      await m.startAsync();
      expect(purchases.initialized, isTrue);
      expect(m.offers.value.length, Products.all.length);
      await m.dispose();
    });

    test('결제 미지원 플랫폼에서도 상점은 열린다(참고가 표시용)', () async {
      final m = Monetization(purchases: StubPurchaseService());
      await m.startAsync();
      expect(m.offers.value.length, Products.all.length);
      expect(m.purchases.isSupported, isFalse);
      final result = await m.buy(Products.boostPack10);
      expect(result.status, PurchaseStatus.notSupported);
      await m.dispose();
    });

    test('두 번 시작해도 한 번만 초기화한다', () async {
      final purchases = _FakePurchases();
      final m = Monetization(purchases: purchases);
      await m.startAsync();
      await m.startAsync();
      expect(purchases.offersLoaded, 1);
      await m.dispose();
    });
  });
}
