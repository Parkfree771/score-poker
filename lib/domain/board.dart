import 'card.dart';

/// 판(보드)의 공용 정의 — 규칙 엔진과 UI 위젯이 같이 쓴다.
///
/// 판은 스코어 포커의 정체성이다: **양쪽 3줄 × 5칸**, 같은 번호 줄끼리 대결.
enum PlayerId { p0, p1 }

extension PlayerIdX on PlayerId {
  PlayerId get other => this == PlayerId.p0 ? PlayerId.p1 : PlayerId.p0;
}

const int kRows = 3;
const int kCols = 5;

/// 보드 한 칸에 그려질 카드 + 주인. 보드 위젯은 규칙 엔진을 모른다 —
/// 엔진이 자기 칸을 이 형태로 변환해서 넘긴다.
class PlacedCard {
  const PlacedCard(this.card, this.owner);
  final PlayingCard card;
  final PlayerId owner;
}
