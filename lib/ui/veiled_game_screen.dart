import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../audio/sfx.dart';
import '../domain/card.dart';
import '../domain/game.dart' show PlacedCard, PlayerId, kRows;
import '../domain/hand.dart';
import '../domain/scoring.dart';
import '../domain/veiled_game.dart';
import '../feedback/haptics.dart';
import '../l10n/app_localizations.dart';
import 'hand_text.dart';
import 'theme.dart';
import 'widgets/board_view.dart';
import 'widgets/card_back.dart';
import 'widgets/card_cell.dart';
import 'widgets/emote_bubble.dart';
import 'widgets/flying_card.dart';
import 'widgets/impact_effects.dart';
import 'widgets/table_decor.dart';

/// 가림 룰 화면 — **기존 게임 화면과 같은 뼈대**(상대 스트립 / 펠트 테이블(덱|보드|우측 열) /
/// 내 스트립+손패)에 규칙만 바뀐다. 룰은 `domain/veiled_game.dart` 참고.
///
/// 흐름: 딜링 연출 → 타이머(30초) 안에 3장 배치 + 숨김 지정/변경 + 상대 숨김 열어보기
/// → 타이머 종료 시 **동시 공개**(둘 다 일찍 끝내면 타이머가 5초로 줄어 마지막 수정 창만
/// 남는다) → 다음 라운드 자동 진행 → 5라운드 후 최후 공개·정산.
class VeiledGameScreen extends StatefulWidget {
  const VeiledGameScreen({super.key, this.seed});
  final int? seed;

  @override
  State<VeiledGameScreen> createState() => _VeiledGameScreenState();
}

enum _Phase { dealing, placing, revealing, finished }

