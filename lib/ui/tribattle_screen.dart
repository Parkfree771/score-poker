import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../audio/sfx.dart';
import '../domain/tribattle.dart';
import '../feedback/haptics.dart';
import 'theme.dart';
import 'tribattle_icons.dart';

/// 트라이 배틀 화면 (실험 모드) — 룰 정본은 `docs/TRIBATTLE.md`.
///
/// 원칙 "계산은 게임이 하고 플레이어는 비교만 한다":
///  - 마켓 카드를 고르면 놓을 수 있는 칸마다 **얻는 점수(+N)** 를 미리 띄운다.
///  - 내 격자의 행/열 배지는 상대 같은 줄과의 **우세/열세를 색**으로 보여준다.
/// 문자열은 한국어 하드코딩 — 실험 모드가 정식 승격되면 ARB로 옮긴다.
class TriBattleScreen extends StatefulWidget {
  const TriBattleScreen({super.key, this.seed});

  /// 테스트용 시드. null이면 판마다 무작위.
  final int? seed;

  @override
  State<TriBattleScreen> createState() => _TriBattleScreenState();
}

enum _Phase { picking, resolving, matchOver }

class _TriBattleScreenState extends State<TriBattleScreen> {
  final _rng = Random();
  final _bot = const TriGreedyBot();
  final match = TriMatch();

  late TriGame game;
  _Phase phase = _Phase.picking;
  int gameNo = 1;

  /// 내가 고른 마켓 카드(배치 후보 미리보기 중). 봇 연출용으로도 쓴다.
  int? selectedMarket;
  bool botPicking = false;

  /// 판 정산 결과(정산 오버레이 표시용).
  TriResolution? lastRes;
  int _seq = 0; // 화면 이탈/재시작 시 비동기 루프 중단용

  @override
  void initState() {
    super.initState();
    _newGame(meFirst: true);
  }

  @override
  void dispose() {
    _seq++;
    super.dispose();
  }

  void _newGame({required bool meFirst}) {
    game = TriGame(
        seed: widget.seed ?? _rng.nextInt(1 << 30), leaderIsA: meFirst);
    selectedMarket = null;
    phase = _Phase.picking;
    lastRes = null;
    _playSfx(Sfx.shuffle);
    _afterMove();
  }

  // ---- 진행 ----

  /// 테스트 전용 — 탭 좌표 없이 픽·배치를 실행한다.
  @visibleForTesting
  void myPlaceForTest(int i, int r, int c) => _myPlace(i, r, c);

  /// 내 픽: 마켓 [i]를 (r,c)에 배치.
  void _myPlace(int i, int r, int c) {
    final merging = game.boardA.g[r][c] != null;
    game.pickAndPlace(i, r, c);
    selectedMarket = null;
    if (merging) {
      _playSfx(Sfx.chipTing);
      _haptic(Haptic.shieldLock);
    } else {
      _playSfx(Sfx.cardPlace);
      _haptic(Haptic.place);
    }
    setState(() {});
    _afterMove();
  }

  /// 수가 끝난 뒤 — 판 종료 확인, 아니면 봇 차례 진행.
  void _afterMove() {
    if (game.finished) {
      _resolveGame();
      return;
    }
    if (game.turnOwner == false) _botLoop();
  }

  /// 봇(상대) 픽 루프 — 고르는 카드를 잠깐 비춰서 "상대가 뭘 집는지"가 보이게 한다.
  Future<void> _botLoop() async {
    final seq = ++_seq;
    botPicking = true;
    while (mounted && seq == _seq && game.turnOwner == false) {
      await Future<void>.delayed(const Duration(milliseconds: 550));
      if (!mounted || seq != _seq) return;
      final pick = _bot.choose(game);
      if (pick == null) {
        // 둘 곳이 전혀 없다(이론상 보드 가득) — 첫 장 소각.
        game.pickAndBurn(0);
        setState(() {});
        continue;
      }
      final (i, r, c) = pick;
      setState(() => selectedMarket = i); // 상대가 집은 카드 하이라이트
      await Future<void>.delayed(const Duration(milliseconds: 420));
      if (!mounted || seq != _seq) return;
      final merging = game.boardB.g[r][c] != null;
      game.pickAndPlace(i, r, c);
      selectedMarket = null;
      _playSfx(merging ? Sfx.chipTick : Sfx.cardSlide);
      setState(() {});
    }
    botPicking = false;
    if (mounted && seq == _seq && game.finished) _resolveGame();
  }

