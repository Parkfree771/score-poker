import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

import '../data/app_settings.dart';
import '../data/records_store.dart';
import '../domain/records.dart';
import '../l10n/app_localizations.dart';
import 'fx_lab.dart';
import 'game_screen.dart';
import 'how_to_play_screen.dart';
import 'match_screen.dart';
import 'ranking_screen.dart';
import 'settings_screen.dart';
import 'shop_screen.dart';
import 'theme.dart';

/// 메인 메뉴: 모드 선택(사람 vs AI / 사람 vs 사람).
/// 랭킹은 오른쪽 위 모서리의 티어 배지로 진입한다.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, this.rankingPreloaded});

  /// 테스트/스크린샷 전용: 모서리 랭킹 배지에 표시할 데이터(저장소를 읽지 않음).
  final RankingData? rankingPreloaded;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _tutorialChecked = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _maybeShowTutorial();
  }

  /// 첫 실행이면 튜토리얼을 한 번 띄운다.
  ///
  /// 설정 스코프가 없는 환경(위젯 테스트·스크린샷)에서는 아무것도 하지 않는다 —
  /// 기존 골든이 튜토리얼에 가려지면 안 된다.
  void _maybeShowTutorial() {
    if (_tutorialChecked) return;
    final settings = AppSettingsScope.maybeOf(context);
    if (settings == null || settings.isLoading) return; // 로드 후 다시 불린다
    _tutorialChecked = true;
    if (settings.seenHowToPlay) return;

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await settings.markHowToPlaySeen();
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const HowToPlayScreen()),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        // 디버그 빌드: 제목을 길게 누르면 연출 실험실(강타·칩 튕김을 버튼으로).
        title: GestureDetector(
          onLongPress: kDebugMode
              ? () => Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) => GameScreen(initialGame: fxLabState(), fxLab: true)))
              : null,
          child: Text(l10n.appTitle),
        ),
        actions: [
          IconButton(
            tooltip: l10n.settingsTitle,
            icon: const Icon(Icons.settings_rounded),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const SettingsScreen()),
            ),
          ),
          IconButton(
            tooltip: l10n.shopTitle,
            icon: const Icon(Icons.storefront_rounded),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const ShopScreen()),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Center(child: _RankingBadge(preloaded: widget.rankingPreloaded)),
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
                  // 지금 할 수 있는 것이 첫 번째. 온라인은 출시 전이라 '준비 중'을 붙인다.
                  _ModeCard(
                    asset: 'assets/lottie/mode_ai.json',
                    glow: const Color(0xFF2F9EA8),
                    title: l10n.modeSingleTitle,
                    description: l10n.modeSingleDesc,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(builder: (_) => const MatchScreen()),
                    ),
                  ),
                  const SizedBox(height: 14),
                  _ModeCard(
                    asset: 'assets/lottie/mode_human.json',
                    glow: AppColors.gold,
                    title: l10n.modePvpTitle,
                    description: l10n.modePvpDesc,
                    badge: l10n.comingSoon,
                    onTap: () => _notReady(context, l10n),
                  ),
                  const SizedBox(height: 10),
                  // 규칙이 특이한 게임이라 "어떻게 하는 건데?"가 첫 화면에서 보여야 한다.
                  TextButton.icon(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(builder: (_) => const HowToPlayScreen()),
                    ),
                    icon: const Icon(Icons.help_outline_rounded,
                        size: 18, color: AppColors.textMuted),
                    label: Text(l10n.howToPlayTitle,
                        style: const TextStyle(
                            color: AppColors.textMuted, fontWeight: FontWeight.w700)),
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
    required this.asset,
    required this.glow,
    required this.title,
    required this.description,
    required this.onTap,
    this.badge,
  });

  /// 모드 로티(wired-lineal 재채색 — AI는 스페이드 카드, 사람은 하트 칩).
  final String asset;

  /// 아이콘 뒤 은은한 원 배경색.
  final Color glow;
  final String title;
  final String description;
  final VoidCallback onTap;

  /// 제목 옆 작은 라벨('준비 중'). 있으면 카드가 살짝 가라앉는다.
  final String? badge;

  @override
  Widget build(BuildContext context) {
    final muted = badge != null;
    return Opacity(
      opacity: muted ? 0.72 : 1,
      child: Card(
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          leading: Container(
            width: 68,
            height: 68,
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Color.alphaBlend(glow.withValues(alpha: 0.18), AppColors.panel),
              border: Border.all(color: glow.withValues(alpha: 0.55), width: 1.2),
            ),
            // RepaintBoundary: 로티는 초당 수십 번 다시 칠해진다 — 홈 전체로 번지면 안 된다.
            child: RepaintBoundary(
              child: Lottie.asset(asset,
                  repeat: true, fit: BoxFit.contain, frameRate: const FrameRate(30)),
            ),
          ),
          title: Row(
            children: [
              Flexible(
                child: Text(title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleLarge),
              ),
              if (badge != null) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: AppColors.gold, width: 1.2),
                  ),
                  child: Text(badge!,
                      style: const TextStyle(
                          color: AppColors.gold, fontSize: 11, fontWeight: FontWeight.w800)),
                ),
              ],
            ],
          ),
          subtitle: Text(description),
          trailing: const Icon(Icons.chevron_right),
          onTap: onTap,
        ),
      ),
    );
  }
}
