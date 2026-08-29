import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../audio/sfx.dart';
import '../domain/tribattle.dart';
import '../feedback/haptics.dart';
import 'theme.dart';
import 'tribattle_icons.dart';

/// 트라이 배틀 v3 화면 (실험 모드) — 룰 정본은 `docs/TRIBATTLE.md`.
///
/// 원칙 "계산은 게임이 하고 플레이어는 비교만 한다":
///  - 손패를 고르면 놓을 수 있는 열마다 **얻는 점수(+N)**, 때릴 수 있는
///    상대 카드는 **빨간 테두리**로 미리 보여준다.
///  - 열 배지는 점수 + 현재 조합 라벨, 색은 상대 같은 열과의 우세/열세.
/// 문자열은 한국어 하드코딩 — 실험 모드가 정식 승격되면 ARB로 옮긴다.
class TriBattleScreen extends StatefulWidget {
  const TriBattleScreen({super.key, this.seed});

  /// 테스트용 시드. null이면 판마다 무작위.
  final int? seed;

  @override
  State<TriBattleScreen> createState() => _TriBattleScreenState();
}

enum _Phase { playing, resolving, matchOver }

class _TriBattleScreenState extends State<TriBattleScreen> {
  final _rng = Random();
  final _bot = const TriBot();
  final match = TriMatch();

  late TriGame game;
  _Phase phase = _Phase.playing;
  int gameNo = 1;

  /// 내가 고른 손패 인덱스(배치·공격 미리보기 중).
  int? selectedHand;

  /// 뒷면 배치 모드(코인 1) — 다음 배치에 적용.
  bool faceDownMode = false;

