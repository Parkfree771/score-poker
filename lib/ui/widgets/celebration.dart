import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../theme.dart';

/// 족보 완성 연출: 무광 딥 버건디 3D 타이포 배너 + 배경 딤 + 축포 버스트.
/// 광택·하이라이트 없이 두께와 그림자로만 입체를 낸다(근엄한 매트 룩).
/// 게임 진행을 막지 않는다 — 입력은 전부 통과, 배너 0.95초 / 축포 1.3초 뒤 자동 소멸.
///
/// 배너는 항상 버건디 — [accent]는 축포 색의 기준색만 담당
/// (나 = 브라스 골드, 상대 = 페르소나 색). [burstAlignment]는 완성한 쪽 필드 위치.
class HandCelebration extends StatelessWidget {
  const HandCelebration({
    super.key,
    required this.title,
    this.subtitle = '',
    this.accent = AppColors.gold,
    this.burstAlignment = const Alignment(0, 0.45),
    this.bannerAlignment = const Alignment(0, -0.18),
    this.seed = 0,
    this.onDone,
  });

  final String title; // 예: 'FOUR CARD!'
  final String subtitle; // 예: '포카드'
  final Color accent;
  final Alignment burstAlignment;
  final Alignment bannerAlignment;
  final int seed;
  final VoidCallback? onDone;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      // Material로 감싸 어디에 올려도 텍스트 스타일이 보장되게 한다.
      child: Material(
        type: MaterialType.transparency,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ConfettiBurst(alignment: burstAlignment, accent: accent, seed: seed),
            _Banner(
                title: title, subtitle: subtitle, alignment: bannerAlignment, onDone: onDone),
          ],
        ),
      ),
    );
  }
}

// ---- 배너 ----

class _Banner extends StatefulWidget {
  const _Banner(
      {required this.title, required this.subtitle, required this.alignment, this.onDone});
  final String title;
  final String subtitle;
  final Alignment alignment;
  final VoidCallback? onDone;

  @override
  State<_Banner> createState() => _BannerState();
}

