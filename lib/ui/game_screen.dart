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
import 'widgets/card_face.dart';
import 'widgets/card_cell.dart';
import 'widgets/emote_bubble.dart';
import 'widgets/chip_3d.dart';
import 'widgets/flying_card.dart';
import 'widgets/impact_effects.dart';
import 'widgets/joker_card.dart' show JokerColors, JokerFace;
import 'widgets/joker_picker.dart';
import 'widgets/table_decor.dart';
import 'widgets/veil_chip.dart';

/// 게임 화면 — 상대 스트립 / 펠트 테이블(덱|보드|우측 열) / 내 스트립+손패.
/// 룰은 `domain/game.dart` 참고.
///
/// 흐름: 딜링 연출 → 타이머(60초) 안에 3장 배치 + 숨김 지정/변경 + 상대 숨김 열어보기
/// → 타이머 종료 시 **동시 공개**(둘 다 일찍 끝내면 타이머가 5초로 줄어 마지막 수정 창만
/// 남는다) → 다음 라운드 자동 진행 → 5라운드 후 최후 공개·정산.
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

  /// 부스트 판(상점): 내 비공개권 칩 +1, 손패 스왑 1회. 판당 1개 — 도메인이 강제한다.
  final bool boosted;

  /// 대전 상대 캐릭터. null이면 이름/색만 기본값이고 대사가 없다(테스트·스크린샷용).
  final Persona? persona;

  /// 테스트·스크린샷 전용 **정지 화면**. 주입하면 딜링 연출·타이머·AI가 돌지 않고
  /// 그 상태 그대로 그려진다(연출 타이머가 없어야 캡처가 재현된다). 기록도 남기지 않는다.
  final ScoreGame? initialGame;

  /// 연출 실험실(디버그) — [initialGame] 위에 강타·칩 연출을 버튼으로 쏘는 패널을 띄운다.
  /// `fxLabState()`와 함께 쓴다(`fx_lab.dart`).
  final bool fxLab;

  @override
  State<GameScreen> createState() => _GameScreenState();
}

enum _Phase { dealing, placing, revealing, finished }

class _GameScreenState extends State<GameScreen> with TickerProviderStateMixin {
  static const me = PlayerId.p0;
  static const ai = PlayerId.p1;
  static const roundSeconds = 60.0;

  /// 둘 다 배치를 끝냈을 때 남겨줄 최종 수정 시간.
  static const lastCallSeconds = 5.0;

  late ScoreGame g;

  /// 상대 AI. 페르소나의 기풍(크로드/헷/제나)이 곧 행동 계수다.
  late final VeiledAi _ai = VeiledAi(widget.persona?.style ?? AiStyle.clode,
      level: widget.level, seed: widget.seed);

  /// 타임업 때 **내 남은 배치**를 대신 채워 주는 손. 성격이 없어야 하므로 기본형.
  late final VeiledAi _autoPlay = VeiledAi(AiStyle.clode, seed: widget.seed);

  _Phase _phase = _Phase.dealing;
  int? selected;
  int? _flyingHandIndex;
  final Set<(int, int)> _hideMarks = {};

  /// 비공개권으로 열어본 칸 → 연 사람. 카드는 앞면이 됐지만 칩은 그 위에 남는다.

  /// 열어보기 연출 중(칩 비행) — 중복 탭 방지.
  bool _peeking = false;

  /// 스왑 연출 중(손패가 덱으로 돌아갔다 새로 온다) — 그동안 손패 탭 금지.
  bool _swapping = false;

  final Map<(PlayerId, int), GlobalKey<VeilChipState>> _chipKeys = {};

  /// 지금 날아가는 중인 레일 칩(주인, 인덱스). 레일에서는 빈 소켓으로 그린다 —
  /// 칩이 손을 떠났는데 바닥에 그대로 남아 있으면 "복사본이 날아갔다"로 보인다.
  (PlayerId, int)? _chipInFlight;
  GlobalKey<VeilChipState> _chipKey(PlayerId p, int i) =>
      _chipKeys.putIfAbsent((p, i), () => GlobalKey<VeilChipState>(debugLabel: 'chip-$p-$i'));
  MatchResult? _result;
  String? _banner; // 공개/최후 공개 배너 문구
  int _dealtMine = 0; // 딜링 연출 중 보이는 내 손패 장수
  int _dealtOpp = 0;
  int _seq = 0;

  /// 상대 캐릭터 대사(말풍선). 이모트와 같은 자리를 쓰므로 대사가 우선한다.
  String? _oppSpeech;
  int _speechSeq = 0;