  /// 판 정산 — 오버레이를 띄우고 HP를 깎는다.
  void _resolveGame() {
    final r = resolve(game.boardA, game.boardB);
    lastRes = r;
    phase = _Phase.resolving;
    final iWonJackpot = r.winner == 0 && r.jackpotRowsA.isNotEmpty;
    _playSfx(iWonJackpot ? Sfx.sting : Sfx.attackHit);
    _haptic(Haptic.impact);
    match.applyGame(r);
    setState(() {});
    if (match.over) {
      Future<void>.delayed(const Duration(milliseconds: 900), () {
        if (!mounted) return;
        _playSfx(match.winner == 0 ? Sfx.win : Sfx.lose);
        setState(() => phase = _Phase.matchOver);
      });
    }
  }

  void _nextGame() {
    // 진 쪽이 다음 판 선픽 — 역전 장치.
    final loserIsMe = lastRes!.winner == 1;
    gameNo++;
    setState(() => _newGame(meFirst: loserIsMe));
  }

  void _restartMatch() {
    match
      ..hpA = TriRules.hp.toDouble()
      ..hpB = TriRules.hp.toDouble()
      ..games.clear();
    gameNo = 1;
    setState(() => _newGame(meFirst: true));
  }

  void _playSfx(Sfx sfx) =>
      context.getInheritedWidgetOfExactType<SfxScope>()?.notifier?.play(sfx);

  void _haptic(Haptic h) =>
      context.getInheritedWidgetOfExactType<HapticScope>()?.notifier?.play(h);

  // ---- 빌드 ----

