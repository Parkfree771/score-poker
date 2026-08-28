import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../audio/sfx.dart';
import '../domain/tribattle.dart';
import '../feedback/haptics.dart';
import 'theme.dart';
import 'tribattle_icons.dart';

/// 트라이 배틀 (실험 모드) — 룰 정본은 `docs/TRIBATTLE.md`.
///
/// 한 줄 5열 누적 전장. 연출 셋이 이 게임의 손맛이다:
///  1. **표롱(합체)**: 카드가 열로 날아가 얹히며 값이 촤륵 합쳐지고 팝.
///  2. **원소 공격**: 라운드 정산 때 이긴 열에서 진 열로 원소색 탄이 날아가 명중.
///  3. **족보 대결**: "풀하우스 612 vs 플러시 487" 배너 후 큰 한 방.
/// 문자열은 한국어 하드코딩 — 정식 승격 시 ARB로 옮긴다.
class TriBattleScreen extends StatefulWidget {
  const TriBattleScreen({super.key, this.seed});

  /// 테스트용 시드. null이면 게임마다 무작위.
  final int? seed;

  @override
  State<TriBattleScreen> createState() => _TriBattleScreenState();
}

const _elemColor = {
  TriElement.water: Color(0xFF57A7E0),
  TriElement.fire: Color(0xFFE0733C),
  TriElement.forest: Color(0xFF63B052),
};

