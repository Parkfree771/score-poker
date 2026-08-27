import 'package:flutter/material.dart';

import '../data/records_store.dart';
import '../domain/records.dart';
import '../domain/scoring.dart';
import '../l10n/app_localizations.dart';
import 'theme.dart';
import 'widgets/level_stars.dart';

/// 랭킹 페이지: 랭킹 점수(RP)·티어 + 전적 + 최고 점수 TOP 10 + 최근 대국.
/// 세로 = 한 열 스크롤, 가로 = [요약 | 기록 리스트] 두 열.
class RankingScreen extends StatefulWidget {
  const RankingScreen({super.key, this.preloaded});

  /// 테스트/스크린샷 전용: 지정 시 저장소를 읽지 않는다.
  final RankingData? preloaded;

  @override
  State<RankingScreen> createState() => _RankingScreenState();
}

class _RankingScreenState extends State<RankingScreen> {
  RankingData? _data;

  /// 랭킹은 두 판이다 — 사람 vs 사람(온라인, 준비 중) / 사람 vs AI(이 기기의 기록).
  _RankTab _tab = _RankTab.ai;

  @override
  void initState() {
    super.initState();
    if (widget.preloaded != null) {
      _data = widget.preloaded;
    } else {
      RecordsStore.load().then((d) {
        if (mounted) setState(() => _data = d);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final data = _data;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.menuRankingTitle)),
      body: DecoratedBox(
        decoration: const BoxDecoration(gradient: AppColors.bgGradient),
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
                child: SegmentedButton<_RankTab>(
                  segments: [
                    ButtonSegment(
                        value: _RankTab.pvp,
                        icon: const Icon(Icons.people_alt_rounded, size: 16),
                        label: Text(l10n.rankTabPvp)),
                    ButtonSegment(
                        value: _RankTab.ai,
                        icon: const Icon(Icons.smart_toy, size: 16),
                        label: Text(l10n.rankTabAi)),
                  ],
                  selected: {_tab},
                  onSelectionChanged: (v) => setState(() => _tab = v.first),
                  style: SegmentedButton.styleFrom(
                    foregroundColor: AppColors.textMuted,
                    selectedForegroundColor: AppColors.ink,
                    selectedBackgroundColor: AppColors.gold,
                    side: const BorderSide(color: AppColors.stroke),
                  ),
                ),
              ),
              Expanded(
                child: _tab == _RankTab.pvp
                    ? _PvpComingSoon(l10n: l10n)
                    : data == null
                        ? const Center(child: CircularProgressIndicator())
                        : data.games == 0
                            ? _EmptyState(l10n: l10n)
                            : LayoutBuilder(
                                builder: (context, cons) => cons.maxWidth > cons.maxHeight
                                    ? _landscape(l10n, data)
                                    : _portrait(l10n, data),
                              ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _portrait(AppLocalizations l10n, RankingData data) => ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          _RatingCard(l10n: l10n, data: data),
          const SizedBox(height: 12),
          _StatsRow(l10n: l10n, data: data),
          const SizedBox(height: 20),
          _SectionTitle(l10n.bestScoresTitle),
          _BestScoresPanel(l10n: l10n, data: data),
          const SizedBox(height: 20),
          _SectionTitle(l10n.recentGamesTitle),
          _RecentGamesPanel(l10n: l10n, data: data),
        ],
      );

  Widget _landscape(AppLocalizations l10n, RankingData data) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 330,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 8, 16),
              children: [
                _RatingCard(l10n: l10n, data: data),
                const SizedBox(height: 12),
                _StatsRow(l10n: l10n, data: data),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(8, 8, 16, 16),
              children: [
                _SectionTitle(l10n.bestScoresTitle),
                _BestScoresPanel(l10n: l10n, data: data),
                const SizedBox(height: 20),
                _SectionTitle(l10n.recentGamesTitle),
                _RecentGamesPanel(l10n: l10n, data: data),
              ],
            ),
          ),
        ],
      );
}

// ---- 티어 표시 ----

/// 미도달 티어 사다리 칸(불투명 단색 — 희미한 반투명 금지).
const _ladderOff = AppColors.gaugeOff;

({String name, Color color}) tierStyle(AppLocalizations l10n, RankTier t) =>
    switch (t) {
      RankTier.iron => (name: l10n.tierIron, color: const Color(0xFF9BA0AB)),
      RankTier.bronze => (name: l10n.tierBronze, color: const Color(0xFFC08552)),
      RankTier.silver => (name: l10n.tierSilver, color: const Color(0xFFC7CEDC)),
      RankTier.gold => (name: l10n.tierGold, color: AppColors.gold),
      RankTier.platinum => (name: l10n.tierPlatinum, color: const Color(0xFF6FD8CC)),
      RankTier.diamond => (name: l10n.tierDiamond, color: const Color(0xFF6FB4F5)),
    };

enum _RankTab { pvp, ai }

