import 'package:flutter/material.dart';

import '../domain/card.dart';
import '../l10n/app_localizations.dart';
import 'rules_screen.dart';
import 'theme.dart';
import 'widgets/board_view.dart';
import 'widgets/card_back.dart';
import 'widgets/card_face.dart';

/// 첫 실행 튜토리얼 — 5장으로 끝나는 "1분 설명".
///
/// **전체 규칙을 여기서 다 가르치려 하지 않는다.** 첫 판을 둘 수 있을 만큼만 보여주고,
/// 나머지는 [RulesScreen]으로 넘긴다. 길어지면 아무도 안 읽는다.
class HowToPlayScreen extends StatefulWidget {
  const HowToPlayScreen({super.key});

  @override
  State<HowToPlayScreen> createState() => _HowToPlayScreenState();
}

class _HowToPlayScreenState extends State<HowToPlayScreen> {
  final _controller = PageController();
  int _page = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  List<_Page> _pages(AppLocalizations l10n) => [
        _Page(l10n.tutGoalTitle, l10n.tutGoalBody, const _GoalArt()),
        _Page(l10n.tutPlaceTitle, l10n.tutPlaceBody, const _PlaceArt()),
        _Page(l10n.tutRevealTitle, l10n.tutRevealBody, const _RevealArt()),
        _Page(l10n.tutVeilTitle, l10n.tutVeilBody, const _VeilArt()),
        _Page(l10n.tutPeekTitle, l10n.tutPeekBody, const _PeekArt()),
      ];

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final pages = _pages(l10n);
    final isLast = _page == pages.length - 1;

    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(gradient: AppColors.bgGradient),
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                children: [
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: _finish,
                      child:
                          Text(l10n.skip, style: const TextStyle(color: AppColors.textMuted)),
                    ),
                  ),
                  Expanded(
                    child: PageView.builder(
                      controller: _controller,
                      onPageChanged: (i) => setState(() => _page = i),
                      itemCount: pages.length,
                      itemBuilder: (context, i) => _PageView(page: pages[i]),
                    ),
                  ),
                  _Dots(count: pages.length, active: _page),
                  const SizedBox(height: 14),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 10),
                    child: SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: isLast ? _finish : _nextPage,
                        child: Text(isLast ? l10n.startPlaying : l10n.next),
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(builder: (_) => const RulesScreen()),
                    ),
                    child: Text(l10n.rulesFullLink,
                        style: const TextStyle(color: AppColors.goldSoft, fontSize: 12.5)),
                  ),
                  const SizedBox(height: 6),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _nextPage() => _controller.nextPage(
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOut,
      );

  void _finish() => Navigator.of(context).maybePop();
}

class _Page {
  const _Page(this.title, this.body, this.art);
  final String title;
  final String body;
  final Widget art;
}

class _PageView extends StatelessWidget {
  const _PageView({required this.page});
  final _Page page;

  @override
  Widget build(BuildContext context) {
    // 내용이 짧으면 세로 가운데, 길면(큰 글씨 설정 등) 스크롤되게 한다.
    // 그냥 SingleChildScrollView만 쓰면 Column의 center 정렬이 먹지 않아 위로 쏠린다.
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(height: 8),
              SizedBox(height: 150, child: Center(child: page.art)),
              const SizedBox(height: 26),
              Text(
                page.title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: AppColors.textMain,
                    fontSize: 21,
                    fontWeight: FontWeight.w800,
                    height: 1.25),
              ),
              const SizedBox(height: 12),
              Text(
                page.body,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.inkSoft, fontSize: 13.5, height: 1.6),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}

class _Dots extends StatelessWidget {
  const _Dots({required this.count, required this.active});
  final int count;
  final int active;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < count; i++)
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            margin: const EdgeInsets.symmetric(horizontal: 3),
            width: i == active ? 18 : 6,
            height: 6,
            decoration: BoxDecoration(
              color: i == active ? AppColors.gold : AppColors.gaugeOff,
              borderRadius: BorderRadius.circular(999),
            ),
          ),
      ],
    );
  }
}