class _TriBattleScreenState extends State<TriBattleScreen>
    with TickerProviderStateMixin {
  final _rng = Random();
  final _bot = const TriGreedyBot();

  late TriGame game;

  /// 연출 중 표시용 HP — 열 공격이 명중할 때마다 하나씩 깎여 내려간다.
  /// (도메인 HP는 라운드 정산을 확정할 때 한 번에 반영된다.)
  late double shownHpA;
  late double shownHpB;

  int? selectedMarket;
  bool botPicking = false;
  bool ceremony = false; // 정산 연출 재생 중 — 입력 잠금
  bool gameOver = false;

  /// 족보 대결 배너(정산 연출의 마지막 장).
  TriRoundResult? rowBanner;

  int _seq = 0;

  /// 살아 있는 오버레이 연출(컨트롤러, 엔트리) — 화면이 닫히면 일괄 정리한다.
  /// (비행 중 dispose되면 ticker가 새는 것을 막는다.)
  final _fx = <(AnimationController, OverlayEntry)>[];
  final _marketKeys = [
    for (var i = 0; i < TriRules.marketSize; i++) GlobalKey()
  ];
  final _cellKeysA = [for (var i = 0; i < TriRules.cols; i++) GlobalKey()];
  final _cellKeysB = [for (var i = 0; i < TriRules.cols; i++) GlobalKey()];

  @override
  void initState() {
    super.initState();
    _newGame();
  }

  @override
  void dispose() {
    _seq++;
    for (final (c, e) in _fx) {
      e.remove();
      c.dispose();
    }
    _fx.clear();
    super.dispose();
  }

  /// 연출 하나를 등록·실행·정리한다. dispose가 먼저 오면 거기서 정리된다.
  Future<void> _runFx(AnimationController ctrl, OverlayEntry entry,
      {bool wait = true}) async {
    final rec = (ctrl, entry);
    _fx.add(rec);
    Overlay.of(context).insert(entry);
    try {
      if (wait) {
        await ctrl.forward();
      } else {
        unawaited(ctrl.forward().whenComplete(() {
          if (_fx.remove(rec)) {
            entry.remove();
            ctrl.dispose();
          }
        }));
        return;
      }
    } finally {
      if (wait && _fx.remove(rec)) {
        entry.remove();
        ctrl.dispose();
      }
    }
  }

  void _newGame() {
    game = TriGame(seed: widget.seed ?? _rng.nextInt(1 << 30));
    shownHpA = game.hpA;
    shownHpB = game.hpB;
    selectedMarket = null;
    ceremony = false;
    gameOver = false;
    rowBanner = null;
    _playSfx(Sfx.shuffle);
    _maybeBotTurn();
  }

  // ---- 진행 ----------------------------------------------------------------

  /// 테스트 전용 — 좌표·연출 없이 픽·배치.
  @visibleForTesting
  void myPlaceForTest(int i, int col) {
    game.pickAndPlace(i, col);
    setState(() {});
    _afterMove();
  }

  Future<void> _myPlace(int i, int col) async {
    final seq = _seq;
    final from = _rectOf(_marketKeys[i]);
    final to = _rectOf(_cellKeysA[col]);
    final card = game.market[i]!;
    final merging = game.rowA[col] != null;
    selectedMarket = null;
    game.pickAndPlace(i, col);
    _haptic(Haptic.place);
    setState(() {});
    if (from != null && to != null) {
      await _flyCard(from, to, card);
      if (!mounted || seq != _seq) return;
    }
    _playSfx(merging ? Sfx.chipTing : Sfx.cardPlace);
    if (merging) _haptic(Haptic.shieldLock);
    setState(() {}); // 셀이 새 값으로 — _StackCell이 카운트업·팝을 잇는다
    _afterMove();
  }

  void _afterMove() {
    if (game.pendingResult != null) {
      _playCeremony();
      return;
    }
    _maybeBotTurn();
  }

  void _maybeBotTurn() {
    if (game.turnOwner == false) _botLoop();
  }

  Future<void> _botLoop() async {
    final seq = ++_seq;
    botPicking = true;
    while (mounted && seq == _seq && game.turnOwner == false) {
      await Future<void>.delayed(const Duration(milliseconds: 480));
      if (!mounted || seq != _seq) return;
      final pick = _bot.choose(game);
      if (pick == null) break;
      final (i, col) = pick;
      setState(() => selectedMarket = i); // 뭘 집는지 보여준다 — 정보전
      await Future<void>.delayed(const Duration(milliseconds: 380));
      if (!mounted || seq != _seq) return;
      final from = _rectOf(_marketKeys[i]);
      final to = _rectOf(_cellKeysB[col]);
      final card = game.market[i]!;
      final merging = game.rowB[col] != null;
      selectedMarket = null;
      game.pickAndPlace(i, col);
      setState(() {});
      if (from != null && to != null) {
        await _flyCard(from, to, card);
        if (!mounted || seq != _seq) return;
      }
      _playSfx(merging ? Sfx.chipTick : Sfx.cardSlide);
      setState(() {});
    }
    botPicking = false;
    if (mounted && seq == _seq && game.pendingResult != null) _playCeremony();
  }

  /// 라운드 정산 연출 — 열 대결 5방(원소탄) → 족보 배너 → HP 확정.
  Future<void> _playCeremony() async {
    final seq = ++_seq;
    final r = game.pendingResult!;
    setState(() => ceremony = true);
    await Future<void>.delayed(const Duration(milliseconds: 450));

    for (final duel in r.duels) {
      if (!mounted || seq != _seq) return;
      if (duel.winnerElem == null) continue; // 무승부 열은 조용히
      final aWins = duel.dmgToB > 0;
      final from = _rectOf(aWins ? _cellKeysA[duel.col] : _cellKeysB[duel.col]);
      final to = _rectOf(aWins ? _cellKeysB[duel.col] : _cellKeysA[duel.col]);
      final dmg = aWins ? duel.dmgToB : duel.dmgToA;
      if (from != null && to != null) {
        await _shootElement(from, to, duel.winnerElem!);
        if (!mounted || seq != _seq) return;
        unawaited(_floatDamage(to, dmg));
      }
      _playSfx(Sfx.attackHit);
      _haptic(Haptic.select);
      setState(() {
        if (aWins) {
          shownHpB = max(0, shownHpB - dmg);
        } else {
          shownHpA = max(0, shownHpA - dmg);
        }
      });
      await Future<void>.delayed(const Duration(milliseconds: 240));
    }

    // 족보 대결 — 배너를 띄우고 큰 한 방.
    if (!mounted || seq != _seq) return;
    setState(() => rowBanner = r);
    _playSfx(Sfx.sting);
    await Future<void>.delayed(const Duration(milliseconds: 1100));
    if (!mounted || seq != _seq) return;
    final rowDmg = max(r.rowDmgToA, r.rowDmgToB);
    if (rowDmg > 0) {
      _playSfx(Sfx.attackHit);
      _haptic(Haptic.impact);
      final aLoses = r.rowDmgToA > 0;
      final to = _rectOf(aLoses ? _cellKeysA[2] : _cellKeysB[2]);
      if (to != null) unawaited(_floatDamage(to, rowDmg, big: true));
      setState(() {
        if (aLoses) {
          shownHpA = max(0, shownHpA - rowDmg);
        } else {
          shownHpB = max(0, shownHpB - rowDmg);
        }
      });
    }
    await Future<void>.delayed(const Duration(milliseconds: 900));
    if (!mounted || seq != _seq) return;

    game.applyPendingResult();
    shownHpA = game.hpA;
    shownHpB = game.hpB;
    rowBanner = null;
    ceremony = false;
    if (game.over) {
      _playSfx(game.winner == 0 ? Sfx.win : Sfx.lose);
      setState(() => gameOver = true);
      return;
    }
    _playSfx(Sfx.shuffle);
    setState(() {});
    _maybeBotTurn();
  }

  // ---- 오버레이 연출 헬퍼 --------------------------------------------------

  Rect? _rectOf(GlobalKey key) {
    final box = key.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.attached) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  Future<void> _flyCard(Rect from, Rect to, TriCard card) async {
    final ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 260));
    final curve = CurvedAnimation(parent: ctrl, curve: Curves.easeInOutCubic);
    late OverlayEntry e;
    e = OverlayEntry(builder: (_) {
      return AnimatedBuilder(
        animation: curve,
        builder: (_, __) {
          final rect = Rect.lerp(from, to, curve.value)!;
          return Positioned(
            left: rect.left,
            top: rect.top,
            width: rect.width,
            height: rect.height,
            child:
                IgnorePointer(child: _CardFace(card: card, size: rect.width)),
          );
        },
      );
    });
    await _runFx(ctrl, e);
  }

  /// 원소탄 — 이긴 열에서 진 열로 원소색 구체가 날아가 터진다.
  Future<void> _shootElement(Rect from, Rect to, TriElement elem) async {
    final color = _elemColor[elem]!;
    final ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 300));
    final move = CurvedAnimation(parent: ctrl, curve: Curves.easeIn);
    late OverlayEntry e;
    e = OverlayEntry(builder: (_) {
      return AnimatedBuilder(
        animation: move,
        builder: (_, __) {
          final c = Offset.lerp(from.center, to.center, move.value)!;
          const size = 34.0;
          return Positioned(
            left: c.dx - size / 2,
            top: c.dy - size / 2,
            width: size,
            height: size,
            child: IgnorePointer(
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color.withValues(alpha: 0.35),
                  boxShadow: [
                    BoxShadow(color: color, blurRadius: 18, spreadRadius: 2)
                  ],
                ),
                padding: const EdgeInsets.all(4),
                child: ElementIcon(elem, size: size - 8),
              ),
            ),
          );
        },
      );
    });
    await _runFx(ctrl, e);
    if (!mounted) return;
    // 명중 플래시.
    final flash = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 220));
    late OverlayEntry f;
    f = OverlayEntry(builder: (_) {
      return AnimatedBuilder(
        animation: flash,
        builder: (_, __) {
          final t = flash.value;
          final size = to.width * (0.6 + t * 1.2);
          return Positioned(
            left: to.center.dx - size / 2,
            top: to.center.dy - size / 2,
            width: size,
            height: size,
            child: IgnorePointer(
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                      color: color.withValues(alpha: 1 - t), width: 3),
                ),
              ),
            ),
          );
        },
      );
    });
    await _runFx(flash, f, wait: false);
  }

  /// 데미지 숫자가 떠올랐다 사라진다.
  Future<void> _floatDamage(Rect at, double dmg, {bool big = false}) async {
    final ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 700));
    late OverlayEntry e;
    e = OverlayEntry(builder: (_) {
      return AnimatedBuilder(
        animation: ctrl,
        builder: (_, __) {
          final t = Curves.easeOut.transform(ctrl.value);
          return Positioned(
            left: at.center.dx - 40,
            top: at.top - 10 - 30 * t,
            width: 80,
            child: IgnorePointer(
              child: Opacity(
                opacity: (1 - t).clamp(0, 1),
                child: Text(
                  '-${dmg.round()}',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: big ? 30 : 19,
                    fontWeight: FontWeight.w900,
                    color: AppColors.lose,
                    shadows: const [Shadow(color: Colors.black, blurRadius: 6)],
                  ),
                ),
              ),
            ),
          );
        },
      );
    });
    await _runFx(ctrl, e);
  }

  void _playSfx(Sfx sfx) =>
      context.getInheritedWidgetOfExactType<SfxScope>()?.notifier?.play(sfx);

  void _haptic(Haptic h) =>
      context.getInheritedWidgetOfExactType<HapticScope>()?.notifier?.play(h);

  // ---- 빌드 ----------------------------------------------------------------

  bool get _myTurn => !ceremony && !gameOver && game.turnOwner == true;

  @override
  Widget build(BuildContext context) {
    final preview =
        _myTurn && selectedMarket != null ? game.market[selectedMarket!] : null;
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: AppColors.bgGradient),
        child: SafeArea(
          child: Stack(children: [
            Column(children: [
              _topBar(),
              _hpBar(isMe: false),
              const Spacer(),
              _comboLabel(game.rowB, mine: false),
              const SizedBox(height: 6),
              _row(game.rowB, _cellKeysB, mine: false, preview: null),
              const SizedBox(height: 8),
              _duelHints(),
              // 가운데 마켓 판 — 정산 중엔 **샥 접혀서** 두 줄이 맞붙는다.
              AnimatedSize(
                duration: const Duration(milliseconds: 380),
                curve: Curves.easeInOutCubic,
                child: ceremony || gameOver
                    ? const SizedBox(width: double.infinity, height: 8)
                    : _marketBoard(),
              ),
              const SizedBox(height: 8),
              _row(game.rowA, _cellKeysA, mine: true, preview: preview),
              const SizedBox(height: 6),
              _comboLabel(game.rowA, mine: true),
              const Spacer(),
              _hpBar(isMe: true),
              const SizedBox(height: 8),
            ]),
            if (rowBanner != null) _rowDuelBanner(rowBanner!),
            if (gameOver) _gameOverOverlay(),
          ]),
        ),
      ),
    );
  }

  Widget _topBar() {
    final status = gameOver
        ? ''
        : ceremony
            ? '정산 중…'
            : _myTurn
                ? (selectedMarket == null
                    ? '내 차례 — 마켓에서 카드를 고르세요'
                    : '얹을 열을 고르세요')
                : '상대가 고르는 중…';
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 2, 10, 2),
      child: Row(children: [
        IconButton(
          icon: const Icon(Icons.close_rounded, color: AppColors.textMuted),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        Text(
            '라운드 ${min(game.round + 1, TriRules.maxRounds)}/${TriRules.maxRounds}',
            style: const TextStyle(
                color: AppColors.textMain, fontWeight: FontWeight.w800)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(status,
              textAlign: TextAlign.right,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 12.5,
                  color: _myTurn ? AppColors.goldSoft : AppColors.textMuted,
                  fontWeight: FontWeight.w700)),
        ),
      ]),
    );
  }

  Widget _hpBar({required bool isMe}) {
    final hp = isMe ? shownHpA : shownHpB;
    final color = isMe ? AppColors.mePrimary : AppColors.oppPrimary;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Row(children: [
        Text(isMe ? '나' : '상대',
            style: TextStyle(
                color: color, fontWeight: FontWeight.w900, fontSize: 13)),
        const SizedBox(width: 8),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: SizedBox(
              height: 12,
              child: Stack(children: [
                Container(color: AppColors.gaugeOff),
                AnimatedFractionallySizedBox(
                  duration: const Duration(milliseconds: 420),
                  curve: Curves.easeOutCubic,
                  widthFactor: (hp / TriRules.hp).clamp(0.0, 1.0),
                  child: Container(color: color),
                ),
              ]),
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 40,
          child: Text('${hp.ceil()}',
              textAlign: TextAlign.right,
              style: const TextStyle(
                  color: AppColors.textMain,
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                  fontFeatures: [FontFeature.tabularFigures()])),
        ),
      ]),
    );
  }

  /// 두 줄 사이 — 열별 우세 화살표(누가 위인지 항상 보인다).
  Widget _duelHints() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var c = 0; c < TriRules.cols; c++)
          SizedBox(width: 66, child: Center(child: _duelHint(c))),
      ],
    );
  }

  Widget _duelHint(int c) {
    final a = game.rowA[c], b = game.rowB[c];
    if (a == null || b == null) {
      return const Text('·', style: TextStyle(color: AppColors.textMuted));
    }
    final d = colDuel(c, a, b);
    if (d.winnerElem == null) {
      return const Text('=',
          style: TextStyle(
              color: AppColors.tie, fontWeight: FontWeight.w900, fontSize: 13));
    }
    final aWins = d.dmgToB > 0;
    return Icon(
      aWins
          ? Icons.keyboard_double_arrow_up_rounded
          : Icons.keyboard_double_arrow_down_rounded,
      size: 20,
      color: _elemColor[d.winnerElem]!,
    );
  }

  Widget _row(List<TriCard?> row, List<GlobalKey> keys,
      {required bool mine, required TriCard? preview}) {
    final open = mine ? game.openA : game.openB;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var c = 0; c < TriRules.cols; c++)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: _StackCell(
              key: keys[c],
              card: row[c],
              highlight: mine && preview != null && open.contains(c),
              previewCard: mine && preview != null && open.contains(c)
                  ? (row[c] == null ? preview : row[c]!.mergeWith(preview))
                  : null,
              dimmed: mine &&
                  !ceremony &&
                  game.turnOwner == true &&
                  !open.contains(c),
              onTap: mine && preview != null && open.contains(c)
                  ? () => _myPlace(selectedMarket!, c)
                  : null,
            ),
          ),
      ],
    );
  }

  /// 줄 옆 족보 라벨 — "투페어 ×2.5 · 156".
  Widget _comboLabel(List<TriCard?> row, {required bool mine}) {
    final e = evalRow(row);
    final filled = row.whereType<TriCard>().length;
    final text = filled == 0
        ? ' '
        : filled < TriRules.cols
            ? '합계 ${e.score.round()}'
            : '${e.combo.label} ×${e.combo.mult} · ${e.score.round()}';
    return Text(
      text,
      style: TextStyle(
        fontSize: 12.5,
        fontWeight: FontWeight.w800,
        color: mine ? AppColors.goldSoft : AppColors.textMuted,
      ),
    );
  }

  /// 가운데 마켓 판 — 5×2 고정 슬롯. 픽된 자리는 홈만 남아 "소진"이 보인다.
  Widget _marketBoard() {
    final myTurn = _myTurn;
    Widget slot(int i) {
      final card = game.market[i];
      final selected = selectedMarket == i;
      if (card == null) {
        return Container(
          width: 50,
          height: 62,
          margin: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: AppColors.slotRecess,
            borderRadius: BorderRadius.circular(9),
            border: Border.all(color: AppColors.stroke),
          ),
        );
      }
      return GestureDetector(
        onTap: myTurn
            ? () {
                _haptic(Haptic.select);
                setState(() => selectedMarket = selected ? null : i);
              }
            : null,
        child: Padding(
          padding: const EdgeInsets.all(3),
          child: KeyedSubtree(
            key: _marketKeys[i],
            child: _CardFace(
              card: card,
              size: 50,
              highlight: selected
                  ? (botPicking ? AppColors.oppPrimary : AppColors.gold)
                  : null,
            ),
          ),
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.stroke),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          for (var i = 0; i < 5; i++) slot(i),
        ]),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          for (var i = 5; i < 10; i++) slot(i),
        ]),
      ]),
    );
  }

  /// 족보 대결 배너.
  Widget _rowDuelBanner(TriRoundResult r) {
    Widget side(TriRowEval e, bool mine, bool winner) => Column(
          crossAxisAlignment:
              mine ? CrossAxisAlignment.start : CrossAxisAlignment.end,
          children: [
            Text(mine ? '나' : '상대',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: mine ? AppColors.mePrimary : AppColors.oppPrimary)),
            Text(e.combo.label,
                style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: winner ? AppColors.gold : AppColors.textMain)),
            Text('${e.score.round()}',
                style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textMuted)),
          ],
        );
    final aWins = r.rowA.score >= r.rowB.score;
    return Positioned.fill(
      child: IgnorePointer(
        child: Center(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 24),
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
            decoration: BoxDecoration(
              color: AppColors.surface.withValues(alpha: 0.97),
              borderRadius: BorderRadius.circular(AppShapes.radius),
              border: Border.all(color: AppColors.feltEdge),
              boxShadow: AppShapes.panelShadow,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                side(r.rowA, true, aWins),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: Text('VS',
                      style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                          color: AppColors.gold)),
                ),
                side(r.rowB, false, !aWins),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _gameOverOverlay() {
    final iWin = game.winner == 0;
    final draw = game.winner == -1;
    return Positioned.fill(
      child: ColoredBox(
        color: Colors.black.withValues(alpha: 0.6),
        child: Center(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 28),
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 14),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppShapes.radius),
              border: Border.all(color: AppColors.feltEdge),
              boxShadow: AppShapes.panelShadow,
            ),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(draw ? '무승부' : (iWin ? '🏆 승리!' : '패배'),
                  style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w900,
                      color: iWin ? AppColors.gold : AppColors.lose)),
              const SizedBox(height: 4),
              Text(
                  '${game.round}라운드 · 나 ${game.hpA.ceil()} vs 상대 ${game.hpB.ceil()}',
                  style: const TextStyle(color: AppColors.textMuted)),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => setState(_newGame),
                style: FilledButton.styleFrom(
                    backgroundColor: AppColors.gold,
                    foregroundColor: AppColors.ink),
                child: const Text('다시 하기',
                    style: TextStyle(fontWeight: FontWeight.w900)),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).maybePop(),
                child: const Text('나가기',
                    style: TextStyle(color: AppColors.textMuted)),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

