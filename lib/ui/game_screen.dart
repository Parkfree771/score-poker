import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../audio/sfx.dart';
import '../data/records_store.dart';
import '../domain/ai.dart';
import '../domain/card.dart';
import '../domain/game.dart';
import '../domain/hand.dart';
import '../domain/records.dart';
import '../domain/scoring.dart';
import '../feedback/haptics.dart';
import '../monetization/monetization.dart';
import '../l10n/app_localizations.dart';
import 'fx_lab.dart';
import 'widgets/level_stars.dart';
import 'hand_text.dart';
import 'personas.dart';
import 'theme.dart';
import 'widgets/board_view.dart';
import 'widgets/card_back.dart';
import 'widgets/card_cell.dart';
import 'widgets/emote_bubble.dart';
import 'widgets/chip_3d.dart';
import 'widgets/flying_card.dart';
import 'widgets/impact_effects.dart';
import 'widgets/joker_picker.dart';
import 'widgets/table_decor.dart';
import 'widgets/veil_chip.dart';

/// 게임 화면 — 상대 스트립 / 펠트 테이블(덱|보드|우측 열) / 내 스트립+손패.
/// 룰(v4 스트라이크)은 `domain/game.dart` 참고.
///
/// 흐름: 딜링 연출 → **교대 턴**(매 턴 덱에서 1장 드로) — 배치(앞면/뒷면 칩1),
/// 같은 숫자 공격(두 장 소멸 + 방어막 배치), 훔쳐보기(칩1, 턴 유지) →
/// 필드 완성·덱 소진 시 최후 공개·정산.
///
/// 실험 중 문자열은 한국어 하드코딩([_K]) — 룰이 굳으면 ARB로 옮긴다.
class GameScreen extends StatefulWidget {
  const GameScreen(
      {super.key,
      this.seed,
      this.persona,
      this.initialGame,
      this.boosted = false,
      this.fxLab = false,
      this.level = 3});

  final int? seed;

  /// 상대 AI 레벨(1~5). 매칭 화면이 RP·연승으로 정해 넘긴다. 기록에도 남는다.
  final int level;

  /// 부스트 판(상점): 내 칩 +1, 손패 스왑 1회. 판당 1개 — 도메인이 강제한다.
  final bool boosted;

  /// 대전 상대 캐릭터. null이면 이름/색만 기본값이고 대사가 없다(테스트·스크린샷용).
  final Persona? persona;

  /// 테스트·스크린샷 전용 **정지 화면**. 주입하면 딜링 연출·타이머·AI가 돌지 않고
  /// 그 상태 그대로 그려진다. 기록도 남기지 않는다.
  final ScoreGame? initialGame;

  /// 연출 실험실(디버그) — [initialGame] 위에 공격·칩 연출을 버튼으로 쏘는 패널.
  /// `fxLabState()`와 함께 쓴다(`fx_lab.dart`).
  final bool fxLab;

  @override
  State<GameScreen> createState() => _GameScreenState();
}

enum _Phase { dealing, playing, finished }

/// 실험 룰 전용 문구(한국어 하드코딩 — 룰 확정 후 ARB 이관).
abstract final class _K {
  static const myTurnPick = '내 차례 — 카드를 고르세요 · 상대 뒷면 탭 = 칩으로 훔쳐보기';
  static const myTurnPlace = '금색 칸에 놓기 · 같은 숫자의 상대 카드 = 공격!';
  static const myTurnJoker = '조커: 내 줄의 금색 칸에 원하는 카드로 놓는다';
  static const oppTurn = '상대 차례…';
  static const shieldPlace = '방어막 배치 — 내 줄을 채우거나, 상대 줄을 방해하세요';
  static const shieldBanner = '🛡 방어막!';
  static const oppStruckMe = '상대가 내 카드를 쳐냈다!';
  static const hideOn = '뒷면 배치 켜짐 — 다음 카드는 칩 1로 숨겨진다';
  static const discardTip = '놓을 곳이 없다 — 카드를 골라 버리세요';
  static const turnMine = '내 턴';
  static const turnOpp = '상대 턴';
}

class _GameScreenState extends State<GameScreen> with TickerProviderStateMixin {
  static const me = PlayerId.p0;
  static const ai = PlayerId.p1;

  /// 내 턴 제한 시간 — 한 수만 두면 되므로 짧다.
  static const turnSeconds = 20.0;

  /// 오디오 출력 지연 상쇄분(실기기 청취로 튜닝).
  static const sfxLeadMs = 45;

  late ScoreGame g;

  /// 상대 AI. 페르소나의 기풍이 곧 행동 계수다.
  late final VeiledAi _ai = VeiledAi(widget.persona?.style ?? AiStyle.clode,
      level: widget.level, seed: widget.seed);

  /// 타임업 때 내 수를 대신 두는 손. 성격이 없어야 하므로 기본형.
  late final VeiledAi _autoPlay = VeiledAi(AiStyle.clode, seed: widget.seed);

  _Phase _phase = _Phase.dealing;
  int? selected;
  int? _flyingHandIndex;

  /// 다음 배치를 칩으로 숨긴다(토글). 배치하면 자동 해제.
  bool _hideNext = false;

  /// 이번 턴의 드로 연출을 이미 했는가(카드 객체로 식별).
  PlayingCard? _drawAnimated;

  /// 드로 연출 중 — 손패 마지막 장을 잠시 투명하게.
  bool _drawAnimating = false;

  /// 열어보기 연출 중(칩 비행) — 중복 탭 방지.
  bool _peeking = false;

  /// 스왑 연출 중 — 그동안 손패 탭 금지.
  bool _swapping = false;

  final Map<(PlayerId, int), GlobalKey<VeilChipState>> _chipKeys = {};

  /// 지금 날아가는 중인 레일 칩(주인, 인덱스) — 레일에서는 빈 소켓으로 그린다.
  (PlayerId, int)? _chipInFlight;
  GlobalKey<VeilChipState> _chipKey(PlayerId p, int i) =>
      _chipKeys.putIfAbsent((p, i), () => GlobalKey<VeilChipState>(debugLabel: 'chip-$p-$i'));
  MatchResult? _result;
  String? _banner;
  int _dealtMine = 0; // 딜링/드로 연출 중 보이는 내 손패 장수
  int _dealtOpp = 0;
  int _seq = 0;

  /// 상대 캐릭터 대사(말풍선).
  String? _oppSpeech;
  int _speechSeq = 0;

  /// 결과를 랭킹 기록에 저장했는가(판당 1회).
  bool _recorded = false;

  // ---- 이모트 ----
  bool _emoteOpen = false;
  String? _myEmote;
  String? _oppEmote;
  int _emoteSeq = 0;

