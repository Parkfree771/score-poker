import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../audio/sfx.dart';
import '../domain/card.dart';
import '../domain/hand.dart';
import '../domain/scoring.dart';
import '../domain/strike.dart';
import '../feedback/haptics.dart';
import 'theme.dart';
import 'widgets/card_face.dart';
import 'widgets/flying_card.dart';
import 'widgets/impact_effects.dart';
import 'widgets/veil_chip.dart';

/// 스트라이크 모드 화면 (실험) — 룰 정본은 `docs/STRIKE.md`.
///
/// 연출 문법은 본편과 같은 부품을 쓴다: [flyCard] 비행, [poofCard] 쳐내기,
/// [hitFlash]/[sparkBurst] 타격, [shieldGlint] 잠금, [VeilChip] 칩.
/// 원칙 "계산은 게임이 하고 플레이어는 비교만 한다":
///  - 손패를 고르면 놓을 칸이 금색으로, 때릴 수 있는 상대 카드가 붉게 빛난다.
///  - 줄 오른쪽 라벨이 현재 족보 → (선택 카드를 놓으면) 다음 족보를 미리 보여준다.
/// 문자열은 한국어 하드코딩 — 정식 승격 시 ARB로 옮긴다.
class StrikeScreen extends StatefulWidget {
  const StrikeScreen({super.key, this.seed, this.instantMoves = false});

  /// 테스트용 시드. null이면 판마다 무작위.
  final int? seed;

  /// 테스트·골든용 — 비행/타격 오버레이 없이 상태만 즉시 반영.
  final bool instantMoves;

  @override
  State<StrikeScreen> createState() => StrikeScreenState();
}

/// 화면 상태 — 애니메이션 중에는 입력을 막는다.
enum _Ui { idle, animating, resolved }

