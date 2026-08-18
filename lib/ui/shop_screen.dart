import 'package:flutter/material.dart';
import 'package:intl/intl.dart' as intl;

import '../l10n/app_localizations.dart';
import '../monetization/monetization.dart';
import 'theme.dart';

/// 상점: 토큰 잔량 · 데일리 무료 지급 · 토큰 구매.
///
/// 화면이 지켜야 하는 것 두 가지:
/// 1. **가격은 스토어가 준 문자열을 그대로 쓴다.** 앱에서 통화를 조립하면 나라마다 틀린다.
/// 2. **할인율도 실제 가격으로 계산한다.** "24% 할인"을 하드코딩하면 가격 포인트가 다른
///    나라에서 거짓 표시가 되고, 이건 스토어 정책 위반이다.
class ShopScreen extends StatefulWidget {
  const ShopScreen({super.key});

  @override
  State<ShopScreen> createState() => _ShopScreenState();
}

class _ShopScreenState extends State<ShopScreen> {
  /// 구매 진행 중인 상품 id. 같은 버튼을 두 번 누르는 걸 막는다(중복 결제창).
  String? _busyProductId;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final m = MonetizationScope.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.shopTitle)),
      // 내용이 짧아도 위에서부터 쌓는다(세로 가운데 정렬이면 제목 아래가 크게 빈다).
      body: Align(
        alignment: Alignment.topCenter,
        child: SingleChildScrollView(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
              child: AnimatedBuilder(
                animation: m.wallet,
                builder: (context, _) => Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _BalancePanel(wallet: m.wallet),
                    const SizedBox(height: 14),
                    const _WhatTokensDo(),
                    const SizedBox(height: 14),
                    _DailyCard(wallet: m.wallet),
                    const SizedBox(height: 18),
                    ValueListenableBuilder<List<ProductOffer>>(
                      valueListenable: m.offers,
                      builder: (context, offers, _) => _ProductList(
                        offers: offers,
                        busyProductId: _busyProductId,
                        onBuy: (p) => _buy(m, p),
                      ),
                    ),
                    const SizedBox(height: 18),
                    if (!m.purchases.isSupported)
                      _Notice(icon: Icons.science_outlined, text: l10n.shopReferencePrice),
                    _Notice(icon: Icons.info_outline, text: l10n.shopConsumableNotice),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _buy(Monetization m, Product product) async {
    if (_busyProductId != null) return;
    setState(() => _busyProductId = product.id);
    final l10n = AppLocalizations.of(context);
    PurchaseResult result;
    try {
      result = await m.buy(product);
    } on Object {
      result = const PurchaseResult(PurchaseStatus.error);
    }
    if (!mounted) return;
    setState(() => _busyProductId = null);

    // 성공은 따로 알리지 않는다 — 잔량 숫자가 올라가는 게 더 확실한 피드백이고,
    // 지급은 스토어 배달 스트림으로 오므로 여기서 "완료"라고 말하면 거짓일 수 있다.
    final message = switch (result.status) {
      PurchaseStatus.purchased => null,
      PurchaseStatus.pending => l10n.shopPurchasePending,
      PurchaseStatus.cancelled => l10n.shopPurchaseCancelled,
      PurchaseStatus.notSupported => l10n.shopNotSupported,
      PurchaseStatus.error => result.message ?? l10n.shopPurchaseFailed,
    };
    if (message != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    }
  }
}

/// 보유 토큰. 상점에 들어오자마자 "내가 뭘 얼마나 가졌는지"가 먼저 보여야 한다.
class _BalancePanel extends StatelessWidget {
  const _BalancePanel({required this.wallet});
  final TokenWallet wallet;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(AppShapes.radius),
        border: Border.all(color: AppColors.stroke),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.shopOwnedTitle,
              style: const TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 11.5,
                  letterSpacing: 1.2,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                  child: TokenChip(
                      kind: TokenKind.shield, count: wallet.balanceOf(TokenKind.shield))),
              const SizedBox(width: 10),
              Expanded(
                  child: TokenChip(
                      kind: TokenKind.attack, count: wallet.balanceOf(TokenKind.attack))),
            ],
          ),
        ],
      ),
    );
  }
}

/// 토큰 1종의 아이콘 + 이름 + 개수. 게임 화면에서도 재사용한다.
class TokenChip extends StatelessWidget {
  const TokenChip({super.key, required this.kind, required this.count, this.compact = false});

