import 'package:flutter/material.dart';

import '../personas.dart';
import '../theme.dart';

/// 이모트 말풍선 — 아바타 옆에 스케일 팝으로 등장한다. (게임/가림 룰 공용)
class EmoteBubble extends StatelessWidget {
  const EmoteBubble({super.key, required this.asset});
  final String asset;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutBack,
        builder: (context, t, child) => Opacity(
            opacity: t.clamp(0.0, 1.0),
            child: Transform.scale(scale: 0.6 + 0.4 * t, child: child)),
        child: Container(
          padding: const EdgeInsets.all(9),
          decoration: BoxDecoration(
            color: AppColors.cardBody,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(20),
              topRight: Radius.circular(20),
              bottomRight: Radius.circular(20),
              bottomLeft: Radius.circular(6), // 꼬리 방향(아바타 쪽)
            ),
            border: Border.all(color: AppColors.goldDeep, width: 1.2),
            boxShadow: AppShapes.panelShadow,
          ),
          child: PersonaIcon(asset: asset, size: 52),
        ),
      ),
    );
  }
}

/// 이모트 6종 피커 패널. (게임/가림 룰 공용)
class EmotePicker extends StatelessWidget {
  const EmotePicker({super.key, required this.onPick});
  final void Function(String asset) onPick;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.gold, width: 1.2),
        boxShadow: AppShapes.panelShadow,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final e in kEmoteAssets)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: InkWell(
                borderRadius: BorderRadius.circular(999),
                onTap: () => onPick(e),
                child: Container(
                  decoration: BoxDecoration(
                    color: AppColors.bgBottom,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.stroke),
                  ),
                  padding: const EdgeInsets.all(6),
                  child: PersonaIcon(asset: e, size: 34),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 이모트 열기 버튼. (게임/가림 룰 공용)
class EmoteButton extends StatelessWidget {
  const EmoteButton({super.key, required this.open, required this.onTap, this.tooltip});
  final bool open;
  final VoidCallback onTap;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final button = OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.all(10),
        minimumSize: Size.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        side: BorderSide(
            color: open ? AppColors.gold : AppColors.goldSoft, width: 1.4),
      ),
      child: const Icon(Icons.emoji_emotions_rounded, size: 18, color: AppColors.gold),
    );
    return tooltip == null ? button : Tooltip(message: tooltip!, child: button);
  }
}
