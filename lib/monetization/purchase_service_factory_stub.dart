import 'purchase_service.dart';

/// 웹: 결제 SDK가 없다. 상점은 열리되 구매는 "지원하지 않음"으로 응답한다.
PurchaseService createPurchaseService() => StubPurchaseService();
