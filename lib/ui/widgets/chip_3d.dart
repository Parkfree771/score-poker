import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

import '../../domain/card.dart';
import 'card_back.dart';
import 'card_face.dart';
import 'veil_chip.dart' show ChipPainter;

/// 열어보기 연출의 **3D 칩** — 두께가 있는 원반을 정사영으로 그린다.
///
/// 칩은 지름 2r, 두께 h의 원반. [pitch]만큼 [axisAngle] 축(화면 평면 안)을 중심으로
/// 기울면 앞면은 세로가 |cos pitch|로 눌린 타원이 되고, 그 아래로 옆면 띠가
/// h·|sin pitch| 높이만큼 드러난다. 옆면에는 카지노 칩의 에지 스팟(크림 줄)이
/// 각도에 맞춰 흐르고, [light] 방향으로 하이라이트/그늘이 진다.
///
/// [spin]은 칩 면 안에서의 회전(스페이드가 돈다). 세 회전이 합쳐지면 던져진 칩이
/// 공중에서 구르는 것처럼 보인다.
class Chip3DPainter extends CustomPainter {
  const Chip3DPainter({
    required this.ring,
    this.pitch = 0,
    this.axisAngle = 0,
    this.spin = 0,
    this.thickness = 0.18,
    this.light = const Offset(-0.6, -0.8),
    this.shadow = 0,
  });

  final Color ring;
  final double pitch;
  final double axisAngle;
  final double spin;

  /// 두께 / 반지름.
  final double thickness;

  /// 조명 방향(화면 좌표). 왼쪽 위 기본.
  final Offset light;

  /// 0~1: 칩 바로 아래 접촉 그림자 세기(착지·안착 시).
  final double shadow;

