import 'dart:math';

import 'package:flutter/material.dart';

/// 타격·강조 순간의 오버레이 이펙트 모음.
///
/// 전부 [flyCard]와 같은 계약이다 — 오버레이에 스스로 올라갔다 스스로 정리되고,
/// 실패해도 게임 상태를 건드리지 않는다. 색은 테마(브라스/골드)를 기본으로 쓴다.
///
/// 절제 원칙: 이펙트는 **이벤트당 1회, 300~450ms 안에 끝난다.** 길거나 겹치면
/// 화려한 게 아니라 싸구려가 된다.

const _gold = Color(0xFFD8B24A);

/// 타격 지점의 **히트 플래시** — 흰 코어 + 금색 링이 퍼지며 사라진다. (~160ms)
Future<void> hitFlash({
  required OverlayState overlay,
  required TickerProvider vsync,
  required Rect at,
  Color color = _gold,
}) {
  return _run(overlay, vsync, const Duration(milliseconds: 160), (t) {
    return Positioned.fromRect(
      rect: at.inflate(at.width * 0.9 * t),
      child: IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            // 코어는 빨리 죽고 링은 끝까지 살아 "번쩍"의 잔상만 남긴다.
            gradient: RadialGradient(
              colors: [
                Colors.white.withValues(alpha: (1 - t) * (1 - t) * 0.95),
                color.withValues(alpha: (1 - t) * 0.55),
                color.withValues(alpha: 0),
              ],
              stops: const [0, 0.55, 1],
            ),
          ),
        ),
      ),
    );
  });
}

/// 타격 지점에서 **파편이 튀는** 스파크 버스트. 카드 조각(흰 사각형)과
/// 금색 불꽃이 섞여 날아가며 중력을 받는다. (~420ms)
Future<void> sparkBurst({
  required OverlayState overlay,
  required TickerProvider vsync,
  required Rect at,
  Color color = _gold,
  int count = 14,
}) {
  // 타격 위치 기반 결정적 시드 — 칸마다 파편 모양이 다르면서도 골든 캡처가 재현된다.
  final rng = Random(at.center.dx.round() * 31 + at.center.dy.round());
  final sparks = List.generate(count, (i) {
    final angle = rng.nextDouble() * 2 * pi;
    final speed = at.width * (1.6 + rng.nextDouble() * 2.6);
    return _Spark(
      dir: Offset(cos(angle), sin(angle) * 0.85 - 0.35), // 살짝 위로 치우침
      speed: speed,
      size: at.width * (0.05 + rng.nextDouble() * 0.07),
      spin: (rng.nextDouble() - 0.5) * 10,
      isShard: i.isEven, // 절반은 카드 조각, 절반은 불꽃 점
    );
  });
  return _run(overlay, vsync, const Duration(milliseconds: 420), (t) {
    return Positioned.fromRect(
      rect: at.inflate(at.width * 4),
      child: IgnorePointer(
        child: CustomPaint(painter: _SparkPainter(sparks, t, color)),
      ),
    );
  });
}

/// 쉴드로 **잠기는 순간**의 금색 글린트 링 — 칸 테두리에서 수축하며 또렷해진다. (~300ms)
Future<void> shieldGlint({
  required OverlayState overlay,
  required TickerProvider vsync,
  required Rect at,
  Color color = _gold,
}) {
  return _run(overlay, vsync, const Duration(milliseconds: 300), (t) {
    // 바깥에서 카드 크기로 조여든다 — "고정됐다"는 방향성.
    final rect = at.inflate(at.width * 0.5 * (1 - t));
    return Positioned.fromRect(
      rect: rect,
      child: IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: color.withValues(alpha: (t < 0.7 ? 1 : (1 - t) / 0.3) * 0.9),
              width: 2.5,
            ),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: (1 - t) * 0.5),
                blurRadius: 14,
              ),
            ],
          ),
        ),
      ),
    );
  });
}

class _Spark {
  const _Spark(
      {required this.dir,
      required this.speed,
      required this.size,
      required this.spin,
      required this.isShard});
  final Offset dir;
  final double speed;
  final double size;
  final double spin;
  final bool isShard;
}

class _SparkPainter extends CustomPainter {
  const _SparkPainter(this.sparks, this.t, this.color);
  final List<_Spark> sparks;
  final double t;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final gravity = size.height * 0.18;
    final fade = (1 - t).clamp(0.0, 1.0);
    for (final s in sparks) {
      // easeOut 감속 + 중력 낙하.
      final travel = 1 - (1 - t) * (1 - t);
      final pos = center +
          s.dir * s.speed * travel +
          Offset(0, gravity * t * t);
      final paint = Paint()
        ..color = (s.isShard ? Colors.white : color).withValues(alpha: fade * 0.9);
      if (s.isShard) {
        canvas.save();
        canvas.translate(pos.dx, pos.dy);
        canvas.rotate(s.spin * t);
        canvas.drawRect(
            Rect.fromCenter(
                center: Offset.zero, width: s.size, height: s.size * 1.5),
            paint);
        canvas.restore();
      } else {
        canvas.drawCircle(pos, s.size * 0.55 * fade + 0.5, paint);
      }
    }
  }

  @override
  bool shouldRepaint(_SparkPainter old) => old.t != t;
}

/// 공통 러너: 컨트롤러 하나로 [builder]를 구동하는 오버레이 엔트리를 올렸다가
/// 끝나면 스스로 정리한다.
Future<void> _run(
  OverlayState overlay,
  TickerProvider vsync,
  Duration duration,
  Widget Function(double t) builder,
) async {
  final controller = AnimationController(vsync: vsync, duration: duration);
  final anim = CurvedAnimation(parent: controller, curve: Curves.easeOut);
  late OverlayEntry entry;
  entry = OverlayEntry(
    builder: (context) => AnimatedBuilder(
      animation: anim,
      builder: (context, _) => builder(anim.value),
    ),
  );
  overlay.insert(entry);
  try {
    await controller.forward();
  } finally {
    entry.remove();
    controller.dispose();
  }
}
