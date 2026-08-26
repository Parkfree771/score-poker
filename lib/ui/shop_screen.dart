import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../monetization/monetization.dart';
import 'theme.dart';
import 'widgets/veil_chip.dart';

/// 상점 — 부스트 팩 하나를 판다.
///
/// 부스트 1개 = 한 판을 부스트해서 시작(비공개권 칩 +1, 손패 스왑 1회). 판마다 1개까지.
/// 가격은 **스토어가 준 문자열**을 그대로 보여준다(웹·데스크톱은 스텁 참고가 + "참고가" 표시).
/// `MonetizationScope`가 없는 환경(단독 위젯 테스트)에서는 상품 없이 빈 화면만 그린다.
class ShopScreen extends StatefulWidget {
  const ShopScreen({super.key});

  @override
  State<ShopScreen> createState() => _ShopScreenState();
}

class _ShopScreenState extends State<ShopScreen> {
  bool _buying = false;
  bool _watching = false;

  Future<void> _watchAd(Monetization m) async {
    if (_watching) return;
    setState(() => _watching = true);
    final l10n = AppLocalizations.of(context);
    try {
      final r = await m.watchAdForBoost();
      if (!mounted) return;
      final msg = switch (r) {
        AdRewardOutcome.rewarded => l10n.adRewarded(m.policyAdReward),
        AdRewardOutcome.dismissed => l10n.adDismissed,
        AdRewardOutcome.capReached => l10n.adCapReached,
        AdRewardOutcome.notReady => l10n.adNotReady,
        AdRewardOutcome.failed => l10n.adFailed,
        AdRewardOutcome.notSupported => l10n.adNotSupported,
        AdRewardOutcome.busy => null,
      };
      if (msg != null) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(msg)));
      }
    } finally {
      if (mounted) setState(() => _watching = false);
    }
  }

  Future<void> _buy(Monetization m, Product product) async {
    if (_buying) return;
    setState(() => _buying = true);
    final l10n = AppLocalizations.of(context);
    try {
      final r = await m.buy(product);
      if (!mounted) return;
      final msg = switch (r.status) {
        PurchaseStatus.purchased => l10n.shopPurchased,
        PurchaseStatus.cancelled => null,
        PurchaseStatus.pending => l10n.shopPending,
        PurchaseStatus.notSupported => l10n.shopNotSupported,
        PurchaseStatus.error => r.message ?? l10n.shopError,
      };
      if (msg != null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      }
    } finally {
      if (mounted) setState(() => _buying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final m = MonetizationScope.maybeOf(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.shopTitle)),
      body: DecoratedBox(
        decoration: const BoxDecoration(gradient: AppColors.bgGradient),
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: m == null
                  ? const SizedBox.shrink()
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
                      children: [
                        _BalanceCard(l10n: l10n, wallet: m.wallet),
                        const SizedBox(height: 16),
                        ValueListenableBuilder<List<ProductOffer>>(
                          valueListenable: m.offers,
                          builder: (context, offers, _) {
                            if (offers.isEmpty) {
                              return Padding(
                                padding: const EdgeInsets.all(24),
                                child: Text(l10n.shopLoading,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                        color: AppColors.textMuted,
                                        fontWeight: FontWeight.w600)),
                              );
                            }
                            return Column(
                              children: [
                                for (final o in offers)
                                  _OfferCard(
                                    l10n: l10n,
                                    offer: o,
                                    reference: !m.purchases.isSupported,
                                    busy: _buying,
                                    onBuy: () => _buy(m, o.product),
                                  ),
                              ],
                            );
                          },
                        ),
                        const SizedBox(height: 12),
                        _AdRewardCard(
                          l10n: l10n,
                          m: m,
                          busy: _watching || _buying,
                          onWatch: () => _watchAd(m),
                        ),
                        const SizedBox(height: 18),
                        _Notice(text: l10n.shopConsumableNotice),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 남은 부스트 — 칩 아이콘 + 판 수.
class _BalanceCard extends StatelessWidget {
  const _BalanceCard({required this.l10n, required this.wallet});
  final AppLocalizations l10n;
  final TokenWallet wallet;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: wallet,
      builder: (context, _) {
        final n = wallet.balanceOf(TokenKind.boost);
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          decoration: BoxDecoration(
            color: AppColors.panel,
            borderRadius: BorderRadius.circular(AppShapes.radius),
            border: Border.all(color: AppColors.stroke),
          ),
          child: Row(
            children: [
              const ChipBadge(size: 34, ring: AppColors.goldSoft),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l10n.shopBalanceLabel,
                        style: const TextStyle(
                            color: AppColors.textMuted,
                            fontSize: 12,
                            fontWeight: FontWeight.w700)),
                    Text(l10n.shopBalanceGames(n),
                        style: const TextStyle(
                            color: AppColors.textMain,
                            fontSize: 20,
                            fontWeight: FontWeight.w900)),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _OfferCard extends StatelessWidget {
  const _OfferCard({
    required this.l10n,
    required this.offer,
    required this.reference,
    required this.busy,
    required this.onBuy,
  });

  final AppLocalizations l10n;
  final ProductOffer offer;

  /// 스텁 참고가인가(웹·데스크톱). 실제 결제가 아니라는 표시를 붙인다.
  final bool reference;
  final bool busy;
  final VoidCallback onBuy;

  @override
  Widget build(BuildContext context) {
    final games = offer.product.tokenCount;
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.alphaBlend(AppColors.gold.withValues(alpha: 0.14), AppColors.surface),
            AppColors.surface,
          ],
        ),
        borderRadius: BorderRadius.circular(AppShapes.radius),
        border: Border.all(color: AppColors.gold.withValues(alpha: 0.7), width: 1.3),
        boxShadow: AppShapes.panelShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(l10n.shopBoostPackTitle(games),
                    style: const TextStyle(
                        color: AppColors.goldSoft,
                        fontSize: 19,
                        fontWeight: FontWeight.w900)),
              ),
              Text(offer.formattedPrice,
                  style: const TextStyle(
                      color: AppColors.textMain,
                      fontSize: 19,
                      fontWeight: FontWeight.w900)),
            ],
          ),
          const SizedBox(height: 10),
          _Perk(icon: Icons.add_circle_outline_rounded, text: l10n.shopPerkChip),
          const SizedBox(height: 6),
          _Perk(icon: Icons.swap_horiz_rounded, text: l10n.shopPerkSwap),
          const SizedBox(height: 6),
          _Perk(icon: Icons.rule_rounded, text: l10n.shopPerkLimit),
          const SizedBox(height: 14),
          Row(
            children: [
              if (reference)
                Expanded(
                  child: Text(l10n.shopReferencePrice,
                      style: const TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600)),
                )
              else
                const Spacer(),
              FilledButton(
                onPressed: busy ? null : onBuy,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.gold,
                  foregroundColor: AppColors.ink,
                  padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                ),
                child: Text(l10n.shopBuy,
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// "광고 보고 부스트 받기" — 유료 팩의 **대안**이라 팩 아래에, 톤도 한 단계 낮게.
///
/// 보여주는 상태는 셋: 오늘 남은 횟수(현황), 광고 준비 여부(버튼 활성), 캡 도달(내일).
/// 지급 여부는 여기서 판단하지 않는다 — [Monetization.watchAdForBoost]의 결과만 안내한다.
class _AdRewardCard extends StatelessWidget {
  const _AdRewardCard({
    required this.l10n,
    required this.m,
    required this.busy,
    required this.onWatch,
  });

  final AppLocalizations l10n;
  final Monetization m;
  final bool busy;
  final VoidCallback onWatch;

  @override
  Widget build(BuildContext context) {
    if (m.wallet.policy.adDailyCap <= 0) return const SizedBox.shrink();
    return ListenableBuilder(
      listenable: Listenable.merge([m.wallet, m.adReady]),
      builder: (context, _) {
        final cap = m.wallet.policy.adDailyCap;
        final left = m.wallet.adRewardsLeftToday();
        final ready = m.adReady.value;
        final capped = left <= 0;
        final String buttonText;
        if (capped) {
          buttonText = l10n.adButtonTomorrow;
        } else if (!ready) {
          buttonText = l10n.adButtonLoading;
        } else {
          buttonText = l10n.adButtonWatch;
        }
        return Container(
          key: const ValueKey('ad-reward-card'),
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
          decoration: BoxDecoration(
            color: AppColors.panel,
            borderRadius: BorderRadius.circular(AppShapes.radius),
            border: Border.all(color: AppColors.stroke),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.ondemand_video_rounded, size: 20, color: AppColors.goldSoft),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(l10n.adCardTitle(m.policyAdReward),
                        style: const TextStyle(
                            color: AppColors.textMain,
                            fontSize: 16,
                            fontWeight: FontWeight.w800)),
                  ),
                  Text(l10n.adLeftToday(left, cap),
                      key: const ValueKey('ad-left-today'),
                      style: TextStyle(
                          color: capped ? AppColors.textMuted : AppColors.goldSoft,
                          fontSize: 13,
                          fontWeight: FontWeight.w800)),
                ],
              ),
              const SizedBox(height: 8),
              Text(l10n.adCardBody,
                  style: const TextStyle(
                      color: AppColors.textMuted, fontSize: 12.5, height: 1.4)),
              const SizedBox(height: 12),
              Row(
                children: [
                  if (!m.rewardedAds.isSupported)
                    Expanded(
                      child: Text(l10n.adMockLabel,
                          style: const TextStyle(
                              color: AppColors.textMuted,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600)),
                    )
                  else
                    const Spacer(),
                  OutlinedButton.icon(
                    key: const ValueKey('ad-watch'),
                    onPressed: (busy || capped || !ready) ? null : onWatch,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.goldSoft,
                      side: BorderSide(
                          color: (capped || !ready)
                              ? AppColors.stroke
                              : AppColors.gold.withValues(alpha: 0.8)),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
                    ),
                    icon: Icon(capped ? Icons.schedule_rounded : Icons.play_arrow_rounded,
                        size: 18),
                    label: Text(buttonText,
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Perk extends StatelessWidget {
  const _Perk({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Icon(icon, size: 18, color: AppColors.goldSoft),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text,
                style: const TextStyle(
                    color: AppColors.textMain, fontSize: 13.5, fontWeight: FontWeight.w600)),
          ),
        ],
      );
}

class _Notice extends StatelessWidget {
  const _Notice({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline_rounded, size: 16, color: AppColors.textMuted),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text,
                style: const TextStyle(
                    color: AppColors.textMuted, fontSize: 12, height: 1.45)),
          ),
        ],
      );
}
