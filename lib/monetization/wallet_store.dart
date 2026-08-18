import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'tokens.dart';

/// 지갑의 저장 형태. 한 덩어리 JSON으로 읽고 쓴다(부분 갱신 중 전원이 꺼져도
/// 잔량과 "지급 완료 목록"이 서로 어긋나지 않게).
class WalletData {
  const WalletData({
    this.balances = const {},
    this.lastDailyYmd,
    this.welcomed = false,
    this.deliveredPurchaseIds = const [],
  });

  final TokenBundle balances;

  /// 마지막으로 데일리 무료 지급을 받은 날짜(yyyymmdd, 기기 로컬 날짜).
  final int? lastDailyYmd;

  /// 첫 설치 환영 지급을 이미 했는가.
  final bool welcomed;

  /// **이미 토큰으로 바꿔준 스토어 거래 id.**
  ///
  /// 소비성 상품은 `completePurchase` 전에 앱이 죽으면 다음 실행에 같은 구매가 다시
  /// 배달된다. 이 목록이 없으면 그때마다 토큰을 또 준다.
  final List<String> deliveredPurchaseIds;

  WalletData copyWith({
    TokenBundle? balances,
    int? lastDailyYmd,
    bool? welcomed,
    List<String>? deliveredPurchaseIds,
  }) =>
      WalletData(
        balances: balances ?? this.balances,
        lastDailyYmd: lastDailyYmd ?? this.lastDailyYmd,
        welcomed: welcomed ?? this.welcomed,
        deliveredPurchaseIds: deliveredPurchaseIds ?? this.deliveredPurchaseIds,
      );

  Map<String, Object?> toJson() => {
        'b': {for (final e in balances.entries) tokenKey(e.key): e.value},
        'd': lastDailyYmd,
        'w': welcomed,
        'p': deliveredPurchaseIds,
      };

  static WalletData fromJson(Map<String, dynamic> json) {
    final balances = <TokenKind, int>{};
    final raw = json['b'];
    if (raw is Map) {
      for (final e in raw.entries) {
        final kind = tokenKindFromKey('${e.key}');
        final value = e.value;
        if (kind != null && value is int && value > 0) balances[kind] = value;
      }
    }
    return WalletData(
      balances: balances,
      lastDailyYmd: json['d'] as int?,
      welcomed: json['w'] as bool? ?? false,
      deliveredPurchaseIds: [
        for (final id in (json['p'] as List? ?? const [])) '$id',
      ],
    );
  }
}

/// 지갑의 로컬 저장소.
///
/// **주의: 여기가 진실의 원천이다.** 소비성 상품은 스토어의 "구매 복원" 대상이 아니라
/// 서버가 없는 한 다른 사본이 존재하지 않는다. 앱을 지우면 잔량도 사라진다.
class WalletStore {
  const WalletStore();

  static const _key = 'wallet.v1';

  /// 지급 완료 목록이 무한히 자라지 않게 최근 것만 남긴다.
  /// (스토어는 오래된 거래를 다시 배달하지 않는다)
  static const maxDeliveredIds = 200;

  Future<WalletData> load() async {
    // 저장소 자체를 못 여는 환경(플러그인 없는 테스트 등)과 손상된 값을 모두 흡수한다.
    // 잔량을 잃는 건 아프지만, 앱이 안 켜지는 것보다는 낫다.
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null) return const WalletData();
      return WalletData.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } on Object {
      return const WalletData();
    }
  }

  /// 저장 실패는 삼킨다. 메모리 상태는 이미 옳고, 실패하면 다음 실행에 되돌아갈 뿐이다
  /// (사용자에게 유리한 방향 — 토큰이 되살아난다).
  Future<void> save(WalletData data) async {
    try {
      await _save(data);
    } on Object {
      // 무시
    }
  }

  Future<void> _save(WalletData data) async {
    final prefs = await SharedPreferences.getInstance();
    final trimmed = data.deliveredPurchaseIds.length > maxDeliveredIds
        ? data.copyWith(
            deliveredPurchaseIds: data.deliveredPurchaseIds
                .sublist(data.deliveredPurchaseIds.length - maxDeliveredIds))
        : data;
    await prefs.setString(_key, jsonEncode(trimmed.toJson()));
  }
}