  static const _edgeDark = Color(0xFF0B0A0C);
  static const _edgeMid = Color(0xFF34303A);
  static const _cream = Color(0xFFF1E6C8);

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.width / 2;
    final h = r * thickness;
    final cosP = math.cos(pitch), sinP = math.sin(pitch);
    final k = cosP.abs(); // 세로 압축률
    final band = h * sinP.abs(); // 보이는 옆면 높이

    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);

    // 접촉 그림자(칩 아래 바닥).
    if (shadow > 0) {
      canvas.drawOval(
        Rect.fromCenter(
            center: Offset(0, r * 0.14), width: r * 2.1, height: r * 2.1 * k + band),
        Paint()
          ..color = Colors.black.withValues(alpha: 0.45 * shadow)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.12),
      );
    }

    canvas.rotate(axisAngle);
    // 보이는 면은 축 좌표의 위쪽(-y), 옆면 띠는 그 아래로 드러난다.
    final faceY = -band / 2, backY = band / 2;
    final faceRect =
        Rect.fromCenter(center: Offset(0, faceY), width: 2 * r, height: 2 * r * k);
    final backRect =
        Rect.fromCenter(center: Offset(0, backY), width: 2 * r, height: 2 * r * k);

    // 축 회전 후 좌표계에서의 조명 x 성분(옆면 좌우 명암).
    final lx = light.dx * math.cos(-axisAngle) - light.dy * math.sin(-axisAngle);

    if (band > 0.2) {
      // 옆면 = 뒷면 타원 ∪ 가운데 직사각형 (앞면 타원이 위를 덮는다).
      final side = Path()
        ..addOval(backRect)
        ..addRect(Rect.fromLTRB(-r, faceY, r, backY));
      final sideBounds = Rect.fromLTRB(-r, faceY - r * k, r, backY + r * k);
      canvas.drawPath(
        side,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment(-lx.sign, 0),
            end: Alignment(lx.sign, 0),
            colors: const [_edgeMid, _edgeDark, _edgeMid, _edgeDark],
            stops: const [0, 0.38, 0.72, 1],
          ).createShader(sideBounds),
      );
      // 에지 스팟: 림 각도 φ의 크림 줄 — 보이는 반원(sinφ·sinP>0)만.
      canvas.save();
      canvas.clipPath(side);
      final creamPaint = Paint()..color = _cream.withValues(alpha: 0.92);
      const spots = 6;
      const half = math.pi / spots * 0.42;
      for (var i = 0; i < spots; i++) {
        final phi = spin + i * 2 * math.pi / spots;
        final s = math.sin(phi);
        if (s * sinP <= 0) continue;
        final x0 = r * math.cos(phi - half), x1 = r * math.cos(phi + half);
        final l = math.min(x0, x1), w = (x1 - x0).abs();
        final yOnFace = faceY + r * k * s.abs();
        final yOnBack = backY + r * k * s.abs();
        final stripe = Rect.fromLTRB(l, yOnFace - 0.5, l + w, yOnBack + 0.5);
        canvas.drawRect(stripe, creamPaint);
        if (math.cos(phi) * lx < 0) {
          canvas.drawRect(stripe, Paint()..color = Colors.black.withValues(alpha: 0.35));
        }
      }
      canvas.restore();
    }

    // 앞면: 칩 그림을 세로 압축 + 면내 회전으로. 뒷면이 보일 땐 좌우 반전(양면 칩).
    canvas.save();
    canvas.translate(0, faceY);
    canvas.scale(1, math.max(k, 0.02));
    canvas.rotate(spin);
    if (cosP < 0) canvas.scale(-1, 1);
    canvas.translate(-r, -r);
    ChipPainter(ring: ring).paint(canvas, Size.square(2 * r));
    canvas.restore();

    // 조명: 면의 스페큘러 + 림 베벨. 눕을수록 빛을 덜 받는다.
    final lit = (0.55 + 0.45 * k).clamp(0.0, 1.0);
    canvas.save();
    canvas.clipPath(Path()..addOval(faceRect));
    canvas.drawRect(
      faceRect,
      Paint()
        ..shader = RadialGradient(
          center: Alignment(light.dx * 0.55, light.dy * 0.55),
          radius: 0.95,
          colors: [
            Colors.white.withValues(alpha: 0.40 * lit),
            Colors.white.withValues(alpha: 0.06 * lit),
            Colors.black.withValues(alpha: 0.30),
          ],
          stops: const [0, 0.42, 1],
        ).createShader(faceRect),
    );
    canvas.drawOval(
      faceRect.deflate(r * 0.06),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.05
        ..shader = SweepGradient(
          transform: GradientRotation(math.atan2(light.dy, light.dx) - 0.6),
          colors: [
            Colors.white.withValues(alpha: 0.8 * lit),
            Colors.white.withValues(alpha: 0),
            Colors.white.withValues(alpha: 0),
            Colors.white.withValues(alpha: 0.35 * lit),
            Colors.white.withValues(alpha: 0),
            Colors.white.withValues(alpha: 0.8 * lit),
          ],
          stops: const [0, 0.18, 0.5, 0.62, 0.8, 1],
        ).createShader(faceRect),
    );
    canvas.restore();
    canvas.restore();
  }

  @override
  bool shouldRepaint(Chip3DPainter o) =>
      o.ring != ring ||
      o.pitch != pitch ||
      o.axisAngle != axisAngle ||
      o.spin != spin ||
      o.shadow != shadow ||
      o.thickness != thickness;
}

/// 한 프레임의 칩 포즈.
class _Pose {
  const _Pose({
    required this.center,
    required this.height,
    required this.pitch,
    required this.axisAngle,
    required this.spin,
    this.opacity = 1,
  });

  /// 바닥 위 위치(그림자가 놓이는 곳).
  final Offset center;

  /// 바닥에서 뜬 높이(px) — 원근 스케일·그림자에 쓴다.
  final double height;
  final double pitch, axisAngle, spin, opacity;
}

/// 바닥 그림자 — 뜰수록 옅고 넓어진다.
Widget _groundShadow(_Pose p, double d, double sh) {
  return Positioned(
    left: p.center.dx - d * (0.6 + 0.4 * (1 - sh)),
    top: p.center.dy - d * 0.42,
    width: d * (1.2 + 0.8 * (1 - sh)),
    height: d * 0.84,
    child: IgnorePointer(
      child: Opacity(
        opacity: 0.38 * sh * p.opacity,
        child: DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(colors: [
              Colors.black.withValues(alpha: 0.9),
              Colors.black.withValues(alpha: 0),
            ]),
          ),
        ),
      ),
    ),
  );
}

