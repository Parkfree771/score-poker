import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme.dart';

/// 덮인 카드의 두 가지 기분. **배지·아이콘 대신 이 차이가 상태를 말한다.**
enum VeilMood {
  /// 그냥 덮여 있는 카드 — 죽은 듯 무거운 어둠이 느리게 흐른다.
  still,

  /// 지금 내 코인으로 열 수 있는 카드 — 어둠이 안절부절 못하고(두 배 빠르게),
  /// 갈라진 틈으로 **브라스 불씨**가 새어 나오며 테두리 안쪽 잔광이 숨 쉰다.
  restless,
}

/// **검은 일렁거림** — 비공개권으로 덮어 둔 카드 위에서 흐르는 어둠.
///
/// 숨긴 카드를 아이콘(눈 배지, 코너 마커 따위)으로 표시하지 않는다. 카드가 **그늘 속에
/// 가라앉아 있고 그 안에서 뭔가 일렁인다**로 보여준다 — 무엇이 덮여 있는지는 몰라도
/// 덮을 만한 것이라는 인상이 남아야 한다.
///
/// 그리는 것:
/// 1. 카드를 눌러 앉히는 **바닥 어둠**(느린 호흡으로 짙어졌다 옅어진다)
/// 2. 그 어둠을 **갉아내며 흘러가는 틈 두 줄**(사인파, 반대 방향·다른 속도).
///    어둠 위에 더 어두운 띠를 얹으면 작은 카드에선 그냥 검은 판이 된다 —
///    반대로 어둠을 덜어내야 아래 카드백이 언뜻 비치며 움직임이 읽힌다.
/// 3. 가장자리로 갈수록 깊어지는 어둠
/// 4. [VeilMood.restless]면 그 틈을 따라 흐르는 **불씨**와 테두리 잔광
///
/// [phase]로 카드마다 위상을 어긋나게 해 여러 장이 한 박자로 뛰지 않게 한다
/// (같은 칸이면 같은 값이어야 하므로 난수가 아니라 좌표에서 뽑아 넘긴다).
class VeilShimmer extends StatefulWidget {
  const VeilShimmer({
    super.key,
    required this.radius,
    this.phase = 0,
    this.intensity = 1,
    this.mood = VeilMood.still,
  });

  /// 카드 모서리 둥글기(카드 폭 × 0.16). 그늘이 카드 밖으로 새지 않게 잘라낸다.
  final double radius;

  /// 0~1. 카드마다 다른 시작 위상.
  final double phase;

  /// 어둠의 세기(0~1). 내 카드처럼 내용을 읽어야 하는 쪽은 조금 낮춘다.
  final double intensity;

  final VeilMood mood;

  @override
  State<VeilShimmer> createState() => _VeilShimmerState();
}

class _VeilShimmerState extends State<VeilShimmer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: _durationFor(widget.mood),
  )..repeat();

  /// 열 수 있는 카드는 눈에 띄게 빠르다 — 같은 어둠인데 안절부절 못한다.
  static Duration _durationFor(VeilMood mood) => switch (mood) {
        VeilMood.still => const Duration(milliseconds: 5200),
        VeilMood.restless => const Duration(milliseconds: 2400),
      };

  @override
  void didUpdateWidget(VeilShimmer old) {
    super.didUpdateWidget(old);
    if (old.mood != widget.mood) {
      // 코인을 다 쓰면 열 수 없게 되고, 그 순간 카드는 다시 잠잠해진다.
      _c
        ..duration = _durationFor(widget.mood)
        ..repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      // 이 칸만 다시 그리게 격리한다 — 보드 전체가 매 프레임 리페인트되면 안 된다.
      child: RepaintBoundary(
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, _) => CustomPaint(
            painter: _VeilPainter(
              t: _c.value,
              phase: widget.phase,
              intensity: widget.intensity,
              radius: widget.radius,
              mood: widget.mood,
            ),
            size: Size.infinite,
          ),
        ),
      ),
    );
  }
}

class _VeilPainter extends CustomPainter {
  _VeilPainter({
    required this.t,
    required this.phase,
    required this.intensity,
    required this.radius,
    required this.mood,
  });

  final double t; // 0~1 루프
  final double phase;
  final double intensity;
  final double radius;
  final VeilMood mood;

  static const _shadow = AppColors.ink; // 웜 블랙 — 순수 검정은 카드에서 구멍처럼 보인다
  static const _ember = AppColors.gold; // 틈으로 새는 불씨

