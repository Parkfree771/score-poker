import 'package:flutter/material.dart';

import '../../domain/card.dart';
import '../theme.dart';
import 'card_back.dart';
import 'card_face.dart';

/// 게임 테이블 장식/공용 소품 모음.
/// - [TableDecorPainter]: 테이블 안쪽 골드 핀스트라이프 + 모서리 ◆ 스터드
/// - [BracketPainter]: 빈칸 모서리 'ㄱ'자 브래킷
/// - [DiamondCap]: 골드 중앙선 양끝 ◆ 캡
/// - [LaneSeparator]: 레인 사이 세로 구분선
/// - [DeckPileView] / [DiscardPileView]: 드로우 덱 / 버린 카드 무덤
/// - [TurnAvatar]: 차례 표시 아바타(내 차례면 골드 링이 숨쉬듯 빛남)

/// 테이블 안쪽을 한 바퀴 도는 골드 핀스트라이프(레이스트랙 라인) + 모서리 ◆ 스터드.
class TableDecorPainter extends CustomPainter {
  const TableDecorPainter();

  @override
  void paint(Canvas canvas, Size size) {
    const inset = 8.0;
    const r = 16.0;

    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = AppColors.gold.withValues(alpha: 0.55);
    final rrect = RRect.fromRectAndRadius(
      Rect.fromLTWH(inset, inset, size.width - inset * 2, size.height - inset * 2),
      const Radius.circular(r),
    );
    canvas.drawRRect(rrect, line);

    // 모서리 곡선 한가운데(45도 지점)에 작은 다이아 스터드
    final stud = Paint()..color = AppColors.gold;
    const d = 3.4;
    const k = 0.2929; // 1 - cos45
    final pts = [
      const Offset(inset + r * k, inset + r * k),
      Offset(size.width - inset - r * k, inset + r * k),
      Offset(inset + r * k, size.height - inset - r * k),
      Offset(size.width - inset - r * k, size.height - inset - r * k),
    ];
    for (final c in pts) {
      final path = Path()
        ..moveTo(c.dx, c.dy - d)
        ..lineTo(c.dx + d, c.dy)
        ..lineTo(c.dx, c.dy + d)
        ..lineTo(c.dx - d, c.dy)
        ..close();
      canvas.drawPath(path, stud);
    }
  }

  @override
  bool shouldRepaint(TableDecorPainter old) => false;
}

/// 칸 네 모서리의 'ㄱ'자 브래킷(조준 표시 느낌). 전부 불투명.
class BracketPainter extends CustomPainter {
  const BracketPainter(this.color, {this.strokeWidth = 2.4});
  final Color color;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    const inset = 5.0;
    final len = size.width * 0.2;
    final w = size.width, h = size.height;

    void corner(double x, double y, double dx, double dy) {
      canvas.drawLine(Offset(x, y), Offset(x + len * dx, y), p);
      canvas.drawLine(Offset(x, y), Offset(x, y + len * dy), p);
    }

    corner(inset, inset, 1, 1);
    corner(w - inset, inset, -1, 1);
    corner(inset, h - inset, 1, -1);
    corner(w - inset, h - inset, -1, -1);
  }

  @override
  bool shouldRepaint(BracketPainter old) => old.color != color || old.strokeWidth != strokeWidth;
}

/// 골드 중앙선 양끝의 ◆ 장식 캡.
class DiamondCap extends StatelessWidget {
  const DiamondCap({super.key});

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: 0.7854,
      child: Container(
        width: 7,
        height: 7,
        decoration: BoxDecoration(
          color: AppColors.gold,
          boxShadow: [BoxShadow(color: AppColors.gold.withValues(alpha: 0.6), blurRadius: 6)],
        ),
      ),
    );
  }
}

/// 레인 사이 세로 구분선: 가운데(골드 선 근처)가 또렷하고 위아래로 갈수록 사라진다.
class LaneSeparator extends StatelessWidget {
  const LaneSeparator({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1.6,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.white.withValues(alpha: 0),
            Colors.white.withValues(alpha: 0.38),
            Colors.white.withValues(alpha: 0.38),
            Colors.white.withValues(alpha: 0),
          ],
          stops: const [0, 0.18, 0.82, 1],
        ),
      ),
    );
  }
}

/// 장수 배지(덱 남은 장수 / 무덤 장수).
class CountBadge extends StatelessWidget {
  const CountBadge({super.key, required this.count, this.icon = Icons.style});
  final int count;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.gold.withValues(alpha: 0.4), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: AppColors.goldSoft),
          const SizedBox(width: 4),
          Text('$count',
              style: const TextStyle(color: AppColors.textMain, fontWeight: FontWeight.w800, fontSize: 12)),
        ],
      ),
    );
  }
}