  @override
  Widget build(BuildContext context) {
    final myTurn = phase == _Phase.picking && game.turnOwner == true;
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: AppColors.bgGradient),
        child: SafeArea(
          child: Stack(children: [
            Column(children: [
              _topBar(),
              _hpBar(isMe: false),
              const SizedBox(height: 4),
              Expanded(
                  flex: 3,
                  child: _Grid(
                    board: game.boardB,
                    opp: game.boardA,
                    mine: false,
                    preview: null,
                    onTap: null,
                  )),
              _marketStrip(myTurn),
              Expanded(
                  flex: 4,
                  child: _Grid(
                    board: game.boardA,
                    opp: game.boardB,
                    mine: true,
                    preview: myTurn && selectedMarket != null
                        ? game.market[selectedMarket!]
                        : null,
                    onTap: myTurn && selectedMarket != null
                        ? (r, c) => _myPlace(selectedMarket!, r, c)
                        : null,
                  )),
              const SizedBox(height: 4),
              _hpBar(isMe: true),
              const SizedBox(height: 6),
            ]),
            if (phase == _Phase.resolving && !match.over) _resolutionOverlay(),
            if (phase == _Phase.matchOver) _matchOverOverlay(),
          ]),
        ),
      ),
    );
  }

  Widget _topBar() {
    final myTurn = game.turnOwner == true;
    final status = phase != _Phase.picking
        ? '정산'
        : myTurn
            ? '내 차례 — 마켓에서 카드를 고르세요'
            : '상대가 고르는 중…';
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 2, 8, 2),
      child: Row(children: [
        IconButton(
          icon: const Icon(Icons.close_rounded, color: AppColors.textMuted),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        Text('판 $gameNo · 라운드 ${min(game.round + 1, TriRules.rounds)}/3',
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
                  color: myTurn ? AppColors.goldSoft : AppColors.textMuted,
                  fontWeight: FontWeight.w700)),
        ),
      ]),
    );
  }

  Widget _hpBar({required bool isMe}) {
    final hp = isMe ? match.hpA : match.hpB;
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
              height: 10,
              child: Stack(children: [
                Container(color: AppColors.gaugeOff),
                AnimatedFractionallySizedBox(
                  duration: const Duration(milliseconds: 600),
                  curve: Curves.easeOutCubic,
                  widthFactor: (hp / TriRules.hp).clamp(0.0, 1.0),
                  child: Container(color: color),
                ),
              ]),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text('${hp.ceil()}',
            style: const TextStyle(
                color: AppColors.textMain,
                fontWeight: FontWeight.w800,
                fontSize: 13,
                fontFeatures: [FontFeature.tabularFigures()])),
      ]),
    );
  }

  /// 가운데 마켓 줄 — 남은 픽 순서를 점으로 보여준다.
  Widget _marketStrip(bool myTurn) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      padding: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.stroke),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        SizedBox(
          height: 58,
          child: game.market.isEmpty
              ? const Center(
                  child: Text('다음 라운드 준비…',
                      style: TextStyle(color: AppColors.textMuted)))
              : ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  itemCount: game.market.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 6),
                  itemBuilder: (_, i) {
                    final selected = selectedMarket == i;
                    return GestureDetector(
                      onTap: myTurn
                          ? () {
                              _haptic(Haptic.select);
                              setState(() =>
                                  selectedMarket = selected ? null : i);
                            }
                          : null,
                      child: _CardFace(
                        card: game.market[i],
                        size: 44,
                        highlight: selected
                            ? (botPicking
                                ? AppColors.oppPrimary
                                : AppColors.gold)
                            : null,
                      ),
                    );
                  },
                ),
        ),
      ]),
    );
  }

  // ---- 정산 오버레이 ----

  Widget _resolutionOverlay() {
    final r = lastRes!;
    final iWin = r.winner == 0;
    return _Scrim(
      child: _Panel(children: [
        Text(iWin ? '판 승리!' : (r.winner == 1 ? '판 패배' : '무승부'),
            style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w900,
                color: iWin ? AppColors.win : AppColors.lose)),
        const SizedBox(height: 4),
        Text(
            r.winner == -1
                ? 'HP 변화 없음'
                : '${iWin ? '상대' : '나'} HP −${r.net.ceil()}',
            style: const TextStyle(
                color: AppColors.textMain, fontWeight: FontWeight.w700)),
        if ((iWin ? r.jackpotRowsA : r.jackpotRowsB).isNotEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Text('🎰 잭팟 행 — 상한 돌파!',
                style: TextStyle(
                    color: AppColors.gold, fontWeight: FontWeight.w900)),
          ),
        const SizedBox(height: 10),
        _frontsTable(r),
        const SizedBox(height: 14),
        FilledButton(
          onPressed: _nextGame,
          style: FilledButton.styleFrom(
              backgroundColor: AppColors.gold, foregroundColor: AppColors.ink),
          child: const Text('다음 판',
              style: TextStyle(fontWeight: FontWeight.w900)),
        ),
      ]),
    );
  }

  /// 8전선 정산표 — 어느 줄에서 얼마나 벌었는지.
  Widget _frontsTable(TriResolution r) {
    Widget line(String name, double my, double opp) {
      final d = my - opp;
      final color = d > 0
          ? AppColors.win
          : d < 0
              ? AppColors.lose
              : AppColors.textMuted;
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 1.5),
        child: Row(children: [
          SizedBox(
              width: 44,
              child: Text(name,
                  style: const TextStyle(
                      color: AppColors.textMuted, fontSize: 12))),
          Expanded(
            child: Text(
                '${my.round()}  vs  ${opp.round()}',
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: AppColors.textMain,
                    fontSize: 12.5,
                    fontFeatures: [FontFeature.tabularFigures()])),
          ),
          SizedBox(
            width: 44,
            child: Text(d == 0 ? '—' : (d > 0 ? '+${d.round()}' : '${d.round()}'),
                textAlign: TextAlign.right,
                style: TextStyle(
                    color: color, fontWeight: FontWeight.w800, fontSize: 12.5)),
          ),
        ]),
      );
    }

    final rows = <Widget>[];
    for (var c = 0; c < TriRules.cols; c++) {
      rows.add(line('열${c + 1}', lineScore(game.boardA.col(c), isRow: false),
          lineScore(game.boardB.col(c), isRow: false)));
    }
    for (var i = 0; i < TriRules.rows; i++) {
      rows.add(line('행${i + 1}', lineScore(game.boardA.row(i), isRow: true),
          lineScore(game.boardB.row(i), isRow: true)));
    }
    return Column(mainAxisSize: MainAxisSize.min, children: rows);
  }

  Widget _matchOverOverlay() {
    final iWin = match.winner == 0;
    return _Scrim(
      child: _Panel(children: [
        Text(iWin ? '🏆 매치 승리!' : '매치 패배',
            style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w900,
                color: iWin ? AppColors.gold : AppColors.lose)),
        const SizedBox(height: 6),
        Text('${match.games.length}판 만에 결착',
            style: const TextStyle(color: AppColors.textMuted)),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: _restartMatch,
          style: FilledButton.styleFrom(
              backgroundColor: AppColors.gold, foregroundColor: AppColors.ink),
          child: const Text('다시 하기',
              style: TextStyle(fontWeight: FontWeight.w900)),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).maybePop(),
          child:
              const Text('나가기', style: TextStyle(color: AppColors.textMuted)),
        ),
      ]),
    );
  }
}

