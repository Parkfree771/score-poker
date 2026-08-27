import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

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

/// 손패의 조커 카드. 카드 프레임은 다른 카드와 같고, 안쪽이 보라 바탕 + 회전하는
/// 금빛 별 + "JOKER" 글자다. 크기는 [CardFace]와 같은 규칙([CardFace.heightFor]).
class JokerFace extends StatelessWidget {
  const JokerFace({super.key, required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    final w = size, h = CardFace.heightFor(size);
    return SizedBox(
      width: w,
      height: h,
      child: Stack(
        children: [
          Positioned.fill(
            child: SvgPicture(cardFrameLoader('#2e1348'), fit: BoxFit.fill),
          ),
          // 프레임 안쪽 보라 면.
          Positioned.fill(
            child: Padding(
              padding: EdgeInsets.all(w * 0.11),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(w * 0.1),
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [JokerColors.purple, JokerColors.purpleDeep],
                  ),
                ),
              ),
            ),
          ),
          Align(
            alignment: const Alignment(0, -0.18),
            child: CustomPaint(
              size: Size(w * 0.5, w * 0.5),
              painter: const _StarPainter(JokerColors.gold, JokerColors.lime),
            ),
          ),
          Align(
            alignment: const Alignment(0, 0.66),
            child: Text('JOKER',
                style: TextStyle(
                    color: JokerColors.gold,
                    fontWeight: FontWeight.w900,
                    fontSize: w * 0.17,
                    letterSpacing: w * 0.012,
                    height: 1)),
          ),
        ],
      ),
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