class _VeiledGameScreenState extends State<VeiledGameScreen>
    with TickerProviderStateMixin {
  static const me = PlayerId.p0;
  static const ai = PlayerId.p1;
  static const roundSeconds = 60.0;

  /// 둘 다 배치를 끝냈을 때 남겨줄 최종 수정 시간.
  static const lastCallSeconds = 5.0;

  late VeiledGame g;
  _Phase _phase = _Phase.dealing;
  int? selected;
  int? _flyingHandIndex;
  final Set<(int, int)> _hideMarks = {};
  MatchResult? _result;
  String? _banner; // 공개/최후 공개 배너 문구
  int _dealtMine = 0; // 딜링 연출 중 보이는 내 손패 장수
  int _dealtOpp = 0;
  int _seq = 0;

  // ---- 이모트 ----
  bool _emoteOpen = false;
  String? _myEmote;
  String? _oppEmote;
  int _emoteSeq = 0;

  /// 남은 시간. **ValueNotifier인 이유**: setState로 매 0.1초 화면 전체를 다시
  /// 그리면 웹에서 눈에 띄게 버벅인다 — 타이머 바 위젯만 이 값을 구독한다.
  final ValueNotifier<double> _time = ValueNotifier(roundSeconds);
  Timer? _ticker;
  int _lastWholeSecond = roundSeconds.ceil();

  final Random _rng = Random();
  final _deckKey = GlobalKey();
  final _oppHandKey = GlobalKey();
  final List<GlobalKey> _handKeys = [];
  final Map<String, GlobalKey> _cellKeys = {};

  GlobalKey _handKey(int i) {
    while (_handKeys.length <= i) {
      _handKeys.add(GlobalKey());
    }
    return _handKeys[i];
  }

  GlobalKey _cellKey(PlayerId p, int r, int c) =>
      _cellKeys.putIfAbsent('${p.name}-$r-$c', () => GlobalKey());

  @override
  void initState() {
    super.initState();
    g = VeiledGame.deal(seed: widget.seed);
    WidgetsBinding.instance.addPostFrameCallback((_) => _startRound(dealt: 0));
  }

  @override
  void dispose() {
    _seq++;
    _ticker?.cancel();
    _time.dispose();
    super.dispose();
  }

  void _restart() {
    _seq++;
    _ticker?.cancel();
    setState(() {
      g = VeiledGame.deal(seed: widget.seed);
      _phase = _Phase.dealing;
      selected = null;
      _flyingHandIndex = null;
      _hideMarks.clear();
      _result = null;
      _banner = null;
      _dealtMine = 0;
      _dealtOpp = 0;
      _emoteOpen = false;
      _myEmote = null;
      _oppEmote = null;
      _emoteSeq++;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _startRound(dealt: 0));
  }

  void _playSfx(Sfx sfx) {
    if (!mounted) return;
    context.getInheritedWidgetOfExactType<SfxScope>()?.notifier?.play(sfx);
  }

  void _haptic(Haptic h) {
    if (!mounted) return;
    context.getInheritedWidgetOfExactType<HapticScope>()?.notifier?.play(h);
  }

  Rect? _rectFor(GlobalKey? key) {
    final box = key?.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  Future<void> _fly(GlobalKey? from, GlobalKey? to, PlayingCard card,
      {bool faceDown = false, int ms = 300}) async {
    final f = _rectFor(from), t = _rectFor(to);
    if (f == null || t == null || !mounted) return;
    await flyCard(
      overlay: Overlay.of(context),
      vsync: this,
      from: f,
      to: t,
      card: card,
      faceDown: faceDown,
      duration: Duration(milliseconds: ms),
    );
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg), duration: const Duration(seconds: 2)));
  }

  // ---- 라운드 진행 ----

  /// [dealt]: 딜링 연출 없이 이미 보여도 되는 내 손패 장수(라운드 보충 시 = 기존 장수).
  Future<void> _startRound({required int dealt}) async {
    if (!mounted) return;
    final seq = _seq;
    setState(() {
      _phase = _Phase.dealing;
      selected = null;
      _hideMarks.clear();
      _dealtMine = dealt;
      _dealtOpp = dealt;
    });
    await _dealAnimation(seq);
    if (!mounted || seq != _seq) return;
    _time.value = roundSeconds;
    _lastWholeSecond = roundSeconds.ceil();
    setState(() => _phase = _Phase.placing);
    _scheduleAi(seq);
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (!mounted || seq != _seq) return;
      // 화면 전체 setState 금지 — 타이머 바만 이 값을 구독한다(버벅임 방지).
      _time.value = (_time.value - 0.1).clamp(0, roundSeconds);
      final whole = _time.value.ceil();
      if (whole != _lastWholeSecond) {
        _lastWholeSecond = whole;
        if (whole <= 3 && whole > 0) _haptic(Haptic.select); // 초읽기
      }
      if (_time.value <= 0) _onTimeUp(seq);
    });
  }

  /// 덱에서 카드가 서로에게 날아가는 딜링 연출.
  /// 소리는 **카드가 안착하는 순간마다** "착" — 받는 타이밍과 리듬이 맞아야 한다.
  Future<void> _dealAnimation(int seq) async {
    final total = g.hands[me]!.length;
    if (_dealtMine >= total) return;
    // 상대/나 번갈아 한 장씩. 손패 슬롯은 투명하게 이미 자리를 잡고 있어서
    // 비행이 실제 슬롯 위치에 정확히 안착한다.
    for (var i = _dealtMine; i < total; i++) {
      unawaited(
          _fly(_deckKey, _oppHandKey, g.hands[ai]![i], faceDown: true, ms: 240)
              .then((_) {
        if (!mounted || seq != _seq) return;
        setState(() => _dealtOpp = i + 1);
        _playSfx(Sfx.cardPlace);
      }));
      await Future<void>.delayed(const Duration(milliseconds: 100));
      if (!mounted || seq != _seq) return;
      unawaited(_fly(_deckKey, _handKey(i), g.hands[me]![i], ms: 240).then((_) {
        if (!mounted || seq != _seq) return;
        setState(() => _dealtMine = i + 1);
        _playSfx(Sfx.cardPlace);
      }));
      await Future<void>.delayed(const Duration(milliseconds: 100));
      if (!mounted || seq != _seq) return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 300));
    if (mounted && seq == _seq) {
      setState(() {
        _dealtMine = total;
        _dealtOpp = total;
      });
    }
  }

  /// AI는 라운드 시작에 3장을 계획하고 타이머 중간중간 실제로 놓는다 —
  /// 내 눈에는 뒷면 카드가 실시간으로 깔린다(위치가 곧 정보 = 순서 심리전).
  void _scheduleAi(int seq) {
    final plan = veiledAiPlan(g, ai)
      ..sort((a, b) => b.handIndex.compareTo(a.handIndex)); // 인덱스 안전 순서
    var delayMs = 2000 + _rng.nextInt(3000);
    for (final m in plan) {
      final d = delayMs;
      delayMs += 3000 + _rng.nextInt(5000);
      Future<void>.delayed(Duration(milliseconds: d), () async {
        if (!mounted || seq != _seq || _phase != _Phase.placing) return;
        if (m.handIndex >= g.hands[ai]!.length || g.leftToPlace(ai) <= 0) return;
        if (g.fields[ai]![m.row][m.col] != null) return;
        final card = g.hands[ai]![m.handIndex];
        await _fly(_oppHandKey, _cellKey(ai, m.row, m.col), card, faceDown: true);
        if (!mounted || seq != _seq || _phase != _Phase.placing) return;
        setState(() => g.place(ai, m.handIndex, m.row, m.col));
        _playSfx(Sfx.cardPlace);
        _afterPlacement(seq);
      });
    }
    // AI의 열어보기: 내가 지난 라운드에 숨긴 카드가 있으면 중반쯤 하나 깐다.
    Future<void>.delayed(Duration(milliseconds: 6000 + _rng.nextInt(6000)), () {
      if (!mounted || seq != _seq || _phase != _Phase.placing) return;
      final target = veiledAiPeek(g, ai);
      if (target == null) return;
      g.peek(ai, target.$1, target.$2);
      _playSfx(Sfx.attackHit);
      _haptic(Haptic.impact);
      setState(() {});
      _snack(AppLocalizations.of(context).vlOppPeeked);
      final rect = _rectFor(_cellKey(me, target.$1, target.$2));
      if (rect != null && mounted) {
        unawaited(hitFlash(overlay: Overlay.of(context), vsync: this, at: rect));
      }
    });
  }

  /// 타임업: 남은 배치를 자동으로 채우고 동시 공개.
  void _onTimeUp(int seq) {
    _ticker?.cancel();
    if (!mounted || seq != _seq || _phase != _Phase.placing) return;
    var autoMine = false;
    for (final p in [me, ai]) {
      while (g.leftToPlace(p) > 0) {
        final plan = veiledAiPlan(g, p)
          ..sort((a, b) => b.handIndex.compareTo(a.handIndex));
        if (plan.isEmpty) break;
        for (final m in plan) {
          g.place(p, m.handIndex, m.row, m.col);
          if (p == me) autoMine = true;
        }
      }
    }
    setState(() {});
    if (autoMine) {
      _snack(AppLocalizations.of(context).vlTimeout);
      _haptic(Haptic.impact);
    }
    _doReveal(seq);
  }

  /// 둘 다 3장을 다 놓으면 즉시 공개하지 않고 **타이머를 5초로 줄인다** —
  /// 숨김 지정을 바꿀 마지막 창구. (공개는 언제나 타이머 종료 시점)
  void _afterPlacement(int seq) {
    if (!mounted || seq != _seq) return;
    if (!g.allPlaced || _phase != _Phase.placing) return;
    if (_time.value > lastCallSeconds) {
      _time.value = lastCallSeconds;
    }
  }

  Future<void> _doReveal(int seq) async {
    if (!mounted || seq != _seq || _phase != _Phase.placing) return;
    setState(() => _phase = _Phase.revealing);
    final l10n = AppLocalizations.of(context);
    final aiHides = veiledAiHides(g, ai);
    g.reveal({me: Set.of(_hideMarks), ai: aiHides});
    // 동시 공개 — 이 룰의 하이라이트. "두-둥" 스팅과 함께 전 카드가 뒤집힌다.
    setState(() => _banner = l10n.vlRevealBanner);
    _playSfx(Sfx.sting);
    _haptic(Haptic.place);
    if (aiHides.isNotEmpty) _snack(l10n.vlOppHid(aiHides.length));
    await Future<void>.delayed(const Duration(milliseconds: 900));
    if (!mounted || seq != _seq) return;
    setState(() => _banner = null);

    // 판정 세리머니: 1줄부터 차례로 WIN / LOSE.
    await _laneVerdictCeremony(seq);
    if (!mounted || seq != _seq) return;

    if (g.isFinished) {
      await _finish(seq);
      return;
    }
    final dealt = g.hands[me]!.length; // 보충 전 장수 — 새 카드만 딜링 연출
    setState(() => g.nextRound());
    await _startRound(dealt: dealt);
  }

  /// 줄별 판정 세리머니 — 첫째 줄부터 차례로, 공개된 정보 기준의
  /// 족보(또는 합계)와 WIN/LOSE 칩이 레인 위에 튀어나온다.
  Future<void> _laneVerdictCeremony(int seq) async {
    final l10n = AppLocalizations.of(context);
    for (var lane = 0; lane < kRows; lane++) {
      if (!mounted || seq != _seq) return;
      final mine = g.publicRow(me, lane);
      final opp = g.publicRow(ai, lane);
      final out = g.publicLine(me, lane);
      switch (out) {
        case LineOutcome.win:
          _playSfx(Sfx.token);
          _haptic(Haptic.shieldLock);
        case LineOutcome.lose:
          _playSfx(Sfx.attackHit);
          _haptic(Haptic.impact);
        case LineOutcome.tie:
          _playSfx(Sfx.cardPlace);
          _haptic(Haptic.select);
      }
      _showLaneVerdict(
        lane: lane,
        outcome: out,
        myLabel: _handLabel(l10n, mine),
        oppLabel: _handLabel(l10n, opp),
      );
      await Future<void>.delayed(const Duration(milliseconds: 550));
    }
    // 세 칩이 함께 보이는 여운.
    await Future<void>.delayed(const Duration(milliseconds: 900));
  }

  /// 판정 칩 라벨: 족보가 원페어 이상이면 족보명, 아니면 합계.
  String _handLabel(AppLocalizations l10n, List<PlayingCard> cards) {
    final r = evaluateHand(cards);
    return r.category.index >= HandCategory.onePair.index
        ? handCategoryName(l10n, r.category)
        : l10n.vlSum(lineScore(cards));
  }

  /// [lane] 위(내 첫 칸과 상대 첫 칸 사이 = 점수 알약 자리)에 판정 칩을 띄운다.
  /// 등장은 오버슛, 잠시 머물다 스스로 사라진다.
  void _showLaneVerdict({
    required int lane,
    required LineOutcome outcome,
    required String myLabel,
    required String oppLabel,
  }) {
    final a = _rectFor(_cellKey(me, lane, 0));
    final b = _rectFor(_cellKey(ai, lane, 0));
    if (a == null || b == null || !mounted) return;
    final center = Offset(
      (a.center.dx + b.center.dx) / 2,
      (a.center.dy + b.center.dy) / 2,
    );
    final l10n = AppLocalizations.of(context);
    final (word, color) = switch (outcome) {
      LineOutcome.win => (l10n.vlWin, AppColors.win),
      LineOutcome.lose => (l10n.vlLose, AppColors.lose),
      LineOutcome.tie => (l10n.vlTie, AppColors.tie),
    };
    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (context) => Positioned(
        left: center.dx - 70,
        top: center.dy - 40,
        width: 140,
        child: IgnorePointer(
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 2400),
            builder: (context, t, child) {
              // 0~0.12 등장(오버슛) · 0.12~0.85 유지 · 0.85~1 퇴장.
              final enter = (t / 0.12).clamp(0.0, 1.0);
              final exit = t < 0.85 ? 0.0 : (t - 0.85) / 0.15;
              final scale = Curves.easeOutBack.transform(enter) * (1 - 0.15 * exit);
              return Opacity(
                opacity: ((enter) * (1 - exit)).clamp(0.0, 1.0),
                child: Transform.scale(scale: scale, child: child),
              );
            },
            onEnd: () => entry.remove(),
            // 오버레이는 테마 DefaultTextStyle 밖 — 투명 Material로 잇는다.
            child: Material(
              type: MaterialType.transparency,
              child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(oppLabel,
                    style: const TextStyle(
                        color: AppColors.oppPrimary,
                        fontWeight: FontWeight.w800,
                        fontSize: 12)),
                Container(
                  margin: const EdgeInsets.symmetric(vertical: 3),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: color, width: 2),
                    boxShadow: [
                      BoxShadow(color: color.withValues(alpha: 0.5), blurRadius: 12),
                    ],
                  ),
                  child: Text(word,
                      style: TextStyle(
                          color: color,
                          fontWeight: FontWeight.w900,
                          fontSize: 18,
                          letterSpacing: 1.5)),
                ),
                Text(myLabel,
                    style: const TextStyle(
                        color: AppColors.mePrimary,
                        fontWeight: FontWeight.w800,
                        fontSize: 12)),
              ],
              ),
            ),
          ),
        ),
      ),
    );
    Overlay.of(context).insert(entry);
  }

  /// 최후 공개(남은 숨김 카드를 하나씩 극적으로) → 기존 규칙으로 정산.
  Future<void> _finish(int seq) async {
    final l10n = AppLocalizations.of(context);
    final hidden = [
      for (final p in PlayerId.values)
        for (final (r, c) in g.hiddenOf(p)) (p, r, c),
    ];
    if (hidden.isNotEmpty) {
      setState(() => _banner = l10n.vlFinalReveal);
      _playSfx(Sfx.sting);
      await Future<void>.delayed(const Duration(milliseconds: 900));
      if (!mounted || seq != _seq) return;
      setState(() => _banner = null);
    }
    for (final (p, r, c) in hidden) {
      await Future<void>.delayed(const Duration(milliseconds: 420));
      if (!mounted || seq != _seq) return;
      setState(() => g.fields[p]![r][c]!.faceUp = true);
      _playSfx(Sfx.cardPlace);
      _haptic(Haptic.select);
      final rect = _rectFor(_cellKey(p, r, c));
      if (rect != null && mounted) {
        unawaited(hitFlash(overlay: Overlay.of(context), vsync: this, at: rect));
      }
    }
    await Future<void>.delayed(const Duration(milliseconds: 600));
    if (!mounted || seq != _seq) return;
    // 전부 공개된 상태 — 마지막 세리머니는 진짜 최종 판정이다.
    await _laneVerdictCeremony(seq);
    if (!mounted || seq != _seq) return;
    final res = g.judge();
    setState(() {
      _result = res;
      _phase = _Phase.finished;
    });
    switch (res.outcome) {
      case MatchOutcome.win:
        _playSfx(Sfx.win);
        _haptic(Haptic.win);
      case MatchOutcome.lose:
        _playSfx(Sfx.lose);
        _haptic(Haptic.lose);
      case MatchOutcome.draw:
        break;
    }
  }

  // ---- 상호작용 (전부 타이머 안에서) ----

  int _nextCol(PlayerId p, int row) {
    for (var c = 0; c < VeiledGame.colsN; c++) {
      if (g.fields[p]![row][c] == null) return c;
    }
    return -1;
  }

  void _tapHand(int i) {
    if (_phase != _Phase.placing || g.leftToPlace(me) <= 0) return;
    _haptic(Haptic.select);
    setState(() => selected = selected == i ? null : i);
  }

  void _onCellTap(PlayerId owner, int row, int col) {
    if (_phase != _Phase.placing) return;
    if (owner == me) {
      final slot = g.fields[me]![row][col];
      if (selected != null && slot == null) {
        _placeSelected(row);
      } else if (slot != null && slot.round == g.round && !slot.faceUp) {
        _toggleHide(row, col); // 타이머가 끝나기 전까지는 자유롭게 변경
      }
    } else {
      _tapPeek(row, col);
    }
  }

  Future<void> _placeSelected(int row) async {
    if (selected == null || g.leftToPlace(me) <= 0) return;
    final col = _nextCol(me, row);
    if (col < 0) return; // 줄이 가득
    final seq = _seq;
    final i = selected!;
    if (i >= g.hands[me]!.length) return;
    final card = g.hands[me]![i];
    setState(() {
      selected = null;
      _flyingHandIndex = i;
    });
    await _fly(_handKey(i), _cellKey(me, row, col), card);
    if (!mounted || seq != _seq || _phase != _Phase.placing) return;
    setState(() {
      _flyingHandIndex = null;
      g.place(me, i, row, col);
    });
    _playSfx(Sfx.cardPlace);
    _haptic(Haptic.place);
    _afterPlacement(seq);
  }

  void _toggleHide(int r, int c) {
    final pos = (r, c);
    setState(() {
      if (_hideMarks.contains(pos)) {
        _hideMarks.remove(pos);
        _haptic(Haptic.select);
      } else if (_hideMarks.length < g.veilLeft[me]!) {
        _hideMarks.add(pos);
        // 봉인 도장이 찍히는 순간 — 동전 핑 + 잠금 촉감.
        _playSfx(Sfx.token);
        _haptic(Haptic.shieldLock);
      }
    });
  }

  /// 뒤집힌(지난 라운드에 숨겨진) 상대 카드를 클릭하면 비공개권으로 뒤집는다.
  Future<void> _tapPeek(int r, int c) async {
    if (g.veilLeft[me]! <= 0) return;
    final slot = g.fields[ai]![r][c];
    if (slot == null || slot.faceUp || slot.round >= g.round) return;
    setState(() => g.peek(me, r, c));
    _playSfx(Sfx.token);
    _haptic(Haptic.shieldLock);
    final rect = _rectFor(_cellKey(ai, r, c));
    if (rect != null && mounted) {
      unawaited(shieldGlint(overlay: Overlay.of(context), vsync: this, at: rect));
    }
  }

  // ---- build (기존 게임 화면과 같은 뼈대) ----

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final size = MediaQuery.sizeOf(context);
    final landscape = size.width > size.height;
    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(gradient: AppColors.bgGradient),
        child: SafeArea(
          child: Stack(
            children: [
              landscape ? _landscapeLayout(l10n, size.height) : _portraitLayout(l10n),
              // 이모트: 바깥 탭으로 닫힘, 말풍선은 아바타 옆 (기존 게임과 동일)
              if (_emoteOpen) ...[
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => setState(() => _emoteOpen = false),
                  ),
                ),
                Positioned(
                  right: 12,
                  bottom: landscape ? 116 : 128,
                  child: EmotePicker(onPick: _sendEmote),
                ),
              ],
              if (_oppEmote != null)
                Positioned(
                  key: const ValueKey('emote-opp'),
                  left: 14,
                  top: landscape ? 92 : 60,
                  child: EmoteBubble(key: ValueKey('opp-$_oppEmote'), asset: _oppEmote!),
                ),
              if (_myEmote != null)
                Positioned(
                  key: const ValueKey('emote-me'),
                  left: 14,
                  bottom: landscape ? 116 : 128,
                  child: EmoteBubble(key: ValueKey('me-$_myEmote'), asset: _myEmote!),
                ),
              if (_banner != null) _bannerOverlay(_banner!),
              if (_result != null) _resultOverlay(l10n, _result!),
            ],
          ),
        ),
      ),
    );
  }

  Widget _portraitLayout(AppLocalizations l10n) => Column(
        children: [
          _opponentStrip(l10n),
          _timerBar(),
          Expanded(child: _tableArea(landscape: false)),
          _myBottomRow(l10n),
        ],
      );

  Widget _landscapeLayout(AppLocalizations l10n, double h) {
    final topH = (h * 0.14).clamp(58.0, 88.0);
    final handH = (h * 0.19).clamp(74.0, 100.0);
    return Column(
      children: [
        SizedBox(height: topH, child: _lsTopRow(l10n)),
        _timerBar(),
        Expanded(child: _tableArea(landscape: true)),
        SizedBox(height: handH + 4, child: _lsBottomRow(l10n, handH)),
      ],
    );
  }

  ({int mine, int opp}) _publicWins() {
    var m = 0, o = 0;
    for (var i = 0; i < kRows; i++) {
      final r = g.publicLine(me, i);
      if (r == LineOutcome.win) m++;
      if (r == LineOutcome.lose) o++;
    }
    return (mine: m, opp: o);
  }

  Widget _opponentStrip(AppLocalizations l10n) {
    final wins = _publicWins();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 6, 2),
      child: Row(
        children: [
          TurnAvatar(
              color: AppColors.oppPrimary,
              active: _phase == _Phase.placing && !g.isFinished),
          const SizedBox(width: 8),
          Flexible(
            child: Text(l10n.player2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: AppColors.textMuted, fontWeight: FontWeight.w700, fontSize: 13)),
          ),
          const SizedBox(width: 10),
          _WinsPill(count: wins.opp, color: AppColors.oppPrimary),
          const Spacer(),
          FaceDownHand(
              key: _oppHandKey,
              count: _phase == _Phase.dealing ? _dealtOpp : g.hands[ai]!.length),
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            color: AppColors.inkSoft,
            tooltip: l10n.newGame,
            onPressed: _phase == _Phase.revealing ? null : _restart,
          ),
        ],
      ),
    );
  }

  Widget _lsTopRow(AppLocalizations l10n) {
    final wins = _publicWins();
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 6, 8, 0),
      child: Row(
        children: [
          TurnAvatar(
              color: AppColors.oppPrimary,
              active: _phase == _Phase.placing && !g.isFinished),
          const SizedBox(width: 8),
          _WinsPill(count: wins.opp, color: AppColors.oppPrimary),
          const SizedBox(width: 10),
          // 기회(비공개권)는 게임판 위 — 상대/내 코인이 한눈에 비교된다.
          _coinsRow(g.veilLeft[ai]!, ring: AppColors.oppPrimary),
          Expanded(
            child: Center(
              child: FaceDownHand(
                  key: _oppHandKey,
                  count: _phase == _Phase.dealing ? _dealtOpp : g.hands[ai]!.length),
            ),
          ),
          _coinsRow(g.veilLeft[me]! - _hideMarks.length, ring: AppColors.mePrimary),
          const SizedBox(width: 10),
          _placePips(horizontal: true),
          const SizedBox(width: 6),
          _deckCounter(),
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            color: AppColors.inkSoft,
            tooltip: l10n.newGame,
            onPressed: _phase == _Phase.revealing ? null : _restart,
          ),
        ],
      ),
    );
  }

  /// 비공개권 코인 3개(가로). 쓴 만큼 빈 소켓.
  Widget _coinsRow(int filled, {required Color ring}) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < 3; i++)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 1.5),
              child: VeilCoin(size: 17, filled: i < filled, ring: ring),
            ),
        ],
      );

  /// 이번 라운드 남은 배치 3칸 — 미니 카드 핍. 놓을수록 비워진다.
  Widget _placePips({required bool horizontal}) {
    final left = g.leftToPlace(me);
    final pips = [
      for (var i = 0; i < VeiledGame.perRound; i++)
        Padding(
          padding: const EdgeInsets.all(1.5),
          child: Container(
            width: 9,
            height: 13,
            decoration: BoxDecoration(
              color: i < left ? AppColors.gold : AppColors.slotRecess,
              borderRadius: BorderRadius.circular(2.5),
              border: Border.all(
                  color: i < left ? AppColors.goldSoft : AppColors.stroke),
            ),
          ),
        ),
    ];
    return horizontal
        ? Row(mainAxisSize: MainAxisSize.min, children: pips)
        : Column(mainAxisSize: MainAxisSize.min, children: pips);
  }

  Widget _deckCounter() {
    return Padding(
      key: _deckKey,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.style_rounded, size: 15, color: AppColors.textMuted),
          const SizedBox(width: 4),
          Text('${g.deckRemaining}',
              style: const TextStyle(
                  color: AppColors.textMuted, fontWeight: FontWeight.w800, fontSize: 13)),
        ],
      ),
    );
  }

  /// 배치 제한 시간 — 이 룰에서 유일하게 추가된 크롬.
  /// ValueListenableBuilder로 이 바만 다시 그린다(화면 전체 리빌드 금지).
  Widget _timerBar() {
    final active = _phase == _Phase.placing;
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 2, 18, 2),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(99),
        child: ValueListenableBuilder<double>(
          valueListenable: _time,
          builder: (context, left, _) {
            final urgent = active && left <= 5;
            return LinearProgressIndicator(
              value: active ? (left / roundSeconds).clamp(0.0, 1.0) : 1,
              minHeight: 4,
              backgroundColor: AppColors.slotRecess,
              valueColor: AlwaysStoppedAnimation(
                active
                    ? (urgent ? AppColors.oppPrimary : AppColors.gold)
                    : AppColors.stroke,
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _tableArea({required bool landscape}) => Padding(
        padding: const EdgeInsets.all(4),
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: AppColors.feltGradient,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: AppColors.feltEdge, width: 1),
          ),
          child: Stack(
            children: [
              const Positioned.fill(
                child: RepaintBoundary(child: CustomPaint(painter: TableDecorPainter())),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                child: landscape
                    ? _boardView(landscape: true)
                    : Row(
                        children: [
                          SizedBox(
                            width: 66,
                            child: Center(
                              child: DeckPileView(
                                  remaining: g.deckRemaining, pileKey: _deckKey),
                            ),
                          ),
                          Expanded(child: _boardView(landscape: false)),
                          SizedBox(width: 66, child: Center(child: _sideColumn())),
                        ],
                      ),
              ),
            ],
          ),
        ),
      );

  /// 우측 열(무덤 자리): 라운드 + **기회 코인들** + 남은 배치 — 판 위의 상황판.
  /// 손패 옆을 비우기 위해 자원 표시는 전부 여기로 모았다.
  Widget _sideColumn() {
    final l10n = AppLocalizations.of(context);
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.stroke),
          ),
          child: Text(
            l10n.sdRound(g.round + 1),
            textAlign: TextAlign.center,
            style: const TextStyle(
                color: AppColors.gold, fontWeight: FontWeight.w900, fontSize: 11),
          ),
        ),
        const SizedBox(height: 14),
        // 상대 코인(위쪽 = 상대 필드 쪽)
        _coinsColumn(g.veilLeft[ai]!, ring: AppColors.oppPrimary),
        const SizedBox(height: 18),
        // 내 코인(아래쪽 = 내 필드 쪽)
        _coinsColumn(g.veilLeft[me]! - _hideMarks.length, ring: AppColors.mePrimary),
        const SizedBox(height: 14),
        _placePips(horizontal: false),
      ],
    );
  }

  Widget _coinsColumn(int filled, {required Color ring}) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < 3; i++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 1.5),
              child: VeilCoin(size: 19, filled: i < filled, ring: ring),
            ),
        ],
      );

  Widget _boardView({required bool landscape}) => BoardView(
        cellAt: (owner, row, col) {
          final s = g.fields[owner]![row][col];
          return s == null ? null : PlacedCard(s.card, owner);
        },
        viewer: me,
        onCellTap: _onCellTap,
        isHighlighted: _isHighlighted,
        lookOf: _lookOf,
        lineCardsOf: (p, line) => g.publicRow(p, line),
        cellKeyFor: _cellKey,
        landscape: landscape,
      );

  CellLook _lookOf(PlayerId owner, int row, int col) {
    final s = g.fields[owner]![row][col];
    if (s == null || s.faceUp) return CellLook.face;
    if (owner != me) {
      // 지금 코인으로 열어볼 수 있는 카드는 골드 코인 마커가 박힌 뒷면.
      final peekable = _phase == _Phase.placing &&
          g.veilLeft[me]! > 0 &&
          s.round < g.round;
      return peekable ? CellLook.backPeekable : CellLook.back;
    }
    // 숨김 지정된 내 카드 = 봉인 도장. (확정은 공개 순간, 그 전까지 탭으로 해제)
    return _hideMarks.contains((row, col)) ? CellLook.sealed : CellLook.peek;
  }

  bool _isHighlighted(PlayerId owner, int row, int col) {
    if (_phase != _Phase.placing) return false;
    // 봉인은 도장이, 열어보기는 코인 마커가 말한다 — 하이라이트는 배치 목적지뿐.
    return owner == me &&
        selected != null &&
        g.fields[owner]![row][col] == null &&
        col == _nextCol(me, row);
  }

  // ---- 하단: 내 아바타 + 손패 + 남은 배치 ----

  // 손패 양옆은 비워 둔다 — 왼쪽 아바타(+줄 승수), 오른쪽 이모트뿐.
  // 자원(코인·배치 핍)은 전부 게임판 위의 상황판으로 올렸다.
  Widget _myBottomRow(AppLocalizations l10n) {
    final wins = _publicWins();
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 4, 10, 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TurnAvatar(
                      color: AppColors.mePrimary,
                      active: _phase == _Phase.placing && !g.isFinished),
                  const SizedBox(height: 5),
                  _WinsPill(count: wins.mine, color: AppColors.mePrimary),
                ],
              ),
              Expanded(child: _handBar(height: 104)),
              EmoteButton(
                tooltip: l10n.emotesTitle,
                open: _emoteOpen,
                onTap: () => setState(() => _emoteOpen = !_emoteOpen),
              ),
            ],
          ),
          _hint(l10n),
        ],
      ),
    );
  }

  Widget _lsBottomRow(AppLocalizations l10n, double handH) {
    final wins = _publicWins();
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
      child: Row(
        children: [
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TurnAvatar(
                  color: AppColors.mePrimary,
                  active: _phase == _Phase.placing && !g.isFinished),
              const SizedBox(height: 6),
              _WinsPill(count: wins.mine, color: AppColors.mePrimary),
            ],
          ),
          Expanded(child: _handBar(height: handH)),
          EmoteButton(
            tooltip: l10n.emotesTitle,
            open: _emoteOpen,
            onTap: () => setState(() => _emoteOpen = !_emoteOpen),
          ),
        ],
      ),
    );
  }

  /// 내 이모트 전송 → 잠시 뒤 상대(AI)도 반응한다. (기존 게임과 같은 동작)
  void _sendEmote(String asset) {
    setState(() {
      _emoteOpen = false;
      _myEmote = asset;
    });
    final seq = ++_emoteSeq;
    Future<void>.delayed(const Duration(milliseconds: 2800), () {
      if (mounted && seq == _emoteSeq) setState(() => _myEmote = null);
    });
    Future<void>.delayed(const Duration(milliseconds: 900), () {
      if (!mounted || seq != _emoteSeq) return;
      setState(() => _oppEmote = _emoteReply(asset));
      Future<void>.delayed(const Duration(milliseconds: 2800), () {
        if (mounted && seq == _emoteSeq) setState(() => _oppEmote = null);
      });
    });
  }

  String _emoteReply(String sent) => switch (sent) {
        'assets/lottie/emoji_smile.json' => 'assets/lottie/emoji_wow.json',
        'assets/lottie/emoji_lol.json' => 'assets/lottie/emoji_angry.json',
        'assets/lottie/emoji_wow.json' => 'assets/lottie/emoji_smile.json',
        'assets/lottie/emoji_sad.json' => 'assets/lottie/emoji_lol.json',
        'assets/lottie/emoji_angry.json' => 'assets/lottie/emoji_lol.json',
        _ => 'assets/lottie/emoji_smile.json',
      };

  Widget _handBar({required double height}) {
    final hand = g.hands[me]!;
    for (var i = 0; i < hand.length; i++) {
      _handKey(i);
    }
    final dealing = _phase == _Phase.dealing;
    final dim = !dealing && (_phase != _Phase.placing || g.leftToPlace(me) <= 0);
    return SizedBox(
      height: height,
      child: hand.isEmpty
          ? const Center(
              child: Text('—', style: TextStyle(color: AppColors.textMuted, fontSize: 20)))
          : Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var i = 0; i < hand.length; i++)
                      Opacity(
                        // 딜링 중엔 아직 도착하지 않은 카드 슬롯을 투명하게 —
                        // 자리는 잡혀 있어 비행이 정확한 위치에 안착한다.
                        opacity: (dealing && i >= _dealtMine) || _flyingHandIndex == i
                            ? 0
                            : (dim ? 0.5 : 1),
                        child: AnimatedSlide(
                          duration: const Duration(milliseconds: 140),
                          curve: Curves.easeOut,
                          offset: selected == i ? const Offset(0, -0.18) : Offset.zero,
                          child: CardCell(
                            key: _handKey(i),
                            placed: PlacedCard(hand[i], me),
                            size: 50,
                            side: CellSide.me,
                            highlighted: selected == i,
                            onTap: () => _tapHand(i),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _hint(AppLocalizations l10n) {
    final String text;
    switch (_phase) {
      case _Phase.dealing:
      case _Phase.revealing:
      case _Phase.finished:
        text = '';
      case _Phase.placing:
        text = g.leftToPlace(me) > 0 ? l10n.vlPlacePrompt : l10n.vlWaitOpp;
    }
    if (text.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Text(text,
          textAlign: TextAlign.center,
          style: const TextStyle(
              color: AppColors.textMuted, fontSize: 11.5, fontWeight: FontWeight.w600)),
    );
  }

  /// 공개/최후 공개 배너.
  Widget _bannerOverlay(String text) {
    return Positioned.fill(
      child: IgnorePointer(
        child: Center(
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 260),
            builder: (context, t, child) => Opacity(
                opacity: t,
                child: Transform.scale(scale: 0.85 + 0.15 * t, child: child)),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: AppColors.gold, width: 1.6),
                boxShadow: AppShapes.panelShadow,
              ),
              child: Text(text,
                  style: const TextStyle(
                      color: AppColors.gold,
                      fontWeight: FontWeight.w900,
                      fontSize: 20,
                      letterSpacing: 2)),
            ),
          ),
        ),
      ),
    );
  }

  Widget _resultOverlay(AppLocalizations l10n, MatchResult res) {
    final title = switch (res.outcome) {
      MatchOutcome.win => l10n.sdResultWin,
      MatchOutcome.lose => l10n.sdResultLose,
      MatchOutcome.draw => l10n.sdResultDraw,
    };
    final color = switch (res.outcome) {
      MatchOutcome.win => AppColors.gold,
      MatchOutcome.lose => AppColors.oppPrimary,
      MatchOutcome.draw => AppColors.textMuted,
    };
    return Positioned.fill(
      child: ColoredBox(
        color: AppColors.ink.withValues(alpha: 0.6),
        child: Center(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 30),
            padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 24),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: color, width: 1.8),
              boxShadow: AppShapes.panelShadow,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title,
                    style: TextStyle(
                        color: color, fontWeight: FontWeight.w900, fontSize: 26)),
                const SizedBox(height: 8),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var i = 0; i < res.lineOutcomes.length; i++)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Icon(
                          switch (res.lineOutcomes[i]) {
                            LineOutcome.win => Icons.check_circle_rounded,
                            LineOutcome.lose => Icons.cancel_rounded,
                            LineOutcome.tie => Icons.remove_circle_rounded,
                          },
                          size: 22,
                          color: switch (res.lineOutcomes[i]) {
                            LineOutcome.win => AppColors.mePrimary,
                            LineOutcome.lose => AppColors.oppPrimary,
                            LineOutcome.tie => AppColors.textMuted,
                          },
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                Text('${res.myTotal} : ${res.opponentTotal}',
                    style: const TextStyle(
                        color: AppColors.textMain,
                        fontWeight: FontWeight.w900,
                        fontSize: 18)),
                const SizedBox(height: 18),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FilledButton(onPressed: _restart, child: Text(l10n.sdPlayAgain)),
                    const SizedBox(width: 10),
                    OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: Text(l10n.sdExit),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 줄 승수 알약(기존 게임 화면과 동일한 모양) — 공개 정보 기준.
class _WinsPill extends StatelessWidget {
  const _WinsPill({required this.count, required this.color});
  final int count;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color, width: 1.3),
      ),
      child: Text('$count',
          style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: 13)),
    );
  }
}