// ---- 격자 ----------------------------------------------------------------

class _Grid extends StatelessWidget {
  const _Grid({
    required this.board,
    required this.opp,
    required this.mine,
    required this.preview,
    required this.onTap,
  });

  final TriBoard board;
  final TriBoard opp;
  final bool mine;

  /// 배치 미리보기 중인 카드(내 격자에서만). 놓을 수 있는 칸에 +점수가 뜬다.
  final TriCard? preview;
  final void Function(int r, int c)? onTap;

  /// (r,c)에 [preview]를 놓았을 때 늘어나는 내 점수(행+열).
  double _gain(int r, int c) {
    final beforeR = lineScore(board.row(r), isRow: true);
    final beforeC = lineScore(board.col(c), isRow: false);
    final cur = board.g[r][c];
    final wasMerge = cur != null;
    board.put(r, c, preview!);
    final g = (lineScore(board.row(r), isRow: true) - beforeR) +
        (lineScore(board.col(c), isRow: false) - beforeC);
    board.g[r][c] = cur;
    if (wasMerge) board.merges--;
    return g;
  }

  @override
  Widget build(BuildContext context) {
    final legal = preview == null
        ? const <(int, int)>{}
        : board.places(preview!).toSet();
    return LayoutBuilder(builder: (context, box) {
      // 셀 크기: 가로 5칸 + 행 배지, 세로 3칸 + 열 배지에 맞춘다.
      // 62 상한: 큰 화면에서 내 격자가 비대해지지 않게.
      final cell = min(
          62.0,
          min((box.maxWidth - 60) / TriRules.cols,
              (box.maxHeight - 26) / TriRules.rows));
      final gridW = cell * TriRules.cols;
      Widget rowBadge(int r) {
        final my = lineScore(board.row(r), isRow: true);
        final theirs = lineScore(opp.row(r), isRow: true);
        return _ScoreBadge(
            score: my, winning: my > theirs, losing: my < theirs, mine: mine);
      }

      Widget colBadge(int c) {
        final my = lineScore(board.col(c), isRow: false);
        final theirs = lineScore(opp.col(c), isRow: false);
        return SizedBox(
          width: cell,
          child: Center(
              child: _ScoreBadge(
                  score: my,
                  winning: my > theirs,
                  losing: my < theirs,
                  mine: mine)),
        );
      }

      final grid = Column(mainAxisSize: MainAxisSize.min, children: [
        // 열 배지: 내 격자는 위(상대 쪽을 향해), 상대 격자는 아래.
        if (mine)
          SizedBox(
              width: gridW,
              child: Row(children: [
                for (var c = 0; c < TriRules.cols; c++) colBadge(c)
              ])),
        for (var r = 0; r < TriRules.rows; r++)
          Row(mainAxisSize: MainAxisSize.min, children: [
            for (var c = 0; c < TriRules.cols; c++)
              _cellWidget(mine ? r : TriRules.rows - 1 - r, c, cell, legal),
            const SizedBox(width: 4),
            rowBadge(mine ? r : TriRules.rows - 1 - r),
          ]),
        if (!mine)
          SizedBox(
              width: gridW,
              child: Row(children: [
                for (var c = 0; c < TriRules.cols; c++) colBadge(c)
              ])),
      ]);
      // FittedBox: 배지 높이까지 합친 실측이 칸 계산과 어긋나도 넘치지 않게.
      return Center(child: FittedBox(fit: BoxFit.scaleDown, child: grid));
    });
  }