// ---- 열 스택 셀 ------------------------------------------------------------

/// 열 하나의 누적 카드. 값이 바뀌면(합체) **카운트업 + 팝** — "표롱"의 몸통.
class _StackCell extends StatefulWidget {
  const _StackCell({
    super.key,
    required this.card,
    required this.highlight,
    required this.previewCard,
    required this.dimmed,
    required this.onTap,
  });

  final TriCard? card;
  final bool highlight; // 지금 얹을 수 있는 열(골드 테두리)
  final TriCard? previewCard; // 얹으면 이렇게 된다(값·원소 미리보기)
  final bool dimmed; // 이번 라운드에 이미 채운 열
  final VoidCallback? onTap;

  @override
  State<_StackCell> createState() => _StackCellState();
}

class _StackCellState extends State<_StackCell>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pop = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
      value: 1);
  int _shownValue = 0;
  int _fromValue = 0;

  @override
  void initState() {
    super.initState();
    _shownValue = widget.card?.value ?? 0;
    _fromValue = _shownValue;
  }

  @override
  void didUpdateWidget(covariant _StackCell old) {
    super.didUpdateWidget(old);
    final v = widget.card?.value ?? 0;
    if (v != _shownValue) {
      _fromValue = old.card?.value ?? 0;
      _shownValue = v;
      if (v > 0 && _fromValue > 0) {
        _pop
          ..value = 0
          ..forward(); // 합체 순간에만 카운트업·팝
      } else {
        _pop.value = 1;
      }
    }
  }

  @override
  void dispose() {
    _pop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const size = 62.0;
    final card = widget.card;
    return GestureDetector(
      onTap: widget.onTap,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 150),
        opacity: widget.dimmed ? 0.55 : 1,
        child: AnimatedBuilder(
          animation: _pop,
          builder: (context, child) {
            // 팝: 1 → 1.18 → 1 (표롱).
            final scale = 1 + 0.18 * sin(pi * _pop.value);
            return Transform.scale(scale: scale, child: child);
          },
          child: Container(
            width: size,
            height: size * 1.18,
            decoration: BoxDecoration(
              color: card == null ? AppColors.slotRecess : AppColors.cardBody,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: widget.highlight ? AppColors.gold : AppColors.stroke,
                width: widget.highlight ? 2.4 : 1,
              ),
              boxShadow: widget.highlight
                  ? [
                      BoxShadow(
                          color: AppColors.gold.withValues(alpha: 0.4),
                          blurRadius: 10)
                    ]
                  : null,
            ),
            child: card == null
                ? (widget.previewCard != null
                    ? Center(child: _previewChip(widget.previewCard!))
                    : null)
                : Stack(alignment: Alignment.center, children: [
                    Opacity(
                        opacity: 0.92,
                        child: ElementIcon(card.elem, size: size * 0.6)),
                    Positioned(
                      bottom: 3,
                      child: AnimatedBuilder(
                        animation: _pop,
                        builder: (_, __) {
                          // 카운트업: 이전 값 → 새 값이 촤륵 올라간다.
                          final t = Curves.easeOut.transform(_pop.value);
                          final v = (_fromValue +
                                  (_shownValue - _fromValue) * t)
                              .round();
                          return Text(
                            '$v',
                            style: const TextStyle(
                              fontSize: size * 0.36,
                              height: 1,
                              fontWeight: FontWeight.w900,
                              color: AppColors.ink,
                              shadows: [
                                Shadow(
                                    color: AppColors.cardBody, blurRadius: 3),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                    if (widget.previewCard != null)
                      Positioned(
                          top: 2, child: _previewChip(widget.previewCard!)),
                  ]),
          ),
        ),
      ),
    );
  }

  /// "얹으면 이렇게 된다" — 합체 결과 값·원소 미리보기.
  Widget _previewChip(TriCard preview) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: _elemColor[preview.elem]!.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        ElementIcon(preview.elem, size: 12),
        const SizedBox(width: 2),
        Text('${preview.value}',
            style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w900,
                color: Colors.white)),
      ]),
    );
  }
}

/// 마켓의 카드(원소 아이콘 + 숫자).
class _CardFace extends StatelessWidget {
  const _CardFace({required this.card, required this.size, this.highlight});
  final TriCard card;
  final double size;
  final Color? highlight;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 140),
      width: size,
      height: size * 1.24,
      decoration: BoxDecoration(
        color: AppColors.cardBody,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(
            color: highlight ?? AppColors.stroke,
            width: highlight != null ? 2.5 : 1),
        boxShadow: highlight != null
            ? [
                BoxShadow(
                    color: highlight!.withValues(alpha: 0.5), blurRadius: 8)
              ]
            : null,
      ),
      child: Stack(alignment: Alignment.center, children: [
        Opacity(opacity: 0.9, child: ElementIcon(card.elem, size: size * 0.6)),
        Positioned(
          right: 3,
          bottom: 1,
          child: Text(
            '${card.value}',
            style: TextStyle(
              fontSize: size * 0.4,
              height: 1,
              fontWeight: FontWeight.w900,
              color: AppColors.ink,
              shadows: const [
                Shadow(color: AppColors.cardBody, blurRadius: 3),
                Shadow(color: AppColors.cardBody, blurRadius: 3),
              ],
            ),
          ),
        ),
      ]),
    );
  }
}
