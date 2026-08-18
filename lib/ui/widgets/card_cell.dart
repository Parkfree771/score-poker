import 'package:flutter/material.dart';

import '../../domain/game.dart';
import '../theme.dart';
import 'card_face.dart';

/// 빈 칸이 어느 쪽 필드인지 — 빈 슬롯 색조를 살짝 다르게 준다.
enum CellSide { me, opp, neutral }

/// 보드/손패의 한 칸. 비어있으면 슬롯, 카드가 있으면 [CardFace].
class CardCell extends StatelessWidget {
  const CardCell({
    super.key,
    required this.placed,
    required this.size,
    this.highlighted = false,
    this.side = CellSide.neutral,
    this.onTap,
  });

  final PlacedCard? placed;
  final double size;
  final bool highlighted;
  final CellSide side;
  final VoidCallback? onTap;

  static double cellHeight(double size) => CardFace.heightFor(size) + size * 0.08;

  @override
  Widget build(BuildContext context) {
    final w = size;
    final h = CardFace.heightFor(size);
    final inner = placed == null
        ? Container(
            width: w,
            height: h,
            decoration: BoxDecoration(
              color: highlighted ? AppColors.slotNext : AppColors.slotRecess,
              borderRadius: BorderRadius.circular(w * 0.14),
              border: Border.all(
                color: highlighted ? AppColors.gold : AppColors.stroke,
                width: highlighted ? 2.6 : 1.2,
              ),
            ),
          )
        : (highlighted
            ? Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(w * 0.18),
                  border: Border.all(color: AppColors.gold, width: 2.6),
                  boxShadow: [BoxShadow(color: AppColors.gold.withValues(alpha: 0.5), blurRadius: 12)],
                ),
                child: CardFace(card: placed!.card, size: w),
              )
            : CardFace(card: placed!.card, size: w));

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(padding: EdgeInsets.all(w * 0.04), child: inner),
    );
  }
}