@visibleForTesting
class StrikeScreenState extends State<StrikeScreen>
    with TickerProviderStateMixin {
  final _rng = Random();
  late final _bot = StrikeBot(rng: _rng);

  late StrikeGame game;
  _Ui _ui = _Ui.idle;
  MatchResult? result;
  int wins = 0, losses = 0; // 세션 전적(가볍게)

  int? selectedHand;
  bool hideMode = false;
  int _seq = 0;

  // 비행 좌표용 키: [player][row][slot], 손패, 덱, 상대 손패 더미, 방어막 무대.
  final slotKeys = [
    List.generate(StrikeRules.rows,
        (_) => List.generate(StrikeRules.slots, (_) => GlobalKey())),
    List.generate(StrikeRules.rows,
        (_) => List.generate(StrikeRules.slots, (_) => GlobalKey())),
  ];
  final handKeys = List.generate(12, (_) => GlobalKey());
  final deckKey = GlobalKey();
  final oppHandKey = GlobalKey();
  final shieldStageKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _newGame();
  }

  @override
  void dispose() {
    _seq++;
    super.dispose();
  }

  void _newGame() {
    game = StrikeGame(seed: widget.seed ?? _rng.nextInt(1 << 30));
    selectedHand = null;
    hideMode = false;
    result = null;
    _ui = _Ui.idle;
    _playSfx(Sfx.shuffle);
  }

  bool get myActionTurn =>
      _ui == _Ui.idle &&
      !game.finished &&
      game.current == 0 &&
      game.phase == StrikePhase.action;

  bool get myShieldTurn =>
      _ui == _Ui.idle &&
      !game.finished &&
      game.current == 0 &&
      game.phase == StrikePhase.shield;

  // ---- 좌표·연출 도우미 ----

  Rect? _rectOf(GlobalKey key) {
    final box = key.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;
    final origin = box.localToGlobal(Offset.zero);
    return origin & box.size;
  }

  OverlayState? get _overlay => Overlay.maybeOf(context);

  /// [from]→[to]로 카드를 날린다. 좌표를 못 구하면 조용히 생략(상태는 호출자가).
  Future<void> _fly(GlobalKey from, GlobalKey to, PlayingCard card,
      {bool faceDown = false,
      bool strike = false,
      Duration? duration}) async {
    if (widget.instantMoves) return;
    final overlay = _overlay;
    final f = _rectOf(from), t = _rectOf(to);
    if (overlay == null || f == null || t == null) return;
    await flyCard(
      overlay: overlay,
      vsync: this,
      from: f,
      to: t,
      card: card,
      faceDown: faceDown,
      trail: strike,
      curve: strike ? Curves.easeIn : Curves.easeInOutCubic,
      duration: duration ??
          (strike
              ? const Duration(milliseconds: 260)
              : const Duration(milliseconds: 380)),
    );
  }

  /// 타격 지점 연출 묶음 — 플래시 + 파편 + 표적 카드 쳐내기.
  Future<void> _impactAt(GlobalKey key, PlayingCard victim,
      {required bool towardRight}) async {
    if (widget.instantMoves) return;
    final overlay = _overlay;
    final r = _rectOf(key);
    if (overlay == null || r == null) return;
    unawaited(hitFlash(overlay: overlay, vsync: this, at: r));
    unawaited(sparkBurst(overlay: overlay, vsync: this, at: r));
    await poofCard(
        overlay: overlay,
        vsync: this,
        rect: r,
        card: victim,
        driftX: towardRight ? 0.7 : -0.7);
  }

  Future<void> _glintAt(GlobalKey key) async {
    if (widget.instantMoves) return;
    final overlay = _overlay;
    final r = _rectOf(key);
    if (overlay == null || r == null) return;
    await shieldGlint(overlay: overlay, vsync: this, at: r);
  }

  Future<void> _pause(int ms) => widget.instantMoves
      ? Future<void>.value()
      : Future<void>.delayed(Duration(milliseconds: ms));

  // ---- 내 행동 ----

  void _tapHand(int i) {
    if (!myActionTurn) return;
    _haptic(Haptic.select);
    setState(() => selectedHand = selectedHand == i ? null : i);
  }

  /// 테스트 전용 — 손패 [i]를 [row]에 즉시 배치.
  @visibleForTesting
  Future<void> placeForTest(int i, int row) async {
    selectedHand = i;
    await _myPlace(row);
  }

  Future<void> _myPlace(int row) async {
    final hi = selectedHand;
    if (hi == null || game.fields[0][row].length >= StrikeRules.slots) return;
    final seq = ++_seq;
    final card = game.hands[0][hi];
    final hidden = hideMode && game.chips[0] >= StrikeRules.costHide;
    final slot = game.fields[0][row].length;
    setState(() {
      _ui = _Ui.animating;
      selectedHand = null;
    });
    _playSfx(hidden ? Sfx.chipTick : Sfx.cardPlace);
    _haptic(Haptic.place);
    await _fly(handKeys[hi], slotKeys[0][row][slot], card, faceDown: hidden);
    if (!mounted || seq != _seq) return;
    game.place(hi, row, hidden: hidden);
    hideMode = false;
    setState(() => _ui = _Ui.idle);
    _afterTurn();
  }

  Future<void> _myAttack(int row, int idx) async {
    final hi = selectedHand;
    if (hi == null) return;
    final seq = ++_seq;
    final card = game.hands[0][hi];
    final victim = game.fields[1][row][idx].card;
    setState(() {
      _ui = _Ui.animating;
      selectedHand = null;
    });
    // 돌진 → 타격.
    await _fly(handKeys[hi], slotKeys[1][row][idx], card, strike: true);
    if (!mounted || seq != _seq) return;
    _playSfx(Sfx.attackHit);
    _haptic(Haptic.impact);
    game.attack(hi, row, idx);
    setState(() {}); // 표적이 사라진 보드를 먼저 보여주고
    await _impactAt(slotKeys[1][row][idx], victim, towardRight: true);
    if (!mounted || seq != _seq) return;
    if (game.phase == StrikePhase.shield) {
      // 방어막 드로 — 덱에서 무대로 날아온다.
      _playSfx(Sfx.cardSlide);
      await _fly(deckKey, shieldStageKey, game.pendingShield!.card,
          duration: const Duration(milliseconds: 320));
      if (!mounted || seq != _seq) return;
      setState(() => _ui = _Ui.idle); // 방어막 배치 입력 대기
      return;
    }
    setState(() => _ui = _Ui.idle);
    _afterTurn();
  }

  Future<void> _myShieldPlace(bool own, int row) async {
    if (!myShieldTurn) return;
    final seq = ++_seq;
    final shield = game.pendingShield!;
    final player = own ? 0 : 1;
    final slot = game.fields[player][row].length;
    setState(() => _ui = _Ui.animating);
    _playSfx(Sfx.cardSlide);
    _haptic(Haptic.shieldLock);
    await _fly(shieldStageKey, slotKeys[player][row][slot], shield.card);
    if (!mounted || seq != _seq) return;
    game.placeShield(own, row);
    setState(() => _ui = _Ui.idle);
    unawaited(_glintAt(slotKeys[player][row][slot]));
    _afterTurn();
  }

  Future<void> _myPeek(int row, int idx) async {
    if (!myActionTurn ||
        selectedHand != null ||
        game.chips[0] < StrikeRules.costPeek) {
      return;
    }
    final c = game.fields[1][row][idx];
    if (!c.faceDown || c.peeked || c.shield) return;
    game.peek(row, idx);
    _playSfx(Sfx.chipTing);
    _haptic(Haptic.select);
    setState(() {});
    unawaited(_glintAt(slotKeys[1][row][idx]));
  }

  Future<void> _myDiscard() async {
    if (!myActionTurn ||
        game.openRows(0).isNotEmpty ||
        game.hands[0].isEmpty) {
      return;
    }
    final seq = ++_seq;
    final hi = selectedHand ?? game.hands[0].length - 1;
    final card = game.hands[0][hi];
    setState(() {
      _ui = _Ui.animating;
      selectedHand = null;
    });
    _playSfx(Sfx.cardSlide);
    final overlay = _overlay;
    final r = _rectOf(handKeys[hi]);
    if (!widget.instantMoves && overlay != null && r != null) {
      await poofCard(
          overlay: overlay, vsync: this, rect: r, card: card, driftX: -0.8);
    }
    if (!mounted || seq != _seq) return;
    game.discard(hi);
    setState(() => _ui = _Ui.idle);
    _afterTurn();
  }

  // ---- 진행 ----

  void _afterTurn() {
    if (game.finished) {
      unawaited(_finishGame());
      return;
    }
    if (game.current == 1) unawaited(_botLoop());
  }

  /// 봇 턴 — 내 연출과 같은 문법으로, 행동 사이 딜레이를 둔다.
  Future<void> _botLoop() async {
    final seq = ++_seq;
    setState(() => _ui = _Ui.animating);
    while (mounted && seq == _seq && !game.finished && game.current == 1) {
      await _pause(620);
      if (!mounted || seq != _seq) return;
      final move = _bot.choose(game);
      switch (move) {
        case MovePeek(:final row, :final idx):
          game.peek(row, idx);
          _playSfx(Sfx.chipTing);
          setState(() {});
        // 훔쳐보기는 턴 소모가 없다 — 루프 계속.
        case MoveAttack(:final handIdx, :final row, :final idx):
          final victim = game.fields[0][row][idx].card;
          final card = game.hands[1][handIdx];
          await _fly(oppHandKey, slotKeys[0][row][idx], card, strike: true);
          if (!mounted || seq != _seq) return;
          _playSfx(Sfx.attackHit);
          _haptic(Haptic.impact);
          game.attack(handIdx, row, idx);
          setState(() {});
          await _impactAt(slotKeys[0][row][idx], victim, towardRight: false);
        case MoveShield(:final ownField, :final row):
          final shield = game.pendingShield!;
          final player = ownField ? 1 : 0;
          final slot = game.fields[player][row].length;
          _playSfx(Sfx.cardSlide);
          await _fly(deckKey, slotKeys[player][row][slot], shield.card);
          if (!mounted || seq != _seq) return;
          game.placeShield(ownField, row);
          setState(() {});
          unawaited(_glintAt(slotKeys[player][row][slot]));
        case MovePlace(:final handIdx, :final row, :final hidden):
          final card = game.hands[1][handIdx];
          final slot = game.fields[1][row].length;
          _playSfx(hidden ? Sfx.chipTick : Sfx.cardSlide);
          await _fly(oppHandKey, slotKeys[1][row][slot], card,
              faceDown: true); // 상대 배치는 내용이 안 보이게 날아간다
          if (!mounted || seq != _seq) return;
          game.place(handIdx, row, hidden: hidden);
          setState(() {});
        case MoveDiscard(:final handIdx):
          game.discard(handIdx);
          _playSfx(Sfx.cardSlide);
          setState(() {});
      }
    }
    if (!mounted || seq != _seq) return;
    if (game.finished) {
      unawaited(_finishGame());
    } else {
      setState(() => _ui = _Ui.idle);
    }
  }

  Future<void> _finishGame() async {
    final seq = ++_seq;
    setState(() => _ui = _Ui.animating); // 공개 연출 동안 입력 잠금
    await _pause(350);
    if (!mounted || seq != _seq) return;
    _playSfx(Sfx.sting);
    result = game.judge();
    if (result!.outcome == MatchOutcome.win) wins++;
    if (result!.outcome == MatchOutcome.lose) losses++;
    setState(() => _ui = _Ui.resolved);
    await _pause(500);
    if (!mounted || seq != _seq) return;
    _playSfx(result!.outcome == MatchOutcome.win
        ? Sfx.win
        : result!.outcome == MatchOutcome.lose
            ? Sfx.lose
            : Sfx.chipTing);
  }

  void _restart() {
    _seq++;
    setState(_newGame);
  }

  void _playSfx(Sfx sfx) =>
      context.getInheritedWidgetOfExactType<SfxScope>()?.notifier?.play(sfx);

  void _haptic(Haptic h) =>
      context.getInheritedWidgetOfExactType<HapticScope>()?.notifier?.play(h);

  // ---- 빌드 ----

  @override
  Widget build(BuildContext context) {
    final atkRank = myActionTurn &&
            selectedHand != null &&
            selectedHand! < game.hands[0].length
        ? game.hands[0][selectedHand!].rank
        : null;
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: AppColors.bgGradient),
        child: SafeArea(
          child: LayoutBuilder(builder: (context, box) {
            final cardW = min(52.0, (box.maxWidth - 120) / StrikeRules.slots);
            return Stack(children: [
              Column(children: [
                _topBar(),
                _oppStrip(),
                const SizedBox(height: 2),
                _field(player: 1, cardW: cardW, attackRank: atkRank),
                _centerStrip(cardW),
                _field(player: 0, cardW: cardW, attackRank: null),
                const SizedBox(height: 4),
                _handStrip(cardW),
                const SizedBox(height: 6),
              ]),
              if (_ui == _Ui.resolved) _resultOverlay(),
            ]);
          }),
        ),
      ),
    );
  }

  Widget _topBar() {
    final String status;
    if (_ui == _Ui.resolved) {
      status = '정산';
    } else if (myShieldTurn) {
      status = '🛡 방어막 배치 — 내 줄, 또는 상대 줄에 꽂아 방해!';
    } else if (myActionTurn) {
      status = selectedHand == null
          ? '내 차례 — 손패를 고르세요'
          : '금색 칸에 놓거나, 붉은 카드를 쳐내세요';
    } else {
      status = '상대 차례…';
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 2, 10, 0),
      child: Row(children: [
        IconButton(
          icon: const Icon(Icons.close_rounded, color: AppColors.textMuted),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        Text('$wins승 $losses패',
            style: const TextStyle(
                color: AppColors.textMain,
                fontWeight: FontWeight.w800,
                fontSize: 13)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(status,
              textAlign: TextAlign.right,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 12.5,
                  color: myActionTurn || myShieldTurn
                      ? AppColors.goldSoft
                      : AppColors.textMuted,
                  fontWeight: FontWeight.w700)),
        ),
      ]),
    );
  }

  /// 상대 정보 줄 — 손패 더미(뒷면) + 칩.
  Widget _oppStrip() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Row(children: [
        // 상대 손패: 겹친 뒷면 부채.
        SizedBox(
          key: oppHandKey,
          height: 34,
          width: 30.0 + 10.0 * max(0, game.hands[1].length - 1),
          child: Stack(children: [
            for (var i = 0; i < game.hands[1].length; i++)
              Positioned(left: i * 10.0, child: cachedCardBack(24)),
          ]),
        ),
        const SizedBox(width: 8),
        const Text('상대',
            style: TextStyle(
                color: AppColors.oppPrimary,
                fontWeight: FontWeight.w900,
                fontSize: 13)),
        const Spacer(),
        _chipRow(player: 1),
      ]),
    );
  }

  /// 한 사람의 필드 — 3줄×5칸 + 줄 오른쪽 족보 라벨.
  Widget _field(
      {required int player, required double cardW, int? attackRank}) {
    final cellH = CardFace.heightFor(cardW) + 6;
    final shieldRows = myShieldTurn
        ? {
            for (final (own, r) in game.shieldSlots())
              if (own == (player == 0)) r
          }
        : const <int>{};
    return Column(mainAxisSize: MainAxisSize.min, children: [
      for (var r = 0; r < StrikeRules.rows; r++)
        SizedBox(
          height: cellH,
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            for (var i = 0; i < StrikeRules.slots; i++)
              _cell(player, r, i, cardW,
                  attackRank: attackRank, shieldRow: shieldRows.contains(r)),
            SizedBox(width: 64, child: _rowLabel(player, r)),
          ]),
        ),
    ]);
  }

  static const _catNames = {
    HandCategory.highCard: '',
    HandCategory.onePair: '페어',
    HandCategory.twoPair: '투페어',
    HandCategory.threeOfAKind: '트리플',
    HandCategory.straight: '스트레이트',
    HandCategory.flush: '플러시',
    HandCategory.fullHouse: '풀하우스',
    HandCategory.fourOfAKind: '포카드',
    HandCategory.straightFlush: '스트플',
  };

  /// 줄 족보 라벨 — 내 줄은 선택 카드를 놓았을 때의 변화를 미리 보여준다.
  Widget _rowLabel(int player, int r) {
    // 내가 볼 수 있는 카드만으로 계산(상대 뒷면은 모르는 게 맞다).
    final cards = [
      for (final c in game.fields[player][r])
        if (game.visibleTo(0, player, c)) c.card
    ];
    final cur = evaluateHand(cards).category;
    var text = _catNames[cur]!;
    var color = AppColors.textMuted;
    if (player == 0 &&
        myActionTurn &&
        selectedHand != null &&
        game.fields[0][r].length < StrikeRules.slots) {
      final next =
          evaluateHand([...cards, game.hands[0][selectedHand!]]).category;
      if (next != cur) {
        text =
            '${_catNames[cur]!.isEmpty ? '·' : _catNames[cur]}→${_catNames[next]}';
        color = AppColors.goldSoft;
      }
    }
    if (text.isEmpty) return const SizedBox.shrink();
    return Text(text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
            fontSize: 9.5, fontWeight: FontWeight.w800, color: color));
  }

  Widget _cell(int player, int r, int i, double cardW,
      {int? attackRank, required bool shieldRow}) {
    final row = game.fields[player][r];
    final card = i < row.length ? row[i] : null;
    final isNext = i == row.length;
    final placeable =
        player == 0 && myActionTurn && selectedHand != null && isNext;
    final shieldable = shieldRow && isNext;
    final attackable = player == 1 &&
        card != null &&
        attackRank != null &&
        !card.shield &&
        game.visibleTo(0, 1, card) &&
        card.card.rank == attackRank;

    void Function()? onTap;
    if (attackable) {
      onTap = () => unawaited(_myAttack(r, i));
    } else if (shieldable) {
      onTap = () => unawaited(_myShieldPlace(player == 0, r));
    } else if (placeable) {
      onTap = () => unawaited(_myPlace(r));
    } else if (player == 1 && card != null) {
      onTap = () => unawaited(_myPeek(r, i));
    }

    final h = CardFace.heightFor(cardW);
    Widget inner;
    if (card == null) {
      inner = Container(
        width: cardW,
        height: h,
        decoration: BoxDecoration(
          color: (placeable || shieldable)
              ? AppColors.slotNext
              : AppColors.slotRecess,
          borderRadius: BorderRadius.circular(cardW * 0.14),
          border: Border.all(
            color: shieldable
                ? AppColors.purple
                : placeable
                    ? AppColors.gold
                    : AppColors.stroke,
            width: placeable || shieldable ? 2.4 : 1.2,
          ),
        ),
        child: shieldable
            ? const Center(child: Text('🛡', style: TextStyle(fontSize: 13)))
            : null,
      );
    } else {
      inner = _cardWidget(player, card, cardW, attackable: attackable);
    }
    return GestureDetector(
      key: slotKeys[player][r][i],
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(padding: const EdgeInsets.all(1.5), child: inner),
    );
  }

  Widget _cardWidget(int player, StrikeCard c, double w,
      {required bool attackable}) {
    final iSee = game.visibleTo(0, player, c);
    Widget core = iSee ? cachedCardFace(c.card, w) : cachedCardBack(w);
    final badges = <Widget>[];
    if (c.shield) {
      badges.add(const Positioned(
          left: 0, top: 0, child: Text('🛡', style: TextStyle(fontSize: 10))));
    }
    if (player == 0 && c.faceDown) {
      badges.add(const Positioned(
          left: 1,
          top: 1,
          child: Icon(Icons.visibility_off_rounded,
              size: 11, color: AppColors.purple)));
    }
    if (c.peeked) {
      // 뒷면인데 누군가 봤다 — 양쪽 다 알아야 공정하다.
      badges.add(const Positioned(
          right: 1,
          top: 1,
          child: Icon(Icons.remove_red_eye_rounded,
              size: 11, color: AppColors.lose)));
    }
    if (attackable) {
      core = DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(w * 0.16),
          border: Border.all(color: AppColors.lose, width: 2.4),
          boxShadow: [
            BoxShadow(
                color: AppColors.lose.withValues(alpha: 0.55), blurRadius: 10)
          ],
        ),
        child: core,
      );
    }
    if (badges.isEmpty) return core;
    return Stack(clipBehavior: Clip.none, children: [core, ...badges]);
  }

  /// 가운데 줄 — 덱 더미 + 방어막 무대 + 남은 장수.
  Widget _centerStrip(double cardW) {
    final shieldWaiting = myShieldTurn && game.pendingShield != null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 14),
      child: Row(children: [
        // 덱 더미.
        SizedBox(
          key: deckKey,
          width: 30,
          height: 40,
          child: Stack(children: [
            if (game.deckLeft > 1)
              Positioned(left: 3, top: 3, child: cachedCardBack(26)),
            if (game.deckLeft > 0) cachedCardBack(26),
          ]),
        ),
        const SizedBox(width: 6),
        Text('${game.deckLeft}',
            style: const TextStyle(
                color: AppColors.textMuted,
                fontWeight: FontWeight.w800,
                fontSize: 12)),
        const Spacer(),
        // 방어막 무대 — 공격 보상 카드가 여기 떠서 배치를 기다린다.
        AnimatedOpacity(
          duration: const Duration(milliseconds: 200),
          opacity: shieldWaiting ? 1 : 0,
          child: Row(key: shieldStageKey, children: [
            const Text('🛡', style: TextStyle(fontSize: 16)),
            const SizedBox(width: 4),
            if (game.pendingShield != null)
              cachedCardFace(game.pendingShield!.card, 30),
          ]),
        ),
        const Spacer(),
        const Text('나',
            style: TextStyle(
                color: AppColors.mePrimary,
                fontWeight: FontWeight.w900,
                fontSize: 13)),
      ]),
    );
  }

  Widget _chipRow({required int player}) {
    final left = game.chips[player];
    return Row(children: [
      for (var i = 0; i < StrikeRules.chips; i++)
        Padding(
          padding: const EdgeInsets.only(left: 3),
          child: VeilChip(
            size: 20,
            filled: i < left,
            ring: player == 0 ? AppColors.mePrimary : AppColors.oppPrimary,
          ),
        ),
    ]);
  }

  /// 내 손패 + 뒷면 토글 + 칩 + (만석 시) 버리기.
  Widget _handStrip(double cardW) {
    final hand = game.hands[0];
    final w = min(46.0, cardW);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 10),
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 10),
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.stroke),
      ),
      child: Row(children: [
        Expanded(
          child: SizedBox(
            height: CardFace.heightFor(w) + 10,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: hand.length,
              separatorBuilder: (_, __) => const SizedBox(width: 5),
              itemBuilder: (_, i) {
                final selected = selectedHand == i;
                final justDrawn = game.current == 0 &&
                    game.phase == StrikePhase.action &&
                    i == hand.length - 1 &&
                    hand[i] == game.lastDrawn;
                return GestureDetector(
                  key: i < handKeys.length ? handKeys[i] : null,
                  onTap: () => _tapHand(i),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 140),
                    transform:
                        Matrix4.translationValues(0, selected ? -8 : 0, 0),
                    decoration: selected
                        ? BoxDecoration(
                            borderRadius: BorderRadius.circular(w * 0.16),
                            boxShadow: [
                              BoxShadow(
                                  color:
                                      AppColors.gold.withValues(alpha: 0.55),
                                  blurRadius: 10)
                            ],
                          )
                        : null,
                    child: Stack(clipBehavior: Clip.none, children: [
                      cachedCardFace(hand[i], w),
                      if (justDrawn)
                        Positioned(
                          left: 0,
                          right: 0,
                          top: -2,
                          child: Center(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 4, vertical: 1),
                              decoration: BoxDecoration(
                                  color: AppColors.gold,
                                  borderRadius: BorderRadius.circular(4)),
                              child: const Text('NEW',
                                  style: TextStyle(
                                      fontSize: 6.5,
                                      fontWeight: FontWeight.w900,
                                      color: AppColors.ink)),
                            ),
                          ),
                        ),
                      if (hideMode && selected)
                        const Positioned(
                            left: 2,
                            top: 2,
                            child: Icon(Icons.visibility_off_rounded,
                                size: 13, color: AppColors.purple)),
                    ]),
                  ),
                );
              },
            ),
          ),
        ),
        const SizedBox(width: 8),
        Column(mainAxisSize: MainAxisSize.min, children: [
          // 뒷면 배치 토글(칩 1) — 다음 배치를 숨긴다.
          GestureDetector(
            onTap: myActionTurn && game.chips[0] >= StrikeRules.costHide
                ? () {
                    _haptic(Haptic.select);
                    setState(() => hideMode = !hideMode);
                  }
                : null,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              decoration: BoxDecoration(
                color: hideMode ? AppColors.purple : AppColors.surface,
                borderRadius: BorderRadius.circular(9),
                border: Border.all(
                    color: hideMode ? AppColors.purple : AppColors.stroke),
              ),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.visibility_off_rounded,
                    size: 15,
                    color: hideMode
                        ? Colors.white
                        : game.chips[0] >= StrikeRules.costHide
                            ? AppColors.textMain
                            : AppColors.textMuted),
                Text('뒷면',
                    style: TextStyle(
                        fontSize: 8,
                        fontWeight: FontWeight.w800,
                        color: hideMode ? Colors.white : AppColors.textMuted)),
              ]),
            ),
          ),
          const SizedBox(height: 4),
          _chipRow(player: 0),
        ]),
        if (myActionTurn && game.openRows(0).isEmpty) ...[
          const SizedBox(width: 4),
          TextButton(
            onPressed: () => unawaited(_myDiscard()),
            style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8)),
            child: const Text('버리기',
                style: TextStyle(
                    color: AppColors.lose, fontWeight: FontWeight.w800)),
          ),
        ],
      ]),
    );
  }

  // ---- 정산 오버레이 ----

  Widget _resultOverlay() {
    final r = result!;
    final iWin = r.outcome == MatchOutcome.win;
    final title = iWin
        ? '승리!'
        : r.outcome == MatchOutcome.lose
            ? '패배'
            : '무승부';
    return Positioned.fill(
      child: ColoredBox(
        color: Colors.black.withValues(alpha: 0.62),
        child: Center(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 28),
            padding: const EdgeInsets.fromLTRB(22, 20, 22, 14),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppShapes.radius),
              border: Border.all(color: AppColors.feltEdge),
              boxShadow: AppShapes.panelShadow,
            ),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(title,
                  style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w900,
                      color: iWin
                          ? AppColors.win
                          : r.outcome == MatchOutcome.lose
                              ? AppColors.lose
                              : AppColors.textMain)),
              const SizedBox(height: 4),
              Text('총점 ${r.myTotal} vs ${r.opponentTotal}',
                  style: const TextStyle(
                      color: AppColors.textMuted,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              for (var i = 0; i < 3; i++) _resultLine(i, r.lineOutcomes[i]),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _restart,
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

  Widget _resultLine(int row, LineOutcome o) {
    final mine = evaluateHand(game.rowsOf(0)[row]);
    final theirs = evaluateHand(game.rowsOf(1)[row]);
    final (mark, color) = switch (o) {
      LineOutcome.win => ('승', AppColors.win),
      LineOutcome.lose => ('패', AppColors.lose),
      LineOutcome.tie => ('무', AppColors.textMuted),
    };
    String label(HandResult h) =>
        _catNames[h.category]!.isEmpty ? '하이' : _catNames[h.category]!;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text('줄${row + 1}',
            style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
        const SizedBox(width: 8),
        SizedBox(
          width: 190,
          child: Text(
              '${label(mine)} ${mine.score}  vs  ${label(theirs)} ${theirs.score}',
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: AppColors.textMain,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700)),
        ),
        const SizedBox(width: 8),
        Text(mark,
            style: TextStyle(
                color: color, fontWeight: FontWeight.w900, fontSize: 13)),
      ]),
    );
  }
}
