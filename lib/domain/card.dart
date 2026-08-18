/// 카드 도메인 모델 (순수 Dart, Flutter 의존성 없음 → `dart test`로 검증 가능).
///
/// 덱 구성: 랭크 1~10, J(11), Q(12), K(13), A(14) × 4 슈트 + 조커 2장.
/// - 숫자 "1" 카드와 A(에이스)는 별개. A의 기본값은 14, 스트레이트에서 0으로도 사용.
/// - 조커는 배치 시 원하는 숫자(rank)와 슈트를 지정하므로, 지정 후에는 일반 카드처럼 점수 계산됨.
library;

/// 슈트. 동점 비교용 순위: ♠ > ♥ > ♦ > ♣.
enum Suit { spades, hearts, diamonds, clubs }

extension SuitX on Suit {
  /// 높을수록 강함 (선공 오픈 동점 등 타이브레이크용).
  int get order => switch (this) {
        Suit.spades => 4,
        Suit.hearts => 3,
        Suit.diamonds => 2,
        Suit.clubs => 1,
      };

  String get symbol => switch (this) {
        Suit.spades => '♠',
        Suit.hearts => '♥',
        Suit.diamonds => '♦',
        Suit.clubs => '♣',
      };
}

/// 랭크 상수. (랭크 == 점수값. A=14가 기본값)
class Ranks {
  Ranks._();
  static const int min = 1; // "1" 카드
  static const int jack = 11;
  static const int queen = 12;
  static const int king = 13;
  static const int ace = 14; // 기본값 14, 스트레이트에서 0으로도 사용
  static const int max = ace;

  /// 일반 덱에 들어가는 모든 랭크 (1..10, J, Q, K, A).
  static const List<int> all = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, jack, queen, king, ace];
}

/// 한 장의 카드.
///
/// 조커는 배치 시점에 [rank]/[suit]를 지정해 일반 카드처럼 다루되, [isJoker] 플래그로
/// "조커로만 제거 가능" 같은 게임 레벨 규칙을 구분한다. 점수/족보 계산에서는 일반 카드와 동일.
class PlayingCard {
  const PlayingCard(this.rank, this.suit, {this.isJoker = false, this.isShield = false})
      : assert(rank >= Ranks.min && rank <= Ranks.max);

  final int rank;
  final Suit suit;

  /// 조커 여부. 배치 시 rank/suit가 지정되며, "조커로만 제거 가능" 규칙에 사용.
  final bool isJoker;

  /// 쉴드 카드 여부(테두리). 배치되면 제거 불가(조커 제외). 점수는 일반 카드와 동일.
  final bool isShield;

  /// 점수 계산용 숫자값. (A = 14)
  int get value => rank;

  /// 지정되지 않은(손패의) 조커를 표현하는 임시 카드. 배치 시 [designate]로 확정한다.
  factory PlayingCard.undesignatedJoker() =>
      const PlayingCard(Ranks.ace, Suit.spades, isJoker: true);

  /// 조커를 특정 rank/suit로 지정해 새 카드를 만든다.
  PlayingCard designate(int newRank, Suit newSuit) {
    assert(isJoker, '조커만 지정할 수 있습니다');
    return PlayingCard(newRank, newSuit, isJoker: true);
  }

  PlayingCard copyWith({int? rank, Suit? suit, bool? isJoker, bool? isShield}) =>
      PlayingCard(
        rank ?? this.rank,
        suit ?? this.suit,
        isJoker: isJoker ?? this.isJoker,
        isShield: isShield ?? this.isShield,
      );

  /// 이 카드를 쉴드 카드로 만든다(제거 보상으로 받은 카드 등).
  PlayingCard asShield() => copyWith(isShield: true, isJoker: false);

  String get label {
    final r = switch (rank) {
      Ranks.jack => 'J',
      Ranks.queen => 'Q',
      Ranks.king => 'K',
      Ranks.ace => 'A',
      _ => '$rank',
    };
    final mark = isShield ? '□' : (isJoker ? '*' : '');
    return '${suit.symbol}$r$mark';
  }

  @override
  String toString() => label;

  @override
  bool operator ==(Object other) =>
      other is PlayingCard &&
      other.rank == rank &&
      other.suit == suit &&
      other.isJoker == isJoker &&
      other.isShield == isShield;

  @override
  int get hashCode => Object.hash(rank, suit, isJoker, isShield);
}
