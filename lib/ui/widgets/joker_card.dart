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
              child: Lottie.asset(
                'assets/lottie/joker_card.json',
                animate: animate,
                repeat: true,
                fit: BoxFit.contain,
              ),
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
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: JokerColors.purpleDeep,
        border: Border.all(color: pending ? color : JokerColors.gold, width: pending ? 2.2 : 1.4),
        boxShadow: [
          BoxShadow(color: color.withValues(alpha: pending ? 0.7 : 0.35), blurRadius: pending ? 10 : 4),
        ],
      ),
      child: const CustomPaint(painter: _StarPainter(JokerColors.gold, JokerColors.lime)),
    );
  }
}

/// 다섯 꼭짓점 별 + 가운데 점. 회전 없음(정지 화면에서도 같은 모양 — 골든 재현).
class _StarPainter extends CustomPainter {
  const _StarPainter(this.fill, this.dot);
  final Color fill;
  final Color dot;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide * 0.42;
    final path = Path();
    for (var i = 0; i < 10; i++) {
      final a = -math.pi / 2 + i * math.pi / 5;
      final rr = i.isEven ? r : r * 0.45;
      final p = Offset(c.dx + rr * math.cos(a), c.dy + rr * math.sin(a));
      i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
    }
    path.close();
    canvas.drawPath(path, Paint()..color = fill);
    canvas.drawCircle(c, r * 0.16, Paint()..color = dot);
  }

  @override
  bool shouldRepaint(_StarPainter old) => old.fill != fill || old.dot != dot;
}

/// 조커 뒷면 — 강타가 상대 카드로 날아갈 때 쓰는 비행체(보통 뒷면에 보라 링).
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
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: JokerColors.purpleDeep.withValues(alpha: 0.92),
            border: Border.all(color: JokerColors.gold, width: 1.6),
          ),
          child: const CustomPaint(painter: _StarPainter(JokerColors.gold, JokerColors.lime)),
        ),
      ],
    );
  }
}

/// 배지를 칸 왼쪽 아래 모서리에 얹는다(오른쪽 위는 비공개권 칩 자리).
Widget withJokerBadge(Widget card, {required double cell, required Color color, bool pending = false}) {
  return Stack(
    fit: StackFit.expand,
    clipBehavior: Clip.none,
    children: [
      card,
      Align(
        alignment: const Alignment(-0.85, 0.8),
        child: IgnorePointer(child: JokerBadge(size: cell * 0.34, color: color, pending: pending)),
      ),
    ],
  );
}
