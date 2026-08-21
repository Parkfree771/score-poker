import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import 'theme.dart';

/// 상점 — **지금은 파는 것이 없다.**
///
/// 예전 상품(쉴드 선언·공격 표식 토큰)은 그 규칙 자체가 사라지면서 같이 내렸다.
/// 결제 배관(`lib/monetization/`)은 그대로 살아 있고, 새 규칙에 맞는 상품이 정해지면
/// 여기에 진열만 다시 붙이면 된다. 규칙에 없는 물건을 파는 화면을 남겨 두지 않는다.
class ShopScreen extends StatelessWidget {
  const ShopScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.shopTitle)),
      body: DecoratedBox(
        decoration: const BoxDecoration(gradient: AppColors.bgGradient),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 92,
                    height: 92,
                    decoration: BoxDecoration(
                      color: AppColors.panel,
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.goldSoft, width: 1.4),
                    ),
                    child: const Icon(Icons.storefront_rounded,
                        size: 44, color: AppColors.goldSoft),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    l10n.shopEmptyTitle,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: AppColors.textMain,
                        fontWeight: FontWeight.w900,
                        fontSize: 20),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    l10n.shopEmptyBody,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: AppColors.textMuted,
                        fontWeight: FontWeight.w600,
                        fontSize: 13.5,
                        height: 1.45),
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