  bool get _restless => mood == VeilMood.restless;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    if (w <= 0 || h <= 0) return;
    final rect = Rect.fromLTWH(0, 0, w, h);
    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(radius));
    const tau = math.pi * 2;
    final p = phase * tau;

    canvas.save();
    canvas.clipRRect(rrect);

    // 틈의 진행도. **깊이는 두 기분이 같다** — 열 수 있는 카드라고 어둠을 걷어내면
    // 카드가 훤해져서 "덮여 있다"가 사라진다. 차이는 속도와 불씨로만 준다.
    final travelA = (t + phase) % 1.0;
    final travelB = 1 - (t * 0.63 + phase) % 1.0;
    const deep = 0.66;
    const shallow = 0.44;

    canvas.saveLayer(rect, Paint());

    // 1) 바닥 어둠 — 느린 호흡(0.53 ↔ 0.67).
    final breathe = 0.60 + 0.07 * math.sin(t * tau * 2 + p);
    canvas.drawRect(
        rect, Paint()..color = _shadow.withValues(alpha: breathe * intensity));

    // 2) 어둠을 갉아내며 흐르는 틈 두 줄(서로 반대 방향·다른 속도).
    _rift(canvas, size,
        travel: travelA, wave: 1.5, thick: 0.44, strength: deep, dir: 1, p: p,
        erase: true);
    _rift(canvas, size,
        travel: travelB, wave: 2.4, thick: 0.28, strength: shallow, dir: -1,
        p: p * 1.7, erase: true);

    canvas.restore(); // saveLayer

    // 3) 가장자리로 갈수록 깊어지는 어둠 — 카드가 그늘에 잠긴 인상.
    canvas.drawRect(
      rect,
      Paint()
        ..shader = RadialGradient(
          radius: 0.95,
          colors: [
            _shadow.withValues(alpha: 0),
            _shadow.withValues(alpha: 0.34 * intensity),
          ],
        ).createShader(rect),
    );

    // 4) 열 수 있는 카드: 갈라진 틈을 따라 불씨가 흐르고 테두리 잔광이 숨 쉰다.
    //    코너 배지 대신 **이 빛이 신호**다.
    if (_restless) {
      _rift(canvas, size,
          travel: travelA, wave: 1.5, thick: 0.44, strength: 0.20, dir: 1, p: p,
          erase: false);
      _rift(canvas, size,
          travel: travelB, wave: 2.4, thick: 0.28, strength: 0.11, dir: -1,
          p: p * 1.7, erase: false);

      // 불씨는 **불씨**여야 한다 — 세게 주면 카드가 금색으로 물들어 어둠이 사라진다.
      final glow = 0.13 + 0.10 * math.sin(t * tau + p);
      canvas.drawRRect(
        rrect.deflate(radius * 0.34),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = radius * 0.30
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, radius * 0.42)
          ..color = _ember.withValues(alpha: glow),
      );
    }
    canvas.restore();
  }

  /// 흐르는 틈 하나.
  ///
  /// [erase]면 어둠을 덜어내고(BlendMode.dstOut), 아니면 그 자리에 불씨를 얹는다.
  /// [travel] 0~1이 카드를 가로질러 지나가는 진행도, [wave]는 물결 수,
  /// [thick]은 카드 높이 대비 두께.
  void _rift(
    Canvas canvas,
    Size size, {
    required double travel,
    required double wave,
    required double thick,
    required double strength,
    required int dir,
    required double p,
    required bool erase,
  }) {
    final w = size.width, h = size.height;
    final band = h * thick;
    final centerY = -band + travel * (h + band * 2);
    final amp = h * 0.09;

    final path = Path()..moveTo(0, centerY);
    const steps = 14;
    for (var i = 0; i <= steps; i++) {
      final x = w * i / steps;
      path.lineTo(
          x,
          centerY +
              amp * math.sin(wave * math.pi * 2 * (i / steps) + p * dir + travel * 5));
    }
    for (var i = steps; i >= 0; i--) {
      final x = w * i / steps;
      path.lineTo(
          x,
          centerY +
              band +
              amp * math.sin(wave * math.pi * 2 * (i / steps) + p * dir - travel * 4));
    }
    path.close();

    // 앞쪽이 진하고 뒤로 길게 끌리는 꼬리 — 흘러가는 방향이 읽힌다.
    final base = erase ? const Color(0xFF000000) : _ember;
    canvas.drawPath(
      path,
      Paint()
        ..blendMode = erase ? BlendMode.dstOut : BlendMode.srcOver
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            base.withValues(alpha: 0),
            base.withValues(alpha: strength),
            base.withValues(alpha: strength * 0.55),
            base.withValues(alpha: 0),
          ],
          stops: const [0.0, 0.38, 0.62, 1.0],
        ).createShader(Rect.fromLTWH(0, centerY, w, band)),
    );
  }

  @override
  bool shouldRepaint(covariant _VeilPainter old) =>
      old.t != t ||
      old.intensity != intensity ||
      old.radius != radius ||
      old.mood != mood;
}

/// 칸 좌표에서 뽑는 고정 위상 — 같은 칸은 늘 같은 박자, 이웃 칸과는 어긋난다.
double veilPhaseFor(int row, int col) => ((row * 7 + col * 3) % 10) / 10.0;
