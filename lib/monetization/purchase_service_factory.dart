/// 플랫폼에 맞는 [PurchaseService] 구현을 고른다.
///
/// **조건부 import를 쓰는 이유**: 실제 구현은 `dart:io`와 결제 SDK에 의존하는데,
/// 웹 빌드는 `dart:io`를 컴파일조차 못 한다. 웹에서는 스텁 쪽 파일만 컴파일된다.
library;

export 'purchase_service_factory_stub.dart'
    if (dart.library.io) 'purchase_service_factory_io.dart';