/// 포즈대로 칩 한 장(+바닥 그림자)을 그린다. [ghost]면 잔상 — 그림자 없이 흐리게.
Widget _chipAt(_Pose p, double d, Color ring, {double ghost = 0}) {
  final scale = 1 + (p.height / 260).clamp(0.0, 0.45); // 원근: 뜰수록 가까워진다
  final sh = (1 - p.height / 110).clamp(0.0, 1.0); // 뜰수록 그림자가 옅고 넓어진다
  final alpha = (ghost > 0 ? ghost : p.opacity).clamp(0.0, 1.0);
  return Stack(children: [
    if (ghost == 0 && sh > 0) _groundShadow(p, d, sh),
    Positioned(
      left: p.center.dx - d / 2,
      top: p.center.dy - p.height - d / 2,
      width: d,
      height: d,
      child: IgnorePointer(
        child: Opacity(
          opacity: alpha,
          child: Transform.scale(
            scale: scale,
            child: CustomPaint(
              painter: Chip3DPainter(
                ring: ring,
                pitch: p.pitch,
                axisAngle: p.axisAngle,
                spin: p.spin,
                shadow: ghost > 0 ? 0 : sh * 0.6,
              ),
            ),
          ),
        ),
      ),
    ),
  ]);
}

Future<void> _runOverlay(
  OverlayState overlay,
  TickerProvider vsync,
  Duration duration,
  Widget Function(double t) build,
) async {
  final c = AnimationController(vsync: vsync, duration: duration);
  late OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => AnimatedBuilder(animation: c, builder: (_, __) => build(c.value)),
  );
  overlay.insert(entry);
  try {
    await c.forward();
  } finally {
    entry.remove();
    c.dispose();
  }
}

/// 비행 중의 칩 스프라이트 — 로티(`chip_spade.json`)의 in-reveal 구간(옆면→정면으로
/// 빙그르 도는 27~66f)을 [t]에 맞춰 재생하고, 주인 색 링을 두른다. 스핀 축이 진행
/// 방향과 직각이 되도록 [angle]만큼 돌린다(굴러가는 바퀴).
class ChipFlightSprite extends StatelessWidget {
  const ChipFlightSprite({super.key, required this.t, required this.ring, this.angle = 0});
  final double t;
  final Color ring;
  final double angle;

  static const _total = 390.0;

  @override
  Widget build(BuildContext context) {
    // 27f(옆면, 스케일인이 끝난 뒤) → 66f(정면): 닿는 프레임에 정확히 정면이 된다.
    final frame = 27 + 39 * t.clamp(0.0, 1.0);
    return Transform.rotate(
      angle: angle,
      child: Stack(fit: StackFit.expand, children: [
        Transform.scale(
          scale: 1.3, // 아이콘 캔버스 여백 보정(레일 칩과 동일)
          child: Lottie.asset(
            'assets/lottie/chip_spade.json',
            controller: AlwaysStoppedAnimation(frame / _total),
            fit: BoxFit.contain,
          ),
        ),
        // 주인 링: 정면에 가까울수록 또렷해진다.
        Opacity(
          opacity: ((t - 0.75) / 0.2).clamp(0.0, 1.0),
          child: DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: ring, width: 2.2),
            ),
          ),
        ),
      ]),
    );
  }
}

