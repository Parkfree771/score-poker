import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

import '../domain/ai_strategy.dart';
import '../l10n/app_localizations.dart';

/// 감정 표현(이모트) 로티 에셋 — 페르소나 화면 미리보기와 게임 화면 공용.
/// 이모지 로티는 원색 그대로 반복 재생한다(틴트를 입히면 표정이 사라진다).
const List<String> kEmoteAssets = [
  'assets/lottie/emoji_smile.json',
  'assets/lottie/emoji_lol.json',
  'assets/lottie/emoji_wow.json',
  'assets/lottie/emoji_sad.json',
  'assets/lottie/emoji_angry.json',
  'assets/lottie/emoji_cry.json',
];

/// 상황별 대사 묶음(각 목록에서 무작위로 한 줄을 골라 말한다).
class PersonaLines {
  const PersonaLines({
    required this.greeting, // 게임 시작
    required this.removeMine, // AI가 내 카드를 제거했을 때
    required this.removed, // 내가 AI의 카드를 제거했을 때
    required this.joker, // AI가 조커를 냈을 때
    required this.shieldTrick, // AI가 내 줄에 쉴드를 꽂았을 때(변칙)
    required this.winGame, // AI 승리
    required this.loseGame, // AI 패배
    required this.drawGame, // 무승부
  });

  final List<String> greeting, removeMine, removed, joker, shieldTrick, winGame, loseGame, drawGame;
}

/// AI 대전 상대 캐릭터.
class Persona {
  const Persona({
    required this.id,
    required this.name,
    required this.tagline,
    required this.desc,
    required this.color,
    required this.badgeBg,
    required this.asset,
    required this.colorOverrides,
    required this.attack,
    required this.defense,
    required this.trick,
    required this.style,
    required this.lines,
  });

  final String id;
  final String name;
  final String tagline;
  final String desc;
  final Color color;
  final Color badgeBg; // 캐릭터에 어울리는 배지 배경(게임 팔레트와 달라도 됨)
  final String asset;
  final List<ValueDelegate>? colorOverrides;
  final int attack, defense, trick; // 기풍 스탯(0~5)
  final AiStyle style;
  final PersonaLines lines;
}

/// 크로드 불꽃: 겉불(딥 레드-오렌지)과 속불(골든 옐로)을 분리해서 물들인다.
final List<ValueDelegate> flameColors = [
  ValueDelegate.color(const ['**', 'flame', '**'], value: const Color(0xFFD9502C)),
  ValueDelegate.strokeColor(const ['**', 'flame', '**'], value: const Color(0xFF8A2E18)),
  ValueDelegate.color(const ['**', 'flame-small', '**'], value: const Color(0xFFF6C445)),
  ValueDelegate.strokeColor(const ['**', 'flame-small', '**'], value: const Color(0xFFB4741B)),
  ValueDelegate.color(const ['**', 'flame 2', '**'], value: const Color(0xFFD9502C)),
  ValueDelegate.strokeColor(const ['**', 'flame 2', '**'], value: const Color(0xFF8A2E18)),
];

/// 헷 행성: 본체(민트 틸) / 고리(크림) / 반짝이 별(골드)로 분리.
final List<ValueDelegate> planetColors = [
  ValueDelegate.color(const ['**', 'Planet fill', '**'], value: const Color(0xFF3FA98C)),
  ValueDelegate.strokeColor(const ['**', 'Planet fill', '**'], value: const Color(0xFF2C7A64)),
  ValueDelegate.color(const ['**', 'Planet', '**'], value: const Color(0xFF4FC9A8)),
  ValueDelegate.strokeColor(const ['**', 'Planet', '**'], value: const Color(0xFFEDEDF2)),
  ValueDelegate.strokeColor(const ['**', 'Planet Ring', '**'], value: const Color(0xFFF0EAD6)),
  ValueDelegate.color(const ['**', 'Planet Ring', '**'], value: const Color(0xFFF0EAD6)),
  ValueDelegate.strokeColor(const ['**', 'Planet Ring 2', '**'], value: const Color(0xFFF0EAD6)),
  ValueDelegate.color(const ['**', 'Planet Ring 2', '**'], value: const Color(0xFFF0EAD6)),
  ValueDelegate.color(const ['**', 'Blinking-star-1', '**'], value: const Color(0xFFE8C88A)),
  ValueDelegate.strokeColor(const ['**', 'Blinking-star-1', '**'], value: const Color(0xFFE8C88A)),
  ValueDelegate.color(const ['**', 'Blinking-star-2', '**'], value: const Color(0xFFE8C88A)),
  ValueDelegate.strokeColor(const ['**', 'Blinking-star-2', '**'], value: const Color(0xFFE8C88A)),
  ValueDelegate.color(const ['**', 'Blinking-star-3', '**'], value: const Color(0xFFE8C88A)),
  ValueDelegate.strokeColor(const ['**', 'Blinking-star-3', '**'], value: const Color(0xFFE8C88A)),
  ValueDelegate.strokeColor(const ['**', 'outline 9', '**'], value: const Color(0xFFEDEDF2)),
  ValueDelegate.color(const ['**', 'outline 9', '**'], value: const Color(0xFFEDEDF2)),
];

