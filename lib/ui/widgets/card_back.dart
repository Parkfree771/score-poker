import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../domain/card.dart';
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

/// **홀카드 필**: 덮인 카드의 모서리가 들려 숫자·무늬가 보인다.
///
/// 가림 룰에서 "상대에겐 뒷면인데 나는 내용을 아는" 내 카드의 표현.
/// 포커에서 홀카드를 손끝으로 들춰 보는 바로 그 동작이다 — 뒷면이 그대로 보이므로
/// "덮여 있다"가 전달되고, 들린 모서리의 랭크·무늬로 "나는 안다"가 전달된다.
///
/// 들린 면은 **카드 폭의 0.72**까지 넓혔다. 그 전(0.52)에는 "10♦"처럼 두 글자짜리
/// 랭크가 삼각형 안에서 잘려 나갔다 — 내가 아는 카드인데 못 읽으면 표현의 의미가 없다.
///
class PeekCardBack extends StatelessWidget {
  const PeekCardBack({
    super.key,
    required this.card,
    required this.size,
  });

  final PlayingCard card;
  final double size;

  @override
  Widget build(BuildContext context) {
    final w = size;
    final h = CardBack.heightFor(w);
    final fold = w * 0.72; // 들리는 모서리 한 변 길이
    final red = suitIsRed(card.suit);
    return SizedBox(
      width: w,
      height: h,
      child: Stack(
        children: [
          Positioned.fill(child: cachedCardBack(w)),
          // 오른쪽 아래 모서리가 들려 속(아이보리)이 드러난다.
          Positioned(
            right: w * 0.045,
            bottom: w * 0.045,
            child: ClipPath(
              clipper: _FoldClipper(),
              child: Container(
                width: fold,
                height: fold,
                decoration: const BoxDecoration(color: Color(0xFFF7F2E4)),
                child: Stack(
                  children: [
                    // 접힌 선(대각선) — 들렸다는 인상을 주는 최소한의 음영선
                    CustomPaint(size: Size(fold, fold), painter: _FoldEdgePainter()),
                    // 삼각형의 가장 두꺼운 구석에 랭크+무늬. FittedBox라 어떤 크기에서도
                    // 잘리지 않고 줄어들 뿐이다.
                    Positioned(
                      right: fold * 0.07,
                      bottom: fold * 0.06,
                      width: fold * 0.66,
                      height: fold * 0.44,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.bottomRight,
                        child: Text(
                          '${rankLabel(card.rank)}${card.suit.symbol}',
                          maxLines: 1,
                          style: TextStyle(
                            color: red ? AppColors.red : AppColors.dark,
                            fontWeight: FontWeight.w900,
                            fontSize: fold * 0.34,
                            height: 1,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 오른쪽 아래 직각 삼각형(들린 모서리 모양).
class _FoldClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) => Path()
    ..moveTo(size.width, 0)
    ..lineTo(size.width, size.height)
    ..lineTo(0, size.height)
    ..close();

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}

class _FoldEdgePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final line = Paint()
      ..color = AppColors.gold
      ..strokeWidth = 1.6
      ..style = PaintingStyle.stroke;
    canvas.drawLine(Offset(size.width, 0), Offset(0, size.height), line);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
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