/// 칩 **슛** — 레일에서 상대 카드로 **직선으로 쏘아** 날아간다.
///
/// 포물선이 아니다: 출발에서 가속해 끝까지 속도가 살아 있고(easeIn), 뒤로 빛 궤적
/// (진행 방향으로 길게 늘어진 그라데이션)과 잔상이 따라붙는다. 진행 방향과 직각인
/// 축으로 옆면→정면 반 바퀴 돈다. [to]에 닿는 순간 끝난다 — 그 프레임에 "팅".
Future<void> tossChip({
  required OverlayState overlay,
  required TickerProvider vsync,
  required Offset from,
  required Offset to,
  required double diameter,
  required Color ring,
  Duration duration = const Duration(milliseconds: 300),
}) {
  final dir = to - from;
  final dist = dir.distance;
  final ang = math.atan2(dir.dy, dir.dx);
  final unit = dist == 0 ? Offset.zero : dir / dist;

  _Pose poseAt(double t) {
    t = t.clamp(0.0, 1.0);
    // 직선 가속: 처음 살짝 밀렸다가(0.12) 끝으로 갈수록 빨라진다.
    final u = Curves.easeInQuad.transform(t);
    return _Pose(
      center: from + dir * u,
      // 테이블에서 아주 살짝 떠서 간다(그림자만 분리될 정도).
      height: 8 * math.sin(math.pi * t),
      pitch: 2 * math.pi * 2.0 * t + 0.35,
      axisAngle: ang + math.pi / 2,
      spin: 0.8 * t,
    );
  }

  /// 빛 궤적 — 칩 뒤로 늘어진 막대. 속도(du/dt)에 비례해 길어지고 끝은 투명하다.
  Widget streakAt(double t) {
    final p = poseAt(t);
    final speed = 2 * t; // easeInQuad의 미분(0→2)
    final len = (dist * 0.42 * speed).clamp(0.0, 170.0);
    if (len < 2) return const SizedBox.shrink();
    final head = p.center - Offset(0, p.height);
    final center = head - unit * (len / 2);
    final thick = diameter * 0.55;
    return Positioned(
      left: center.dx - len / 2,
      top: center.dy - thick / 2,
      width: len,
      height: thick,
      child: IgnorePointer(
        child: Transform.rotate(
          angle: ang,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(thick),
              gradient: LinearGradient(colors: [
                ring.withValues(alpha: 0),
                ring.withValues(alpha: 0.35),
                Colors.white.withValues(alpha: 0.85),
              ], stops: const [0, 0.55, 1]),
            ),
          ),
        ),
      ),
    );
  }

  Widget spriteAt(double t, {double ghost = 0}) {
    final p = poseAt(t);
    final scale = 1 + (p.height / 260).clamp(0.0, 0.45);
    final sh = (1 - p.height / 110).clamp(0.0, 1.0);
    return Stack(children: [
      if (ghost == 0 && sh > 0) _groundShadow(p, diameter, sh),
      Positioned(
        left: p.center.dx - diameter / 2,
        top: p.center.dy - p.height - diameter / 2,
        width: diameter,
        height: diameter,
        child: IgnorePointer(
          child: Opacity(
            opacity: ghost > 0 ? ghost : 1,
            child: Transform.scale(
              scale: scale,
              child: ChipFlightSprite(t: t, ring: ring, angle: ang + math.pi / 2),
            ),
          ),
        ),
      ),
    ]);
  }

  return _runOverlay(overlay, vsync, duration, (t) {
    return Stack(children: [
      streakAt(t),
      if (t > 0.1) ...[
        spriteAt(t - 0.08, ghost: 0.12),
        spriteAt(t - 0.04, ghost: 0.28),
      ],
      spriteAt(t),
    ]);
  });
}