/// 세 캐릭터 정의. **대사까지 전부 l10n을 거친다** — 예전에는 대사만 한글로 박혀 있어서
/// 영어 빌드에서 말풍선만 한국어로 떴다. 번역은 캐릭터 톤(정중/까불/분석)을 유지한다.
List<Persona> buildPersonas(AppLocalizations l10n) => [
      Persona(
        id: 'clode',
        name: l10n.personaClodeName,
        tagline: l10n.personaClodeTagline,
        desc: l10n.personaClodeDesc,
        color: const Color(0xFFE8823D),
        badgeBg: const Color(0xFF3B1A0E),
        asset: 'assets/lottie/flame.json',
        colorOverrides: flameColors,
        attack: 3,
        defense: 5,
        trick: 2,
        style: AiStyle.clode,
        lines: PersonaLines(
          greeting: [l10n.personaClodeGreeting1, l10n.personaClodeGreeting2],
          removeMine: [l10n.personaClodeRemoveMine1, l10n.personaClodeRemoveMine2],
          removed: [l10n.personaClodeRemoved1, l10n.personaClodeRemoved2],
          joker: [l10n.personaClodeJoker1, l10n.personaClodeJoker2],
          shieldTrick: [l10n.personaClodeShield1],
          winGame: [l10n.personaClodeWin1, l10n.personaClodeWin2],
          loseGame: [l10n.personaClodeLose1, l10n.personaClodeLose2],
          drawGame: [l10n.personaClodeDraw1],
        ),
      ),
      Persona(
        id: 'het',
        name: l10n.personaHetName,
        tagline: l10n.personaHetTagline,
        desc: l10n.personaHetDesc,
        color: const Color(0xFFEDEDF2),
        badgeBg: const Color(0xFF15171C),
        asset: 'assets/lottie/planet.json',
        colorOverrides: planetColors,
        attack: 5,
        defense: 2,
        trick: 3,
        style: AiStyle.het,
        lines: PersonaLines(
          greeting: [l10n.personaHetGreeting1, l10n.personaHetGreeting2],
          removeMine: [l10n.personaHetRemoveMine1, l10n.personaHetRemoveMine2],
          removed: [l10n.personaHetRemoved1, l10n.personaHetRemoved2],
          joker: [l10n.personaHetJoker1, l10n.personaHetJoker2],
          shieldTrick: [l10n.personaHetShield1],
          winGame: [l10n.personaHetWin1, l10n.personaHetWin2],
          loseGame: [l10n.personaHetLose1, l10n.personaHetLose2],
          drawGame: [l10n.personaHetDraw1],
        ),
      ),
      Persona(
        id: 'jenna',
        name: l10n.personaJennaName,
        tagline: l10n.personaJennaTagline,
        desc: l10n.personaJennaDesc,
        color: const Color(0xFF7FB7F0),
        badgeBg: const Color(0xFF101A31),
        asset: 'assets/lottie/comet.json',
        colorOverrides: null, // 그라데이션 원색 그대로
        attack: 2,
        defense: 3,
        trick: 5,
        style: AiStyle.jenna,
        lines: PersonaLines(
          greeting: [l10n.personaJennaGreeting1, l10n.personaJennaGreeting2],
          removeMine: [l10n.personaJennaRemoveMine1, l10n.personaJennaRemoveMine2],
          removed: [l10n.personaJennaRemoved1, l10n.personaJennaRemoved2],
          joker: [l10n.personaJennaJoker1],
          shieldTrick: [l10n.personaJennaShield1, l10n.personaJennaShield2],
          winGame: [l10n.personaJennaWin1, l10n.personaJennaWin2],
          loseGame: [l10n.personaJennaLose1, l10n.personaJennaLose2],
          drawGame: [l10n.personaJennaDraw1],
        ),
      ),
    ];

/// 로티 아이콘(기본 반복 재생). [colorOverrides]로 부위(레이어)별 색을 지정한다.
class PersonaIcon extends StatelessWidget {
  const PersonaIcon({
    super.key,
    required this.asset,
    required this.size,
    this.colorOverrides,
    this.animate = true,
  });

  final String asset;
  final double size;
  final List<ValueDelegate>? colorOverrides;
  final bool animate;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Lottie.asset(
        asset,
        animate: animate,
        repeat: true,
        fit: BoxFit.contain,
        delegates:
            colorOverrides == null ? null : LottieDelegates(values: colorOverrides!),
      ),
    );
  }
}