  /// 판 정산 결과: (승자, 데미지).
  (int, double)? lastRes;
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
        seed: widget.seed ?? _rng.nextInt(1 << 30), current: meFirst ? 0 : 1);
    selectedHand = null;
    faceDownMode = false;
    phase = _Phase.playing;
    lastRes = null;
    _playSfx(Sfx.shuffle);
    if (game.current == 1) _botLoop();
  }

  bool get myTurn =>
      phase == _Phase.playing && !game.finished && game.current == 0;

  // ---- 내 행동 ----

  void _tapHand(int i) {
    if (!myTurn || game.phase != TriPhase.action) return;
    _haptic(Haptic.select);
    setState(() => selectedHand = selectedHand == i ? null : i);
  }

  /// 테스트 전용 — 손패 [i]를 [col]에 배치.
  @visibleForTesting
  void placeForTest(int i, int col) {
    selectedHand = i;
    _placeAt(col);
  }

  void _placeAt(int col) {
    if (selectedHand == null || !game.boards[0].canPlace(col)) return;
    final fd = faceDownMode && game.coins[0] >= TriRules.costFaceDown;
    game.place(selectedHand!, col, faceDown: fd);
    selectedHand = null;
    faceDownMode = false;
    _playSfx(fd ? Sfx.chipTick : Sfx.cardPlace);
    _haptic(Haptic.place);
    setState(() {});
    _afterMove();
  }

  void _tapOppCard(int col, int row) {
    if (!myTurn || game.phase != TriPhase.action) return;
    final card = game.boards[1].cols[col][row];
    // 공격: 손패 선택 중 + 랭크 일치 + 보이는 비-방어막 카드.
    if (selectedHand != null &&
        !card.shield &&
        game.visibleTo(0, card) &&
        game.hands[0][selectedHand!].rank == card.rank) {
      game.attack(selectedHand!, col, row);
      selectedHand = null;
      _playSfx(Sfx.attackHit);
      _haptic(Haptic.impact);
      setState(() {});
      if (game.phase != TriPhase.shield) _afterMove();
      return;
    }
    // 훔쳐보기: 손패 미선택 + 뒷면 + 코인.
    if (selectedHand == null &&
        card.faceDown &&
        !card.peeked &&
        !card.shield &&
        game.coins[0] >= TriRules.costPeek) {
      game.peek(col, row);
      _playSfx(Sfx.chipTing);
      _haptic(Haptic.select);
      setState(() {});
    }
  }

  void _tapShieldSlot(bool own, int col) {
    if (game.phase != TriPhase.shield || game.current != 0) return;
    game.placeShield(own, col);
    _playSfx(Sfx.cardSlide);
    _haptic(Haptic.place);
    setState(() {});
    _afterMove();
  }

  void _discard() {
    if (!myTurn ||
        game.boards[0].openCols.isNotEmpty ||
        game.hands[0].isEmpty) {
      return;
    }
    game.discard(selectedHand ?? game.hands[0].length - 1);
    selectedHand = null;
    _playSfx(Sfx.cardSlide);
    setState(() {});
    _afterMove();
  }

  /// 수가 끝난 뒤 — 판 종료 확인, 아니면 봇 차례 진행.
  void _afterMove() {
    if (game.finished) {
      _resolveGame();
      return;
    }
    if (game.current == 1) _botLoop();
  }

  /// 봇(상대) 턴 루프 — 행동 사이에 딜레이를 줘 "뭘 하는지"가 보이게 한다.
  Future<void> _botLoop() async {
    final seq = ++_seq;
    while (mounted && seq == _seq && !game.finished && game.current == 1) {
      await Future<void>.delayed(const Duration(milliseconds: 650));
      if (!mounted || seq != _seq) return;
      final move = _bot.choose(game);
      switch (move) {
        case BotPeek(:final col, :final row):
          game.peek(col, row);
          _playSfx(Sfx.chipTing);
          setState(() {});
        // 훔쳐보기는 덤 행동 — 루프 계속.
        case BotAttack(:final handIdx, :final col, :final row):
          game.attack(handIdx, col, row);
          _playSfx(Sfx.attackHit);
          _haptic(Haptic.impact);
          setState(() {});
        case BotShield(:final ownField, :final col):
          game.placeShield(ownField, col);
          _playSfx(Sfx.cardSlide);
          setState(() {});
        case BotPlace(:final handIdx, :final col, :final faceDown):
          game.place(handIdx, col, faceDown: faceDown);
          _playSfx(faceDown ? Sfx.chipTick : Sfx.cardSlide);
          setState(() {});
        case BotDiscard(:final handIdx):
          game.discard(handIdx);
          _playSfx(Sfx.cardSlide);
          setState(() {});
      }
    }
    if (mounted && seq == _seq && game.finished) _resolveGame();
  }

  /// 판 정산 — 오버레이를 띄우고 HP를 깎는다.
  void _resolveGame() {
    final res = match.applyGame(game);
    lastRes = res;
    phase = _Phase.resolving;
    _playSfx(res.$1 == 0 ? Sfx.sting : Sfx.attackHit);
    _haptic(Haptic.impact);
    setState(() {});
    if (match.over) {
      Future<void>.delayed(const Duration(milliseconds: 900), () {
        if (!mounted) return;
        _playSfx(match.matchWinner == 0 ? Sfx.win : Sfx.lose);
        setState(() => phase = _Phase.matchOver);
      });
    }
  }

  void _nextGame() {
    // 진 쪽이 다음 판 선턴 — 역전 장치. (무승부면 나부터)
    gameNo++;
    setState(() => _newGame(meFirst: lastRes!.$1 != 0));
  }

  void _restartMatch() {
    match
      ..hpA = TriRules.hp.toDouble()
      ..hpB = TriRules.hp.toDouble()
      ..games = 0;
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
    final shieldMine = game.phase == TriPhase.shield && game.current == 0;
    final atkRank = myTurn &&
            game.phase == TriPhase.action &&
            selectedHand != null &&
            selectedHand! < game.hands[0].length
        ? game.hands[0][selectedHand!].rank
        : null;
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: AppColors.bgGradient),
        child: SafeArea(
          child: Stack(children: [
            Column(children: [
              _topBar(),
              _hpBar(isMe: false),
              const SizedBox(height: 2),
              Expanded(
                child: _BoardView(
                  board: game.boards[1],
                  opp: game.boards[0],
                  mine: false,
                  attackRank: atkRank,
                  attackVisible: (c) => game.visibleTo(0, c),
                  shieldCols:
                      shieldMine ? game.boards[1].openCols.toSet() : const {},
                  onCellTap: shieldMine ? null : _tapOppCard,
                  onEmptyColTap:
                      shieldMine ? (c) => _tapShieldSlot(false, c) : null,
                ),
              ),
              _handStrip(shieldMine),
              Expanded(
                child: _BoardView(
                  board: game.boards[0],
                  opp: game.boards[1],
                  mine: true,
                  preview: atkRank != null && !shieldMine
                      ? game.hands[0][selectedHand!]
                      : null,
                  shieldCols:
                      shieldMine ? game.boards[0].openCols.toSet() : const {},
                  onEmptyColTap: shieldMine
                      ? (c) => _tapShieldSlot(true, c)
                      : (myTurn && selectedHand != null ? _placeAt : null),
                ),
              ),
              const SizedBox(height: 2),
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
    final String status;
    if (phase != _Phase.playing) {
      status = '정산';
    } else if (game.phase == TriPhase.shield) {
      status = game.current == 0 ? '방어막 배치 — 아무 필드나!' : '상대가 방어막 배치 중…';
    } else if (myTurn) {
      status = selectedHand == null
          ? '내 차례 — 손패를 고르세요'
          : '놓을 열 또는 빨간 표적을 탭';
    } else {
      status = '상대 차례…';
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 2, 8, 2),
      child: Row(children: [
        IconButton(
          icon: const Icon(Icons.close_rounded, color: AppColors.textMuted),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        Text('판 $gameNo · 덱 ${game.deckLeft}',
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
    final coins = game.coins[isMe ? 0 : 1];
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
        const SizedBox(width: 10),
        Text('🪙$coins',
            style: const TextStyle(
                fontSize: 12,
                color: AppColors.goldSoft,
                fontWeight: FontWeight.w800)),
      ]),
    );
  }

  /// 가운데 손패 줄 — 손패 + 뒷면 토글 + 버리기.
  Widget _handStrip(bool shieldMine) {
    final hand = game.hands[0];
    final canFaceDown = game.coins[0] >= TriRules.costFaceDown;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 8),
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.stroke),
      ),
      child: Row(children: [
        if (shieldMine && game.pendingShield != null) ...[
          const Text('🛡', style: TextStyle(fontSize: 20)),
          const SizedBox(width: 6),
          _CardFace(
              card: game.pendingShield!,
              size: 40,
              highlight: AppColors.purple),
          const SizedBox(width: 8),
          const Expanded(
            child: Text('방어막 — 내 필드를 채우거나, 상대 조합을 망치세요',
                style: TextStyle(
                    fontSize: 11.5,
                    color: AppColors.textMain,
                    fontWeight: FontWeight.w700)),
          ),
        ] else ...[
          Expanded(
            child: SizedBox(
              height: 52,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: hand.length,
                separatorBuilder: (_, __) => const SizedBox(width: 6),
                itemBuilder: (_, i) => GestureDetector(
                  onTap: () => _tapHand(i),
                  child: _CardFace(
                    card: hand[i],
                    size: 40,
                    faceDownBadge: faceDownMode && selectedHand == i,
                    highlight: selectedHand == i ? AppColors.gold : null,
                  ),
                ),
              ),
            ),
          ),
          // 뒷면 배치 토글 — 다음 배치를 코인 1로 숨긴다.
          GestureDetector(
            onTap: myTurn && canFaceDown
                ? () {
                    _haptic(Haptic.select);
                    setState(() => faceDownMode = !faceDownMode);
                  }
                : null,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: faceDownMode ? AppColors.purple : AppColors.surface,
                borderRadius: BorderRadius.circular(9),
                border: Border.all(
                    color:
                        faceDownMode ? AppColors.purple : AppColors.stroke),
              ),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.visibility_off_rounded,
                    size: 16,
                    color: faceDownMode
                        ? Colors.white
                        : canFaceDown
                            ? AppColors.textMain
                            : AppColors.textMuted),
                Text('뒷면 🪙1',
                    style: TextStyle(
                        fontSize: 8.5,
                        fontWeight: FontWeight.w800,
                        color: faceDownMode
                            ? Colors.white
                            : AppColors.textMuted)),
              ]),
            ),
          ),
          if (myTurn && game.boards[0].openCols.isEmpty) ...[
            const SizedBox(width: 6),
            TextButton(
              onPressed: _discard,
              child: const Text('버리기',
                  style: TextStyle(
                      color: AppColors.lose, fontWeight: FontWeight.w800)),
            ),
          ],
        ],
      ]),
    );
  }

  // ---- 정산 오버레이 ----

  Widget _resolutionOverlay() {
    final (winner, dmg) = lastRes!;
    final iWin = winner == 0;
    final (sa, sb) = game.scores;
    return _Scrim(
      child: _Panel(children: [
        Text(iWin ? '판 승리!' : (winner == 1 ? '판 패배' : '무승부'),
            style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w900,
                color: iWin ? AppColors.win : AppColors.lose)),
        const SizedBox(height: 4),
        Text(
            winner == -1
                ? 'HP 변화 없음'
                : '${sa.round()} vs ${sb.round()} — ${iWin ? '상대' : '나'} HP −${dmg.ceil()}',
            style: const TextStyle(
                color: AppColors.textMain, fontWeight: FontWeight.w700)),
        const SizedBox(height: 10),
        _linesTable(),
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

  /// 줄별 정산표 — 어느 줄에서 얼마나 벌었는지 + 조합 라벨.
  Widget _linesTable() {
    Widget line(String name, double my, double opp, String combo) {
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
              width: 40,
              child: Text(name,
                  style: const TextStyle(
                      color: AppColors.textMuted, fontSize: 12))),
          SizedBox(
              width: 56,
              child: Text(combo,
                  style: const TextStyle(
                      color: AppColors.goldSoft,
                      fontSize: 11,
                      fontWeight: FontWeight.w700))),
          Expanded(
            child: Text('${my.round()}  vs  ${opp.round()}',
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: AppColors.textMain,
                    fontSize: 12.5,
                    fontFeatures: [FontFeature.tabularFigures()])),
          ),
          SizedBox(
            width: 40,
            child: Text(
                d == 0 ? '—' : (d > 0 ? '+${d.round()}' : '${d.round()}'),
                textAlign: TextAlign.right,
                style: TextStyle(
                    color: color, fontWeight: FontWeight.w800, fontSize: 12.5)),
          ),
        ]),
      );
    }

    final a = game.boards[0], b = game.boards[1];
    final rows = <Widget>[];
    for (var c = 0; c < TriRules.cols; c++) {
      rows.add(line('열${c + 1}', colScore(a.cols[c]), colScore(b.cols[c]),
          colCombo(a.cols[c]).label));
    }
    for (var r = 0; r < TriRules.rows; r++) {
      rows.add(line('행${r + 1}', rowScore(a.row(r)), rowScore(b.row(r)),
          rowCombo(a.row(r)).label));
    }
    return Column(mainAxisSize: MainAxisSize.min, children: rows);
  }

  Widget _matchOverOverlay() {
    final iWin = match.matchWinner == 0;
    return _Scrim(
      child: _Panel(children: [
        Text(iWin ? '🏆 매치 승리!' : '매치 패배',
            style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w900,
                color: iWin ? AppColors.gold : AppColors.lose)),
        const SizedBox(height: 6),
        Text('${match.games}판 만에 결착',
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

// ---- 전장 ----------------------------------------------------------------

class _BoardView extends StatelessWidget {
  const _BoardView({
    required this.board,
    required this.opp,
    required this.mine,
    this.preview,
    this.attackRank,
    this.attackVisible,
    this.shieldCols = const {},
    this.onCellTap,
    this.onEmptyColTap,
  });

  final TriBoard board;
  final TriBoard opp;
  final bool mine;

  /// 배치 미리보기 중인 카드(내 전장에서만) — 열마다 +점수가 뜬다.
  final TriCard? preview;

  /// 공격 미리보기 랭크(상대 전장에서만) — 일치 카드가 빨갛게 빛난다.
  final int? attackRank;
  final bool Function(TriCard)? attackVisible;

  /// 방어막 배치 가능 열(하이라이트).
  final Set<int> shieldCols;

  final void Function(int col, int row)? onCellTap;
  final void Function(int col)? onEmptyColTap;

  /// [preview]를 [c]열에 놓았을 때 늘어나는 내 점수(열+행).
  double _gain(int c) {
    final before = board.score;
    board.cols[c].add(preview!);
    final g = board.score - before;
    board.cols[c].removeLast();
    return g;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final cell = min(
          46.0,
          min((box.maxWidth - 90) / TriRules.cols,
              (box.maxHeight - 24) / TriRules.rows));

      Widget colBadge(int c) {
        final my = colScore(board.cols[c]);
        final theirs = colScore(opp.cols[c]);
        return SizedBox(
          width: cell + 3,
          child: Center(
            child: _ScoreBadge(
                score: my,
                label: colCombo(board.cols[c]).label,
                winning: my > theirs,
                losing: my < theirs,
                mine: mine),
          ),
        );
      }

      // 내 전장: 위가 5행(꼭대기) — 스택이 위로 자란다.
      // 상대 전장: 미러 — 스택이 아래(가운데)로 자라 정면 대치 느낌.
      final rowOrder = mine
          ? [for (var r = TriRules.rows - 1; r >= 0; r--) r]
          : [for (var r = 0; r < TriRules.rows; r++) r];

      final grid = Column(mainAxisSize: MainAxisSize.min, children: [
        if (!mine)
          Row(mainAxisSize: MainAxisSize.min, children: [
            for (var c = 0; c < TriRules.cols; c++) colBadge(c),
            SizedBox(width: cell * 0.9),
          ]),
        for (final r in rowOrder)
          Row(mainAxisSize: MainAxisSize.min, children: [
            for (var c = 0; c < TriRules.cols; c++) _cell(c, r, cell),
            SizedBox(
              width: cell * 0.9,
              child: _rowBadge(r),
            ),
          ]),
        if (mine)
          Row(mainAxisSize: MainAxisSize.min, children: [
            for (var c = 0; c < TriRules.cols; c++) colBadge(c),
            SizedBox(width: cell * 0.9),
          ]),
      ]);
      return Center(child: FittedBox(fit: BoxFit.scaleDown, child: grid));
    });
  }

  Widget _rowBadge(int r) {
    final cards = board.row(r);
    if (cards.length < 2) return const SizedBox.shrink();
    final combo = rowCombo(cards);
    if (combo == TriCombo.none) return const SizedBox.shrink();
    return Center(
      child: Text(combo.label,
          style: const TextStyle(
              fontSize: 8.5,
              color: AppColors.goldSoft,
              fontWeight: FontWeight.w800)),
    );
  }

  Widget _cell(int c, int r, double size) {
    final col = board.cols[c];
    final card = r < col.length ? col[r] : null;
    // 다음에 채워질 칸(스택 꼭대기)인가.
    final isNext = r == col.length;
    final placeable = isNext && preview != null;
    final shieldable = isNext && shieldCols.contains(c);
    final attackable = card != null &&
        attackRank != null &&
        !card.shield &&
        card.rank == attackRank &&
        (attackVisible?.call(card) ?? true);

    final borderColor = attackable
        ? AppColors.lose
        : shieldable
            ? AppColors.purple
            : placeable
                ? AppColors.gold
                : AppColors.stroke;
    final borderW = attackable || shieldable || placeable ? 2.0 : 1.0;

    Widget? content;
    if (card != null) {
      content = _cardInCell(card, size);
    } else if (placeable) {
      content = Text('+${_gain(c).round()}',
          style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w900,
              color: AppColors.goldSoft));
    } else if (shieldable) {
      content = const Text('🛡', style: TextStyle(fontSize: 14));
    }

    return GestureDetector(
      onTap: card != null
          ? (onCellTap != null ? () => onCellTap!(c, r) : null)
          : ((placeable || shieldable) && onEmptyColTap != null
              ? () => onEmptyColTap!(c)
              : null),
      child: Container(
        width: size,
        height: size,
        margin: const EdgeInsets.all(1.5),
        decoration: BoxDecoration(
          color: card == null ? AppColors.slotRecess : AppColors.cardBody,
          borderRadius: BorderRadius.circular(7),
          border: Border.all(color: borderColor, width: borderW),
          boxShadow: attackable
              ? [
                  BoxShadow(
                      color: AppColors.lose.withValues(alpha: 0.45),
                      blurRadius: 8)
                ]
              : null,
        ),
        child: Center(child: content),
      ),
    );
  }

  /// 칸 속 카드 — 뒷면/훔쳐봄/방어막 상태를 그린다.
  Widget _cardInCell(TriCard card, double size) {
    // 상대 전장의 뒷면(안 훔쳐본) 카드 = 카드 등.
    if (!mine && card.faceDown && !card.peeked) {
      return Container(
        margin: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: AppColors.purple.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(5),
          border: Border.all(color: AppColors.purple),
        ),
        child: const Center(
            child: Text('?',
                style: TextStyle(
                    fontWeight: FontWeight.w900, color: Colors.white))),
      );
    }
    return Stack(alignment: Alignment.center, children: [
      _CardGlyph(card: card, size: size),
      if (card.shield)
        const Positioned(
            left: 1, top: 0, child: Text('🛡', style: TextStyle(fontSize: 9))),
      if (card.faceDown && mine)
        const Positioned(
            left: 1,
            top: 0,
            child: Icon(Icons.visibility_off_rounded,
                size: 10, color: AppColors.purple)),
      if (card.peeked)
        const Positioned(
            right: 1,
            top: 0,
            child: Icon(Icons.remove_red_eye_rounded,
                size: 10, color: AppColors.lose)),
    ]);
  }
}