  /// 결과를 랭킹 기록에 저장했는가(판당 1회).
  bool _recorded = false;

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

  /// 손패 칸 키. 칸 키와 마찬가지로 디버그 라벨을 붙여 테스트가 집어낼 수 있게 한다.
  GlobalKey _handKey(int i) {
    while (_handKeys.length <= i) {
      _handKeys.add(GlobalKey(debugLabel: 'hand-${_handKeys.length}'));
    }
    return _handKeys[i];
  }

  /// 칸 키. 디버그 라벨을 붙여 두면 위젯 테스트가 특정 칸을 찾아 탭할 수 있다.
  GlobalKey _cellKey(PlayerId p, int r, int c) => _cellKeys.putIfAbsent(
      '${p.name}-$r-$c', () => GlobalKey(debugLabel: 'cell-${p.name}-$r-$c'));

  @override
  void initState() {
    super.initState();
    g = widget.initialGame ??
        ScoreGame.deal(seed: widget.seed, boostFor: _boosted ? me : null);
    if (_frozen) {
      // 주입된 상태를 그대로 보여준다 — 진행은 하지 않는다.
      _dealtMine = g.hands[me]!.length;
      _dealtOpp = g.hands[ai]!.length;
      if (g.isFinished) {
        _phase = _Phase.finished;
        _result = g.judge();
      } else {
        _phase = _Phase.placing;
        // 캐릭터가 있는 판이면 인사만은 한다(스크린샷에서 말풍선이 보여야 한다).
        // **첫 줄로 고정** — 무작위로 고르면 캡처가 실행마다 달라져 골든이 흔들린다.
        final hello = _lines?.greeting;
        if (hello != null && hello.isNotEmpty) {
          WidgetsBinding.instance
              .addPostFrameCallback((_) => _say([hello.first]));
        }
      }
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _startRound(dealt: 0));
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

  /// **이 판**이 부스트 판인가. 첫 판은 매칭 화면이 토큰을 쓰고 넘겨주지만,
  /// "다시 하기"는 여기서 다시 하나 쓴다 — 토큰 하나로 무한히 부스트 판을 돌리면 안 된다.
  late bool _boosted = widget.boosted;

  /// 부스트 토큰을 썼는데 아직 아무 행동도 안 했는가(이탈하면 돌려준다).
  bool get _boostUnused =>
      _boosted &&
      g.round == 0 &&
      g.leftToPlace(me) == ScoreGame.perRound &&
      g.swapLeft[me] == 1 &&
      _hideMarks.isEmpty;

  /// 화면을 떠날 때 — 부스트를 쓰고 한 수도 안 뒀으면 토큰을 돌려준다.
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
      // 새 판도 부스트로 — 토큰이 있으면 하나 더 쓰고, 없으면 보통 판.
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
      _hideMarks.clear();
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
    WidgetsBinding.instance.addPostFrameCallback((_) => _startRound(dealt: 0));
  }

  /// 상대 캐릭터가 상황 대사를 말한다(약 3초 뒤 사라짐). 페르소나가 없으면 조용하다.
  void _say(List<String>? lines) {
    if (lines == null || lines.isEmpty || !mounted) return;
    setState(() {
      _oppSpeech = lines[_rng.nextInt(lines.length)];
      _oppEmote = null; // 대사와 이모트가 같은 자리를 쓴다 — 대사가 우선
    });
    final seq = ++_speechSeq;
    Future<void>.delayed(const Duration(milliseconds: 3200), () {
      if (mounted && seq == _speechSeq) setState(() => _oppSpeech = null);
    });
  }

  PersonaLines? get _lines => widget.persona?.lines;

