import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

import '../../domain/ai.dart';
import '../theme.dart';

/// 상대 AI 레벨(1~5)을 **별 개수**로 보여준다 — 숫자보다 먼저 읽힌다.
///
/// 켜진 별은 금빛 로티(`level_star.json`)가 움직이고, 꺼진 별은 어두운 윤곽만 남는다.
/// 5레벨이면 별 다섯이 함께 반짝여서 "아, 이번 상대는 5레벨이구나"가 바로 온다.
/// [animate]가 false면(골든·정지 화면) 로티를 첫 프레임에 멈춘다.
class LevelStars extends StatelessWidget {
  const LevelStars({
    super.key,
    required this.level,
    this.size = 18,
    this.animate = true,
    this.gap = 2,
  });

  final int level;
  final double size;
  final bool animate;
  final double gap;

  @override
  Widget build(BuildContext context) {
    final lit = level.clamp(AiStrength.minLevel, AiStrength.maxLevel);
    return Semantics(
      label: 'level $lit',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < AiStrength.maxLevel; i++)
            Padding(
              padding: EdgeInsets.only(right: i == AiStrength.maxLevel - 1 ? 0 : gap),
              child: SizedBox(
                width: size,
                height: size,
                child: i < lit
                    ? Lottie.asset(
                        'assets/lottie/level_star.json',
                        animate: animate,
                        repeat: true,
                        fit: BoxFit.contain,
                      )
                    : Icon(Icons.star_border_rounded,
                        size: size * 0.92, color: AppColors.gaugeOff),
              ),
            ),
        ],
      ),
    );
  }
}