/// **팅** — 카드에 맞은 칩이 되튀어 오른다.
///
/// 45ms 히트스톱(닿은 자리에서 파르르 떨림) → 큰 바운스(높이 1.5d, 빠른 텀블) →
/// 작은 바운스 둘(높이·거리 감쇠, 회전도 죽는다) → 납작하게 정착·짧게 미끄러지며
/// 사라진다. 되튀는 방향은 날아온 쪽 + 살짝 옆(정면 반사는 어색하다).
/// [onBounce]는 2·3번째 착지 순간에 불린다(틱 소리용). 약 660ms.
Future<void> ricochetChip3D({
  required OverlayState overlay,
  required TickerProvider vsync,
  required Offset at,
  required Offset from,
  required double diameter,
  required Color ring,
  void Function(int bounce)? onBounce,
  Duration duration = const Duration(milliseconds: 660),
  double side = 0.32, // 되튀는 방향의 옆 성분(+오른쪽/−왼쪽). 두 칩을 다른 각도로 보낼 때.
  double reach = 1.0, // 튕겨 나가는 거리 배율.
  Duration delay = Duration.zero, // 출발 지연(두 칩이 같은 프레임에 겹치지 않게).
}) async {
  if (delay > Duration.zero) await Future<void>.delayed(delay);
  final back = from - at;
  final ang = math.atan2(back.dy, back.dx);
  final u = back.distance == 0 ? const Offset(0, 1) : back / back.distance;
  final dirUnit = (u * 0.9 + Offset(-u.dy, u.dx) * side);
  final d = diameter;

  // 구간(ms): 히트스톱 · 바운스1 · 바운스2 · 바운스3 · 정착
  const hold = 45.0, b1 = 240.0, b2 = 140.0, b3 = 90.0;
  final settle = duration.inMilliseconds - hold - b1 - b2 - b3;
  // 각 바운스의 수평 거리·최고 높이
  final dist = [d * 1.7 * reach, d * 0.7 * reach, d * 0.3 * reach];
  final peak = [d * 1.5, d * 0.5, d * 0.16];
  final fired = <int>{};

  _Pose poseAt(double tNorm) {
    var ms = tNorm * duration.inMilliseconds;
    var pos = at;
    var pitch = math.pi / 2; // 닿는 순간 옆면
    // 히트스톱: 제자리에서 떨린다
    if (ms < hold) {
      final j = math.sin(ms / hold * math.pi * 6) * d * 0.05;
      return _Pose(
        center: at + Offset(-dirUnit.dy, dirUnit.dx) * j,
        height: 0,
        pitch: pitch,
        axisAngle: ang + math.pi / 2 + 0.4,
        spin: 0.7,
      );
    }
    ms -= hold;
    final turns = [1.6, 0.6, 0.25];
    final durs = [b1, b2, b3];
    var height = 0.0;
    var travelled = 0.0;
    for (var i = 0; i < 3; i++) {
      if (ms < durs[i]) {
        final f = ms / durs[i];
        height = peak[i] * 4 * f * (1 - f);
        travelled += dist[i] * f;
        pitch += turns[i] * 2 * math.pi * f;
        pos = at + dirUnit * travelled;
        return _Pose(
          center: pos,
          height: height,
          pitch: pitch,
          axisAngle: ang + math.pi / 2 + 0.4,
          spin: 0.7 + 0.4 * tNorm,
        );
      }
      ms -= durs[i];
      travelled += dist[i];
      pitch += turns[i] * 2 * math.pi;
      if (i >= 1 && !fired.contains(i)) {
        fired.add(i);
        onBounce?.call(i);
      }
    }
    // 정착: 남은 회전을 눕히고 살짝 미끄러지며 사라진다
    final f = (ms / settle).clamp(0.0, 1.0);
    final ease = 1 - (1 - f) * (1 - f);
    final folded = math.atan(math.tan(pitch)); // 가장 가까운 눕는 자세
    pos = at + dirUnit * (travelled + d * 0.25 * ease);
    return _Pose(
      center: pos,
      height: 0,
      pitch: folded * (1 - ease),
      axisAngle: ang + math.pi / 2 + 0.4,
      spin: 0.7 + 0.4 * tNorm,
      opacity: f < 0.45 ? 1 : 1 - (f - 0.45) / 0.55,
    );
  }

  return _runOverlay(overlay, vsync, duration, (t) => _chipAt(poseAt(t), d, ring));
}

/// 카드가 **제자리에서 뒤집힌다** — 세로축 회전으로 뒷면이 얇아졌다가 앞면이 펴진다.
/// 오버레이에 그리므로 아래 칸은 이미 앞면으로 바뀌어 있어도 된다(위를 덮는다).
Future<void> flipCardInPlace({
  required OverlayState overlay,
  required TickerProvider vsync,
  required Rect rect,
  required PlayingCard card,
  Duration duration = const Duration(milliseconds: 320),
  double dir = 1,
  Offset kick = Offset.zero, // 맞은 순간 밀렸다 돌아오는 변위(px)
}) {
  return _runOverlay(overlay, vsync, duration, (raw) {
    final t = Curves.easeInOutCubic.transform(raw);
    // 킥: 빠르게 밀렸다(0~25%) 천천히 제자리로.
    final k = raw < 0.25
        ? math.sin(raw / 0.25 * math.pi / 2)
        : math.cos((raw - 0.25) / 0.75 * math.pi / 2);
    final angle = math.pi * t;
    final showBack = angle < math.pi / 2;
    final m = Matrix4.identity()
      ..setEntry(3, 2, 0.0016)
      ..rotateY(dir * (showBack ? angle : angle - math.pi));
    final lift = 6 * math.sin(math.pi * t);
    return Positioned.fromRect(
      rect: rect.translate(kick.dx * k, -lift + kick.dy * k),
      child: IgnorePointer(
        child: Transform(
          alignment: Alignment.center,
          transform: m,
          child: Material(
            type: MaterialType.transparency,
            child: FittedBox(
              fit: BoxFit.contain,
              child:
                  showBack ? const CardBack(size: 120) : CardFace(card: card, size: 120),
            ),
          ),
        ),
      ),
    );
  });
}
