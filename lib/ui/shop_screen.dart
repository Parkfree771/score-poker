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
