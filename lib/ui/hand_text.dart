import '../domain/hand.dart';
import '../l10n/app_localizations.dart';

/// 족보 이름을 현재 로케일로 옮긴다.
///
/// 도메인은 사용자 문구를 갖지 않는다([moveErrorText]와 같은 규칙).
/// 게임 화면과 규칙 화면이 함께 쓴다 — 두 곳에 같은 switch를 두면 하나만 고치게 된다.
String handCategoryName(AppLocalizations l10n, HandCategory c) => switch (c) {
      HandCategory.highCard => l10n.handHighCard,
      HandCategory.onePair => l10n.handOnePair,
      HandCategory.twoPair => l10n.handTwoPair,
      HandCategory.threeOfAKind => l10n.handThreeOfAKind,
      HandCategory.straight => l10n.handStraight,
      HandCategory.flush => l10n.handFlush,
      HandCategory.fullHouse => l10n.handFullHouse,
      HandCategory.fourOfAKind => l10n.handFourOfAKind,
      HandCategory.straightFlush => l10n.handStraightFlush,
    };

/// 보드 점수 알약에 넣을 **짧은 족보 이름**. 하이카드는 이름이 없다(숫자만 보여준다) —
/// 알약은 좁고, "하이카드"는 알려주는 것이 없다.
String? handCategoryShort(AppLocalizations l10n, HandCategory c) => switch (c) {
      HandCategory.highCard => null,
      HandCategory.onePair => l10n.handShortOnePair,
      HandCategory.twoPair => l10n.handShortTwoPair,
      HandCategory.threeOfAKind => l10n.handShortThreeOfAKind,
      HandCategory.straight => l10n.handShortStraight,
      HandCategory.flush => l10n.handShortFlush,
      HandCategory.fullHouse => l10n.handShortFullHouse,
      HandCategory.fourOfAKind => l10n.handShortFourOfAKind,
      HandCategory.straightFlush => l10n.handShortStraightFlush,
    };