/// 사람 vs 사람 랭킹 — 온라인 대전이 열리기 전까지의 자리표시.
class _PvpComingSoon extends StatelessWidget {
  const _PvpComingSoon({required this.l10n});
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.people_alt_rounded, size: 48, color: AppColors.textMuted),
              const SizedBox(height: 14),
              Text(l10n.rankPvpSoonTitle,
                  style: const TextStyle(
                      color: AppColors.textMain, fontSize: 17, fontWeight: FontWeight.w900)),
              const SizedBox(height: 6),
              Text(l10n.rankPvpSoonDesc,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.textMuted, fontSize: 13, height: 1.4)),
            ],
          ),
        ),
      );
}

class _RatingCard extends StatelessWidget {
  const _RatingCard({required this.l10n, required this.data});
  final AppLocalizations l10n;
  final RankingData data;

  @override
  Widget build(BuildContext context) {
    final tier = tierStyle(l10n, data.tier);
    final next = RankingData.nextTierAt(data.tier);
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppShapes.radius),
        border: Border.all(color: tier.color, width: 1.4),
        boxShadow: AppShapes.panelShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.emoji_events_rounded, color: tier.color, size: 30),
              const SizedBox(width: 10),
              Text(tier.name,
                  style: TextStyle(
                      color: tier.color, fontWeight: FontWeight.w900, fontSize: 20, letterSpacing: 1)),
              const Spacer(),
              Text('${data.rating}',
                  style: const TextStyle(
                      color: AppColors.textMain, fontWeight: FontWeight.w900, fontSize: 30)),
              const SizedBox(width: 5),
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text('RP',
                    style: TextStyle(
                        color: AppColors.textMuted, fontWeight: FontWeight.w800, fontSize: 12)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // 상위 % — 티어색 단색 칩(가장 직관적인 한 줄).
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              color: tier.color,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(l10n.topPercent(data.topPercent),
                style: const TextStyle(
                    color: AppColors.ink, fontWeight: FontWeight.w900, fontSize: 14)),
          ),
          const SizedBox(height: 12),
          // 다음 판 상대 레벨 — "이기면 더 센 상대"가 여기서 읽힌다.
          Row(
            children: [
              Text(l10n.nextOpponentLevel,
                  style: const TextStyle(
                      color: AppColors.textMuted, fontSize: 12, fontWeight: FontWeight.w800)),
              const SizedBox(width: 8),
              LevelStars(level: data.opponentLevel, size: 18, gap: 1),
              const SizedBox(width: 6),
              Text(l10n.opponentLevel(data.opponentLevel),
                  style: const TextStyle(
                      color: AppColors.goldSoft, fontSize: 12, fontWeight: FontWeight.w800)),
            ],
          ),
          const SizedBox(height: 14),
          _TierLadder(l10n: l10n, current: data.tier),
          if (next != null) ...[
            const SizedBox(height: 12),
            Text(
              l10n.toNextTier(next - data.rating,
                  tierStyle(l10n, RankTier.values[data.tier.index + 1]).name),
              style: const TextStyle(
                  color: AppColors.textMuted, fontSize: 12, fontWeight: FontWeight.w700),
            ),
          ],
        ],
      ),
    );
  }
}

/// 아이언 → 다이아 6단계 사다리. 도달한 칸은 각 티어의 단색, 현재 칸은 강조.
class _TierLadder extends StatelessWidget {
  const _TierLadder({required this.l10n, required this.current});
  final AppLocalizations l10n;
  final RankTier current;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final t in RankTier.values) ...[
          Expanded(
            child: Column(
              children: [
                Container(
                  height: t == current ? 12 : 8,
                  decoration: BoxDecoration(
                    color: t.index <= current.index ? tierStyle(l10n, t).color : _ladderOff,
                    borderRadius: BorderRadius.circular(4),
                    border: t == current
                        ? Border.all(color: Colors.white, width: 1.2)
                        : null,
                  ),
                ),
                const SizedBox(height: 5),
                Text(tierStyle(l10n, t).name,
                    maxLines: 1,
                    overflow: TextOverflow.visible,
                    style: TextStyle(
                      color: t.index <= current.index
                          ? tierStyle(l10n, t).color
                          : AppColors.textMuted,
                      fontWeight: t == current ? FontWeight.w900 : FontWeight.w600,
                      fontSize: 9.5,
                    )),
              ],
            ),
          ),
          if (t != RankTier.diamond) const SizedBox(width: 4),
        ],
      ],
    );
  }
}

class _StatsRow extends StatelessWidget {
  const _StatsRow({required this.l10n, required this.data});
  final AppLocalizations l10n;
  final RankingData data;

