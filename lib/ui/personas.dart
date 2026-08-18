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

/// 세 캐릭터 정의. 이름/태그라인/설명은 l10n, 대사는 캐릭터 고유 톤이라 한글 고정.
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
        lines: const PersonaLines(
          greeting: ['좋은 승부를 기대하겠습니다.', '차분히, 그러나 확실하게 두겠습니다.'],
          removeMine: ['실례합니다 — 그 카드는 회수하겠습니다.', '아깝지만, 필요한 수였습니다.'],
          removed: ['…좋은 판단이시군요.', '한 수 배웠습니다.'],
          joker: ['조커는 이럴 때 쓰는 겁니다.', '지금이 그 순간이라고 판단했습니다.'],
          shieldTrick: ['방어는 최선의 공격이기도 하죠.'],
          winGame: ['좋은 승부였습니다. 다음에도 기대하죠.', '운이 아니라 계획이었습니다.'],
          loseGame: ['완패입니다. 인정하죠.', '다음 판은 다를 겁니다.'],
          drawGame: ['호각이군요. 흥미롭습니다.'],
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
        lines: const PersonaLines(
          greeting: ['각오는 됐지? 시작하자고.', '내가 왜 승부사라 불리는지 보여줄게.'],
          removeMine: ['그 카드, 아까웠지? ㅋ', '어이쿠, 손이 미끄러졌네~'],
          removed: ['야, 그건 반칙 아니야?!', '…방금 건 노카운트로 하자.'],
          joker: ['짜잔! 조커 타임!', '이 맛에 승부하는 거지!'],
          shieldTrick: ['선물이야, 사양 말고 받아.'],
          winGame: ['거봐, 내가 이긴다니까~', '좋은 승부였어. 나한텐.'],
          loseGame: ['오늘 컨디션이 좀… 아무튼 다시 해!', '한 판 더. 지금 당장.'],
          drawGame: ['비겼다고? 찝찝하네.'],
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
        lines: const PersonaLines(
          greeting: ['승률 계산이 끝났습니다. 시작하죠.', '데이터는 거짓말을 하지 않아요.'],
          removeMine: ['변수 하나를 제거했습니다.', '그 카드의 기대값이 가장 높더군요.'],
          removed: ['…예측 범위 밖의 수네요.', '모델을 갱신하겠습니다.'],
          joker: ['조커 투입 — 최적 타이밍입니다.'],
          shieldTrick: ['그 줄, 제가 조금 손봤습니다.', '작은 변수를 심어뒀어요.'],
          winGame: ['계산대로입니다.', '이 결과, 예측 구간 안이었어요.'],
          loseGame: ['오차 범위… 밖이군요. 흥미롭네요.', '데이터를 더 모아야겠어요.'],
          drawGame: ['정확히 50 대 50. 아름답네요.'],
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
