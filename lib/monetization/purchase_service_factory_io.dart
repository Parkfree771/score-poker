import 'dart:io';

import 'purchase_service.dart';
import 'store_purchase_service.dart';

/// 모바일에서만 실제 스토어를 붙인다.
///
/// 데스크톱(Windows/macOS/Linux)과 **테스트(Dart VM)** 는 스텁을 쓴다 —
/// 테스트가 실제 결제 SDK를 건드리면 플러그인 채널이 없어 죽는다.
PurchaseService createPurchaseService() {
  if (Platform.isAndroid || Platform.isIOS) return StorePurchaseService();
  return StubPurchaseService();
}
