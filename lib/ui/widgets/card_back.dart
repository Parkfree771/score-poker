import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../theme.dart';
import 'card_face.dart';
import 'suit_glyphs.dart';

/// 뒤집힌 카드 한 장(상대 손패용). [CardFace]와 동일한 프레임/비율.
///
/// 여러 장을 동시에 그릴 때는 [cachedCardBack]을 쓸 것.
class CardBack extends StatelessWidget {
  const CardBack({super.key, required this.size});

  final double size;

  static double heightFor(double size) => CardFace.heightFor(size);


  @override
  Widget build(BuildContext context) {
    final w = size;
    final h = heightFor(size);
    return SizedBox(
      width: w,
      height: h,
      child: Stack(
        children: [
          Positioned.fill(
            child: Padding(
              padding: EdgeInsets.all(w * 0.04),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(w * 0.16),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.ink.withValues(alpha: 0.16),
                      blurRadius: w * 0.09,
                      offset: Offset(0, w * 0.045),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Positioned.fill(child: SvgPicture(cardBackLoader, fit: BoxFit.fill)),
        ],
      ),
    );
  }
}

/// 상대 손패를 **겹쳐진 뒷면 카드 부채**로 표시하고, 옆에 장수 배지를 붙인다.
class FaceDownHand extends StatelessWidget {
  const FaceDownHand({super.key, required this.count, this.cardSize = 30, this.maxShown = 6});

  final int count;
  final double cardSize;
  final int maxShown;

  @override
  Widget build(BuildContext context) {
    final shown = count.clamp(0, maxShown);
    final w = cardSize;
    final h = CardBack.heightFor(w);
    final overlap = w * 0.52; // 겹치는 정도
    final stackWidth = shown == 0 ? 0.0 : w + (shown - 1) * (w - overlap);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (shown > 0)
          SizedBox(
            width: stackWidth,
            height: h,
            child: Stack(
              children: [
                for (var i = 0; i < shown; i++)
                  Positioned(
                    left: i * (w - overlap),
                    child: Transform.rotate(
                      angle: (i - (shown - 1) / 2) * 0.045,
                      child: cachedCardBack(w),
                    ),
                  ),
              ],
            ),
          )
        else
          Icon(Icons.inbox_outlined, size: w, color: AppColors.textMuted),
        const SizedBox(width: 8),
        _CountBadge(count: count),
      ],
    );
  }
}

class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.ink,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.style, size: 13, color: AppColors.goldSoft),
          const SizedBox(width: 4),
          Text('$count',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13)),
        ],
      ),
    );
  }
}
