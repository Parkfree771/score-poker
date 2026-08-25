/// 인게임 토큰의 종류.
///
/// 지금은 **부스트 한 종류뿐**이다. 부스트 1개 = 한 판을 부스트해서 시작한다:
/// 그 판에서 비공개권 칩이 3 → 4개가 되고, 손패 스왑(받은 카드 전부 교체) 1회가 생긴다.
/// 판마다 부스트는 **1개까지만** 쓸 수 있다(`ScoreGame.deal(boostFor:)`) — 100개를 사도
/// 한 판에서 얻는 이득은 1개 쓴 사람과 같다. 돈은 "이득을 쓸 수 있는 판의 수"만 늘린다.
enum TokenKind {
  /// 한 판 부스트(칩 +1, 스왑 1회).
  boost,
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
      TokenKind.boost => 'boost',
    };

/// 옛 저장값('shield'/'attack' — 폐기된 규칙의 토큰)은 null을 돌려줘 조용히 버린다.
TokenKind? tokenKindFromKey(String key) => switch (key) {
      'boost' => TokenKind.boost,
      _ => null,
    };
