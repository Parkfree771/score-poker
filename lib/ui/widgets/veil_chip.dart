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
  State<VeilChip> createState() => _VeilChipState();
}

class _VeilChipState extends State<VeilChip> with SingleTickerProviderStateMixin {
  static const _idleEnd = 120 / 150;
  late final AnimationController _c = AnimationController(vsync: this);
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
  void didUpdateWidget(VeilChip old) {
    super.didUpdateWidget(old);
    if (old.animate != widget.animate) _idle();
  }

  Future<void> _flip() async {
    if (!_loaded) return;
    _c.stop();
    _c.value = _idleEnd;
    await _c.animateTo(1,
        duration: _c.duration! * (1 - _idleEnd), curve: Curves.easeOut);
    _idle();
  }

  void _tap() {
    _flip();
    widget.onTap?.call();
  }

  @override
  void dispose() {
    _c.dispose();
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
