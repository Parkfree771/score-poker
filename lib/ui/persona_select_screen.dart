import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import 'game_screen.dart';
import 'personas.dart';
import 'theme.dart';

/// AI 대전 상대(페르소나) 선택 화면.
/// 캐릭터 카드: 컬러 글로우 배지(로티 반복 재생) + 태그라인 칩 + 기풍 스탯.
/// 세로 = 카드 3장 세로 스택, 가로 = 3열 + 하단 감정 표현 스트립.
class PersonaSelectScreen extends StatelessWidget {
  const PersonaSelectScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final personas = buildPersonas(l10n);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.personaSelectTitle)),
      body: DecoratedBox(
        decoration: const BoxDecoration(gradient: AppColors.bgGradient),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, cons) {
              final landscape = cons.maxWidth > cons.maxHeight;
              return landscape
                  ? _landscape(context, l10n, personas)
                  : _portrait(context, l10n, personas);
            },
          ),
        ),
      ),
    );
  }

  Widget _portrait(BuildContext context, AppLocalizations l10n, List<Persona> personas) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 14),
          child: Text(l10n.personaSelectDesc,
              style: const TextStyle(color: AppColors.textMuted, fontSize: 13, fontWeight: FontWeight.w600)),
        ),
        for (final p in personas) ...[
          _PersonaCard(l10n: l10n, persona: p, onTap: () => _start(context, p)),
          const SizedBox(height: 16),
        ],
        const SizedBox(height: 6),
        _EmoteStrip(l10n: l10n),
      ],
    );
  }

  Widget _landscape(BuildContext context, AppLocalizations l10n, List<Persona> personas) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < personas.length; i++) ...[
              if (i > 0) const SizedBox(width: 14),
              Expanded(
                child: _PersonaCard(
                  l10n: l10n,
                  persona: personas[i],
                  vertical: true,
                  onTap: () => _start(context, personas[i]),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 14),
        _EmoteStrip(l10n: l10n),
      ],
    );
  }

  void _start(BuildContext context, Persona persona) {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(builder: (_) => GameScreen(persona: persona)),
    );
  }
}

class _PersonaCard extends StatelessWidget {
  const _PersonaCard({
    required this.l10n,
    required this.persona,
    required this.onTap,
    this.vertical = false,
  });

  final AppLocalizations l10n;
  final Persona persona;
  final VoidCallback onTap;

  /// 가로 화면용 세로형 카드(아이콘 위, 텍스트 아래).
  final bool vertical;

  @override
  Widget build(BuildContext context) {
    final c = persona.color;
    // 카드 배경: surface에 페르소나 색을 아주 얕게 섞은 "불투명" 그라데이션.
    final tintedTop = Color.alphaBlend(c.withValues(alpha: 0.14), AppColors.surface);
    final cardBg = LinearGradient(
      begin: vertical ? Alignment.topCenter : Alignment.centerLeft,
      end: vertical ? Alignment.bottomCenter : Alignment.centerRight,
      colors: [tintedTop, AppColors.surface],
    );

    final badge = Container(
      width: vertical ? 96 : 84,
      height: vertical ? 96 : 84,
      decoration: BoxDecoration(
        color: persona.badgeBg,
        shape: BoxShape.circle,
        border: Border.all(color: c, width: 2),
        boxShadow: [
          BoxShadow(color: c.withValues(alpha: 0.45), blurRadius: 22, spreadRadius: 1),
        ],
      ),
      padding: const EdgeInsets.all(12),
      child: PersonaIcon(
        asset: persona.asset,
        size: vertical ? 66 : 54,
        colorOverrides: persona.colorOverrides,
      ),
    );

    final taglineChip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: c,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(persona.tagline,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: AppColors.ink, fontWeight: FontWeight.w900, fontSize: 11.5)),
    );

    final stats = _StatRow(l10n: l10n, persona: persona, center: vertical);

    final text = Column(
      crossAxisAlignment: vertical ? CrossAxisAlignment.center : CrossAxisAlignment.start,
      children: [
        // 이름과 태그라인은 둘 다 줄어들 수 있어야 한다 — 번역에 따라 길이가 크게
        // 달라진다("신중한 전략가" vs "Cautious strategist"). 고정 크기로 두면
        // 영어에서 가로로 넘친다.
        Row(
          mainAxisSize: vertical ? MainAxisSize.min : MainAxisSize.max,
          children: [
            Flexible(
              child: Text(persona.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: c, fontWeight: FontWeight.w900, fontSize: 23, letterSpacing: 0.5)),
            ),
            const SizedBox(width: 10),
            Flexible(child: taglineChip),
          ],
        ),
        const SizedBox(height: 5),
        Text(persona.desc,
            textAlign: vertical ? TextAlign.center : TextAlign.start,
            style: const TextStyle(color: AppColors.textMuted, fontSize: 12.5)),
        const SizedBox(height: 10),
        stats,
      ],
    );

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(AppShapes.radius),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppShapes.radius),
        onTap: onTap,
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: vertical ? 14 : 16, vertical: vertical ? 18 : 16),
          decoration: BoxDecoration(
            gradient: cardBg,
            borderRadius: BorderRadius.circular(AppShapes.radius),
            border: Border.all(color: c.withValues(alpha: 0.6), width: 1.3),
            boxShadow: AppShapes.panelShadow,
          ),
          child: vertical
              ? Column(children: [badge, const SizedBox(height: 14), text])
              : Row(
                  children: [
                    badge,
                    const SizedBox(width: 16),
                    Expanded(child: text),
                    const SizedBox(width: 6),
                    Icon(Icons.chevron_right_rounded, color: c, size: 28),
                  ],
                ),
        ),
      ),
    );
  }
}

/// 기풍 스탯 3종(공격/수비/변칙)을 도트 게이지로 표시.
class _StatRow extends StatelessWidget {
  const _StatRow({required this.l10n, required this.persona, required this.center});
  final AppLocalizations l10n;
  final Persona persona;
  final bool center;

  @override
  Widget build(BuildContext context) {
    Widget stat(String label, int value) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label,
                style: const TextStyle(
                    color: AppColors.textMuted, fontSize: 10.5, fontWeight: FontWeight.w800)),
            const SizedBox(width: 5),
            for (var i = 0; i < 5; i++)
              Padding(
                padding: const EdgeInsets.only(right: 2.5),
                child: Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: i < value ? persona.color : AppColors.gaugeOff,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
          ],
        );

    return Wrap(
      alignment: center ? WrapAlignment.center : WrapAlignment.start,
      spacing: 14,
      runSpacing: 6,
      children: [
        stat(l10n.statPressure, persona.pressure),
        stat(l10n.statSteady, persona.steady),
        stat(l10n.statBluff, persona.bluff),
      ],
    );
  }
}

/// 감정 표현(이모트) 미리보기 — 대전 중 상대에게 보내는 기능의 예고편.
class _EmoteStrip extends StatelessWidget {
  const _EmoteStrip({required this.l10n});
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppShapes.radius),
        border: Border.all(color: AppColors.goldDeep, width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.emoji_emotions_rounded, size: 18, color: AppColors.gold),
              const SizedBox(width: 8),
              Text(l10n.emotesTitle,
                  style: const TextStyle(color: AppColors.textMain, fontWeight: FontWeight.w800, fontSize: 14)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(l10n.emotesDesc,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              for (final e in kEmoteAssets)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Container(
                      decoration: BoxDecoration(
                        color: AppColors.bgBottom,
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.stroke),
                      ),
                      padding: const EdgeInsets.all(8),
                      child: PersonaIcon(asset: e, size: 36),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