/// 더미 밑의 바닥 그림자(테이블에 놓인 느낌).
class _GroundShadow extends StatelessWidget {
  const _GroundShadow({required this.width});
  final double width;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: 8,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(4),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.5), blurRadius: 10, spreadRadius: 1)],
      ),
    );
  }
}

/// 드로우 덱: 뒷면 카드 3장이 어긋나게 쌓인 더미 + 남은 장수. 드로우 연출의 출발점.
class DeckPileView extends StatelessWidget {
  const DeckPileView({super.key, required this.remaining, this.cardSize = 42, this.pileKey});
  final int remaining;
  final double cardSize;
  final GlobalKey? pileKey;

  @override
  Widget build(BuildContext context) {
    final s = cardSize;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          key: pileKey,
          width: s + 10,
          height: CardBack.heightFor(s) + 8,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(left: 4, right: 0, bottom: 0, child: _GroundShadow(width: s)),
              for (var i = 0; i < 3; i++)
                Positioned(left: i * 4.0, top: (2 - i) * 3.0, child: CardBack(size: s)),
            ],
          ),
        ),
        const SizedBox(height: 6),
        CountBadge(count: remaining),
      ],
    );
  }
}

/// 버린 카드 무덤: 최근 카드들이 비스듬히 쌓임(제거/오프닝 버림 연출의 도착점).
class DiscardPileView extends StatelessWidget {
  const DiscardPileView({super.key, required this.cards, this.cardSize = 42, this.pileKey});

  /// 무덤에 쌓인 카드(오래된 것부터). 마지막 2장만 그린다.
  final List<PlayingCard> cards;
  final double cardSize;
  final GlobalKey? pileKey;

  @override
  Widget build(BuildContext context) {
    final s = cardSize;
    final shown = cards.length <= 2 ? cards : cards.sublist(cards.length - 2);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          key: pileKey,
          width: s + 18,
          height: CardFace.heightFor(s) + 12,
          child: Stack(
            alignment: Alignment.center,
            clipBehavior: Clip.none,
            children: [
              Positioned(left: 8, right: 8, bottom: 2, child: _GroundShadow(width: s)),
              if (shown.isEmpty)
                // 빈 무덤: 파인 홈 모양
                Container(
                  width: s,
                  height: CardFace.heightFor(s),
                  decoration: BoxDecoration(
                    color: AppColors.slotRecess,
                    borderRadius: BorderRadius.circular(s * 0.14),
                    border: Border.all(color: AppColors.stroke, width: 1),
                  ),
                )
              else
                for (var i = 0; i < shown.length; i++)
                  Transform.rotate(
                    angle: (i - (shown.length - 1) / 2) * 0.16 - 0.06,
                    child: Opacity(
                      opacity: i == shown.length - 1 ? 0.9 : 0.55,
                      child: CardFace(card: shown[i], size: s),
                    ),
                  ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        CountBadge(count: cards.length, icon: Icons.delete_outline),
      ],
    );
  }
}

/// 차례 표시 아바타. [active]면 골드 링이 숨쉬듯 은은하게 밝아졌다 어두워진다.
class TurnAvatar extends StatefulWidget {
  const TurnAvatar({super.key, required this.color, required this.active});
  final Color color;
  final bool active;

  @override
  State<TurnAvatar> createState() => _TurnAvatarState();
}

class _TurnAvatarState extends State<TurnAvatar> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1400));

  @override
  void initState() {
    super.initState();
    if (widget.active) _c.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(TurnAvatar old) {
    super.didUpdateWidget(old);
    if (widget.active && !_c.isAnimating) _c.repeat(reverse: true);
    if (!widget.active && _c.isAnimating) {
      _c.stop();
      _c.value = 0;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) {
        final glow = widget.active ? 0.35 + 0.35 * _c.value : 0.0;
        return Container(
          padding: const EdgeInsets.all(2.5),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: widget.active ? AppColors.gold : Colors.white.withValues(alpha: 0.18),
              width: 2,
            ),
            boxShadow: widget.active
                ? [BoxShadow(color: AppColors.gold.withValues(alpha: glow), blurRadius: 10)]
                : null,
          ),
          child: child,
        );
      },
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: widget.color.withValues(alpha: 0.9),
          shape: BoxShape.circle,
        ),
        alignment: Alignment.center,
        child: const Icon(Icons.person_rounded, size: 17, color: Colors.white),
      ),
    );
  }
}