  final TokenKind kind;
  final int count;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final color = tokenColor(kind);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: compact ? 10 : 12, vertical: compact ? 6 : 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.55), width: 1.2),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(tokenIcon(kind), size: compact ? 16 : 20, color: color),
          const SizedBox(width: 8),
          if (!compact)
            Expanded(
              child: Text(tokenName(l10n, kind),
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: AppColors.textMain, fontWeight: FontWeight.w600, fontSize: 13)),
            ),
          const SizedBox(width: 6),
          Text('$count',
              style: TextStyle(
                  color: color, fontWeight: FontWeight.w900, fontSize: compact ? 14 : 17)),
        ],
      ),
    );
  }
}

/// 이 토큰이 무엇을 하는 물건인지.
///
/// **설명 없이 팔면 안 팔린다.** 특히 이 게임의 토큰은 효과가 규칙과 얽혀 있어서
/// ("조커로만 깨진다", "덱에서 뽑은 카드로도 공격") 이름만 봐서는 뭔지 알 수 없다.
/// 마지막 줄의 "판당 1개" 안내는 판매 문구가 아니라 **약속**이다 — 많이 사도 한 판의
/// 이득이 같다는 걸 사기 전에 알려야 나중에 분쟁이 없다.
class _WhatTokensDo extends StatelessWidget {
  const _WhatTokensDo();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(AppShapes.radius),
        border: Border.all(color: AppColors.stroke),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final kind in TokenKind.values) ...[
            if (kind != TokenKind.values.first) const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: Icon(tokenIcon(kind), size: 17, color: tokenColor(kind)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(tokenName(l10n, kind),
                          style: TextStyle(
                              color: tokenColor(kind),
                              fontWeight: FontWeight.w800,
                              fontSize: 13)),
                      const SizedBox(height: 2),
                      Text(tokenDescription(l10n, kind),
                          style: const TextStyle(
                              color: AppColors.textMain, fontSize: 12.5, height: 1.4)),
                    ],
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          const Divider(height: 1, color: AppColors.stroke),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.balance_rounded, size: 14, color: AppColors.textMuted),
              const SizedBox(width: 8),
              Expanded(
                child: Text(l10n.shopSubtitle,
                    style: const TextStyle(
                        color: AppColors.textMuted, fontSize: 11.5, height: 1.4)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 하루 1회 무료 지급.
///
/// 무료 지급은 매출을 깎는 장치가 아니라 **아이템을 써 보게 만드는 장치**다.
/// 써 본 적 없는 아이템은 아무도 사지 않는다.
class _DailyCard extends StatelessWidget {
  const _DailyCard({required this.wallet});
  final TokenWallet wallet;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final canClaim = wallet.canClaimDaily();
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 16, 16),
        child: Row(
          children: [
            const Icon(Icons.card_giftcard_rounded, color: AppColors.gold, size: 28),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l10n.shopDailyTitle, style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 3),
                  Text(l10n.shopDailyDesc,
                      style: const TextStyle(color: AppColors.textMuted, fontSize: 12.5)),
                ],
              ),
            ),
            const SizedBox(width: 10),
            if (canClaim)
              FilledButton(
                onPressed: () => _claim(context),
                style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12)),
                child: Text(l10n.shopClaim),
              )
            else
              Text(l10n.shopClaimed,
                  style: const TextStyle(
                      color: AppColors.textMuted, fontSize: 12, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }

  Future<void> _claim(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final granted = await wallet.claimDaily();
    if (granted.isEmpty) return;
    messenger.showSnackBar(SnackBar(
      content: Text(l10n.shopClaimToast(
        granted[TokenKind.shield] ?? 0,
        granted[TokenKind.attack] ?? 0,
      )),
    ));
  }
}

class _ProductList extends StatelessWidget {
  const _ProductList(
      {required this.offers, required this.busyProductId, required this.onBuy});

  final List<ProductOffer> offers;
  final String? busyProductId;
  final void Function(Product) onBuy;

