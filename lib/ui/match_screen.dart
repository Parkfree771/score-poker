import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../monetization/monetization.dart';
import 'game_screen.dart';
import 'persona_select_screen.dart' show PersonaCard, BoostCard;
import 'personas.dart';
import 'theme.dart';

/// **사람 vs AI 매칭** — 상대를 고르지 않는다. 랜덤으로 배정된 상대가 공개된다.
///
/// 흐름: "상대를 찾는 중…"(프로필들이 빠르게 돌아감, ~1.2초) → 상대 카드 공개 →
/// 부스트 토글 → 대전 시작. 다시 뽑기는 없다(랜덤 매칭의 의미가 사라진다).
/// [fixed]/[seed]는 테스트·캡처용.
class MatchScreen extends StatefulWidget {
  const MatchScreen({super.key, this.fixed, this.seed, this.searchDuration});

  final Persona? fixed;
  final int? seed;

  /// 찾는 중 연출 길이(테스트에서 0으로).
  final Duration? searchDuration;

  @override
  State<MatchScreen> createState() => _MatchScreenState();
}

class _MatchScreenState extends State<MatchScreen> {
  Persona? _opponent;
  bool _boost = true;
  bool _starting = false;
  int _spin = 0;
  Timer? _spinTimer;
  Timer? _revealTimer;

  @override
  void initState() {
    super.initState();
    final dur = widget.searchDuration ?? const Duration(milliseconds: 1300);
    _spinTimer = Timer.periodic(const Duration(milliseconds: 110), (_) {
      if (mounted) setState(() => _spin++);
    });
    _revealTimer = Timer(dur, _reveal);
  }

  void _reveal() {
    _spinTimer?.cancel();
    if (!mounted) return;
    final l10n = AppLocalizations.of(context);
    final personas = buildPersonas(l10n);
    final rng = Random(widget.seed);
    setState(() => _opponent = widget.fixed ?? personas[rng.nextInt(personas.length)]);
  }

  @override
  void dispose() {
    _spinTimer?.cancel();
    _revealTimer?.cancel();
    super.dispose();
  }

  Future<void> _start() async {
    final persona = _opponent;
    if (persona == null || _starting) return;
    setState(() => _starting = true);
    final wallet = MonetizationScope.maybeOf(context)?.wallet;
    // 부스트는 **판을 시작하는 순간** 하나 소모된다(도메인이 판당 1개를 강제한다).
    final boosted = _boost && wallet != null && await wallet.spend(TokenKind.boost);
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(builder: (_) => GameScreen(persona: persona, boosted: boosted)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final personas = buildPersonas(l10n);
    final opp = _opponent;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.matchTitle)),
      body: DecoratedBox(
        decoration: const BoxDecoration(gradient: AppColors.bgGradient),
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                children: [
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 380),
                    switchInCurve: Curves.easeOutBack,
                    child: opp == null
                        ? _Searching(
                            key: const ValueKey('searching'),
                            l10n: l10n,
                            personas: personas,
                            tick: _spin,
                          )
                        : Column(
                            key: const ValueKey('found'),
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding: const EdgeInsets.only(left: 4, bottom: 12),
                                child: Text(l10n.matchFound,
                                    style: const TextStyle(
                                        color: AppColors.goldSoft,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: 0.4)),
                              ),
                              PersonaCard(l10n: l10n, persona: opp, onTap: _start),
                            ],
                          ),
                  ),
                  const SizedBox(height: 18),
                  BoostCard(
                      l10n: l10n, enabled: _boost, onChanged: (v) => setState(() => _boost = v)),
                  const SizedBox(height: 18),
                  FilledButton(
                    key: const ValueKey('match-start'),
                    onPressed: opp == null || _starting ? null : _start,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.gold,
                      foregroundColor: AppColors.ink,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: Text(opp == null ? l10n.matchSearching : l10n.matchStart,
                        style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 찾는 중 — 후보 프로필이 슬롯처럼 빠르게 돌아간다.
class _Searching extends StatelessWidget {
  const _Searching({super.key, required this.l10n, required this.personas, required this.tick});
  final AppLocalizations l10n;
  final List<Persona> personas;
  final int tick;

  @override
  Widget build(BuildContext context) {
    final p = personas[tick % personas.length];
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(AppShapes.radius),
        border: Border.all(color: AppColors.stroke),
      ),
      child: Column(
        children: [
          Container(
            width: 96,
            height: 96,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: p.badgeBg,
              shape: BoxShape.circle,
              border: Border.all(color: p.color.withValues(alpha: 0.6), width: 2),
            ),
            child: PersonaIcon(
                asset: p.asset, size: 68, colorOverrides: p.colorOverrides, animate: false),
          ),
          const SizedBox(height: 16),
          Text(l10n.matchSearching,
              style: const TextStyle(
                  color: AppColors.textMain, fontSize: 16, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text(l10n.matchSearchingHint,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textMuted, fontSize: 12.5)),
        ],
      ),
    );
  }
}
