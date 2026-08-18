import 'package:flutter/material.dart';

import '../domain/card.dart';
import '../domain/hand.dart';
import '../l10n/app_localizations.dart';
import 'hand_text.dart';
import 'theme.dart';
import 'widgets/card_face.dart';

/// 규칙 전문. 게임 안에서 언제든 다시 볼 수 있어야 한다.
///
/// **`docs/RULES.md`의 요약이 아니라 플레이에 필요한 전부다.** 이 게임은 규칙이 특이해서
/// (58장 덱, "1"과 A가 별개, 빼앗기, 쉴드) 설명 없이 첫 판을 두면 무슨 일이 일어나는지
/// 모른다 — 특히 카드 게임 관습이 다른 나라 사용자에게 그렇다.
class RulesScreen extends StatelessWidget {
  const RulesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.rulesTitle)),
      body: Align(
        alignment: Alignment.topCenter,
        child: SingleChildScrollView(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 36),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _Section(
                    icon: Icons.flag_rounded,
                    title: l10n.rulesGoalTitle,
                    body: l10n.rulesGoalBody,
                  ),
                  _Section(
                    icon: Icons.style_rounded,
                    title: l10n.rulesDeckTitle,
                    body: l10n.rulesDeckBody,
                    note: l10n.rulesDeckNote,
                    extra: const _DeckSample(),
                  ),
                  _Section(
                    icon: Icons.play_circle_outline_rounded,
                    title: l10n.rulesSetupTitle,
                    body: l10n.rulesSetupBody,
                  ),
                  _Section(
                    icon: Icons.refresh_rounded,
                    title: l10n.rulesTurnTitle,
                    body: l10n.rulesTurnBody,
                  ),
                  _Section(
                    icon: Icons.bolt_rounded,
                    title: l10n.rulesAttackTitle,
                    body: l10n.rulesAttackBody,
                    note: l10n.rulesAttackBonus,
                  ),
                  _Section(
                    icon: Icons.shield_rounded,
                    title: l10n.rulesShieldTitle,
                    body: l10n.rulesShieldBody,
                    accent: AppColors.gold,
                  ),
                  _Section(
                    icon: Icons.auto_awesome_rounded,
                    title: l10n.rulesJokerTitle,
                    body: l10n.rulesJokerBody,
                    accent: AppColors.purple,
                  ),
                  _Section(
                    icon: Icons.leaderboard_rounded,
                    title: l10n.rulesHandsTitle,
                    body: l10n.rulesHandsNote,
                    extra: const _HandRankTable(),
                  ),
                  _Section(
                    icon: Icons.calculate_rounded,
                    title: l10n.rulesScoreTitle,
                    body: l10n.rulesScoreBody,
                  ),
                  _Section(
                    icon: Icons.done_all_rounded,
                    title: l10n.rulesEndTitle,
                    body: l10n.rulesEndBody,
                  ),
                  _Section(
                    icon: Icons.local_fire_department_rounded,
                    title: l10n.rulesTokenTitle,
                    body: l10n.rulesTokenBody,
                    accent: AppColors.red,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.icon,
    required this.title,
    required this.body,
    this.note,
    this.extra,
    this.accent,
  });

  final IconData icon;
  final String title;
  final String body;

  /// 본문보다 한 단계 강조되는 보충 설명(헷갈리기 쉬운 지점).
  final String? note;
  final Widget? extra;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final color = accent ?? AppColors.textMain;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppShapes.radius),
          border: Border.all(color: AppColors.stroke),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: color),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(title,
                      style: TextStyle(
                          color: color, fontWeight: FontWeight.w800, fontSize: 15)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(body,
                style: const TextStyle(
                    color: AppColors.inkSoft, fontSize: 13, height: 1.55)),
            if (note != null) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                decoration: BoxDecoration(
                  color: AppColors.panel,
                  borderRadius: BorderRadius.circular(10),
                  border: Border(left: BorderSide(color: color, width: 2.5)),
                ),
                child: Text(note!,
                    style: const TextStyle(
                        color: AppColors.textMain, fontSize: 12.5, height: 1.5)),
              ),
            ],
            if (extra != null) ...[const SizedBox(height: 12), extra!],
          ],
        ),
      ),
    );
  }
}

/// "1"과 A가 다른 카드라는 걸 글로만 읽으면 잘 안 들어온다 — 나란히 보여준다.
class _DeckSample extends StatelessWidget {
  const _DeckSample();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        alignment: WrapAlignment.center,
        children: [
          CardFace(card: PlayingCard(1, Suit.spades), size: 46),
          CardFace(card: PlayingCard(10, Suit.hearts), size: 46),
          CardFace(card: PlayingCard(11, Suit.diamonds), size: 46),
          CardFace(card: PlayingCard(14, Suit.clubs), size: 46),
          CardFace(card: PlayingCard(7, Suit.spades, isShield: true), size: 46),
          CardFace(card: PlayingCard(12, Suit.hearts, isJoker: true), size: 46),
        ],
      ),
    );
  }
}

/// 족보 10종을 강한 순서대로. 이름은 게임 화면과 같은 헬퍼를 쓴다.
class _HandRankTable extends StatelessWidget {
  const _HandRankTable();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // HandCategory는 약한 것부터 정의돼 있으므로 뒤집어서 강한 순으로 보여준다.
    final strongestFirst = HandCategory.values.reversed.toList();
    return Column(
      children: [
        for (var i = 0; i < strongestFirst.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 5),
            child: Row(
              children: [
                SizedBox(
                  width: 22,
                  child: Text('${i + 1}',
                      style: const TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w800)),
                ),
                Expanded(
                  child: Text(handCategoryName(l10n, strongestFirst[i]),
                      style: TextStyle(
                        color: i == 0 ? AppColors.gold : AppColors.textMain,
                        fontSize: 13,
                        fontWeight: i == 0 ? FontWeight.w800 : FontWeight.w600,
                      )),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