  @override
  Widget build(BuildContext context) {
    final byId = {for (final o in offers) o.product.id: o};
    final set = byId[Products.set20.id];
    final singles = [byId[Products.shield10.id], byId[Products.attack10.id]].nonNulls;
    final discount = set == null ? null : discountPercent(set, singles);

    return Column(
      children: [
        for (final product in Products.all) ...[
          _ProductTile(
            product: product,
            offer: byId[product.id],
            discount: product == Products.set20 ? discount : null,
            busy: busyProductId == product.id,
            enabled: busyProductId == null,
            onBuy: () => onBuy(product),
          ),
          const SizedBox(height: 10),
        ],
      ],
    );
  }
}

class _ProductTile extends StatelessWidget {
  const _ProductTile({
    required this.product,
    required this.offer,
    required this.discount,
    required this.busy,
    required this.enabled,
    required this.onBuy,
  });

  final Product product;
  final ProductOffer? offer;
  final int? discount;
  final bool busy;
  final bool enabled;
  final VoidCallback onBuy;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final o = offer;
    final highlight = discount != null;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppShapes.radius),
        border: Border.all(
          color: highlight ? AppColors.gold.withValues(alpha: 0.7) : AppColors.stroke,
          width: highlight ? 1.6 : 1,
        ),
      ),
      padding: const EdgeInsets.fromLTRB(18, 14, 14, 14),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(productName(l10n, product),
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleMedium),
                    ),
                    if (discount != null) ...[
                      const SizedBox(width: 8),
                      _DiscountBadge(percent: discount!),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Text(productDescription(l10n, product),
                    style: const TextStyle(color: AppColors.textMuted, fontSize: 12.5)),
                if (o?.pricePerToken != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    l10n.shopPerToken(_formatMoney(context, o!.pricePerToken!, o.currencyCode)),
                    style: const TextStyle(color: AppColors.inkSoft, fontSize: 11.5),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 104,
            child: busy
                ? const Center(
                    child: SizedBox(
                        width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.2)))
                : FilledButton(
                    onPressed: (o == null || !enabled) ? null : onBuy,
                    style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 13)),
                    child: Text(
                      o?.formattedPrice ?? l10n.shopLoadingPrice,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  /// 개당 단가 표시용. 스토어가 통화 코드를 주므로 그 통화로 포맷한다.
  static String _formatMoney(BuildContext context, double amount, String? currencyCode) {
    final locale = Localizations.localeOf(context).toString();
    try {
      return intl.NumberFormat.simpleCurrency(locale: locale, name: currencyCode).format(amount);
    } on Object {
      return amount.toStringAsFixed(0);
    }
  }
}

class _DiscountBadge extends StatelessWidget {
  const _DiscountBadge({required this.percent});
  final int percent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.gold,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        AppLocalizations.of(context).shopDiscount(percent),
        style: const TextStyle(
            color: AppColors.bgBottom, fontWeight: FontWeight.w900, fontSize: 11),
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 14, color: AppColors.textMuted),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text,
                style: const TextStyle(
                    color: AppColors.textMuted, fontSize: 11.5, height: 1.4)),
          ),
        ],
      ),
    );
  }
}

// ── 토큰·상품의 표시 정보 (l10n 매핑을 한 곳에 모아둔다) ─────────────────────────

Color tokenColor(TokenKind kind) => switch (kind) {
      TokenKind.shield => AppColors.gold, // 브라스 골드 = 쉴드(테마 규칙)
      TokenKind.attack => AppColors.red,
    };

IconData tokenIcon(TokenKind kind) => switch (kind) {
      TokenKind.shield => Icons.shield_rounded,
      TokenKind.attack => Icons.local_fire_department_rounded,
    };

String tokenName(AppLocalizations l10n, TokenKind kind) => switch (kind) {
      TokenKind.shield => l10n.tokenShieldName,
      TokenKind.attack => l10n.tokenAttackName,
    };

String tokenDescription(AppLocalizations l10n, TokenKind kind) => switch (kind) {
      TokenKind.shield => l10n.tokenShieldDesc,
      TokenKind.attack => l10n.tokenAttackDesc,
    };

String productName(AppLocalizations l10n, Product p) {
  if (p == Products.set20) return l10n.productSet20Name;
  if (p == Products.shield10) return l10n.productShield10Name;
  if (p == Products.attack10) return l10n.productAttack10Name;
  return p.id;
}

String productDescription(AppLocalizations l10n, Product p) {
  if (p == Products.set20) return l10n.productSet20Desc;
  if (p == Products.shield10) return l10n.productShield10Desc;
  if (p == Products.attack10) return l10n.productAttack10Desc;
  return '';
}
