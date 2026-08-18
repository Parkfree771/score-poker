import 'package:flutter/material.dart';

import '../../domain/card.dart';
import 'card_face.dart';

/// 손패의 카드가 보드 칸으로 **날아가 안착**하는 오버레이 애니메이션.
///
/// [from]/[to]는 화면(글로벌) 좌표 기준 사각형. 카드가 살짝 떠오르며(아치) 이동하고,
/// 안착 순간 아주 짧게 튕기는 느낌을 준다. 애니메이션이 끝나면 스스로 정리된다.
Future<void> flyCard({
  required OverlayState overlay,
  required TickerProvider vsync,
  required Rect from,
  required Rect to,
  required PlayingCard card,
  Duration duration = const Duration(milliseconds: 380),
  double spinTurns = 0, // 이동 중 회전(바퀴 수). 제거→무덤 비행에 사용.
  double endOpacity = 1, // 도착 시 투명도(무덤에 스며들 때 살짝 흐리게).
}) async {
  final controller = AnimationController(vsync: vsync, duration: duration);
  final move = CurvedAnimation(parent: controller, curve: Curves.easeInOutCubic);

  late OverlayEntry entry;
  entry = OverlayEntry(
    builder: (context) {
      return AnimatedBuilder(
        animation: move,
        builder: (context, _) {
          final t = move.value;
          final rect = Rect.lerp(from, to, t)!;
          // 이동 중 살짝 위로 뜨는 아치 (가운데서 최대).
          final lift = -26 * (1 - (2 * t - 1) * (2 * t - 1));
          // 안착 직전 살짝 커졌다 제자리 (탄성 느낌).
          final pop = 1 + 0.06 * (t < 0.85 ? t / 0.85 : (1 - t) / 0.15);
          return Positioned(
            left: rect.left,
            top: rect.top + lift,
            width: rect.width,
            height: rect.height,
            child: IgnorePointer(
              child: Opacity(
                opacity: ((t * 6).clamp(0.0, 1.0)) * (1 - (1 - endOpacity) * t),
                child: Transform.rotate(
                  angle: spinTurns * 6.2832 * t,
                  child: Transform.scale(
                    scale: pop,
                    child: FittedBox(
                      fit: BoxFit.contain,
                      child: CardFace(card: card, size: 120),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      );
    },
  );

  overlay.insert(entry);
  try {
    await controller.forward();
  } finally {
    entry.remove();
    controller.dispose();
  }
}

/// 카드가 **쳐내져 튕겨 나가는** 녹아웃 연출. [rect] 위치에서 살짝 커졌다가
/// 회전하며 위로 튀어오르고 사라진다. (같은 숫자/조커 제거 등)
Future<void> poofCard({
  required OverlayState overlay,
  required TickerProvider vsync,
  required Rect rect,
  required PlayingCard card,
  Duration duration = const Duration(milliseconds: 300),
}) async {
  final controller = AnimationController(vsync: vsync, duration: duration);
  final anim = CurvedAnimation(parent: controller, curve: Curves.easeOut);

  late OverlayEntry entry;
  entry = OverlayEntry(
    builder: (context) {
      return AnimatedBuilder(
        animation: anim,
        builder: (context, _) {
          final t = anim.value;
          final scale = 1 + 0.45 * t;
          final dy = -rect.height * 0.55 * t; // 위로 튐
          final rot = 0.5 * t;
          return Positioned(
            left: rect.left,
            top: rect.top + dy,
            width: rect.width,
            height: rect.height,
            child: IgnorePointer(
              child: Opacity(
                opacity: (1 - t).clamp(0.0, 1.0),
                child: Transform.rotate(
                  angle: rot,
                  child: Transform.scale(
                    scale: scale,
                    child: FittedBox(fit: BoxFit.contain, child: CardFace(card: card, size: 120)),
                  ),
                ),
              ),
            ),
          );
        },
      );
    },
  );

  overlay.insert(entry);
  try {
    await controller.forward();
  } finally {
    entry.remove();
    controller.dispose();
  }
}
