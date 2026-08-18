import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../domain/card.dart';
import '../theme.dart';
import 'suit_glyphs.dart';

String rankLabel(int rank) => switch (rank) {
      Ranks.jack => 'J',
      Ranks.queen => 'Q',
      Ranks.king => 'K',
      Ranks.ace => 'A',
      _ => '$rank',
    };

const String _inkHex = '#121330';
const String _goldHex = '#9A7A34'; // 앤티크 골드(쉴드 테두리)

/// 카드 한 장: **lordicon 카드 프레임(SVG) 그대로** + 코너 랭크 + 가운데 무늬(작게).
class CardFace extends StatelessWidget {
  const CardFace({super.key, required this.card, required this.size});

  final PlayingCard card;
  final double size; // 카드 폭

  static double heightFor(double size) => size * 1.36;

  @override
  Widget build(BuildContext context) {
    final w = size;
    final h = heightFor(size);
    final red = suitIsRed(card.suit);
    final ink = card.isJoker ? AppColors.purple : (red ? AppColors.red : AppColors.dark);

    return SizedBox(
      width: w,
      height: h,
      child: Stack(
        children: [
          // 은은한 그림자 (밝은 배경에서 카드가 떠 보이게)
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
          // 카드 프레임 (lordicon 원본). 쉴드는 골드 외곽선.
          Positioned.fill(
            child: SvgPicture.string(
              cardFrameSvg(card.isShield ? _goldHex : _inkHex),
              fit: BoxFit.fill,
            ),
          ),
          // 쉴드: 은은한 골드 바디 워시 + 방패 워터마크(정체성).
          if (card.isShield) ...[
            Positioned.fill(
              child: Padding(
                padding: EdgeInsets.all(w * 0.06),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(w * 0.12),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          AppColors.goldSoft.withValues(alpha: 0.35),
                          AppColors.gold.withValues(alpha: 0.14),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Align(
              alignment: const Alignment(0, -0.04),
              child: Icon(Icons.shield, size: w * 0.64, color: AppColors.gold.withValues(alpha: 0.28)),
            ),
          ],
          // 가운데 무늬 (조커는 원본 아트를 크게)
          Align(
            alignment: Alignment(0, card.isJoker ? 0 : -0.02),
            child: SizedBox(
              width: card.isJoker ? w * 0.74 : w * 0.38,
              height: card.isJoker ? w * 0.74 : w * 0.38,
              child: SvgPicture.string(card.isJoker ? jokerSvg() : suitSvg(card.suit), fit: BoxFit.contain),
            ),
          ),
          // 코너 랭크 (조커는 글자 없음)
          if (!card.isJoker) ...[
            Positioned(left: w * 0.13, top: h * 0.04, child: _rank(ink, w)),
            Positioned(
              right: w * 0.13,
              bottom: h * 0.04,
              child: Transform.rotate(angle: 3.14159, child: _rank(ink, w)),
            ),
          ],
        ],
      ),
    );
  }

  Widget _rank(Color ink, double w) => Text(
        rankLabel(card.rank),
        style: TextStyle(color: ink, fontWeight: FontWeight.w800, fontSize: w * 0.27, height: 1),
      );
}
