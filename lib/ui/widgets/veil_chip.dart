import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

import '../theme.dart';
import 'board_view.dart' show VeilCoin;

/// 비공개권 = 포커 칩.
///
/// 살아 있는 칩은 로티(`assets/lottie/chip.json`)로 림을 따라 글린트가 천천히 돌고,
/// 누르면 **탁 뒤집힌다**(플립 구간 재생 + 툴팁으로 남은 개수·용법 안내).
/// 쓴 칩은 빈 소켓([VeilCoin]의 socket 분기 재사용)으로 남아 "얼마나 썼는지"가 보인다.
///
/// 로티 마커: `idle` 0~120f(루프), `flip` 120~150f(탭 반응). 파일은 외부에서 받은 것이
/// 아니라 이 프로젝트에서 직접 생성한 자산(`tool/gen_chip_lottie.py`)이다.
class VeilChip extends StatefulWidget {
  const VeilChip({
    super.key,
    required this.size,
    required this.filled,
    this.ring,
    this.label,
    this.onTap,
    this.animate = true,
  });

  final double size;
  final bool filled;

  /// 칩 테두리 색(내/상대 구분). null이면 브라스.
  final Color? ring;

  /// 탭 시 보여줄 안내(남은 개수·용법). null이면 툴팁 없음.
  final String? label;
  final VoidCallback? onTap;

  /// false면 글린트 루프를 돌리지 않는다(판이 끝난 뒤 — 결과 오버레이가 주인공이고,
  /// 무한 애니메이션은 pumpAndSettle을 영원히 붙잡는다).
  final bool animate;

  @override
  State<VeilChip> createState() => VeilChipState();
}

class VeilChipState extends State<VeilChip> with TickerProviderStateMixin {
  static const _idleEnd = 120 / 150;
  late final AnimationController _c = AnimationController(vsync: this);

  /// "팅" — 제자리에서 튀어 오르는 짧은 홉. 열어보기 직전 레일에서 울린다.
  late final AnimationController _hop =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 190));
  bool _loaded = false;

  void _idle() {
    if (!mounted || !_loaded) return;
    if (!widget.animate) {
      _c.stop();
      _c.value = 0;
      return;
    }
    _c.repeat(min: 0, max: _idleEnd, period: _c.duration! * _idleEnd);
  }

  @override
  void didUpdateWidget(VeilChip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.animate != widget.animate) _idle();
  }

  Future<void> _flip() async {
    if (!_loaded) return;
    _c.stop();
    _c.value = _idleEnd;
    await _c.animateTo(1,
        duration: _c.duration! * (1 - _idleEnd), curve: Curves.easeOut);
    _idle();
  }

  /// 제자리 홉. 끝나면 완료되는 Future — 비행은 이 다음에 출발한다.
  Future<void> bounce() async {
    if (!mounted) return;
    _hop.value = 0;
    await _hop.forward();
  }

  void _tap() {
    _flip();
    widget.onTap?.call();
  }

  @override
  void dispose() {
    _c.dispose();
    _hop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    Widget chip = Container(
      key: const ValueKey('chip'),
      width: s,
      height: s,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: widget.ring ?? AppColors.goldSoft, width: 1.6),
        boxShadow: [
          BoxShadow(
              color: AppColors.ink.withValues(alpha: 0.45),
              blurRadius: 4,
              offset: const Offset(0, 1.5)),
        ],
      ),
      child: ClipOval(
        // 칩 로티는 초당 60번 다시 칠해진다 — 보드 레이어로 번지지 않게 격리.
        child: RepaintBoundary(
          child: Lottie.asset(
            'assets/lottie/chip.json',
            controller: _c,
            fit: BoxFit.cover,
            onLoaded: (comp) {
              _c.duration = comp.duration;
              _loaded = true;
              _idle();
            },
          ),
        ),
      ),
    );

    // 홉: 위로 튀었다 내려앉으며 살짝 눌린다(스쿼시). 과장 없이 8px.
    chip = AnimatedBuilder(
      animation: _hop,
      child: chip,
      builder: (context, child) {
        final t = _hop.value;
        final up = math.sin(t * math.pi); // 0→1→0
        final squash = t > 0.85 ? 1 - 0.12 * math.sin((t - 0.85) / 0.15 * math.pi) : 1.0;
        return Transform.translate(
          offset: Offset(0, -8 * up),
          child: Transform.scale(
              scaleX: 1 + (1 - squash) * 0.6, scaleY: squash, child: child),
        );
      },
    );

    if (widget.filled) {
      chip = widget.label == null
          ? GestureDetector(behavior: HitTestBehavior.opaque, onTap: _tap, child: chip)
          : Tooltip(
              message: widget.label!,
              triggerMode: TooltipTriggerMode.tap,
              preferBelow: false,
              onTriggered: _tap,
              child: chip,
            );
    }

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 240),
      transitionBuilder: (child, anim) => ScaleTransition(scale: anim, child: child),
      child: widget.filled ? chip : VeilCoin(size: s, filled: false, ring: widget.ring),
    );
  }
}

