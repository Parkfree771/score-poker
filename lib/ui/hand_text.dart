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
      HandCategory.fiveOfAKind => l10n.handFiveOfAKind,
    };