/// 열 점수 배지 — 색이 곧 전선 상황(초록 우세 / 빨강 열세 / 회색 동률).
class _ScoreBadge extends StatelessWidget {
  const _ScoreBadge(
      {required this.score,
      required this.label,
      required this.winning,
      required this.losing,
      required this.mine});
  final double score;
  final String label;
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
      padding: const EdgeInsets.symmetric(vertical: 1, horizontal: 6),
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text('${score.round()}',
            style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
                color: color,
                fontFeatures: const [FontFeature.tabularFigures()])),
        if (label != '—')
          Text(label,
              style: const TextStyle(
                  fontSize: 7.5,
                  color: AppColors.goldSoft,
                  fontWeight: FontWeight.w800)),
      ]),
    );
  }
}

/// 손패·방어막 카드(원소 아이콘 + 숫자).
class _CardFace extends StatelessWidget {
  const _CardFace(
      {required this.card,
      required this.size,
      this.highlight,
      this.faceDownBadge = false});
  final TriCard card;
  final double size;
  final Color? highlight;
  final bool faceDownBadge;

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
      child: Stack(alignment: Alignment.center, children: [
        _CardGlyph(card: card, size: size),
        if (faceDownBadge)
          const Positioned(
              left: 2,
              top: 2,
              child: Icon(Icons.visibility_off_rounded,
                  size: 12, color: AppColors.purple)),
      ]),
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
    return Stack(alignment: Alignment.center, children: [
      Opacity(opacity: 0.9, child: ElementIcon(card.elem, size: size * 0.62)),
      Positioned(
        right: 2,
        bottom: 0,
        child: Text(
          '${card.rank}',
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
