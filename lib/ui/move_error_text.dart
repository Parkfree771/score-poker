import '../domain/game.dart';
import '../l10n/app_localizations.dart';

/// 규칙 위반([MoveError])을 현재 로케일의 문장으로 옮긴다.
///
/// 도메인 레이어는 사용자 문구를 갖지 않는다 — 예전에는 엔진이 한국어 문자열을
/// 그대로 던지고 UI가 그걸 스낵바에 띄워서, 영어 빌드에서 한국어가 보였다.
String moveErrorText(AppLocalizations l10n, MoveError e) => switch (e) {
      MoveError.notPlaying => l10n.errNotPlaying,
      MoveError.playerFolded => l10n.errPlayerFolded,
      MoveError.alreadyRevealed => l10n.errAlreadyRevealed,
      MoveError.badHandIndex => l10n.errBadHandIndex,
      MoveError.badCell => l10n.errBadCell,
      MoveError.cellOccupied => l10n.errCellOccupied,
      MoveError.jokerOwnFieldOnly => l10n.errJokerOwnFieldOnly,
      MoveError.jokerNeedsDesignation => l10n.errJokerNeedsDesignation,
      MoveError.normalOwnFieldOnly => l10n.errNormalOwnFieldOnly,
      MoveError.attackOncePerTurn => l10n.errAttackOncePerTurn,
      MoveError.shieldCannotAttack => l10n.errShieldCannotAttack,
      MoveError.attackerCardRequired => l10n.errAttackerCardRequired,
      MoveError.noTargetCard => l10n.errNoTargetCard,
      MoveError.needJokerToTakeShield => l10n.errNeedJokerToTakeShield,
      MoveError.rankMismatch => l10n.errRankMismatch,
      MoveError.needEmptyCellForSteal => l10n.errNeedEmptyCellForSteal,
      MoveError.notBonusTurn => l10n.errNotBonusTurn,
      MoveError.tokenExhausted => l10n.errTokenExhausted,
      MoveError.tokenNoCardHere => l10n.errTokenNoCardHere,
      MoveError.shieldTargetNotEligible => l10n.errShieldTargetNotEligible,
      MoveError.attackMarkNotEligible => l10n.errAttackMarkNotEligible,
    };