// ── 삽화 ────────────────────────────────────────────────────────────────────
// 실제 카드 위젯을 그대로 쓴다. 별도 이미지를 만들면 규칙이 바뀔 때 같이 안 바뀐다.

/// 3줄 대결: 위(상대) 3줄 vs 아래(나) 3줄, 내가 2줄을 이긴 상태.
class _GoalArt extends StatelessWidget {
  const _GoalArt();

  @override
  Widget build(BuildContext context) {
    Widget line({required Color color, required bool won}) => Container(
          width: 78,
          height: 13,
          margin: const EdgeInsets.symmetric(vertical: 3),
          decoration: BoxDecoration(
            color: won ? color : AppColors.gaugeOff,
            borderRadius: BorderRadius.circular(4),
          ),
        );

    Widget check(bool mine) => SizedBox(
          width: 26,
          child: mine
              ? const Icon(Icons.check_rounded, size: 17, color: AppColors.win)
              : const SizedBox.shrink(),
        );

    // 줄1: 내가 승 / 줄2: 상대 승 / 줄3: 내가 승 → 2:1로 내가 이긴다.
    const mineWins = [true, false, true];
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final mine in mineWins) line(color: AppColors.oppPrimary, won: !mine),
          ],
        ),
        const SizedBox(width: 10),
        Container(width: 1.5, height: 62, color: AppColors.feltEdge),
        const SizedBox(width: 10),
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final mine in mineWins) line(color: AppColors.mePrimary, won: mine),
          ],
        ),
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [for (final mine in mineWins) SizedBox(height: 19, child: check(mine))],
        ),
      ],
    );
  }
}

/// 손패에서 고른 카드가 **뒷면으로** 내 줄에 놓이는 그림.
class _PlaceArt extends StatelessWidget {
  const _PlaceArt();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const CardFace(card: PlayingCard(9, Suit.hearts), size: 44),
        const SizedBox(width: 6),
        const CardFace(card: PlayingCard(13, Suit.spades), size: 44),
        const SizedBox(width: 14),
        Icon(Icons.arrow_forward_rounded, color: AppColors.gold.withValues(alpha: 0.8)),
        const SizedBox(width: 14),
        const CardBack(size: 52),
      ],
    );
  }
}

/// 라운드가 끝나면 그 라운드에 놓인 카드가 양쪽 동시에 뒤집힌다.
class _RevealArt extends StatelessWidget {
  const _RevealArt();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const CardBack(size: 46),
        const SizedBox(width: 6),
        const CardBack(size: 46),
        const SizedBox(width: 14),
        Icon(Icons.autorenew_rounded, color: AppColors.gold.withValues(alpha: 0.9), size: 22),
        const SizedBox(width: 14),
        const CardFace(card: PlayingCard(10, Suit.diamonds), size: 46),
        const SizedBox(width: 6),
        const CardFace(card: PlayingCard(10, Suit.clubs), size: 46),
      ],
    );
  }
}

/// 비공개권 코인 3개 — 쓰면 빈 소켓이 남는다.
class _VeilArt extends StatelessWidget {
  const _VeilArt();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < 3; i++)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 5),
            child: VeilCoin(size: 34, filled: i < 2, ring: AppColors.mePrimary),
          ),
      ],
    );
  }
}

/// 코인 1개를 태워 상대가 숨긴 카드를 열어본다.
class _PeekArt extends StatelessWidget {
  const _PeekArt();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const VeilCoin(size: 30, filled: true, ring: AppColors.mePrimary),
        const SizedBox(width: 12),
        Icon(Icons.arrow_forward_rounded,
            color: AppColors.gold.withValues(alpha: 0.8), size: 20),
        const SizedBox(width: 12),
        const CardBack(size: 46),
        const SizedBox(width: 10),
        const Icon(Icons.visibility_rounded, color: AppColors.gold, size: 22),
        const SizedBox(width: 10),
        const CardFace(card: PlayingCard(14, Suit.spades), size: 46),
      ],
    );
  }
}