  Widget _cellWidget(int r, int c, double size, Set<(int, int)> legal) {
    final card = board.g[r][c];
    final isLegal = legal.contains((r, c));
    final isMerge = isLegal && card != null;
    final jackpotGlow = card != null && rowTier(board.row(r)) != RowTier.none;
    return GestureDetector(
      onTap: isLegal ? () => onTap?.call(r, c) : null,
      child: Container(
        width: size,
        height: size,
        margin: const EdgeInsets.all(1.5),
        decoration: BoxDecoration(
          color: card == null ? AppColors.slotRecess : AppColors.cardBody,
          borderRadius: BorderRadius.circular(7),
          border: Border.all(
            color: isMerge
                ? AppColors.purple
                : isLegal
                    ? AppColors.gold
                    : jackpotGlow
                        ? AppColors.gold
                        : AppColors.stroke,
            width: isLegal || jackpotGlow ? 2 : 1,
          ),
          boxShadow: jackpotGlow
              ? [
                  BoxShadow(
                      color: AppColors.gold.withValues(alpha: 0.45),
                      blurRadius: 8)
                ]
              : null,
        ),
        child: card == null
            ? (isLegal ? _gainLabel(r, c) : null)
            : Stack(alignment: Alignment.center, children: [
                _CardGlyph(card: card, size: size),
                if (isMerge)
                  Positioned(
                      bottom: 1,
                      child: _gainLabel(r, c, merge: true) ??
                          const SizedBox.shrink()),
              ]),
      ),
    );
  }

  Widget? _gainLabel(int r, int c, {bool merge = false}) {
    if (preview == null) return null;
    final g = _gain(r, c);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
      decoration: merge
          ? BoxDecoration(
              color: AppColors.purple, borderRadius: BorderRadius.circular(5))
          : null,
      child: Text(
        merge ? '합성 +${g.round()}' : '+${g.round()}',
        style: TextStyle(
          fontSize: merge ? 8.5 : 11,
          fontWeight: FontWeight.w900,
          color: merge ? Colors.white : AppColors.goldSoft,
        ),
      ),
    );
  }
}

/// 줄 점수 배지 — 색이 곧 전선 상황(초록 우세 / 빨강 열세 / 회색 동률).
class _ScoreBadge extends StatelessWidget {
  const _ScoreBadge(
      {required this.score,
      required this.winning,
      required this.losing,
      required this.mine});
  final double score;
  final bool winning, losing, mine;

  @override
  Widget build(BuildContext context) {
    final color = !mine
        ? AppColors.textMuted // 상대 배지는 색 없이 — 내 배지가 비교를 담당한다.
        : winning
            ? AppColors.win
            : losing
                ? AppColors.lose
                : AppColors.textMuted;
    return Container(
      width: 34,
      padding: const EdgeInsets.symmetric(vertical: 1),
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text('${score.round()}',
          textAlign: TextAlign.center,
          style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              color: color,
              fontFeatures: const [FontFeature.tabularFigures()])),
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
      duration: const Duration(milliseconds: 150),
      width: size,
      height: size * 1.25,
      decoration: BoxDecoration(
        color: AppColors.cardBody,
        borderRadius: BorderRadius.circular(8),
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
      child: _CardGlyph(card: card, size: size),
    );
  }
}

/// 카드 내용물 — 원소 아이콘 위에 숫자.
class _CardGlyph extends StatelessWidget {
  const _CardGlyph({required this.card, required this.size});
  final TriCard card;
  final double size;

  @override
  Widget build(BuildContext context) {
    final big = card.value > 9; // 합성값은 크게 강조
    return Stack(alignment: Alignment.center, children: [
      Opacity(opacity: 0.9, child: ElementIcon(card.elem, size: size * 0.62)),
      Positioned(
        right: 2,
        bottom: 0,
        child: Text(
          '${card.value}',
          style: TextStyle(
            fontSize: size * (big ? 0.34 : 0.4),
            height: 1,
            fontWeight: FontWeight.w900,
            color: big ? AppColors.purple : AppColors.ink,
            shadows: const [
              Shadow(color: AppColors.cardBody, blurRadius: 3),
              Shadow(color: AppColors.cardBody, blurRadius: 3),
            ],
          ),
        ),
      ),
    ]);
  }
}

// ---- 공용 오버레이 ----

class _Scrim extends StatelessWidget {
  const _Scrim({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Positioned.fill(
        child: ColoredBox(
          color: Colors.black.withValues(alpha: 0.6),
          child: Center(child: child),
        ),
      );
}

class _Panel extends StatelessWidget {
  const _Panel({required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.symmetric(horizontal: 28),
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppShapes.radius),
          border: Border.all(color: AppColors.feltEdge),
          boxShadow: AppShapes.panelShadow,
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: children),
      );
}
