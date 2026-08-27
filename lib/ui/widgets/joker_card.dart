import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:lottie/lottie.dart';

import '../../domain/card.dart';
import '../theme.dart';
import 'card_back.dart';
import 'card_face.dart';
import 'suit_glyphs.dart';

/// 조커 팔레트 — 게임 팔레트(펠트·브라스) 밖의 색은 이 카드 하나뿐이다: 보라 위 금빛 별.
/// "이건 다른 물건이다"가 손패에서 한눈에 읽혀야 한다.
class JokerColors {
  JokerColors._();
  static const purple = Color(0xFF5B2A86);
  static const purpleDeep = Color(0xFF2E1348);
  static const gold = Color(0xFFF2CC5A);
  static const lime = Color(0xFFC6F135);
}

/// 손패의 조커 카드. **일반 카드와 같은 크림 카드**에 가운데 무늬만 광대 로티
/// (사용자 lottie 폴더 `wired-lineal-1451-card-joker`, 원본 색)로 바꾼 것이다.
/// 코너는 "JOKER" — [as]를 주면 그 카드의 숫자·무늬가 코너에 들어간다(강타 연출용:
/// "이 조커가 ♥A가 된다"). 크기는 [CardFace]와 같은 규칙([CardFace.heightFor]).
class JokerFace extends StatelessWidget {
  const JokerFace({super.key, required this.size, this.as, this.animate = true});

  final double size;
  final PlayingCard? as;
  final bool animate;

  @override
  Widget build(BuildContext context) {
    final w = size, h = CardFace.heightFor(size);
    final target = as;
    final ink = target == null
        ? AppColors.dark
        : (suitIsRed(target.suit) ? AppColors.red : AppColors.dark);
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
          Positioned.fill(
            child: SvgPicture(cardFrameLoader('#121330'), fit: BoxFit.fill),
          ),
          Align(
            alignment: const Alignment(0, -0.02),
            child: SizedBox(
              width: w * 0.64,
              height: w * 0.64,
              child: JokerGlyph(animate: animate),
            ),
          ),
          Positioned(left: w * 0.13, top: h * 0.04, child: _corner(ink, w)),
          Positioned(
            right: w * 0.13,
            bottom: h * 0.04,
            child: Transform.rotate(angle: math.pi, child: _corner(ink, w)),
          ),
        ],
      ),
    );
  }

  Widget _corner(Color ink, double w) {
    final target = as;
    if (target == null) {
      return Text('JOKER',
          style: TextStyle(
              color: ink, fontWeight: FontWeight.w900, fontSize: w * 0.13, height: 1));
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(rankLabel(target.rank),
            style: TextStyle(
                color: ink, fontWeight: FontWeight.w800, fontSize: w * 0.27, height: 1)),
        SizedBox(
          width: w * 0.19,
          height: w * 0.19,
          child: SvgPicture(suitLoader(target.suit), fit: BoxFit.contain),
        ),
      ],
    );
  }
}

/// 조커가 관여한 카드 위의 작은 배지(와일드 지정·강타로 바뀐 카드·강타 예고).
/// [pending]이면 "아직 발동 전" — 테두리가 두껍고 살짝 떠 있다.
class JokerBadge extends StatelessWidget {
  const JokerBadge({super.key, required this.size, required this.color, this.pending = false});

  final double size;
  final Color color;
  final bool pending;

  @override
  Widget build(BuildContext context) {
    // 크림 원 위 광대 모자(로티, 정지 프레임) — 손패 조커와 같은 문양이라 한눈에 이어진다.
    return Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(size * 0.1),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.cardBody,
        border: Border.all(color: pending ? color : AppColors.gold, width: pending ? 2.2 : 1.4),
        boxShadow: [
          BoxShadow(color: color.withValues(alpha: pending ? 0.7 : 0.35), blurRadius: pending ? 10 : 4),
        ],
      ),
      child: const JokerGlyph(animate: false),
    );
  }
}

/// 광대 모자 로티 문양 — 손패 조커·배지·비행 뒷면이 전부 이 하나를 쓴다.
/// [animate]가 false면 첫 프레임 정지(배지 여러 개가 동시에 뛰면 산만하고, 골든도 흔들린다).
class JokerGlyph extends StatelessWidget {
  const JokerGlyph({super.key, this.animate = true});
  final bool animate;

  @override
  Widget build(BuildContext context) => RepaintBoundary(
        // 손패의 조커는 계속 뛰므로 자기 레이어에서만 다시 칠한다(보드로 번지지 않게).
        child: Lottie.asset(
          'assets/lottie/joker_card.json',
          animate: animate,
          repeat: true,
          fit: BoxFit.contain,
          frameRate: const FrameRate(30),
        ),
      );
}

/// 조커 뒷면 — 강타가 상대 카드로 날아갈 때 쓰는 비행체(뒷면 위 크림 원 + 광대).
class JokerBack extends StatelessWidget {
  const JokerBack({super.key, required this.size});
  final double size;

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        CardBack(size: size),
        Container(
          width: size * 0.5,
          height: size * 0.5,
          padding: EdgeInsets.all(size * 0.05),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.cardBody,
            border: Border.all(color: AppColors.gold, width: 1.6),
          ),
          child: const JokerGlyph(),
        ),
      ],
    );
  }
}
