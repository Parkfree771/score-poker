/// 인게임 토큰의 종류.
///
/// **판당 각 1개까지만 쓸 수 있다**(`GameRules`). 이 상한이 밸런스의 전부다 —
/// 돈을 더 써도 한 판에서 얻는 이득은 고정이라 "지르면 이긴다"가 성립하지 않는다.
enum TokenKind {
  /// 쉴드 선언: 내 필드의 카드 1장을 쉴드로 만든다. 조커로만 깨진다.
  shield,

  /// 표식 부여: 손패의 카드 1장에 공격 표식을 붙인다(덱에서 뽑은 카드로도 공격 가능).
  attack,
}

/// 토큰 개수 묶음. `{TokenKind: 개수}`를 다루는 코드가 여러 군데라 헬퍼를 모아둔다.
typedef TokenBundle = Map<TokenKind, int>;

extension TokenBundleOps on TokenBundle {
  int get total => values.fold(0, (a, b) => a + b);

  TokenBundle plus(TokenBundle other) {
    final out = {...this};
    for (final e in other.entries) {
      out[e.key] = (out[e.key] ?? 0) + e.value;
    }
    return out;
  }
}

/// 저장용 키(문자열). enum 이름이 바뀌어도 저장 포맷은 안 깨지도록 고정한다.
String tokenKey(TokenKind k) => switch (k) {
      TokenKind.shield => 'shield',
      TokenKind.attack => 'attack',
    };

TokenKind? tokenKindFromKey(String key) => switch (key) {
      'shield' => TokenKind.shield,
      'attack' => TokenKind.attack,
      _ => null,
    };