/// 카드 위에 **앉아 있는 칩** — 로티 없는 정적 그림(칩 로티 0프레임과 같은 생김새).
///
/// 숨긴 카드(내 봉인·상대 뒷면)와 열어본 카드 위에 놓여 "여기에 비공개권이 쓰였다"를
/// 말한다. 한 판에 최대 여섯 개가 동시에 보이므로 로티 대신 페인터로 그린다.
/// [ring]이 주인(내 색/상대 색)을 말한다.
class ChipBadge extends StatelessWidget {
  const ChipBadge({super.key, required this.size, this.ring, this.land = false});

  final double size;
  final Color? ring;

  /// true면 위에서 내려와 **툭 안착**하는 등장(봉인 지정 순간).
  final bool land;

  @override
  Widget build(BuildContext context) {
    final chip = CustomPaint(
      size: Size.square(size),
      painter: ChipPainter(ring: ring ?? AppColors.goldSoft),
    );
    if (!land) return chip;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutBack,
      builder: (context, t, child) => Opacity(
        opacity: t.clamp(0.0, 1.0),
        child: Transform.scale(scale: 1.6 - 0.6 * t, child: child),
      ),
      child: chip,
    );
  }
}

/// 칩 그림 — 브라스 림 + 크림 노치 8개 + 안쪽 원·링·점. 오버레이 비행에도 쓴다.
class ChipPainter extends CustomPainter {
  const ChipPainter({required this.ring, this.tilt = 0});
  final Color ring;

  /// 비행 중 기울기(0~1) — 가로로 눌려 보이며 "굴러간다".
  final double tilt;

  static const _gold = Color(0xFFD6B25C);
  static const _goldDark = Color(0xFFA8843A);
  static const _cream = Color(0xFFF4E7C2);

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2;
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.scale(1 - 0.35 * tilt, 1);
    // 그림자
    canvas.drawCircle(Offset(0, r * 0.06), r * 0.98,
        Paint()..color = Colors.black.withValues(alpha: 0.32));
    // 림
    canvas.drawCircle(Offset.zero, r * 0.92, Paint()..color = _gold);
    canvas.drawCircle(
        Offset.zero,
        r * 0.92,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = r * 0.06
          ..color = _goldDark);
    // 노치 8개
    final notch = Paint()..color = _cream;
    for (var k = 0; k < 8; k++) {
      canvas.save();
      canvas.rotate(k * math.pi / 4);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromCenter(center: Offset(0, -r * 0.8), width: r * 0.3, height: r * 0.2),
            Radius.circular(r * 0.04)),
        notch,
      );
      canvas.restore();
    }
    // 안쪽 원 + 링 + 점
    canvas.drawCircle(Offset.zero, r * 0.59, Paint()..color = _gold);
    final creamStroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = r * 0.05
      ..color = _cream;
    canvas.drawCircle(Offset.zero, r * 0.59, creamStroke);
    canvas.drawCircle(Offset.zero, r * 0.33, creamStroke);
    canvas.drawCircle(Offset.zero, r * 0.11, notch);
    // 주인 링(바깥 테두리)
    canvas.drawCircle(
        Offset.zero,
        r * 0.97,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = r * 0.09
          ..color = ring);
    canvas.restore();
  }

  @override
  bool shouldRepaint(ChipPainter old) => old.ring != ring || old.tilt != tilt;
}

/// 칩이 레일에서 카드로 **날아가 꽂히는** 오버레이 비행.
///
/// 출발은 느리고 도착은 빠르다(easeInCubic) — 던진 칩의 가속감. 중간에 살짝 떠올랐다
/// 내려앉고, 구르듯 기울어진다. 끝나면 스스로 정리된다. [flyCard]와 같은 계약.
Future<void> flyChip({
  required OverlayState overlay,
  required TickerProvider vsync,
  required Rect from,
  required Rect to,
  required Color ring,
  Duration duration = const Duration(milliseconds: 300),
}) async {
  final controller = AnimationController(vsync: vsync, duration: duration);
  final move = CurvedAnimation(parent: controller, curve: Curves.easeInCubic);
  late OverlayEntry entry;
  entry = OverlayEntry(
    builder: (context) => AnimatedBuilder(
      animation: move,
      builder: (context, _) {
        final t = move.value;
        final rect = Rect.lerp(from, to, t)!;
        final lift = -22 * math.sin(t * math.pi);
        final tilt = math.sin(t * math.pi); // 중간에 가장 눕는다
        return Positioned(
          left: rect.left,
          top: rect.top + lift,
          width: rect.width,
          height: rect.height,
          child: IgnorePointer(
            child: Transform.rotate(
              angle: 1.2 * t,
              child: CustomPaint(painter: ChipPainter(ring: ring, tilt: tilt * 0.8)),
            ),
          ),
        );
      },
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