  /// 남은 시간 — 타이머 바 위젯만 이 값을 구독한다(전체 리빌드 금지).
  final ValueNotifier<double> _time = ValueNotifier(turnSeconds);
  Timer? _ticker;
  int _lastWholeSecond = turnSeconds.ceil();

  final Random _rng = Random();
  final _deckKey = GlobalKey();
  final _oppHandKey = GlobalKey();
  final List<GlobalKey> _handKeys = [];
  final Map<String, GlobalKey> _cellKeys = {};

  GlobalKey _handKey(int i) {
    while (_handKeys.length <= i) {
      _handKeys.add(GlobalKey(debugLabel: 'hand-${_handKeys.length}'));
    }
    return _handKeys[i];
  }

  GlobalKey _cellKey(PlayerId p, int r, int c) => _cellKeys.putIfAbsent(
      '${p.name}-$r-$c', () => GlobalKey(debugLabel: 'cell-${p.name}-$r-$c'));

  @override
  void initState() {
    super.initState();
    g = widget.initialGame ??
        ScoreGame.deal(seed: widget.seed, boostFor: _boosted ? me : null);
    if (_frozen) {
      _dealtMine = g.hands[me]!.length;
      _dealtOpp = g.hands[ai]!.length;
      _drawAnimated = g.lastDrawn;
      if (g.isFinished) {
        _phase = _Phase.finished;
        _result = g.judge();
      } else {
        _phase = _Phase.playing;
        final hello = _lines?.greeting;
        if (hello != null && hello.isNotEmpty) {
          WidgetsBinding.instance
              .addPostFrameCallback((_) => _say([hello.first]));
        }
      }
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _startGame());
  }

  @override
  void dispose() {
    _seq++;
    _ticker?.cancel();
    _time.dispose();
    super.dispose();
  }

  /// 주입된 상태를 보여 주는 정지 모드인가.
  bool get _frozen => widget.initialGame != null;

  late bool _boosted = widget.boosted;

  /// 부스트를 쓰고 한 수도 안 뒀는가(이탈하면 토큰을 돌려준다).
  bool get _boostUnused =>
      _boosted &&
      !g.acted[me]! &&
      g.swapLeft[me] == 1 &&
      g.veilLeft[me] == g.veilsMax(me);

  void _refundBoostIfUnused() {
    if (_frozen || !_boostUnused) return;
    _boosted = false;
    final wallet = MonetizationScope.maybeOf(context)?.wallet;
    if (wallet != null) unawaited(wallet.refund(TokenKind.boost));
  }

  @visibleForTesting
  Future<void> restartForTest() => _restart();

