/// 카드 도메인 모델 (순수 Dart, Flutter 의존성 없음 → `dart test`로 검증 가능).
///
/// 덱 구성: 표준 포커 덱 — 랭크 2~10, J(11), Q(12), K(13), A(14) × 4 슈트 + 조커 2장.
/// - **공격 카드**: 게임 시작 시 받은 손패에만 [isAttacker] 표식이 붙는다. 상대 카드를
///   빼앗는 공격은 이 카드(또는 조커)로만 가능하다 → 공격 횟수가 자연히 제한된다.
/// - A(에이스)의 기본값은 14, 스트레이트에서만 1로도 사용(A-2-3-4-5).
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
  static const int min = 2; // 표준 덱 최저 랭크 (A-low 스트레이트에서만 A가 1로 계산됨)
  static const int jack = 11;
  static const int queen = 12;
  static const int king = 13;
  static const int ace = 14; // 기본값 14, 스트레이트에서만 1로도 사용
  static const int max = ace;

  /// 일반 덱에 들어가는 모든 랭크 (2..10, J, Q, K, A) — 13랭크.
  static const List<int> all = [2, 3, 4, 5, 6, 7, 8, 9, 10, jack, queen, king, ace];
}

/// 한 장의 카드.
///
/// 조커는 배치 시점에 [rank]/[suit]를 지정해 일반 카드처럼 다루되, [isJoker] 플래그로
/// "조커로만 제거 가능" 같은 게임 레벨 규칙을 구분한다. 점수/족보 계산에서는 일반 카드와 동일.
class PlayingCard {
  const PlayingCard(this.rank, this.suit,
      {this.isJoker = false, this.isShield = false, this.isAttacker = false})
      : assert(rank >= Ranks.min && rank <= Ranks.max);

  final int rank;
  final Suit suit;

  /// 조커 여부. 배치 시 rank/suit가 지정되며, "조커로만 제거 가능" 규칙에 사용.
  final bool isJoker;

  /// 쉴드 카드 여부(테두리). 배치되면 제거 불가(조커 제외). 점수는 일반 카드와 동일.
  final bool isShield;

  /// 공격 카드 여부. **처음 받은 손패에만** 붙는 표식으로, 이 카드로만 상대 필드를
  /// 공격(같은 숫자로 빼앗기)할 수 있다. 이후 덱에서 뽑은 카드는 배치 전용.
  /// (조커는 이 표식과 무관하게 언제나 공격 가능)
  final bool isAttacker;

  /// 점수 계산용 숫자값. (A = 14)
  int get value => rank;

  /// 지정되지 않은(손패의) 조커를 표현하는 임시 카드. 배치 시 [designate]로 확정한다.
  factory PlayingCard.undesignatedJoker() =>
      const PlayingCard(Ranks.ace, Suit.spades, isJoker: true);

  /// 이 카드가 지금 상대를 공격할 수 있는가? (공격 표식이 있거나 조커)
  bool get canAttack => (isAttacker || isJoker) && !isShield;

  /// 조커를 특정 rank/suit로 지정해 새 카드를 만든다.
  PlayingCard designate(int newRank, Suit newSuit) {
    assert(isJoker, '조커만 지정할 수 있습니다');
    return PlayingCard(newRank, newSuit, isJoker: true);
  }

  PlayingCard copyWith(
          {int? rank, Suit? suit, bool? isJoker, bool? isShield, bool? isAttacker}) =>
      PlayingCard(
        rank ?? this.rank,
        suit ?? this.suit,
        isJoker: isJoker ?? this.isJoker,
        isShield: isShield ?? this.isShield,
        isAttacker: isAttacker ?? this.isAttacker,
      );

  /// 이 카드를 쉴드 카드로 만든다(빼앗아 온 카드는 쉴드로 고정된다).
  PlayingCard asShield() => copyWith(isShield: true, isJoker: false, isAttacker: false);

  /// 처음 받은 손패 표식(공격 가능)을 붙인다.
  PlayingCard asAttacker() => copyWith(isAttacker: true);

  String get label {
    final r = switch (rank) {
      Ranks.jack => 'J',
      Ranks.queen => 'Q',
      Ranks.king => 'K',
      Ranks.ace => 'A',
      _ => '$rank',
    };
    final mark = isShield ? '□' : (isJoker ? '*' : (isAttacker ? '!' : ''));
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
      other.isShield == isShield &&
      other.isAttacker == isAttacker;

  @override
  int get hashCode => Object.hash(rank, suit, isJoker, isShield, isAttacker);
}