class _BannerState extends State<_Banner> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 950))
        ..addStatusListener((s) {
          if (s == AnimationStatus.completed) widget.onDone?.call();
        })
        ..forward();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final t = _c.value;
        // 등장: 크게 박혀 들어옴(오버슛 없이 급감속 — "딱" 나오는 인상)
        final tIn = Curves.easeOutExpo.transform((t / 0.12).clamp(0.0, 1.0));
        final scale = 1.9 - 0.9 * tIn;
        // 퇴장: 짧게 떠오르며 사라짐
        final tOut = Curves.easeIn.transform(((t - 0.74) / 0.26).clamp(0.0, 1.0));
        final opacity = (tIn * (1 - tOut)).clamp(0.0, 1.0);

        return Opacity(
          opacity: opacity,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // 배경 딤: 배너 뒤 보드를 살짝 눌러 글자를 앞으로 분리(무광 라디얼).
              Align(
                alignment: widget.alignment,
                child: Transform.scale(
                  scaleX: 2.1,
                  child: Container(
                    width: 320,
                    height: 320,
                    decoration: const BoxDecoration(
                      gradient: RadialGradient(
                        colors: [Color(0x8C080E0A), Color(0x00080E0A)],
                        stops: [0, 0.72],
                      ),
                    ),
                  ),
                ),
              ),
              Align(
                alignment: widget.alignment,
                child: Transform.translate(
                  offset: Offset(0, -30 * tOut),
                  child: Transform.scale(
                    scale: scale,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // 화면 폭을 넘는 긴 족보명은 두께·그림자째 자동 축소
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: FittedBox(fit: BoxFit.scaleDown, child: _title()),
                        ),
                        if (widget.subtitle.isNotEmpty) ...[
                          const SizedBox(height: 14),
                          // 다크 리본(불투명) — 어떤 배경 위에서도 읽힌다.
                          Container(
                            padding: const EdgeInsets.fromLTRB(20, 6, 10, 7),
                            decoration: BoxDecoration(
                              color: const Color(0xFF240705),
                              borderRadius: BorderRadius.circular(99),
                              boxShadow: const [
                                BoxShadow(
                                    color: Colors.black54, offset: Offset(0, 4), blurRadius: 8),
                              ],
                            ),
                            child: Text(
                              widget.subtitle,
                              style: const TextStyle(
                                color: Color(0xFFD9CFB6),
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 10,
                                height: 1.2,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// 무광 딥 버건디 3D: 플랫한 버건디 면 아래로 갈수록 어두워지는 두께를
  /// 14px 쌓고, 발밑에 깊은 소프트 섀도. 광택·테두리·그라데이션 없음.
  Widget _title() {
    const face = Color(0xFF7E1F15); // 무광 딥 버건디 면
    const depthTop = Color(0xFF47100A); // 두께 최상단(면 바로 아래)
    const depthBottom = Color(0xFF0F0301); // 두께 최하단
    const depth = 14; // 3D 돌출량(px)
    // 슬라브 폰트에는 한글이 없다 — 라틴 제목만 슬라브, 그 외(한글 족보명)는
    // 기본 서체의 최고 굵기로. 두께 쌓기(3D)는 서체와 무관하게 먹는다.
    final latin = RegExp(r'^[A-Za-z0-9 !?.\-]+$').hasMatch(widget.title);
    final style = TextStyle(
      fontFamily: latin ? 'AlfaSlabOne' : null,
      fontWeight: latin ? null : FontWeight.w900,
      fontSize: latin ? 58 : 52,
      letterSpacing: latin ? 1 : 2,
      height: 1.0,
    );
    Text fillText(Color color) => Text(widget.title, style: style.copyWith(color: color));
    Widget at(double dy, Widget child) =>
        Transform.translate(offset: Offset(0, dy), child: child);

    return Stack(
      clipBehavior: Clip.none, // 섀도(dy 30)가 텍스트 박스 밖까지 나간다
      children: [
        // 바닥 소프트 섀도 — 멀리 떨어뜨려 블록이 앞으로 떠 보이게.
        at(
          30,
          ImageFiltered(
            imageFilter: ui.ImageFilter.blur(sigmaX: 14, sigmaY: 14),
            child: Opacity(opacity: 0.55, child: fillText(Colors.black)),
          ),
        ),
        // 아래로 갈수록 어두워지는 매트 두께(딱딱한 슬라브)
        for (var d = depth; d >= 1; d--)
          at(d.toDouble(), fillText(Color.lerp(depthTop, depthBottom, (d - 1) / (depth - 1))!)),
        fillText(face),
      ],
    );
  }
}

// ---- 축포 ----

/// 한 지점에서 위로 터지는 축포. 색종이 조각(스트립) + 불꽃(점)의 물리 시뮬레이션.
class ConfettiBurst extends StatefulWidget {
  const ConfettiBurst({
    super.key,
    required this.alignment,
    required this.accent,
    this.seed = 0,
    this.particleCount = 46,
  });

  final Alignment alignment;
  final Color accent;
  final int seed;
  final int particleCount;

  @override
  State<ConfettiBurst> createState() => _ConfettiBurstState();
}

class _ConfettiBurstState extends State<ConfettiBurst> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1300))..forward();
  late final List<_Particle> _particles = _spawn();

  List<_Particle> _spawn() {
    final rng = math.Random(widget.seed);
    final palette = [
      widget.accent,
      Color.lerp(widget.accent, Colors.white, 0.5)!,
      AppColors.gold,
      AppColors.goldSoft,
      AppColors.cardBody,
    ];
    return List.generate(widget.particleCount, (i) {
      // 위쪽 부채꼴(±55°)로 발사. 속도/크기/회전은 개체마다 다르게.
      final angle = -math.pi / 2 + (rng.nextDouble() - 0.5) * (math.pi * 0.62);
      final speed = 260 + rng.nextDouble() * 480;
      return _Particle(
        velocity: Offset(math.cos(angle), math.sin(angle)) * speed,
        size: 5.5 + rng.nextDouble() * 6,
        rotation: rng.nextDouble() * math.pi * 2,
        spin: (rng.nextDouble() - 0.5) * 14,
        color: palette[rng.nextInt(palette.length)],
        isSpark: i % 6 == 0, // 1/6은 반짝이 점
        delay: rng.nextDouble() * 0.06,
      );
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) => CustomPaint(
          painter: _ConfettiPainter(_particles, _c.value, widget.alignment),
          size: Size.infinite,
        ),
      ),
    );
  }
}

class _Particle {
  const _Particle({
    required this.velocity,
    required this.size,
    required this.rotation,
    required this.spin,
    required this.color,
    required this.isSpark,
    required this.delay,
  });

  final Offset velocity; // 초기 속도(px/s)
  final double size;
  final double rotation; // 초기 회전
  final double spin; // 회전 속도(rad/s)
  final Color color;
  final bool isSpark;
  final double delay; // 발사 시차(초, 0~0.06)
}

class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter(this.particles, this.t, this.alignment);

  final List<_Particle> particles;
  final double t; // 0~1
  final Alignment alignment;

  static const _duration = 1.3; // 초
  static const _gravity = 1150.0; // px/s²
  static const _drag = 1.6; // 공기저항 계수

  @override
  void paint(Canvas canvas, Size size) {
    final origin = Offset(
      size.width * (alignment.x + 1) / 2,
      size.height * (alignment.y + 1) / 2,
    );
    final paint = Paint();

    for (final p in particles) {
      final tt = (t * _duration - p.delay).clamp(0.0, _duration);
      if (tt <= 0) continue;
      // 감쇠 적분: v(t) = v0·e^(-k·t) → 변위 = v0·(1-e^(-k·t))/k, 중력은 그대로 누적
      final damp = (1 - math.exp(-_drag * tt)) / _drag;
      final pos = origin +
          p.velocity * damp +
          Offset(0, 0.5 * _gravity * tt * tt);

      final life = tt / _duration;
      final opacity = life < 0.62 ? 1.0 : (1 - (life - 0.62) / 0.38);
      paint.color = p.color.withValues(alpha: opacity.clamp(0.0, 1.0));

      if (p.isSpark) {
        canvas.drawCircle(pos, p.size * 0.38, paint);
        continue;
      }
      canvas
        ..save()
        ..translate(pos.dx, pos.dy)
        ..rotate(p.rotation + p.spin * tt);
      final rect = RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset.zero, width: p.size, height: p.size * 2.2),
        const Radius.circular(2),
      );
      canvas
        ..drawRRect(rect, paint)
        ..restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter old) => old.t != t;
}