  Future<void> _restart() async {
    if (_frozen) return;
    if (widget.boosted) {
      final wallet = MonetizationScope.maybeOf(context)?.wallet;
      _boosted = wallet != null && await wallet.spend(TokenKind.boost);
      if (!mounted) return;
      if (!_boosted) _snack(AppLocalizations.of(context).boostNone);
    }
    _seq++;
    _ticker?.cancel();
    setState(() {
      g = ScoreGame.deal(seed: widget.seed, boostFor: _boosted ? me : null);
      _phase = _Phase.dealing;
      selected = null;
      _flyingHandIndex = null;
      _hideNext = false;
      _drawAnimated = null;
      _drawAnimating = false;
      _chipInFlight = null;
      _result = null;
      _banner = null;
      _dealtMine = 0;
      _dealtOpp = 0;
      _emoteOpen = false;
      _myEmote = null;
      _oppEmote = null;
      _oppSpeech = null;
      _speechSeq++;
      _recorded = false;
      _emoteSeq++;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _startGame());
  }

  void _say(List<String>? lines) {
    if (lines == null || lines.isEmpty || !mounted) return;
    setState(() {
      _oppSpeech = lines[_rng.nextInt(lines.length)];
      _oppEmote = null;
    });
    final seq = ++_speechSeq;
    Future<void>.delayed(const Duration(milliseconds: 3200), () {
      if (mounted && seq == _speechSeq) setState(() => _oppSpeech = null);
    });
  }

  PersonaLines? get _lines => widget.persona?.lines;

  Future<void> _recordResult(MatchResult res) async {
    if (_recorded || _frozen) return;
    _recorded = true;
    try {
      await RecordsStore.addRecord(GameRecord(
        playedAt: DateTime.now(),
        myScore: res.myTotal,
        oppScore: res.opponentTotal,
        outcome: res.outcome,
        opponentLevel: widget.level,
      ));
    } on Object {
      // 저장소를 못 쓰는 환경(테스트 등)에서도 판은 끝나야 한다.
    }
  }

  void _playSfx(Sfx sfx, {int? variant}) {
    if (!mounted) return;
    context
        .getInheritedWidgetOfExactType<SfxScope>()
        ?.notifier
        ?.play(sfx, variant: variant);
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
      {bool faceDown = false,
      bool trail = false,
      int ms = 300}) async {
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
      curve: trail ? Curves.easeIn : Curves.easeInOutCubic,
      trail: trail,
    );
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg), duration: const Duration(seconds: 2)));
  }

  // ---- 게임 시작·턴 진행 ----

  bool get _myActionTurn =>
      _phase == _Phase.playing &&
      !g.isFinished &&
      g.turn == me &&
      g.phase == TurnPhase.action;

  bool get _myShieldTurn =>
      _phase == _Phase.playing &&
      !g.isFinished &&
      g.turn == me &&
      g.phase == TurnPhase.shield;

  Future<void> _startGame() async {
    if (!mounted) return;
    final seq = _seq;
    setState(() {
      _phase = _Phase.dealing;
      selected = null;
      _dealtMine = 0;
      _dealtOpp = 0;
    });
    await _dealAnimation(seq);
    if (!mounted || seq != _seq) return;
    _drawAnimated = g.lastDrawn; // 첫 드로는 딜링에 포함됐다
    setState(() => _phase = _Phase.playing);
    _say(_lines?.greeting);
    if (g.turn == me) {
      _beginMyTurn();
    } else {
      unawaited(_botTurn());
    }
  }

  /// 덱에서 카드가 서로에게 날아가는 딜링 연출.
  Future<void> _dealAnimation(int seq, {bool oppToo = true}) async {
    final total = g.hands[me]!.length;
    if (_dealtMine >= total) return;
    for (var i = _dealtMine; i < total; i++) {
      if (oppToo && i < g.hands[ai]!.length) {
        unawaited(
            _fly(_deckKey, _oppHandKey, g.hands[ai]![i], faceDown: true, ms: 240)
                .then((_) {
          if (!mounted || seq != _seq) return;
          setState(() => _dealtOpp = i + 1);
        }));
        await Future<void>.delayed(const Duration(milliseconds: 160));
        if (!mounted || seq != _seq) return;
      }
      unawaited(Future<void>.delayed(const Duration(milliseconds: 240 - sfxLeadMs))
          .then((_) {
        if (!mounted || seq != _seq) return;
        _playSfx(Sfx.cardPlace, variant: 0);
      }));
      unawaited(_fly(_deckKey, _handKey(i), g.hands[me]![i], ms: 240).then((_) {
        if (!mounted || seq != _seq) return;
        setState(() => _dealtMine = i + 1);
        _haptic(Haptic.select);
      }));
      await Future<void>.delayed(const Duration(milliseconds: 160));
      if (!mounted || seq != _seq) return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 300));
    if (mounted && seq == _seq) {
      setState(() {
        _dealtMine = total;
        if (oppToo) _dealtOpp = g.hands[ai]!.length;
      });
    }
  }

  /// 내 턴 시작 — 드로 연출 + 타이머.
  Future<void> _beginMyTurn() async {
    if (!mounted || _frozen) return;
    final seq = _seq;
    await _animateDrawIfNeeded(seq, me);
    if (!mounted || seq != _seq) return;
    _time.value = turnSeconds;
    _lastWholeSecond = turnSeconds.ceil();
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (!mounted || seq != _seq) return;
      _time.value = (_time.value - 0.1).clamp(0, turnSeconds);
      final whole = _time.value.ceil();
      if (whole != _lastWholeSecond) {
        _lastWholeSecond = whole;
        if (whole <= 3 && whole > 0) _haptic(Haptic.select);
      }
      if (_time.value <= 0) _onTimeUp(seq);
    });
    setState(() {});
  }

  /// 이번 턴에 뽑은 카드가 아직 연출 전이면 덱→손 비행을 보여준다.
  Future<void> _animateDrawIfNeeded(int seq, PlayerId p) async {
    final drawn = g.lastDrawn;
    if (drawn == null || _drawAnimated == drawn || g.turn != p) return;
    _drawAnimated = drawn;
    if (p == me) {
      final idx = g.hands[me]!.length - 1;
      setState(() {
        _drawAnimating = true;
        _dealtMine = idx;
      });
      unawaited(Future<void>.delayed(const Duration(milliseconds: 240 - sfxLeadMs))
          .then((_) {
        if (mounted && seq == _seq) _playSfx(Sfx.cardPlace, variant: 0);
      }));
      await _fly(_deckKey, _handKey(idx), drawn, ms: 240);
      if (!mounted || seq != _seq) return;
      setState(() {
        _drawAnimating = false;
        _dealtMine = g.hands[me]!.length;
      });
    } else {
      await _fly(_deckKey, _oppHandKey, drawn, faceDown: true, ms: 240);
      if (!mounted || seq != _seq) return;
      setState(() {});
    }
  }

  /// 내 수가 끝난 뒤 — 정산 확인, 아니면 봇 턴.
  void _afterMyMove() {
    _ticker?.cancel();
    _time.value = turnSeconds;
    if (g.isFinished) {
      unawaited(_finish(_seq));
      return;
    }
    if (g.turn == ai) {
      unawaited(_botTurn());
    } else {
      unawaited(_beginMyTurn());
    }
  }

  /// 타임업: 내 수를 자동으로 두고 턴을 넘긴다.
  void _onTimeUp(int seq) {
    _ticker?.cancel();
    if (!mounted || seq != _seq || !(_myActionTurn || _myShieldTurn)) return;
    var guard = 0;
    while (!g.isFinished && g.turn == me && guard++ < 12) {
      _applyQuiet(me, _autoPlay.chooseTurn(g, me));
    }
    setState(() {
      selected = null;
      _hideNext = false;
    });
    _snack(AppLocalizations.of(context).vlTimeout);
    _haptic(Haptic.impact);
    _afterMyMove();
  }

  /// 연출 없이 수를 적용한다(타임업 자동 진행용).
  void _applyQuiet(PlayerId p, TurnMove m) {
    switch (m) {
      case MovePlace(:final handIndex, :final row, :final hidden, :final wildAs):
        if (wildAs != null) {
          g.placeWild(p, handIndex, row, wildAs, hidden: hidden);
        } else {
          g.place(p, handIndex, row, hidden: hidden);
        }
      case MoveAttack(:final handIndex, :final row, :final col):
        g.attack(p, handIndex, row, col);
      case MoveShield(:final ownField, :final row):
        g.placeShield(p, ownField, row);
      case MoveBurnShield():
        g.burnShield(p);
      case MovePeek(:final row, :final col):
        g.peek(p, row, col);
      case MoveDiscard(:final handIndex):
        g.discard(p, handIndex);
    }
  }

  /// 봇 턴 루프 — 내 연출과 같은 문법, 행동 사이 딜레이.
  Future<void> _botTurn() async {
    if (_frozen) return;
    final seq = _seq;
    _ticker?.cancel();
    setState(() {});
    var guard = 0;
    while (mounted &&
        seq == _seq &&
        !g.isFinished &&
        g.turn == ai &&
        guard++ < 16) {
      await _animateDrawIfNeeded(seq, ai);
      if (!mounted || seq != _seq) return;
      await Future<void>.delayed(Duration(milliseconds: 650 + _rng.nextInt(500)));
      if (!mounted || seq != _seq || g.turn != ai || g.isFinished) break;
      final move = _ai.chooseTurn(g, ai);
      switch (move) {
        case MovePeek(:final row, :final col):
          if (_peeking) break;
          _peeking = true;
          try {
            await _peekWithChip(by: ai, row: row, col: col);
          } finally {
            _peeking = false;
          }
          if (!mounted || seq != _seq) return;
          _snack(AppLocalizations.of(context).vlOppPeeked);
          _say(_lines?.peek);
        // 턴 소모 없음 — 루프 계속.
        case MoveAttack(:final handIndex, :final row, :final col):
          await _attackCeremony(ai, handIndex, row, col);
          if (!mounted || seq != _seq) return;
          _snack(_K.oppStruckMe);
          _say(_lines?.lead);
        case MoveShield(:final ownField, :final row):
          await _shieldPlaceCeremony(ai, ownField, row);
        case MoveBurnShield():
          setState(() => g.burnShield(ai));
        case MovePlace(:final handIndex, :final row, :final hidden, :final wildAs):
          final card = wildAs ?? g.hands[ai]![handIndex];
          final col = g.nextCol(ai, row);
          if (col < 0) break;
          await _fly(_oppHandKey, _cellKey(ai, row, col), card,
              faceDown: hidden);
          if (!mounted || seq != _seq) return;
          setState(() {
            if (wildAs != null) {
              g.placeWild(ai, handIndex, row, wildAs, hidden: hidden);
            } else {
              g.place(ai, handIndex, row, hidden: hidden);
            }
          });
          _playSfx(hidden ? Sfx.token : Sfx.cardPlace);
          if (hidden) _say(_lines?.hide);
        case MoveDiscard(:final handIndex):
          setState(() => g.discard(ai, handIndex));
          _playSfx(Sfx.cardSlide);
      }
    }
    if (!mounted || seq != _seq) return;
    if (g.isFinished) {
      unawaited(_finish(seq));
    } else if (g.turn == me) {
      unawaited(_beginMyTurn());
    }
  }

  // ---- 공격·방어막 연출 (내 수·봇 수·실험실 공용) ----

  /// 공격 세리머니: 돌진 비행 → 타격(플래시·파편) → 표적이 쳐내져 날아감 →
  /// 방어막 드로 배너. 공격자가 봇이면 방어막 배치까지 이어서 한다.
  Future<void> _attackCeremony(
      PlayerId by, int handIndex, int row, int col) async {
    final seq = _seq;
    final target = by.other;
    final atkCard = g.hands[by]![handIndex];
    final victimSlot = g.fields[target]![row][col];
    if (victimSlot == null) return;
    final victim = victimSlot.card;
    if (by == me) {
      setState(() {
        selected = null;
        _flyingHandIndex = handIndex;
      });
    }
    await _fly(by == me ? _handKey(handIndex) : _oppHandKey,
        _cellKey(target, row, col), atkCard,
        ms: 260, trail: true);
    if (!mounted || seq != _seq) return;
    _playSfx(Sfx.attackHit);
    _haptic(Haptic.impact);
    setState(() {
      _flyingHandIndex = null;
      g.attack(by, handIndex, row, col);
    });
    final rect = _rectFor(_cellKey(target, row, col));
    if (rect != null && mounted) {
      final overlay = Overlay.of(context);
      unawaited(hitFlash(overlay: overlay, vsync: this, at: rect));
      unawaited(sparkBurst(overlay: overlay, vsync: this, at: rect));
      await poofCard(
          overlay: overlay,
          vsync: this,
          rect: rect,
          card: victim,
          driftX: by == me ? 0.7 : -0.7);
    }
    if (!mounted || seq != _seq) return;
    if (g.phase != TurnPhase.shield) return; // 덱 소진 — 보충 없음
    // 방어막 드로 배너.
    setState(() => _banner = _K.shieldBanner);
    _playSfx(Sfx.token);
    await Future<void>.delayed(const Duration(milliseconds: 700));
    if (!mounted || seq != _seq) return;
    setState(() => _banner = null);
    if (g.shieldSlots().isEmpty) {
      setState(() => g.burnShield(by));
      return;
    }
    if (by == ai) {
      final mv = _ai.chooseTurn(g, ai);
      if (mv is MoveShield) {
        await _shieldPlaceCeremony(ai, mv.ownField, mv.row);
      } else {
        setState(() => g.burnShield(ai));
      }
    }
    // by == me → 입력 대기(g.phase == shield가 하이라이트를 켠다).
  }

  /// 방어막 배치 연출 — 덱에서 카드가 날아가 앉고 골드 글린트로 잠긴다.
  Future<void> _shieldPlaceCeremony(PlayerId by, bool ownField, int row) async {
    final seq = _seq;
    final owner = ownField ? by : by.other;
    final col = g.nextCol(owner, row);
    final card = g.pendingShield;
    if (col < 0 || card == null) return;
    _playSfx(Sfx.cardSlide);
    await _fly(_deckKey, _cellKey(owner, row, col), card, ms: 320);
    if (!mounted || seq != _seq) return;
    setState(() => g.placeShield(by, ownField, row));
    _playSfx(Sfx.token);
    _haptic(Haptic.shieldLock);
    final rect = _rectFor(_cellKey(owner, row, col));
    if (rect != null && mounted) {
      unawaited(shieldGlint(overlay: Overlay.of(context), vsync: this, at: rect));
    }
  }

  // ---- 연출 실험실 (디버그) ----

  bool _labBusy = false;

  void _labReset() {
    _seq++;
    _ticker?.cancel();
    setState(() {
      g = fxLabState();
      _chipInFlight = null;
      _banner = null;
      selected = null;
      _drawAnimated = g.lastDrawn;
    });
  }

  Future<void> _labRun(Future<void> Function() body) async {
    if (_labBusy) return;
    _labBusy = true;
    _labReset();
    await Future<void>.delayed(const Duration(milliseconds: 120));
    try {
      if (mounted) await body();
    } finally {
      _labBusy = false;
    }
  }

  Widget _fxLabPanel() {
    Widget btn(String label, Future<void> Function() body) => Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: FilledButton.tonal(
            style: FilledButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 10)),
            onPressed: () => _labRun(body),
            child: Text(label, style: const TextStyle(fontSize: 12)),
          ),
        );
    return Material(
      type: MaterialType.transparency,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // 고정 판: 내 손 9♦(0번) ↔ 상대 필드 9♠(줄1,칸0) — 공격 데모.
          btn('공격 나→상대', () async {
            await _attackCeremony(me, 0, 1, 0);
            // 방어막은 자동으로 내 줄0에 — 배치 연출까지 한 번에 본다.
            if (g.phase == TurnPhase.shield) {
              await Future<void>.delayed(const Duration(milliseconds: 500));
              if (mounted && g.phase == TurnPhase.shield) {
                await _shieldPlaceCeremony(me, true, 0);
              }
            }
          }),
          btn('공격 상대→나', () async {
            g.turn = PlayerId.p1; // 실험실 전용 — 상대 턴으로 돌려 공격시킨다
            await _attackCeremony(ai, 0, 0, 0);
          }),
          btn('칩 나→상대', () => _peekWithChip(by: me, row: 1, col: 1)),
          btn('칩 상대→나', () async {
            g.turn = PlayerId.p1; // 실험실 전용 — 상대 턴으로 돌려 훔쳐보게 한다
            await _peekWithChip(by: ai, row: 1, col: 1);
          }),
          btn('딜링', () async {
            setState(() {
              g = ScoreGame.deal(seed: 7);
              _dealtMine = 0;
              _dealtOpp = 0;
            });
            await _dealAnimation(_seq);
          }),
          btn('소리: 슛', () async => _playSfx(Sfx.chipShot)),
          btn('소리: 팅', () async => _playSfx(Sfx.chipTing)),
          btn('소리: 착', () async => _playSfx(Sfx.cardPlace)),
          btn('리셋', () async {}),
        ],
      ),
    );
  }

  /// 판정 칩 라벨: 족보가 원페어 이상이면 족보명, 아니면 합계.
  String _handLabel(AppLocalizations l10n, List<PlayingCard> cards) {
    final r = evaluateHand(cards);
    return r.category.index >= HandCategory.onePair.index
        ? handCategoryName(l10n, r.category)
        : l10n.vlSum(lineScore(cards));
  }

  /// 줄별 판정 세리머니 — 첫째 줄부터 차례로 WIN/LOSE 칩이 레인 위에 튀어나온다.
  Future<void> _laneVerdictCeremony(int seq) async {
    final l10n = AppLocalizations.of(context);
    for (var lane = 0; lane < kRows; lane++) {
      if (!mounted || seq != _seq) return;
      final mine = g.publicRow(me, lane);
      final opp = g.publicRow(ai, lane);
      final out = compareLine(mine, opp);
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
    await Future<void>.delayed(const Duration(milliseconds: 900));
  }

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
              final enter = (t / 0.12).clamp(0.0, 1.0);
              final exit = t < 0.85 ? 0.0 : (t - 0.85) / 0.15;
              final scale = Curves.easeOutBack.transform(enter) * (1 - 0.15 * exit);
              return Opacity(
                opacity: ((enter) * (1 - exit)).clamp(0.0, 1.0),
                child: Transform.scale(scale: scale, child: child),
              );
            },
            onEnd: () => entry.remove(),
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

  /// 최후 공개(남은 뒷면 카드를 하나씩 극적으로) → 정산.
  Future<void> _finish(int seq) async {
    _ticker?.cancel();
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
    unawaited(_recordResult(res));
  }

  // ---- 내 상호작용 ----

  /// **손패 스왑**(부스트): 손 전체가 덱으로 돌아가고 새로 받는다. 한 수라도 뒀으면 불가.
  Future<void> _swapHand() async {
    if (!_myActionTurn || _swapping || !g.canSwap(me)) return;
    final seq = _seq;
    final hand = g.hands[me]!;
    final n = hand.length;
    setState(() {
      _swapping = true;
      selected = null;
    });
    _haptic(Haptic.select);
    for (var i = 0; i < n; i++) {
      unawaited(_fly(_handKey(i), _deckKey, hand[i], faceDown: true, ms: 220));
      _playSfx(Sfx.cardSlide);
      await Future<void>.delayed(const Duration(milliseconds: 70));
      if (!mounted || seq != _seq) return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 200));
    if (!mounted || seq != _seq) return;
    setState(() {
      g.swap(me);
      _dealtMine = 0;
    });
    await _dealAnimation(seq, oppToo: false);
    if (!mounted || seq != _seq) return;
    setState(() => _swapping = false);
  }

  Widget _swapButton(AppLocalizations l10n) {
    final visible = g.isBoosted(me) && g.canSwap(me) && _myActionTurn && !_swapping;
    return AnimatedOpacity(
      opacity: visible ? 1 : 0,
      duration: const Duration(milliseconds: 180),
      child: IgnorePointer(
        ignoring: !visible,
        child: Tooltip(
          message: l10n.swapTip,
          child: Material(
            color: AppColors.surface,
            shape: const StadiumBorder(side: BorderSide(color: AppColors.gold, width: 1.2)),
            child: InkWell(
              customBorder: const StadiumBorder(),
              onTap: _swapHand,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.swap_horiz_rounded, size: 16, color: AppColors.goldSoft),
                    const SizedBox(width: 4),
                    Text(l10n.swapButton,
                        style: const TextStyle(
                            color: AppColors.goldSoft,
                            fontWeight: FontWeight.w900,
                            fontSize: 12)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _tapHand(int i) {
    if (!_myActionTurn || _swapping) return;
    final hand = g.hands[me]!;
    if (i >= hand.length) return;
    _haptic(Haptic.select);
    setState(() => selected = selected == i ? null : i);
  }

  bool get _selectedIsJoker =>
      selected != null && selected! < g.hands[me]!.length && g.hands[me]![selected!].isJoker;

  void _onCellTap(PlayerId owner, int row, int col) {
    if (_phase != _Phase.playing) return;
    // 방어막 배치 대기 — 양쪽 필드의 다음 칸 아무 데나.
    if (_myShieldTurn) {
      if (g.fields[owner]![row][col] == null && col == g.nextCol(owner, row)) {
        unawaited(_shieldPlaceCeremony(me, owner == me, row).then((_) {
          if (mounted) _afterMyMove();
        }));
      }
      return;
    }
    if (!_myActionTurn) return;
    if (owner == me) {
      final slot = g.fields[me]![row][col];
      if (selected != null && slot == null && col == g.nextCol(me, row)) {
        if (_selectedIsJoker) {
          unawaited(_placeWildSelected(row));
        } else {
          unawaited(_placeSelected(row));
        }
      }
    } else {
      final slot = g.fields[ai]![row][col];
      if (slot == null) return;
      // 공격: 선택한 카드와 랭크가 같은, 보이는 비-방어막 카드.
      if (selected != null &&
          !_selectedIsJoker &&
          !slot.shield &&
          g.visibleTo(me, ai, slot) &&
          g.hands[me]![selected!].rank == slot.card.rank) {
        final i = selected!;
        unawaited(_attackCeremony(me, i, row, col).then((_) {
          if (!mounted) return;
          if (g.phase != TurnPhase.shield) _afterMyMove();
          setState(() {});
        }));
        return;
      }
      unawaited(_tapPeek(row, col));
    }
  }

  /// 조커를 내 줄에 와일드로 — 카드를 고르고 나서 날아가 앉는다.
  Future<void> _placeWildSelected(int row) async {
    if (selected == null) return;
    final col = g.nextCol(me, row);
    if (col < 0) return;
    final seq = _seq;
    final i = selected!;
    final card = await showJokerPicker(context, strike: false);
    if (card == null || !mounted || seq != _seq || !_myActionTurn) return;
    if (i >= g.hands[me]!.length || !g.hands[me]![i].isJoker) return;
    if (g.fields[me]![row][col] != null) return;
    final hidden = _hideNext && g.veilLeft[me]! > 0;
    setState(() {
      selected = null;
      _flyingHandIndex = i;
    });
    await _fly(_handKey(i), _cellKey(me, row, col), card, faceDown: hidden);
    if (!mounted || seq != _seq || !_myActionTurn) return;
    setState(() {
      _flyingHandIndex = null;
      _hideNext = false;
      g.placeWild(me, i, row, card, hidden: hidden);
    });
    _playSfx(hidden ? Sfx.token : Sfx.cardPlace);
    _haptic(hidden ? Haptic.shieldLock : Haptic.place);
    _afterMyMove();
  }

  Future<void> _placeSelected(int row) async {
    if (selected == null) return;
    final col = g.nextCol(me, row);
    if (col < 0) return;
    final seq = _seq;
    final i = selected!;
    if (i >= g.hands[me]!.length) return;
    final card = g.hands[me]![i];
    final hidden = _hideNext && g.veilLeft[me]! > 0;
    setState(() {
      selected = null;
      _flyingHandIndex = i;
    });
    await _fly(_handKey(i), _cellKey(me, row, col), card, faceDown: hidden);
    if (!mounted || seq != _seq || !_myActionTurn) return;
    setState(() {
      _flyingHandIndex = null;
      _hideNext = false;
      g.place(me, i, row, hidden: hidden);
    });
    _playSfx(hidden ? Sfx.token : Sfx.cardPlace);
    _haptic(hidden ? Haptic.shieldLock : Haptic.place);
    _afterMyMove();
  }

  /// 버리기 — 내 필드가 만석일 때 손패를 탭한 채로 버림 버튼.
  Future<void> _discardSelected() async {
    if (!_myActionTurn || g.openRows(me).isNotEmpty) return;
    final i = selected ?? g.hands[me]!.length - 1;
    if (i < 0 || i >= g.hands[me]!.length) return;
    final seq = _seq;
    final card = g.hands[me]![i];
    setState(() {
      selected = null;
      _flyingHandIndex = i;
    });
    final rect = _rectFor(_handKey(i));
    if (rect != null) {
      unawaited(poofCard(
          overlay: Overlay.of(context),
          vsync: this,
          rect: rect,
          card: card,
          driftX: -0.8));
    }
    await Future<void>.delayed(const Duration(milliseconds: 220));
    if (!mounted || seq != _seq) return;
    setState(() {
      _flyingHandIndex = null;
      g.discard(me, i);
    });
    _playSfx(Sfx.cardSlide);
    _afterMyMove();
  }

  /// 상대 뒷면 카드를 칩으로 훔쳐본다(나만 확인, 턴 유지).
  Future<void> _tapPeek(int r, int c) async {
    if (g.veilLeft[me]! <= 0 || _peeking) return;
    final slot = g.fields[ai]![r][c];
    if (slot == null || slot.faceUp || slot.peeked || slot.shield) return;
    _peeking = true;
    try {
      await _peekWithChip(by: me, row: r, col: c);
    } finally {
      _peeking = false;
    }
    if (mounted) {
      _say(_lines?.peeked);
      setState(() {}); // 훔쳐본 카드가 내 눈에 보인다
    }
  }

  /// 열어보기 연출 — 홉 → 슛 → 팅. 규칙 적용(`g.peek`)은 팅에서만.
  Future<void> _peekWithChip({
    required PlayerId by,
    required int row,
    required int col,
  }) async {
    final seq = _seq;
    final target = by == me ? ai : me;
    final slot = g.fields[target]![row][col];
    if (slot == null) return;
    final ring = by == me ? AppColors.mePrimary : AppColors.oppPrimary;
    final filled = g.veilLeft[by]!;
    final chipKey = _chipKeys[(by, filled - 1)];
    final cellKey = _cellKey(target, row, col);

    _haptic(Haptic.select);
    await (chipKey?.currentState?.bounce() ??
        Future<void>.delayed(const Duration(milliseconds: 190)));
    if (!mounted || seq != _seq) return;
    setState(() => _chipInFlight = (by, filled - 1));

    const flight = Duration(milliseconds: 300);
    const contactLead = Duration(milliseconds: sfxLeadMs);
    final from = _rectFor(chipKey), to = _rectFor(cellKey);
    if (from != null && to != null) {
      _playSfx(Sfx.chipShot);
      unawaited(Future<void>.delayed(flight - contactLead).then((_) {
        if (!mounted || seq != _seq) return;
        _playSfx(Sfx.chipTing);
        _haptic(Haptic.shieldLock);
      }));
      await tossChip(
        overlay: Overlay.of(context),
        vsync: this,
        from: from.center,
        to: to.center,
        diameter: to.width * 0.5,
        ring: ring,
        duration: flight,
      );
    } else {
      _playSfx(Sfx.chipTing);
      _haptic(Haptic.shieldLock);
    }
    if (!mounted || seq != _seq) return;

    setState(() {
      g.peek(by, row, col);
      _chipInFlight = null;
    });
    if (from != null && to != null) {
      final overlay = Overlay.of(context);
      final travel = to.center - from.center;
      final dirUnit = travel / travel.distance;
      unawaited(hitFlash(overlay: overlay, vsync: this, at: to.deflate(to.width * 0.15)));
      unawaited(sparkBurst(
          overlay: overlay, vsync: this, at: to.deflate(to.width * 0.3), count: 10));
      unawaited(flipCardInPlace(
        overlay: overlay,
        vsync: this,
        rect: to,
        card: slot.card,
        dir: by == me ? 1 : -1,
        kick: dirUnit * (to.width * 0.1),
      ));
      unawaited(ricochetChip3D(
        overlay: overlay,
        vsync: this,
        at: to.center,
        from: from.center,
        diameter: to.width * 0.5,
        ring: ring,
        side: 0.32,
      ));
      unawaited(ricochetChip3D(
        overlay: overlay,
        vsync: this,
        at: to.center,
        from: from.center,
        diameter: to.width * 0.5,
        ring: target == me ? AppColors.mePrimary : AppColors.oppPrimary,
        side: -0.55,
        reach: 1.3,
        delay: const Duration(milliseconds: 25),
      ));
    }
  }

  /// 칸 위에 앉은 칩의 주인 색 — "여기에 칩이 쓰였다".
  /// 내 뒷면 = 내 칩, 상대 뒷면 = 상대 칩, 훔쳐본 카드 = 훔쳐본 쪽 칩.
  Color? _chipOn(PlayerId owner, int row, int col) {
    final s = g.fields[owner]![row][col];
    if (s == null || s.shield) return null;
    if (s.faceUp) return null;
    if (s.peeked) {
      return owner == me ? AppColors.oppPrimary : AppColors.mePrimary;
    }
    return owner == me ? AppColors.mePrimary : AppColors.oppPrimary;
  }

  // ---- build (기존 게임 화면과 같은 뼈대) ----

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final size = MediaQuery.sizeOf(context);
    final landscape = size.width > size.height;
    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) _refundBoostIfUnused();
      },
      child: Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(gradient: AppColors.bgGradient),
        child: SafeArea(
          child: Stack(
            children: [
              landscape ? _landscapeLayout(l10n, size.height) : _portraitLayout(l10n),
              if (widget.fxLab)
                Positioned(right: 8, top: landscape ? 60 : 96, child: _fxLabPanel()),
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
              if (_oppSpeech != null)
                Positioned(
                  key: const ValueKey('speech-opp'),
                  left: 14,
                  top: landscape ? 92 : 60,
                  child: _SpeechBubble(key: ValueKey('sp-$_oppSpeech'), text: _oppSpeech!),
                )
              else if (_oppEmote != null)
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
      final r = compareLine(g.knownRow(me, me, i), g.knownRow(me, ai, i));
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
          _oppAvatar(),
          const SizedBox(width: 8),
          Flexible(
            child: Text(widget.persona?.name ?? l10n.player2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: AppColors.textMuted, fontWeight: FontWeight.w700, fontSize: 13)),
          ),
          if (widget.persona != null) ...[
            const SizedBox(width: 6),
            LevelStars(level: widget.level, size: 13, gap: 0, animate: !_frozen),
          ],
          const SizedBox(width: 10),
          _WinsPill(count: wins.opp, color: AppColors.oppPrimary),
          const Spacer(),
          Tooltip(
            message: l10n.oppHandTip(g.hands[ai]!.length),
            triggerMode: TooltipTriggerMode.tap,
            child: FaceDownHand(
                key: _oppHandKey,
                count: _phase == _Phase.dealing ? _dealtOpp : g.hands[ai]!.length),
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            color: AppColors.inkSoft,
            tooltip: l10n.newGame,
            onPressed: _restart,
          ),
        ],
      ),
    );
  }

  Widget _oppAvatar() {
    final p = widget.persona;
    return TurnAvatar(
      color: p?.color ?? AppColors.oppPrimary,
      active: _phase == _Phase.playing && !g.isFinished && g.turn == ai,
      background: p?.badgeBg,
      child: p == null
          ? null
          : PersonaIcon(asset: p.asset, size: 20, colorOverrides: p.colorOverrides),
    );
  }

  Widget _lsTopRow(AppLocalizations l10n) {
    final wins = _publicWins();
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 6, 8, 0),
      child: Row(
        children: [
          _oppAvatar(),
          const SizedBox(width: 8),
          _WinsPill(count: wins.opp, color: AppColors.oppPrimary),
          const SizedBox(width: 10),
          _coinsRow(g.veilLeft[ai]!, ring: AppColors.oppPrimary),
          Expanded(
            child: Center(
              child: FaceDownHand(
                  key: _oppHandKey,
                  count: _phase == _Phase.dealing ? _dealtOpp : g.hands[ai]!.length),
            ),
          ),
          _coinsRow(g.veilLeft[me]!, ring: AppColors.mePrimary),
          const SizedBox(width: 8),
          _hideToggle(compact: true),
          const SizedBox(width: 6),
          _deckCounter(),
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            color: AppColors.inkSoft,
            tooltip: l10n.newGame,
            onPressed: _restart,
          ),
        ],
      ),
    );
  }

  Widget _coinsRow(int filled, {required Color ring}) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < g.veilsMax(ring == AppColors.mePrimary ? me : ai); i++)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 1.5),
              child: _chip(i, filled, ring, size: 26),
            ),
        ],
      );

  Widget _chip(int i, int filled, Color ring, {required double size}) {
    final l10n = AppLocalizations.of(context);
    final mine = ring == AppColors.mePrimary;
    return VeilChip(
      key: _chipKey(mine ? me : ai, i),
      size: size,
      filled: i < filled && _chipInFlight != (mine ? me : ai, i),
      ring: ring,
      label: mine ? l10n.veilChipsMine(filled) : l10n.veilChipsOpp(filled),
      onTap: () => _haptic(Haptic.select),
      animate: !g.isFinished,
    );
  }

  /// 뒷면 배치 토글 — 켜면 다음 배치가 칩 1로 숨겨진다.
  Widget _hideToggle({bool compact = false}) {
    final canHide = _myActionTurn && g.veilLeft[me]! > 0;
    final size = compact ? 30.0 : 38.0;
    return Tooltip(
      message: _K.hideOn,
      child: GestureDetector(
        onTap: canHide
            ? () {
                _haptic(Haptic.select);
                setState(() => _hideNext = !_hideNext);
                if (_hideNext) _playSfx(Sfx.chipTick);
              }
            : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: _hideNext ? AppColors.gold : AppColors.surface,
            shape: BoxShape.circle,
            border: Border.all(
                color: _hideNext
                    ? AppColors.goldSoft
                    : canHide
                        ? AppColors.gold
                        : AppColors.stroke,
                width: _hideNext ? 2.2 : 1.4),
            boxShadow: _hideNext
                ? [BoxShadow(color: AppColors.gold.withValues(alpha: 0.5), blurRadius: 8)]
                : null,
          ),
          child: Icon(Icons.visibility_off_rounded,
              size: size * 0.55,
              color: _hideNext
                  ? AppColors.ink
                  : canHide
                      ? AppColors.goldSoft
                      : AppColors.textMuted),
        ),
      ),
    );
  }

  Widget _deckCounter() {
    final l10n = AppLocalizations.of(context);
    return Tooltip(
      message: l10n.deckRemainingTip(g.deckRemaining),
      triggerMode: TooltipTriggerMode.tap,
      child: Padding(
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
    ),
    );
  }

  /// 내 턴 제한 시간 바.
  Widget _timerBar() {
    final active = _myActionTurn || _myShieldTurn;
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 2, 18, 2),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(99),
        child: ValueListenableBuilder<double>(
          valueListenable: _time,
          builder: (context, left, _) {
            final urgent = active && left <= 5;
            return LinearProgressIndicator(
              value: active ? (left / turnSeconds).clamp(0.0, 1.0) : 1,
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

  /// 우측 열: 턴 표시 + 상대/내 칩 + 뒷면 토글 — 판 위의 상황판.
  Widget _sideColumn() {
    final myTurn = g.turn == me && !g.isFinished;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: myTurn ? AppColors.gold : AppColors.stroke,
                width: myTurn ? 1.6 : 1),
          ),
          child: Text(
            myTurn ? _K.turnMine : _K.turnOpp,
            textAlign: TextAlign.center,
            style: TextStyle(
                color: myTurn ? AppColors.gold : AppColors.textMuted,
                fontWeight: FontWeight.w900,
                fontSize: 11),
          ),
        ),
        const SizedBox(height: 14),
        _coinsColumn(g.veilLeft[ai]!, ring: AppColors.oppPrimary),
        const SizedBox(height: 18),
        _coinsColumn(g.veilLeft[me]!, ring: AppColors.mePrimary),
        const SizedBox(height: 14),
        _hideToggle(),
      ],
    );
  }

  Widget _coinsColumn(int filled, {required Color ring}) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < g.veilsMax(ring == AppColors.mePrimary ? me : ai); i++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: _chip(i, filled, ring, size: 30),
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
        chipOn: _chipOn,
        jokerOn: _jokerOn,
        lineCardsOf: (p, line) => g.knownRow(me, p, line),
        cellKeyFor: _cellKey,
        landscape: landscape,
      );

  /// 조커 칸(와일드) — 내 것은 항상, 상대 것은 내 눈에 보일 때만 조커 얼굴.
  JokerMark? _jokerOn(PlayerId owner, int row, int col) {
    final s = g.fields[owner]![row][col];
    if (s == null || !s.wild) return null;
    if (owner == me || g.visibleTo(me, owner, s)) return JokerMark(s.card);
    return null;
  }

  CellLook _lookOf(PlayerId owner, int row, int col) {
    final s = g.fields[owner]![row][col];
    if (s == null || s.faceUp) return CellLook.face;
    if (owner != me) {
      // 훔쳐본 카드는 내 눈에 앞면(칩 마커가 흔적).
      if (s.peeked) return CellLook.face;
      final peekable = _myActionTurn && g.veilLeft[me]! > 0;
      return peekable ? CellLook.backPeekable : CellLook.backVeiled;
    }
    // 내 뒷면 카드 = 봉인(모서리 들려 나만 확인).
    return CellLook.sealed;
  }

  bool _isHighlighted(PlayerId owner, int row, int col) {
    if (_phase != _Phase.playing) return false;
    // 방어막 배치: 양쪽 필드의 다음 칸 전부.
    if (_myShieldTurn) {
      return g.fields[owner]![row][col] == null && col == g.nextCol(owner, row);
    }
    if (!_myActionTurn || selected == null) return false;
    if (owner == me) {
      return g.fields[owner]![row][col] == null && col == g.nextCol(me, row);
    }
    // 공격 표적: 선택 카드와 랭크가 같은, 보이는 비-방어막 상대 카드.
    if (_selectedIsJoker) return false;
    final s = g.fields[ai]![row][col];
    return s != null &&
        !s.shield &&
        g.visibleTo(me, ai, s) &&
        s.card.rank == g.hands[me]![selected!].rank;
  }

  // ---- 하단: 내 아바타 + 손패 ----

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
                      active: _phase == _Phase.playing &&
                          !g.isFinished &&
                          g.turn == me),
                  const SizedBox(height: 5),
                  _WinsPill(count: wins.mine, color: AppColors.mePrimary),
                  if (g.isBoosted(me)) ...[
                    const SizedBox(height: 6),
                    _swapButton(l10n),
                  ],
                ],
              ),
              Expanded(child: _handBar(height: 104)),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  EmoteButton(
                    tooltip: l10n.emotesTitle,
                    open: _emoteOpen,
                    onTap: () => setState(() => _emoteOpen = !_emoteOpen),
                  ),
                  if (_myActionTurn && g.openRows(me).isEmpty) ...[
                    const SizedBox(height: 4),
                    TextButton(
                      onPressed: () => unawaited(_discardSelected()),
                      style: TextButton.styleFrom(
                          visualDensity: VisualDensity.compact),
                      child: const Text('버리기',
                          style: TextStyle(
                              color: AppColors.lose,
                              fontWeight: FontWeight.w800,
                              fontSize: 12)),
                    ),
                  ],
                ],
              ),
            ],
          ),
          _hint(),
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
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TurnAvatar(
                    color: AppColors.mePrimary,
                    active: _phase == _Phase.playing &&
                        !g.isFinished &&
                        g.turn == me),
                const SizedBox(height: 6),
                _WinsPill(count: wins.mine, color: AppColors.mePrimary),
                if (g.isBoosted(me)) ...[
                  const SizedBox(height: 6),
                  _swapButton(l10n),
                ],
              ],
            ),
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
    final dealing = _phase == _Phase.dealing || _swapping || _drawAnimating;
    final dim = !dealing && !(_myActionTurn || _myShieldTurn);
    return SizedBox(
      height: height,
      child: hand.isEmpty
          ? const SizedBox.shrink()
          : Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var i = 0; i < hand.length; i++)
                      Opacity(
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

  static const _hintStyle =
      TextStyle(color: AppColors.textMuted, fontSize: 11.5, fontWeight: FontWeight.w600);

  Widget _hint() {
    final String text;
    switch (_phase) {
      case _Phase.dealing:
      case _Phase.finished:
        text = '';
      case _Phase.playing:
        if (_myShieldTurn) {
          text = _K.shieldPlace;
        } else if (!_myActionTurn) {
          text = _K.oppTurn;
        } else if (_selectedIsJoker) {
          text = _K.myTurnJoker;
        } else if (g.openRows(me).isEmpty) {
          text = _K.discardTip;
        } else if (selected != null) {
          text = _K.myTurnPlace;
        } else {
          text = _K.myTurnPick;
        }
    }
    if (text.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: LayoutBuilder(builder: (context, c) {
        final painter = TextPainter(
          text: TextSpan(text: text, style: _hintStyle),
          textDirection: TextDirection.ltr,
          maxLines: 1,
        )..layout(maxWidth: double.infinity);
        final shown =
            painter.width > c.maxWidth ? text.replaceFirst(' · ', '\n') : text;
        painter.dispose();
        return Text(shown,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: _hintStyle);
      }),
    );
  }

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
    final personaLines = switch (res.outcome) {
      MatchOutcome.win => _lines?.loseGame,
      MatchOutcome.lose => _lines?.winGame,
      MatchOutcome.draw => _lines?.drawGame,
    };
    final personaLine = (personaLines == null || personaLines.isEmpty)
        ? null
        : personaLines[(res.myTotal + res.opponentTotal) % personaLines.length];
    final title = switch (res.outcome) {
      MatchOutcome.win => l10n.matchWin,
      MatchOutcome.lose => l10n.matchLose,
      MatchOutcome.draw => l10n.matchDraw,
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
                if (personaLine != null) ...[
                  const SizedBox(height: 14),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: widget.persona!.badgeBg,
                          shape: BoxShape.circle,
                          border: Border.all(color: widget.persona!.color, width: 1.6),
                        ),
                        padding: const EdgeInsets.all(4),
                        child: PersonaIcon(
                          asset: widget.persona!.asset,
                          size: 36,
                          colorOverrides: widget.persona!.colorOverrides,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Flexible(
                        child: Text('“$personaLine”',
                            style: const TextStyle(
                                color: AppColors.textMain,
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                                height: 1.35)),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 18),
                Wrap(
                  spacing: 10,
                  runSpacing: 8,
                  alignment: WrapAlignment.center,
                  children: [
                    FilledButton(onPressed: _restart, child: Text(l10n.playAgain)),
                    OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: Text(l10n.exitGame),
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

/// 상대 캐릭터 대사 말풍선 — 아바타 옆에 스케일 팝으로 등장한다.
class _SpeechBubble extends StatelessWidget {
  const _SpeechBubble({super.key, required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOutBack,
        builder: (context, t, child) => Opacity(
            opacity: t.clamp(0.0, 1.0),
            child: Transform.scale(scale: 0.7 + 0.3 * t, child: child)),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 260),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.cardBody,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(6),
              topRight: Radius.circular(16),
              bottomRight: Radius.circular(16),
              bottomLeft: Radius.circular(16),
            ),
            border: Border.all(color: AppColors.goldDeep, width: 1.2),
            boxShadow: AppShapes.panelShadow,
          ),
          child: Text(text,
              style: const TextStyle(
                  color: AppColors.ink,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  height: 1.35)),
        ),
      ),
    );
  }
}

/// 줄 승수 알약 — 공개 정보 기준.
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