  /// 끝난 판을 로컬 기록(랭킹)에 한 번 저장한다. 저장 실패는 게임에 영향을 주지 않는다.
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
      {bool faceDown = false, bool joker = false, int ms = 300}) async {
    final f = _rectFor(from), t = _rectFor(to);
    if (f == null || t == null || !mounted) return;
    await flyCard(
      overlay: Overlay.of(context),
      vsync: this,
      from: f,
      to: t,
      card: card,
      faceDown: faceDown,
      joker: joker,
      duration: Duration(milliseconds: ms),
      curve: joker ? Curves.easeInCubic : Curves.easeInOutCubic,
      trail: joker,
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
    if (g.round == 0) _say(_lines?.greeting);
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
  Future<void> _dealAnimation(int seq, {bool oppToo = true}) async {
    final total = g.hands[me]!.length;
    if (_dealtMine >= total) return;
    // 상대/나 번갈아 한 장씩. 손패 슬롯은 투명하게 이미 자리를 잡고 있어서
    // 비행이 실제 슬롯 위치에 정확히 안착한다.
    //
    // **소리는 비행이 끝나는 프레임에 낸다**(flyCard의 Future가 안착 프레임에
    // 완료된다). 카드가 손에 닿는 순간과 "착"이 어긋나면 딜링 전체가 싸구려로 들린다.
    for (var i = _dealtMine; i < total; i++) {
      if (oppToo && i < g.hands[ai]!.length) {
        unawaited(
            _fly(_deckKey, _oppHandKey, g.hands[ai]![i], faceDown: true, ms: 240)
                .then((_) {
          if (!mounted || seq != _seq) return;
          // 상대에게 가는 카드는 **무음**. 내 카드와 100ms 차로 붙어 있어서
          // 소리를 같이 내면 두 발이 겹쳐 뭉개진다 — 딜링의 박자는 내 손이 잡는다.
          setState(() => _dealtOpp = i + 1);
        }));
        await Future<void>.delayed(const Duration(milliseconds: 100));
        if (!mounted || seq != _seq) return;
      }
      unawaited(_fly(_deckKey, _handKey(i), g.hands[me]![i], ms: 240).then((_) {
        if (!mounted || seq != _seq) return;
        setState(() => _dealtMine = i + 1);
        // 내 카드만 운다. 손끝의 톡까지 같이, 안착 프레임에 정확히.
        _playSfx(Sfx.cardPlace);
        _haptic(Haptic.select);
      }));
      await Future<void>.delayed(const Duration(milliseconds: 100));
      if (!mounted || seq != _seq) return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 300));
    if (mounted && seq == _seq) {
      setState(() {
        _dealtMine = total;
        if (oppToo) _dealtOpp = total;
      });
    }
  }

  /// **손패 스왑**(부스트): 이번 라운드에 받은 카드가 덱으로 돌아가고 새 카드가 온다.
  /// 받은 카드를 한 장이라도 놓았으면 못 쓴다(도메인 `canSwap`). 타이머는 계속 간다.
  Future<void> _swapHand() async {
    if (_phase != _Phase.placing || _swapping || !g.canSwap(me)) return;
    final seq = _seq;
    final n = g.drawnThisRound(me).length;
    final hand = g.hands[me]!;
    setState(() {
      _swapping = true;
      selected = null;
    });
    _haptic(Haptic.select);
    // 받은 카드(손패 끝 n장)가 덱으로 날아 돌아간다.
    for (var i = hand.length - n; i < hand.length; i++) {
      unawaited(_fly(_handKey(i), _deckKey, hand[i], faceDown: true, ms: 220));
      _playSfx(Sfx.cardSlide);
      await Future<void>.delayed(const Duration(milliseconds: 70));
      if (!mounted || seq != _seq) return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 200));
    if (!mounted || seq != _seq) return;
    setState(() {
      g.swap(me);
      _dealtMine = g.hands[me]!.length - n;
    });
    await _dealAnimation(seq, oppToo: false);
    if (!mounted || seq != _seq) return;
    setState(() => _swapping = false);
  }

  /// 스왑 버튼 — 부스트 판에서, 아직 받은 카드를 놓기 전까지만 보인다.
  Widget _swapButton(AppLocalizations l10n) {
    final visible = g.isBoosted(me) && g.canSwap(me) && _phase == _Phase.placing && !_swapping;
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

  /// AI는 라운드 시작에 3장을 계획하고 타이머 중간중간 실제로 놓는다 —
  /// 내 눈에는 뒷면 카드가 실시간으로 깔린다(위치가 곧 정보 = 순서 심리전).
  void _scheduleAi(int seq) {
    // 조커가 있으면 먼저 결정한다 — 손패에서 조커가 빠진 뒤에 3장 계획을 세워야
    // 인덱스가 밀리지 않는다.
    final jm = _ai.jokerMove(g, ai);
    if (jm == null) {
      _scheduleAiPlacements(seq, 2000 + _rng.nextInt(3000));
      return;
    }
    Future<void>.delayed(Duration(milliseconds: 1500 + _rng.nextInt(1500)), () async {
      if (!mounted || seq != _seq || _phase != _Phase.placing) return;
      final hand = g.hands[ai]!;
      if (jm.handIndex < hand.length && hand[jm.handIndex].isJoker) {
        if (jm.strike && g.fields[me]![jm.row][jm.col] != null) {
          await _fly(_oppHandKey, _cellKey(me, jm.row, jm.col), jm.card, faceDown: true, joker: true);
          if (!mounted || seq != _seq || _phase != _Phase.placing) return;
          setState(() => g.declareStrike(ai, jm.handIndex, jm.row, jm.col, jm.card));
          _playSfx(Sfx.token);
          _haptic(Haptic.impact);
        } else if (!jm.strike &&
            g.leftToPlace(ai) > 0 &&
            g.fields[ai]![jm.row][jm.col] == null) {
          await _fly(_oppHandKey, _cellKey(ai, jm.row, jm.col), jm.card, faceDown: true);
          if (!mounted || seq != _seq || _phase != _Phase.placing) return;
          setState(() => g.placeWild(ai, jm.handIndex, jm.row, jm.col, jm.card));
          _playSfx(Sfx.cardPlace);
          _afterPlacement(seq);
        }
      }
      if (!mounted || seq != _seq || _phase != _Phase.placing) return;
      _scheduleAiPlacements(seq, 1200 + _rng.nextInt(2000));
    });
  }

  void _scheduleAiPlacements(int seq, int firstDelayMs) {
    final plan = _ai.plan(g, ai)
      ..sort((a, b) => b.handIndex.compareTo(a.handIndex)); // 인덱스 안전 순서
    var delayMs = firstDelayMs;
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
      final target = _ai.peek(g, ai);
      if (target == null || _peeking) return;
      unawaited(() async {
        _peeking = true;
        try {
          await _peekWithChip(by: ai, row: target.$1, col: target.$2);
        } finally {
          _peeking = false;
        }
        if (!mounted || seq != _seq) return;
        _snack(AppLocalizations.of(context).vlOppPeeked);
        _say(_lines?.peek);
      }());
    });
  }

  /// 타임업: 남은 배치를 자동으로 채우고 동시 공개.
  void _onTimeUp(int seq) {
    _ticker?.cancel();
    if (!mounted || seq != _seq || _phase != _Phase.placing) return;
    var autoMine = false;
    for (final p in [me, ai]) {
      while (g.leftToPlace(p) > 0) {
        final plan = (p == me ? _autoPlay : _ai).plan(g, p)
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
    final aiHides = _ai.hides(g, ai);
    g.reveal({me: Set.of(_hideMarks), ai: aiHides}, deferStrikes: true);
    // 동시 공개 — 이 룰의 하이라이트. "두-둥" 스팅과 함께 전 카드가 뒤집힌다.
    setState(() => _banner = l10n.vlRevealBanner);
    _playSfx(Sfx.sting);
    _haptic(Haptic.place);
    if (aiHides.isNotEmpty) {
      _snack(l10n.vlOppHid(aiHides.length));
      _say(_lines?.hide);
    }
    await Future<void>.delayed(const Duration(milliseconds: 900));
    if (!mounted || seq != _seq) return;
    setState(() => _banner = null);

    // 조커 강타 — 기본 3장이 뒤집힌 **다음**에 떨어진다.
    await _strikeCeremony(seq);
    if (!mounted || seq != _seq) return;

    // 판정 세리머니: 1줄부터 차례로 WIN / LOSE.
    await _laneVerdictCeremony(seq);
    if (!mounted || seq != _seq) return;

    if (g.isFinished) {
      await _finish(seq);
      return;
    }
    // 공개된 정보만 보고 도발하거나 이를 간다 — 숨긴 카드는 대사로도 새지 않는다.
    if (_lines != null) {
      final wins = _publicWins();
      if (wins.opp >= 2) {
        _say(_lines!.lead);
      } else if (wins.mine >= 2) {
        _say(_lines!.behind);
      }
    }
    final dealt = g.hands[me]!.length; // 보충 전 장수 — 새 카드만 딜링 연출
    setState(() => g.nextRound());
    await _startRound(dealt: dealt);
  }

  // ---- 연출 실험실 (디버그) ----

  bool _labBusy = false;

  /// 판을 고정 상태로 되돌린다 — 매 버튼은 같은 출발점에서 연출을 쏜다.
  void _labReset() {
    _seq++;
    setState(() {
      g = fxLabState();
      _chipInFlight = null;
      _hideMarks.clear();
      _banner = null;
      selected = null;
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
          btn('강타 나→상대', () async {
            g.pendingStrikes[ai]!.clear();
            await _strikeCeremony(_seq);
          }),
          btn('강타 상대→나', () async {
            g.pendingStrikes[me]!.clear();
            await _strikeCeremony(_seq);
          }),
          btn('강타 둘 다', () => _strikeCeremony(_seq)),
          btn('칩 나→상대', () => _peekWithChip(by: me, row: 1, col: 1)),
          btn('칩 상대→나', () => _peekWithChip(by: ai, row: 1, col: 1)),
          btn('리셋', () async {}),
        ],
      ),
    );
  }

  /// 조커 강타 연출 — 두둥(배너) → 표적 위 번쩍·파편 → 카드가 지정 카드로 바뀐다.
  /// 예고된 강타가 없으면 조용히 정산만 한다. 규칙 적용(`resolveStrike`)은 한 방씩.
  Future<void> _strikeCeremony(int seq) async {
    final strikes = [for (final p in PlayerId.values) ...g.pendingStrikes[p]!];
    if (strikes.isEmpty) {
      g.resolveStrikes();
      return;
    }
    final l10n = AppLocalizations.of(context);
    setState(() => _banner = l10n.jokerStrikeBanner);
    _playSfx(Sfx.sting);
    _haptic(Haptic.impact);
    await Future<void>.delayed(const Duration(milliseconds: 750));
    if (!mounted || seq != _seq) return;
    setState(() => _banner = null);
    var struckMine = false;
    for (final s in strikes) {
      await Future<void>.delayed(const Duration(milliseconds: 260));
      if (!mounted || seq != _seq) return;
      // 화면 가운데 조커가 크게 떠서 붕붕 뛰고, 코너에 "무엇이 되는지"(숫자·무늬)가 보인다.
      await _strikeShowcase(s);
      if (!mounted || seq != _seq) return;
      final rect = _rectFor(_cellKey(s.by.other, s.row, s.col));
      if (rect != null) {
        final overlay = Overlay.of(context);
        unawaited(hitFlash(overlay: overlay, vsync: this, at: rect, color: JokerColors.gold));
        unawaited(sparkBurst(overlay: overlay, vsync: this, at: rect, color: JokerColors.gold));
      }
      _playSfx(Sfx.attackHit);
      _haptic(Haptic.impact);
      setState(() => g.resolveStrike(s.by, s.row, s.col));
      if (s.by == ai) struckMine = true;
      await Future<void>.delayed(const Duration(milliseconds: 520));
    }
    if (!mounted || seq != _seq) return;
    if (struckMine) _snack(l10n.vlOppStruck);
  }

  /// 강타 쇼케이스 — 화면 가운데 큰 조커 카드(로티 재생, 코너 = 지정 카드)가 튀어나와
  /// 잠깐 머물다 사라진다. 등장 오버슛 → 유지 → 표적 쪽으로 작아지며 퇴장(≈1.1s).
  Future<void> _strikeShowcase(JokerStrike s) async {
    final size = MediaQuery.sizeOf(context);
    const w = 150.0;
    final h = CardFace.heightFor(w);
    final target = _rectFor(_cellKey(s.by.other, s.row, s.col));
    final origin = Offset(size.width / 2, size.height * 0.42);
    final dest = target?.center ?? origin;
    final color = s.by == me ? AppColors.mePrimary : AppColors.oppPrimary;
    final done = Completer<void>();
    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (context) => TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: const Duration(milliseconds: 1100),
          onEnd: () {
            entry.remove();
            if (!done.isCompleted) done.complete();
          },
          builder: (context, t, child) {
            // 0~0.18 등장(오버슛) · 0.18~0.78 유지 · 0.78~1 표적으로 빨려 들어감.
            final enter = Curves.easeOutBack.transform((t / 0.18).clamp(0.0, 1.0));
            final exit = t < 0.78 ? 0.0 : Curves.easeInCubic.transform((t - 0.78) / 0.22);
            final c = Offset.lerp(origin, dest, exit)!;
            final scale = enter * (1 - 0.8 * exit);
            return Positioned(
              left: c.dx - w / 2,
              top: c.dy - h / 2,
              width: w,
              height: h,
              child: IgnorePointer(
                child: Opacity(
                  opacity: (enter * (1 - exit * 0.6)).clamp(0.0, 1.0),
                  child: Transform.scale(scale: scale, child: child),
                ),
              ),
            );
          },
          child: Material(
            type: MaterialType.transparency,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(w * 0.16),
                boxShadow: [
                  BoxShadow(color: color.withValues(alpha: 0.55), blurRadius: 28, spreadRadius: 2),
                ],
              ),
              child: JokerFace(size: w, as: s.card),
            ),
          ),
      ),
    );
    Overlay.of(context).insert(entry);
    _playSfx(Sfx.cardSlide);
    _haptic(Haptic.select);
    await done.future;
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
    // 결과 오버레이가 캐릭터 대사를 직접 그리므로 말풍선은 띄우지 않는다.
    unawaited(_recordResult(res));
  }

  // ---- 상호작용 (전부 타이머 안에서) ----

  int _nextCol(PlayerId p, int row) {
    for (var c = 0; c < ScoreGame.colsN; c++) {
      if (g.fields[p]![row][c] == null) return c;
    }
    return -1;
  }

  void _tapHand(int i) {
    if (_phase != _Phase.placing || _swapping) return;
    final hand = g.hands[me]!;
    if (i >= hand.length) return;
    // 조커는 배치를 다 했어도 고를 수 있다 — 강타는 별도 행동이다.
    if (!hand[i].isJoker && g.leftToPlace(me) <= 0) return;
    _haptic(Haptic.select);
    setState(() => selected = selected == i ? null : i);
  }

  bool get _selectedIsJoker =>
      selected != null && selected! < g.hands[me]!.length && g.hands[me]![selected!].isJoker;

  void _onCellTap(PlayerId owner, int row, int col) {
    if (_phase != _Phase.placing) return;
    if (owner == me) {
      final slot = g.fields[me]![row][col];
      if (selected != null && slot == null) {
        if (_selectedIsJoker) {
          _placeWildSelected(row);
        } else {
          _placeSelected(row);
        }
      } else if (slot != null && slot.round == g.round && !slot.faceUp) {
        _toggleHide(row, col); // 타이머가 끝나기 전까지는 자유롭게 변경
      }
    } else {
      // 예고해 둔 강타를 다시 탭하면 물린다(조커가 손으로 돌아온다).
      if (g.pendingStrikes[me]!.any((s) => s.row == row && s.col == col)) {
        _cancelStrike(row, col);
        return;
      }
      if (_selectedIsJoker && g.fields[ai]![row][col] != null) {
        _strikeSelected(row, col);
        return;
      }
      _tapPeek(row, col);
    }
  }

  /// 조커를 내 판에 와일드로 — 카드를 고르고 나서 날아가 뒷면으로 앉는다.
  Future<void> _placeWildSelected(int row) async {
    if (selected == null || g.leftToPlace(me) <= 0) return;
    final col = _nextCol(me, row);
    if (col < 0) return;
    final seq = _seq;
    final i = selected!;
    final card = await showJokerPicker(context, strike: false);
    if (card == null || !mounted || seq != _seq || _phase != _Phase.placing) return;
    if (i >= g.hands[me]!.length || !g.hands[me]![i].isJoker) return;
    if (g.fields[me]![row][col] != null || g.leftToPlace(me) <= 0) return;
    setState(() {
      selected = null;
      _flyingHandIndex = i;
    });
    await _fly(_handKey(i), _cellKey(me, row, col), card);
    if (!mounted || seq != _seq || _phase != _Phase.placing) return;
    setState(() {
      _flyingHandIndex = null;
      g.placeWild(me, i, row, col, card);
    });
    _playSfx(Sfx.cardPlace);
    _haptic(Haptic.place);
    _afterPlacement(seq);
  }

  /// 조커 강타 예고 — 카드를 고르면 조커가 상대 카드 위로 날아가 앉는다(발동은 공개 때).
  Future<void> _strikeSelected(int row, int col) async {
    if (selected == null) return;
    final seq = _seq;
    final i = selected!;
    final card = await showJokerPicker(context, strike: true);
    if (card == null || !mounted || seq != _seq || _phase != _Phase.placing) return;
    if (i >= g.hands[me]!.length || !g.hands[me]![i].isJoker) return;
    if (g.fields[ai]![row][col] == null) return;
    setState(() {
      selected = null;
      _flyingHandIndex = i;
    });
    await _fly(_handKey(i), _cellKey(ai, row, col), card, faceDown: true, joker: true);
    if (!mounted || seq != _seq || _phase != _Phase.placing) return;
    setState(() {
      _flyingHandIndex = null;
      g.declareStrike(me, i, row, col, card);
    });
    _playSfx(Sfx.token);
    _haptic(Haptic.shieldLock);
  }

  void _cancelStrike(int row, int col) {
    if (_phase != _Phase.placing) return;
    setState(() => g.cancelStrike(me, row, col));
    _haptic(Haptic.select);
    _snack(AppLocalizations.of(context).jokerStrikeCancelled);
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
    if (g.veilLeft[me]! <= 0 || _peeking) return;
    final slot = g.fields[ai]![r][c];
    if (slot == null || slot.faceUp || slot.round >= g.round) return;
    _peeking = true;
    try {
      await _peekWithChip(by: me, row: r, col: c);
    } finally {
      _peeking = false;
    }
    if (mounted) _say(_lines?.peeked);
  }

  /// 열어보기 연출 — 세 박자. 유치한 폭발 없이, 소리와 타이밍으로만.
  ///
  /// 1. **홉**: 레일의 마지막 칩이 제자리에서 튀어 오른다(무음 — 소리는 비행·충돌
  ///    두 개만 쓴다. 넷을 다 울리면 잔소리가 된다는 청취 피드백).
  /// 2. **슛**: 3D 칩이 빛 궤적을 남기며 직선으로 쏘아진다(chipShot).
  /// 3. **팅**: 닿는 프레임에 충돌음(chipTing)과 함께 칩이 되튀어 통통 구르다
  ///    사라지고, 카드는 제자리에서 앞면으로 뒤집힌다. 칩은 남지 않는다.
  ///
  /// 규칙 적용(`g.peek`)은 3에서만 일어난다 — 연출 중 판이 바뀌면(seq) 그냥 접는다.
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
    final filled = by == me ? g.veilLeft[me]! - _hideMarks.length : g.veilLeft[ai]!;
    final chipKey = _chipKeys[(by, filled - 1)];
    final cellKey = _cellKey(target, row, col);

    // 1) 홉 — 레일의 마지막 칩이 튀어 오르며 손을 떠난다(소리 없이 햅틱만).
    _haptic(Haptic.select);
    await (chipKey?.currentState?.bounce() ??
        Future<void>.delayed(const Duration(milliseconds: 190)));
    if (!mounted || seq != _seq) return;
    // 홉이 끝난 프레임에 레일의 칩이 떠난다 — 이후 비행체가 그 칩이다.
    setState(() => _chipInFlight = (by, filled - 1));

    // 2) 비행 — 3D 칩이 포물선으로 구르며 날아간다.
    //
    // **충돌음은 비행이 끝나기 45ms 전에 미리 쏜다.** `await` 뒤에 내면 완료
    // 콜백(+1프레임)에 오디오 출력 지연(저지연 모드도 30~60ms)이 더해져 시각
    // 충돌보다 50~90ms 늦게 들리는데, 어택이 전부인 소리라 이 지연은 티가 난다.
    // 비행음(chipShot)도 여기에 맞춰 에너지 정점이 235ms — 팅 어택(255ms) 직전 —
    // 에 오도록 구워 뒀다(`tool/mix_chip_sfx.py` 참고).
    const flight = Duration(milliseconds: 300);
    const contactLead = Duration(milliseconds: 45); // ≈ 오디오 출력 지연
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
      // 좌표를 못 잡아 애니메이션이 없어도 판정 피드백(팅)은 준다.
      _playSfx(Sfx.chipTing);
      _haptic(Haptic.shieldLock);
    }
    if (!mounted || seq != _seq) return;

    // 3) 팅 — 칩이 카드에 부딪혀 되튀어 나가고, 카드는 제자리에서 뒤집힌다.
    //    (소리는 위에서 미리 떠났고, 여기는 닿는 프레임의 시각 연출만.)
    setState(() {
      g.peek(by, row, col);
      _chipInFlight = null; // 규칙상 차감됐으니 레일은 이제 스스로 하나 적다.
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
      // 날아온 칩과 카드 위에 앉아 있던 칩이 **둘 다** 날아온 반대쪽으로 튕겨 나간다 —
      // 하나는 왼쪽으로 비껴, 하나는 오른쪽으로 더 멀리. 같은 각도면 한 장으로 보인다.
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

  /// 칸 위에 앉은 칩의 주인 색. 숨긴(덮인) 카드에만 숨긴 쪽 칩이 앉는다.
  Color? _chipOn(PlayerId owner, int row, int col) {
    final s = g.fields[owner]![row][col];
    if (s == null) return null;
    if (s.faceUp) return null;
    if (owner == me) {
      final veiled = _hideMarks.contains((row, col)) || s.round < g.round || g.revealDone;
      return veiled ? AppColors.mePrimary : null;
    }
    return (s.round < g.round || g.revealDone) ? AppColors.oppPrimary : null;
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
            onPressed: _phase == _Phase.revealing ? null : _restart,
          ),
        ],
      ),
    );
  }

  /// 상대 아바타 — 페르소나가 있으면 선택 화면·결과 컷과 같은 로티 아이콘.
  Widget _oppAvatar() {
    final p = widget.persona;
    return TurnAvatar(
      color: p?.color ?? AppColors.oppPrimary,
      active: _phase == _Phase.placing && !g.isFinished,
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

  /// 비공개권 칩 3개(가로). 쓴 만큼 빈 소켓.
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

  /// 칩 하나. 누르면 뒤집히며(로티 flip) 남은 개수·용법 툴팁이 뜬다.
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

  /// 이번 라운드 남은 배치 3칸 — 미니 카드 핍. 놓을수록 비워진다.
  Widget _placePips({required bool horizontal}) {
    final left = g.leftToPlace(me);
    final pips = [
      for (var i = 0; i < ScoreGame.perRound; i++)
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
            l10n.roundLabel(g.round + 1),
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
        lineCardsOf: (p, line) => g.publicRow(p, line),
        cellKeyFor: _cellKey,
        landscape: landscape,
      );

  /// 조커 칸: 강타 예고(상대가 노리는 내 카드 / 내가 노리는 상대 카드)는 지정 카드를 든
  /// 조커, 와일드·강타로 바뀐 카드는 그 카드를 든 조커. 상대의 와일드는 공개된 뒤에만 보인다.
  JokerMark? _jokerOn(PlayerId owner, int row, int col) {
    final attacker = owner.other;
    for (final st in g.pendingStrikes[attacker]!) {
      if (st.row == row && st.col == col) return JokerMark(st.card, pending: true);
    }
    final s = g.fields[owner]![row][col];
    if (s == null) return null;
    if (s.strikeBy != null) return JokerMark(s.card);
    if (s.wild && (owner == me || s.faceUp)) return JokerMark(s.card);
    return null;
  }

  CellLook _lookOf(PlayerId owner, int row, int col) {
    final s = g.fields[owner]![row][col];
    if (s == null || s.faceUp) return CellLook.face;
    if (owner != me) {
      // 이번 라운드 뒷면은 곧 뒤집힌다 — 그냥 뒷면.
      // 공개를 넘기고도 덮여 있는 카드만 "덮어 둔 카드"다: 검은 일렁거림.
      final veiled = s.round < g.round || g.revealDone;
      if (!veiled) return CellLook.back;
      // 그중 지금 내 코인으로 열 수 있는 카드에는 브라스 마커가 하나 더 붙는다.
      final peekable = _phase == _Phase.placing &&
          g.veilLeft[me]! > 0 &&
          s.round < g.round;
      return peekable ? CellLook.backPeekable : CellLook.backVeiled;
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
                  if (g.isBoosted(me)) ...[
                    const SizedBox(height: 6),
                    _swapButton(l10n),
                  ],
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
          // 낮은 가로 화면(360dp)에서는 아바타+승수가 손패 높이보다 커진다 — 축소해 넣는다.
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TurnAvatar(
                    color: AppColors.mePrimary,
                    active: _phase == _Phase.placing && !g.isFinished),
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
    final dealing = _phase == _Phase.dealing || _swapping;
    final dim = !dealing && (_phase != _Phase.placing || g.leftToPlace(me) <= 0);
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

  static const _hintStyle =
      TextStyle(color: AppColors.textMuted, fontSize: 11.5, fontWeight: FontWeight.w600);

  Widget _hint(AppLocalizations l10n) {
    final String text;
    switch (_phase) {
      case _Phase.dealing:
      case _Phase.revealing:
      case _Phase.finished:
        text = '';
      case _Phase.placing:
        text = _selectedIsJoker
            ? l10n.jokerHandTip
            : (g.leftToPlace(me) > 0 ? l10n.vlPlacePrompt : l10n.vlWaitOpp);
    }
    if (text.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: LayoutBuilder(builder: (context, c) {
        // 좁은 화면(360dp)에서는 단어 한가운데서 꺾이지 않도록 첫 구분점(" · ")에서
        // **의도한 두 줄**로 나눈다: "3장을 놓으세요 / 내 카드 탭 = … · 상대 뒷면 탭 = …".
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
    // 결과 대사는 **상대 입장**이다 — 내가 이겼으면 상대는 진 대사를 한다.
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
                // 좁은 화면·긴 번역에서도 넘치지 않게 줄바꿈을 허용한다.
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
              topLeft: Radius.circular(6), // 꼬리 방향(상대 아바타 쪽)
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
