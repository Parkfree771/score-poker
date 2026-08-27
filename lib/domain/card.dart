/// 카드 도메인 모델 (순수 Dart, Flutter 의존성 없음 → `dart test`로 검증 가능).
///
/// 덱 구성: 표준 포커 덱 52장 — 랭크 2~10, J(11), Q(12), K(13), A(14) × 4 슈트 —
/// 에 **조커 2장**([PlayingCard.joker]). 조커는 손에서만 존재하고, 판에 놓이는 순간
/// 주인이 정한 랭크·무늬의 카드가 된다(내 판이면 와일드, 상대 판이면 그 카드를 **바꿔치기**).
/// A(에이스)의 기본값은 14, 스트레이트에서만 1로도 사용(A-2-3-4-5).
library;

/// 슈트. 동점 비교용 순위: ♠ > ♥ > ♦ > ♣.
enum Suit { spades, hearts, diamonds, clubs }

extension SuitX on Suit {
  /// 높을수록 강함 (동점 타이브레이크용).
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
  static const int min = 2; // 표준 덱 최저 랭크 (A-low 스트레이트에서만 A가 1로 계산됨)
  static const int jack = 11;
  static const int queen = 12;
  static const int king = 13;
  static const int ace = 14; // 기본값 14, 스트레이트에서만 1로도 사용
  static const int max = ace;

  /// 덱에 들어가는 모든 랭크 (2..10, J, Q, K, A) — 13랭크.
  static const List<int> all = [2, 3, 4, 5, 6, 7, 8, 9, 10, jack, queen, king, ace];
}

/// 한 장의 카드. 값 객체 — 같은 랭크·슈트면 같은 카드다.
class PlayingCard {
  const PlayingCard(this.rank, this.suit)
      : assert(rank == jokerRank || (rank >= Ranks.min && rank <= Ranks.max));

  /// 조커. 랭크 0 — 족보 계산에 들어가면 안 된다(판에 놓일 때 실제 카드로 바뀐다).
  const PlayingCard.joker() : this(jokerRank, Suit.spades);

  static const int jokerRank = 0;

  final int rank;
  final Suit suit;

  bool get isJoker => rank == jokerRank;

  /// 점수 계산용 숫자값. (A = 14)
  int get value => rank;

  PlayingCard copyWith({int? rank, Suit? suit}) =>
      PlayingCard(rank ?? this.rank, suit ?? this.suit);

  String get label {
    if (isJoker) return 'JOKER';
    final r = switch (rank) {
      Ranks.jack => 'J',
      Ranks.queen => 'Q',
      Ranks.king => 'K',
      Ranks.ace => 'A',
      _ => '$rank',
    };
    return '${suit.symbol}$r';
  }

  @override
  String toString() => label;

  @override
  bool operator ==(Object other) =>
      other is PlayingCard && other.rank == rank && other.suit == suit;

  @override
  int get hashCode => Object.hash(rank, suit);
}
