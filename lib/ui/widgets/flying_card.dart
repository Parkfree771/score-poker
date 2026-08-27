import 'package:flutter/material.dart';

import '../../domain/card.dart';
import 'card_back.dart';
import 'card_face.dart';
import 'joker_card.dart';

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
  Curve curve = Curves.easeInOutCubic, // 돌진(공격)은 easeIn으로 가속감을 준다.
  bool trail = false, // 잔상 2장 — 빠른 돌진의 속도감용.
  bool faceDown = false, // 뒷면으로 비행(쇼다운 모드의 숨김 배치).
  bool joker = false, // 조커 강타 비행 — 뒷면 위에 보라 별 링.
}) async {
  final controller = AnimationController(vsync: vsync, duration: duration);
  final move = CurvedAnimation(parent: controller, curve: curve);

  // t 시점의 카드 1장(본체/잔상 공용).
  Widget cardAt(double t, {double opacity = 1}) {
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
          opacity:
              (((t * 6).clamp(0.0, 1.0)) * (1 - (1 - endOpacity) * t) * opacity)
                  .clamp(0.0, 1.0),
          child: Transform.rotate(
            angle: spinTurns * 6.2832 * t,
            child: Transform.scale(
              scale: pop,
              // Material: 오버레이는 테마의 DefaultTextStyle 밖이라 코너 랭크가
              // 기본 폰트로 그려진다 — 투명 Material로 테마 텍스트 스타일을 잇는다.
              child: Material(
                type: MaterialType.transparency,
                child: FittedBox(
                  fit: BoxFit.contain,
                  child: faceDown
                      ? (joker ? const JokerBack(size: 120) : const CardBack(size: 120))
                      : CardFace(card: card, size: 120),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  late OverlayEntry entry;
  entry = OverlayEntry(
    builder: (context) {
      return AnimatedBuilder(
        animation: move,
        builder: (context, _) {
          final t = move.value;
          return Stack(
            children: [
              if (trail && t > 0.1) ...[
                cardAt((t - 0.12).clamp(0.0, 1.0), opacity: 0.12),
                cardAt((t - 0.06).clamp(0.0, 1.0), opacity: 0.25),
              ],
              cardAt(t),
            ],
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

/// 카드가 **쳐내져 튕겨 나가는** 녹아웃 연출. [rect] 위치에서 확 커지며
/// 회전과 함께 위로 크게 튕겨 나가 사라진다. (같은 숫자/조커 제거 등)
///
/// [driftX]는 튕겨 나가는 수평 방향(-1 왼쪽 ~ 1 오른쪽). 맞은 방향의 반대로
/// 주면 "쳐냈다"는 인과가 몸으로 읽힌다.
Future<void> poofCard({
  required OverlayState overlay,
  required TickerProvider vsync,
  required Rect rect,
  required PlayingCard card,
  Duration duration = const Duration(milliseconds: 340),
  double driftX = 0.6,
  bool faceDown = false, // 뒷면이 쳐내진다(열어보기 — 칩이 카드 뒷면을 걷어낸다).
}) async {
  final controller = AnimationController(vsync: vsync, duration: duration);
  final anim = CurvedAnimation(parent: controller, curve: Curves.easeOutCubic);

  late OverlayEntry entry;
  entry = OverlayEntry(
    builder: (context) {
      return AnimatedBuilder(
        animation: anim,
        builder: (context, _) {
          final t = anim.value;
          // 맞는 순간 확 커졌다가(팝) 날아가며 서서히 줄어든다.
          final scale = t < 0.18 ? 1 + 1.0 * (t / 0.18) : 2.0 - 0.9 * ((t - 0.18) / 0.82);
          final dy = -rect.height * 1.5 * t + rect.height * 0.9 * t * t; // 포물선
          final dx = rect.width * 1.1 * driftX * t;
          final rot = 1.7 * t * driftX.sign;
          // 절반 지점까지는 또렷이 보여주고, 그 뒤에 빠르게 사라진다 —
          // "무슨 카드가 나갔는지"가 읽혀야 명확하다.
          final opacity = t < 0.55 ? 1.0 : (1 - (t - 0.55) / 0.45);
          return Positioned(
            left: rect.left + dx,
            top: rect.top + dy,
            width: rect.width,
            height: rect.height,
            child: IgnorePointer(
              child: Opacity(
                opacity: opacity.clamp(0.0, 1.0),
                child: Transform.rotate(
                  angle: rot,
                  child: Transform.scale(
                    scale: scale,
                    child: Material(
                      type: MaterialType.transparency,
                      child: FittedBox(
                          fit: BoxFit.contain,
                          child: faceDown
                              ? const CardBack(size: 120)
                              : CardFace(card: card, size: 120)),
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
