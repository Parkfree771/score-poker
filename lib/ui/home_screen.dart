import 'package:flutter/material.dart';

import '../data/records_store.dart';
import '../domain/records.dart';
import '../l10n/app_localizations.dart';
import 'persona_select_screen.dart';
import 'ranking_screen.dart';
import 'theme.dart';

/// 메인 메뉴: 모드 선택(온라인 대전 / 싱글 플레이).
/// 랭킹은 오른쪽 위 모서리의 티어 배지로 진입한다.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, this.rankingPreloaded});

  /// 테스트/스크린샷 전용: 모서리 랭킹 배지에 표시할 데이터(저장소를 읽지 않음).
  final RankingData? rankingPreloaded;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.appTitle),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Center(child: _RankingBadge(preloaded: rankingPreloaded)),
          ),
        ],
      ),
      // 작은 가로 화면에서도 넘치지 않도록 스크롤 허용.
      body: Center(
        child: SingleChildScrollView(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    l10n.tagline,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 28),
                  _ModeCard(
                    icon: Icons.public,
                    title: l10n.modePvpTitle,
                    description: l10n.modePvpDesc,
                    onTap: () => _notReady(context, l10n),
                  ),
                  const SizedBox(height: 14),
                  _ModeCard(
                    icon: Icons.smart_toy,
                    title: l10n.modeSingleTitle,
                    description: l10n.modeSingleDesc,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(builder: (_) => const PersonaSelectScreen()),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _notReady(BuildContext context, AppLocalizations l10n) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.comingSoon)),
    );
  }
}

/// 오른쪽 위 모서리 랭킹 배지: 티어 색 트로피 + RP. 탭하면 랭킹 페이지.
/// 기록이 없거나 아직 로드 전이면 트로피 아이콘만 보인다.
class _RankingBadge extends StatefulWidget {
  const _RankingBadge({this.preloaded});
  final RankingData? preloaded;

  @override
  State<_RankingBadge> createState() => _RankingBadgeState();
}

class _RankingBadgeState extends State<_RankingBadge> {
  RankingData? _data;

  @override
  void initState() {
    super.initState();
    if (widget.preloaded != null) {
      _data = widget.preloaded;
    } else {
      _load();
    }
  }

  Future<void> _load() async {
    try {
      final d = await RecordsStore.load();
      if (mounted) setState(() => _data = d);
    } on Object {
      // 저장소를 못 읽는 환경(테스트 등)에서는 아이콘만 표시.
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final data = _data;
    final hasRecord = data != null && data.games > 0;
    final tier = hasRecord ? tierStyle(l10n, data.tier) : null;
    final color = tier?.color ?? Theme.of(context).colorScheme.secondary;
    return Tooltip(
      message: l10n.menuRankingTitle,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const RankingScreen()),
          ),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: color, width: 1.3),
              color: AppColors.surface,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.emoji_events_rounded, size: 18, color: color),
                if (hasRecord) ...[
                  const SizedBox(width: 6),
                  Text('${data.rating}',
                      style: TextStyle(
                          color: color, fontWeight: FontWeight.w900, fontSize: 14)),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ModeCard extends StatelessWidget {
  const _ModeCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String description;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        leading: Icon(icon, size: 36),
        title: Text(title, style: Theme.of(context).textTheme.titleLarge),
        subtitle: Text(description),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}