  @override
  Widget build(BuildContext context) {
    Widget tile(String label, String value, {Color? color}) => Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.stroke),
            ),
            child: Column(
              children: [
                Text(value,
                    style: TextStyle(
                        color: color ?? AppColors.textMain,
                        fontWeight: FontWeight.w900,
                        fontSize: 18)),
                const SizedBox(height: 2),
                Text(label,
                    style: const TextStyle(
                        color: AppColors.textMuted, fontSize: 11, fontWeight: FontWeight.w700)),
              ],
            ),
          ),
        );
    return Row(
      children: [
        tile(l10n.gamesPlayed, '${data.games}'),
        const SizedBox(width: 8),
        tile(l10n.statWins, '${data.wins}', color: AppColors.win),
        const SizedBox(width: 8),
        tile(l10n.statLosses, '${data.losses}', color: AppColors.lose),
        const SizedBox(width: 8),
        tile(l10n.statDraws, '${data.draws}', color: AppColors.tie),
        const SizedBox(width: 8),
        tile(l10n.winRate, '${data.winRatePercent}%', color: AppColors.gold),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 8),
        child: Text(text,
            style: const TextStyle(
                color: AppColors.textMain,
                fontWeight: FontWeight.w800,
                fontSize: 15,
                letterSpacing: 0.5)),
      );
}

Widget _panel(List<Widget> children) => Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppShapes.radius),
        border: Border.all(color: AppColors.stroke),
      ),
      child: Column(children: children),
    );

String _dateLabel(DateTime d) =>
    '${d.year}.${d.month.toString().padLeft(2, '0')}.${d.day.toString().padLeft(2, '0')}';

class _OutcomeChip extends StatelessWidget {
  const _OutcomeChip({required this.l10n, required this.outcome});
  final AppLocalizations l10n;
  final MatchOutcome outcome;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (outcome) {
      MatchOutcome.win => (l10n.statWins, AppColors.win),
      MatchOutcome.lose => (l10n.statLosses, AppColors.lose),
      MatchOutcome.draw => (l10n.statDraws, AppColors.tie),
    };
    // 단색 칩(반투명 배경 금지) — 결과가 한눈에 읽히게.
    return Container(
      width: 30,
      padding: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(label,
          textAlign: TextAlign.center,
          style: const TextStyle(
              color: AppColors.ink, fontWeight: FontWeight.w900, fontSize: 12)),
    );
  }
}

class _BestScoresPanel extends StatelessWidget {
  const _BestScoresPanel({required this.l10n, required this.data});
  final AppLocalizations l10n;
  final RankingData data;

  @override
  Widget build(BuildContext context) {
    final best = data.bestScores();
    return _panel([
      for (var i = 0; i < best.length; i++)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: i == 0
              ? null
              : const BoxDecoration(
                  border: Border(top: BorderSide(color: AppColors.stroke))),
          child: Row(
            children: [
              SizedBox(
                width: 28,
                child: Text('${i + 1}',
                    style: TextStyle(
                        color: i < 3 ? AppColors.gold : AppColors.textMuted,
                        fontWeight: FontWeight.w900,
                        fontSize: i < 3 ? 16 : 14)),
              ),
              Text(l10n.scorePoints(best[i].myScore),
                  style: const TextStyle(
                      color: AppColors.textMain, fontWeight: FontWeight.w800, fontSize: 15)),
              const Spacer(),
              _OutcomeChip(l10n: l10n, outcome: best[i].outcome),
              const SizedBox(width: 12),
              Text(_dateLabel(best[i].playedAt),
                  style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
            ],
          ),
        ),
    ]);
  }
}

class _RecentGamesPanel extends StatelessWidget {
  const _RecentGamesPanel({required this.l10n, required this.data});
  final AppLocalizations l10n;
  final RankingData data;

  @override
  Widget build(BuildContext context) {
    final recent = data.records.take(15).toList();
    return _panel([
      for (var i = 0; i < recent.length; i++)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: i == 0
              ? null
              : const BoxDecoration(
                  border: Border(top: BorderSide(color: AppColors.stroke))),
          child: Row(
            children: [
              _OutcomeChip(l10n: l10n, outcome: recent[i].outcome),
              const SizedBox(width: 14),
              Text('${recent[i].myScore}',
                  style: const TextStyle(
                      color: AppColors.mePrimary, fontWeight: FontWeight.w900, fontSize: 15)),
              const Text(' : ',
                  style: TextStyle(color: AppColors.textMuted, fontWeight: FontWeight.w700)),
              Text('${recent[i].oppScore}',
                  style: const TextStyle(
                      color: AppColors.oppPrimary, fontWeight: FontWeight.w900, fontSize: 15)),
              const Spacer(),
              Text(_dateLabel(recent[i].playedAt),
                  style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
            ],
          ),
        ),
    ]);
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.l10n});
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.emoji_events_outlined,
                size: 56, color: AppColors.textMuted.withValues(alpha: 0.7)),
            const SizedBox(height: 16),
            Text(l10n.noRecordsTitle,
                style: const TextStyle(
                    color: AppColors.textMain, fontWeight: FontWeight.w800, fontSize: 17)),
            const SizedBox(height: 8),
            Text(l10n.noRecordsDesc,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.textMuted, fontSize: 13, height: 1.5)),
          ],
        ),
      ),
    );
  }
}
