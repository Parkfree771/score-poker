import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

import '../domain/ai.dart';
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
/// 항목은 **가림 룰의 사건**과 1:1로 붙어 있다 — 규칙에 없는 상황의 대사는 두지 않는다.
class PersonaLines {
  const PersonaLines({
    required this.greeting, // 게임 시작
    required this.hide, // AI가 자기 카드를 숨겼을 때
    required this.peek, // AI가 내 숨긴 카드를 열었을 때
    required this.peeked, // 내가 AI의 숨긴 카드를 열었을 때
    required this.lead, // 공개 후 AI가 줄에서 앞설 때
    required this.behind, // 공개 후 AI가 밀릴 때
    required this.winGame, // AI 승리
    required this.loseGame, // AI 패배
    required this.drawGame, // 무승부
  });

  final List<String> greeting,
      hide,
      peek,
      peeked,
      lead,
      behind,
      winGame,
      loseGame,
      drawGame;
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
    required this.pressure,
    required this.steady,
    required this.bluff,
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

  /// 기풍 스탯(0~5). 숫자가 아니라 **실제 AI 계수**([AiProfile])를 요약한 것이다:
  /// 압박 = 이길 두 줄에 몰아주는 정도, 침착 = 비공개권을 아끼는 정도,
  /// 허세 = 값어치 없는 카드도 숨기는 정도.
  final int pressure, steady, bluff;

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

/// 여섯 캐릭터 정의(크로드·헷·제나 + 딥시·그록·미스트). **대사까지 전부 l10n을 거친다** — 예전에는 대사만 한글로 박혀 있어서
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
        pressure: 2,
        steady: 5,
        bluff: 1,
        style: AiStyle.clode,
        lines: PersonaLines(
          greeting: [l10n.personaClodeGreeting1, l10n.personaClodeGreeting2],
          hide: [l10n.personaClodeHide1, l10n.personaClodeHide2],
          peek: [l10n.personaClodePeek1, l10n.personaClodePeek2],
          peeked: [l10n.personaClodePeeked1, l10n.personaClodePeeked2],
          lead: [l10n.personaClodeLead1, l10n.personaClodeLead2],
          behind: [l10n.personaClodeBehind1, l10n.personaClodeBehind2],
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
        pressure: 5,
        steady: 2,
        bluff: 3,
        style: AiStyle.het,
        lines: PersonaLines(
          greeting: [l10n.personaHetGreeting1, l10n.personaHetGreeting2],
          hide: [l10n.personaHetHide1, l10n.personaHetHide2],
          peek: [l10n.personaHetPeek1, l10n.personaHetPeek2],
          peeked: [l10n.personaHetPeeked1, l10n.personaHetPeeked2],
          lead: [l10n.personaHetLead1, l10n.personaHetLead2],
          behind: [l10n.personaHetBehind1, l10n.personaHetBehind2],
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
        pressure: 3,
        steady: 2,
        bluff: 5,
        style: AiStyle.jenna,
        lines: PersonaLines(
          greeting: [l10n.personaJennaGreeting1, l10n.personaJennaGreeting2],
          hide: [l10n.personaJennaHide1, l10n.personaJennaHide2],
          peek: [l10n.personaJennaPeek1, l10n.personaJennaPeek2],
          peeked: [l10n.personaJennaPeeked1, l10n.personaJennaPeeked2],
          lead: [l10n.personaJennaLead1, l10n.personaJennaLead2],
          behind: [l10n.personaJennaBehind1, l10n.personaJennaBehind2],
          winGame: [l10n.personaJennaWin1, l10n.personaJennaWin2],
          loseGame: [l10n.personaJennaLose1, l10n.personaJennaLose2],
          drawGame: [l10n.personaJennaDraw1],
        ),
      ),
      Persona(
        id: 'dipsy',
        name: l10n.personaDipsyName,
        tagline: l10n.personaDipsyTagline,
        desc: l10n.personaDipsyDesc,
        color: const Color(0xFFE04B3A),
        badgeBg: const Color(0xFF3A0D0B),
        asset: 'assets/lottie/persona_star.json',
        colorOverrides: null, // tool/recolor_lottie.py로 파일에 색을 구워 넣었다
        pressure: 3,
        steady: 4,
        bluff: 1,
        style: AiStyle.dipsy,
        lines: PersonaLines(
          greeting: [l10n.personaDipsyGreeting1, l10n.personaDipsyGreeting2],
          hide: [l10n.personaDipsyHide1, l10n.personaDipsyHide2],
          peek: [l10n.personaDipsyPeek1, l10n.personaDipsyPeek2],
          peeked: [l10n.personaDipsyPeeked1, l10n.personaDipsyPeeked2],
          lead: [l10n.personaDipsyLead1, l10n.personaDipsyLead2],
          behind: [l10n.personaDipsyBehind1, l10n.personaDipsyBehind2],
          winGame: [l10n.personaDipsyWin1, l10n.personaDipsyWin2],
          loseGame: [l10n.personaDipsyLose1, l10n.personaDipsyLose2],
          drawGame: [l10n.personaDipsyDraw1],
        ),
      ),
      Persona(
        id: 'grok',
        name: l10n.personaGrokName,
        tagline: l10n.personaGrokTagline,
        desc: l10n.personaGrokDesc,
        color: const Color(0xFFA98BFF),
        badgeBg: const Color(0xFF1C1338),
        asset: 'assets/lottie/persona_joker.json',
        colorOverrides: null, // tool/recolor_lottie.py로 파일에 색을 구워 넣었다
        pressure: 4,
        steady: 1,
        bluff: 4,
        style: AiStyle.grok,
        lines: PersonaLines(
          greeting: [l10n.personaGrokGreeting1, l10n.personaGrokGreeting2],
          hide: [l10n.personaGrokHide1, l10n.personaGrokHide2],
          peek: [l10n.personaGrokPeek1, l10n.personaGrokPeek2],
          peeked: [l10n.personaGrokPeeked1, l10n.personaGrokPeeked2],
          lead: [l10n.personaGrokLead1, l10n.personaGrokLead2],
          behind: [l10n.personaGrokBehind1, l10n.personaGrokBehind2],
          winGame: [l10n.personaGrokWin1, l10n.personaGrokWin2],
          loseGame: [l10n.personaGrokLose1, l10n.personaGrokLose2],
          drawGame: [l10n.personaGrokDraw1],
        ),
      ),
      Persona(
        id: 'mist',
        name: l10n.personaMistName,
        tagline: l10n.personaMistTagline,
        desc: l10n.personaMistDesc,
        color: const Color(0xFF7FB3E6),
        badgeBg: const Color(0xFF0F1E33),
        asset: 'assets/lottie/persona_stopwatch.json',
        colorOverrides: null, // tool/recolor_lottie.py로 파일에 색을 구워 넣었다
        pressure: 4,
        steady: 2,
        bluff: 2,
        style: AiStyle.mist,
        lines: PersonaLines(
          greeting: [l10n.personaMistGreeting1, l10n.personaMistGreeting2],
          hide: [l10n.personaMistHide1, l10n.personaMistHide2],
          peek: [l10n.personaMistPeek1, l10n.personaMistPeek2],
          peeked: [l10n.personaMistPeeked1, l10n.personaMistPeeked2],
          lead: [l10n.personaMistLead1, l10n.personaMistLead2],
          behind: [l10n.personaMistBehind1, l10n.personaMistBehind2],
          winGame: [l10n.personaMistWin1, l10n.personaMistWin2],
          loseGame: [l10n.personaMistLose1, l10n.personaMistLose2],
          drawGame: [l10n.personaMistDraw1],
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
      child: RepaintBoundary(
        child: Lottie.asset(
          asset,
          animate: animate,
          repeat: true,
          fit: BoxFit.contain,
          frameRate: const FrameRate(30),
          delegates:
              colorOverrides == null ? null : LottieDelegates(values: colorOverrides!),
        ),
      ),
    );
  }
}
