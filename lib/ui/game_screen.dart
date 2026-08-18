import 'package:flutter/material.dart';

import 'dart:math';

import '../data/records_store.dart';
import '../domain/ai_strategy.dart';
import '../domain/card.dart';
import '../domain/game.dart';
import '../domain/hand.dart';
import '../domain/records.dart';
import '../domain/scoring.dart';
import '../l10n/app_localizations.dart';
import '../monetization/monetization.dart';
import 'hand_text.dart';
import 'move_error_text.dart';
import 'shop_screen.dart';
import 'personas.dart';
import 'theme.dart';
import 'widgets/board_view.dart';
import 'widgets/card_back.dart';
import 'widgets/card_cell.dart';
import 'widgets/card_face.dart';
import 'widgets/flying_card.dart';
import 'widgets/opening_sequence.dart';
import 'widgets/table_decor.dart';

/// 게임 플레이 화면(핫시트 MVP): 선공 정하기 → 보드 플레이.
///
/// 레이아웃(위→아래):
///   [상단바] · [상대 스트립(뒷면 손패)] · [보드(가운데 점수 열)] · [턴 배너] · [내 스트립] · [내 손패] · [액션]
class GameScreen extends StatefulWidget {
  const GameScreen({super.key, this.seed, this.initialState, this.persona});
  final int? seed;

  /// 테스트/스크린샷 전용: 지정 시 첫 화면 상태로 사용(새 게임 버튼은 무시).
  final GameState? initialState;

  /// 대전 상대 캐릭터. null이면 무성격 기본 AI(크로드 기풍)로 둔다.
  final Persona? persona;

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> with TickerProviderStateMixin {
  late GameState state;
  int? selected;

  /// 토큰 사용 대기 모드. 켜져 있으면 다음 탭이 "카드 배치"가 아니라 "토큰 대상 지정"이다.
  /// (쉴드 = 내 필드의 카드를 탭 / 공격 = 내 손패의 카드를 탭)
  TokenKind? _tokenMode;

  // 나는 항상 P0. 화면은 절대 뒤집히지 않는다(내 필드=아래/한쪽 고정).
  static const PlayerId me = PlayerId.p0;
  static const PlayerId ai = PlayerId.p1;

  // 애니메이션 상태
  bool _animating = false;
  int? _flyingHandIndex;
  final Map<String, GlobalKey> _boardKeys = {};

  /// 손패 슬롯별 GlobalKey **풀**. 위치(index)마다 하나씩 재사용한다.
  ///
  /// 이전에는 build()에서 매번 `GlobalKey()`를 새로 만들었는데, 키가 바뀌면
  /// `Widget.canUpdate`가 실패해 손패 카드의 엘리먼트가 **매 프레임 파괴·재생성**됐다.
  /// (성능뿐 아니라 애니메이션 상태도 리셋된다)
  final List<GlobalKey> _handKeys = [];

  GlobalKey _handKey(int i) {
    while (_handKeys.length <= i) {
      _handKeys.add(GlobalKey());
    }
    return _handKeys[i];
  }

  final GlobalKey _oppHandKey = GlobalKey();
  final GlobalKey _deckKey = GlobalKey();
  final GlobalKey _handAreaKey = GlobalKey();
  final GlobalKey _graveKey = GlobalKey();

  /// 버린 카드 무덤(UI 연출용): 오프닝 오픈 카드 + 제거된 카드가 쌓인다.
  final List<PlayingCard> _grave = [];

  // ---- 감정 표현(이모트) ----
  bool _emoteOpen = false; // 피커 펼침 여부
  String? _myEmote; // 내가 보낸 이모트(내 아바타 옆 말풍선)
  String? _oppEmote; // 상대가 보낸 이모트(상대 아바타 옆 말풍선)
  int _emoteSeq = 0; // 늦게 도착한 숨김 타이머 무효화용

  // ---- 페르소나(상대 AI 캐릭터) ----
  late final HeuristicAi _ai =
      HeuristicAi(widget.persona?.style ?? AiStyle.clode, seed: widget.seed ?? 7);
  late final Random _speechRng = Random(widget.seed ?? 7);
  String? _oppSpeech; // 상대 대사 말풍선
  int _speechSeq = 0;

  GlobalKey _boardKey(PlayerId owner, int row, int col) =>
      _boardKeys.putIfAbsent('${owner.name}-$row-$col', () => GlobalKey());

  @override
  void initState() {
    super.initState();
    if (widget.initialState != null) {
      state = widget.initialState!;
      selected = null;
      _flyingHandIndex = null;
      _animating = false;
      if (state.phase == GamePhase.playing && widget.persona != null) {
        // 오프닝 없이 바로 판이 열리는 경우(스크린샷 등)에도 인사는 한다.
        WidgetsBinding.instance
            .addPostFrameCallback((_) => _personaSay(widget.persona!.lines.greeting));
      }
    } else {
      _start();
    }
  }

  void _start() {
    // 토큰 사용 상한은 **규칙**이므로 언제나 건다. 실제로 쓸 수 있는지는 지갑
    // 보유량이 따로 결정한다(도메인은 결제를 모른다). AI(p1)에게는 주지 않는다.
    state = GameState.deal(seed: widget.seed, rules: const {me: GameRules.standard});
    selected = null;
    _tokenMode = null;
    _flyingHandIndex = null;
    _animating = false;
    _recorded = false;
    _grave.clear();
    _emoteOpen = false;
    _myEmote = null;
    _oppEmote = null;
    _emoteSeq++;
    _oppSpeech = null;
    _speechSeq++;
  }

  /// 상대 캐릭터가 상황 대사를 말한다(약 3초 뒤 사라짐).
  void _personaSay(List<String> lines) {
    if (widget.persona == null || lines.isEmpty || !mounted) return;
    setState(() {
      _oppSpeech = lines[_speechRng.nextInt(lines.length)];
      _oppEmote = null; // 대사와 이모트가 같은 자리를 쓰므로 대사가 우선
    });
    final seq = ++_speechSeq;
    Future<void>.delayed(const Duration(milliseconds: 3200), () {
      if (mounted && seq == _speechSeq) setState(() => _oppSpeech = null);
    });
  }

  /// 결과 기록 여부(판당 1회).
  bool _recorded = false;

  /// 게임이 끝났으면 결과를 로컬 기록(랭킹)에 1회 저장한다.
  /// 테스트/스크린샷용 주입 상태([GameScreen.initialState])는 기록하지 않는다.
  void _maybeRecordResult() {
    if (!state.isFinished || _recorded || widget.initialState != null) return;
    _recorded = true;
    final r = state.result(me);
    _persistRecord(GameRecord(
      playedAt: DateTime.now(),
      myScore: r.myTotal,
      oppScore: r.opponentTotal,
      outcome: r.outcome,
    ));
  }

  Future<void> _persistRecord(GameRecord record) async {
    try {
      await RecordsStore.addRecord(record);
    } on Object {
      // 저장 실패(예: 스토리지 미지원 환경)는 게임 진행에 영향을 주지 않는다.
    }
  }

  /// 시점은 항상 나(P0). 절대 뒤집히지 않는다.
  PlayerId get viewer => me;

  /// 내 차례이고 애니메이션 중이 아닐 때만 조작 가능.
  bool get _myTurn => state.current == me && !_animating && !state.isFinished;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final size = MediaQuery.sizeOf(context);
    final landscape = size.width > size.height;
    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(gradient: AppColors.bgGradient),
        child: SafeArea(
          child: state.phase == GamePhase.awaitingReveal
              ? _openingSequence(l10n)
              : Stack(
                  children: [
                    landscape ? _landscapeLayout(l10n, size.height) : _portraitLayout(l10n),
                    // 이모트 피커: 바깥을 탭하면 닫힘
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
                        child: _emotePicker(),
                      ),
                    ],
                    // 이모트 말풍선: 상대(위) / 나(아래) 아바타 옆.
                    // 키 필수 — 상대 말풍선이 앞에 끼어들 때 엘리먼트가 밀려
                    // 내 말풍선의 등장 애니메이션이 리셋되는 것을 막는다.
                    if (_oppEmote != null)
                      Positioned(
                        key: const ValueKey('emote-opp'),
                        left: 14,
                        top: landscape ? 92 : 60,
                        child: _EmoteBubble(key: ValueKey('opp-$_oppEmote'), asset: _oppEmote!),
                      ),
                    if (_myEmote != null)
                      Positioned(
                        key: const ValueKey('emote-me'),
                        left: 14,
                        bottom: landscape ? 116 : 128,
                        child: _EmoteBubble(key: ValueKey('me-$_myEmote'), asset: _myEmote!),
                      ),
                    // 페르소나 대사 말풍선(상대 아바타 옆, 이모트와 같은 슬롯)
                    if (_oppSpeech != null)
                      Positioned(
                        key: const ValueKey('speech-opp'),
                        left: 14,
                        right: 84,
                        top: landscape ? 92 : 60,
                        child: Align(
                          alignment: Alignment.topLeft,
                          child: _SpeechBubble(key: ValueKey('sp-$_oppSpeech'), text: _oppSpeech!),
                        ),
                      ),
                    if (state.isFinished) _resultOverlay(l10n),
                  ],
                ),
        ),
      ),
    );
  }

  // ---- 세로 레이아웃: [상대 스트립] / [테이블(덱|레인 보드|무덤)] / [내 아바타+손패+폴드] ----
  Widget _portraitLayout(AppLocalizations l10n) => Column(
        children: [
          _opponentStrip(l10n),
          Expanded(child: _tableArea(landscape: false)),
          _myBottomRow(l10n),
        ],
      );

  // ---- 가로 레이아웃 (보드가 대부분 공간을 차지, 내 필드 = 오른쪽) ----
  //
  // 폰 가로(높이 ~400)에서는 고정 88/104 바가 화면의 절반을 먹어 보드가 쪼그라든다.
  // 화면이 낮을수록 바를 함께 줄여서 테이블 높이를 지켜준다.
  Widget _landscapeLayout(AppLocalizations l10n, double h) {
    final topH = (h * 0.14).clamp(58.0, 88.0);
    final handH = (h * 0.19).clamp(74.0, 100.0);
    return Column(
      children: [
        SizedBox(height: topH, child: _lsTopRow(l10n)),
        Expanded(child: _tableArea(landscape: true)),
        SizedBox(height: handH + 4, child: _lsBottomRow(l10n, handH)),
      ],
    );
  }

  Widget _lsTopRow(AppLocalizations l10n) {
    final wins = _lineWins();
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 6, 8, 0),
      child: Row(
        children: [
          TurnAvatar(
              color: widget.persona?.color ?? AppColors.oppPrimary,
              active: state.current == ai && !state.isFinished),
          const SizedBox(width: 8),
          _WinsPill(count: wins.opp, color: AppColors.oppPrimary),
          Expanded(
            child: Center(
              child: FaceDownHand(key: _oppHandKey, count: state.hands[ai]!.length),
            ),
          ),
          _deckCounter(),
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            color: AppColors.inkSoft,
            tooltip: l10n.newGame,
            onPressed: _animating ? null : () => setState(_start),
          ),
        ],
      ),
    );
  }

  Widget _lsBottomRow(AppLocalizations l10n, double handH) {
    final wins = _lineWins();
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
      child: Row(
        children: [
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TurnAvatar(color: AppColors.mePrimary, active: _myTurn),
              const SizedBox(height: 6),
              _WinsPill(count: wins.mine, color: AppColors.mePrimary),
            ],
          ),
          Expanded(child: _handBar(l10n, height: handH)),
          _actionCluster(l10n, landscape: true),
        ],
      ),
    );
  }

  /// 가로 모드용 컴팩트 덱 카운터(드로우 연출 출발점).
  Widget _deckCounter() {
    return Padding(
      key: _deckKey,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.style_rounded, size: 15, color: AppColors.textMuted),
          const SizedBox(width: 4),
          Text('${state.deckRemaining}',
              style: const TextStyle(
                  color: AppColors.textMuted, fontWeight: FontWeight.w800, fontSize: 13)),
        ],
      ),
    );
  }

  /// 게임 테이블: 밤의 펠트 + 골드 핀스트라이프 + (세로: 덱|보드|무덤 / 가로: 보드만).
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
              // 정적 장식(shouldRepaint=false) — 레이어로 캐시해 보드가 바뀔 때 같이
              // 다시 칠하지 않게 한다.
              const Positioned.fill(
                child: RepaintBoundary(child: CustomPaint(painter: TableDecorPainter())),
              ),
              // 핀스트라이프 안쪽 여백 — 모든 내용물이 골드 라인 안에 들어온다
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                child: landscape
                    ? _boardView(landscape: true)
                    : Row(
                        children: [
                          SizedBox(
                            width: 66,
                            child: Center(
                              child:
                                  DeckPileView(remaining: state.deckRemaining, pileKey: _deckKey),
                            ),
                          ),
                          Expanded(child: _boardView(landscape: false)),
                          SizedBox(
                            width: 66,
                            child:
                                Center(child: DiscardPileView(cards: _grave, pileKey: _graveKey)),
                          ),
                        ],
                      ),
              ),
            ],
          ),
        ),
      );

  // 보드 자체에는 RepaintBoundary를 두지 않는다 — 이득을 측정할 수 없는데 레이어
  // 비용은 상시 발생하고, 래스터화가 미세하게 달라진다. 대신 **계속 움직이는 것**
  // (TurnAvatar)과 **정적인 것**(TableDecorPainter)을 각각 격리했다.
  Widget _boardView({required bool landscape}) => BoardView(
        state: state,
        viewer: viewer,
        onCellTap: _onCellTap,
        isHighlighted: _isHighlighted,
        cellKeyFor: _boardKey,
        landscape: landscape,
      );

  // ---- 상대 스트립(아바타 + 뒷면 손패 + 새 게임) ----

  Widget _opponentStrip(AppLocalizations l10n) {
    final wins = _lineWins();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 6, 4),
      child: Row(
        children: [
          TurnAvatar(
              color: widget.persona?.color ?? AppColors.oppPrimary,
              active: state.current == ai && !state.isFinished),
          const SizedBox(width: 8),
          Flexible(
            child: Text(widget.persona?.name ?? l10n.player2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: AppColors.textMuted, fontWeight: FontWeight.w700, fontSize: 13)),
          ),
          const SizedBox(width: 10),
          _WinsPill(count: wins.opp, color: AppColors.oppPrimary),
          const Spacer(),
          FaceDownHand(key: _oppHandKey, count: state.hands[ai]!.length),
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            color: AppColors.inkSoft,
            tooltip: l10n.newGame,
            onPressed: _animating ? null : () => setState(_start),
          ),
        ],
      ),
    );
  }

  // ---- 하단: 내 아바타 + 손패 + 폴드 ----

  Widget _myBottomRow(AppLocalizations l10n) {
    final wins = _lineWins();
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 4, 10, 10),
      child: Row(
        children: [
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TurnAvatar(color: AppColors.mePrimary, active: _myTurn),
              const SizedBox(height: 5),
              _WinsPill(count: wins.mine, color: AppColors.mePrimary),
            ],
          ),
          Expanded(child: _handBar(l10n, height: 104)),
          _actionCluster(l10n, landscape: false),
        ],
      ),
    );
  }

  // ---- 감정 표현(이모트) ----

  /// 손패 옆 액션 버튼 묶음: [쉴드][표식] / [이모트][폴드].
  ///
  /// 세로에서는 **2×2 그리드**로 쌓는다. 한 줄에 네 개를 놓으면 손패가 그만큼 좁아져서
  /// 작은 폰에서 카드가 뭉개진다 — 가로 폭은 두 개일 때와 똑같이 유지된다.
  Widget _actionCluster(AppLocalizations l10n, {required bool landscape}) {
    final buttons = <Widget>[
      for (final b in [
        _tokenButton(l10n, TokenKind.shield),
        _tokenButton(l10n, TokenKind.attack),
      ])
        if (b != null) b,
      _emoteButton(l10n),
      _foldButton(l10n),
    ];

    if (landscape) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < buttons.length; i++) ...[
            if (i > 0) const SizedBox(width: 6),
            buttons[i],
          ],
        ],
      );
    }

    final rows = <Widget>[];
    for (var i = 0; i < buttons.length; i += 2) {
      if (rows.isNotEmpty) rows.add(const SizedBox(height: 6));
      rows.add(Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          buttons[i],
          if (i + 1 < buttons.length) ...[
            const SizedBox(width: 6),
            buttons[i + 1],
          ],
        ],
      ));
    }
    return Column(mainAxisSize: MainAxisSize.min, children: rows);
  }

  Widget _emoteButton(AppLocalizations l10n) => Tooltip(
        message: l10n.emotesTitle,
        child: OutlinedButton(
          onPressed: () => setState(() => _emoteOpen = !_emoteOpen),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.all(10),
            minimumSize: Size.zero,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            side: BorderSide(
                color: AppColors.gold.withValues(alpha: _emoteOpen ? 1 : 0.55), width: 1.4),
          ),
          child: const Icon(Icons.emoji_emotions_rounded, size: 18, color: AppColors.gold),
        ),
      );

  /// 이모트 6종이 펼쳐지는 피커 패널.
  Widget _emotePicker() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.gold, width: 1.2),
          boxShadow: AppShapes.panelShadow,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final e in kEmoteAssets)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: InkWell(
                  borderRadius: BorderRadius.circular(999),
                  onTap: () => _sendEmote(e),
                  child: Container(
                    decoration: BoxDecoration(
                      color: AppColors.bgBottom,
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.stroke),
                    ),
                    padding: const EdgeInsets.all(6),
                    child: PersonaIcon(asset: e, size: 34),
                  ),
                ),
              ),
          ],
        ),
      );

  /// 내 이모트 전송 → 잠시 뒤 상대(AI)도 반응 이모트를 보낸다(수신 화면 데모).
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

  /// 상대(AI)의 반응 이모트 — 살짝 놀리는 조합.
  String _emoteReply(String sent) => switch (sent) {
        'assets/lottie/emoji_smile.json' => 'assets/lottie/emoji_wow.json',
        'assets/lottie/emoji_lol.json' => 'assets/lottie/emoji_angry.json',
        'assets/lottie/emoji_wow.json' => 'assets/lottie/emoji_smile.json',
        'assets/lottie/emoji_sad.json' => 'assets/lottie/emoji_lol.json',
        'assets/lottie/emoji_angry.json' => 'assets/lottie/emoji_lol.json',
        _ => 'assets/lottie/emoji_smile.json', // cry → smile(위로인 척)
      };

  Widget _foldButton(AppLocalizations l10n) => Tooltip(
        message: l10n.actionFold,
        child: OutlinedButton(
          onPressed: (state.isFinished || _animating) ? null : _onFold,
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.all(10),
            minimumSize: Size.zero,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: const Icon(Icons.flag_rounded, size: 18),
        ),
      );

  // ---- 내 손패 (앞면) ----

  Widget _handBar(AppLocalizations l10n, {required double height}) {
    final hand = state.hands[me]!; // 항상 내 손패(고정)
    for (var i = 0; i < hand.length; i++) {
      _handKey(i); // 풀 확보(키 자체는 재사용)
    }
    final dim = !_myTurn; // 내 차례 아니면 흐리게(대신 판은 안 뒤집힘)
    return SizedBox(
      key: _handAreaKey,
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
                        opacity: _flyingHandIndex == i ? 0 : (dim ? 0.5 : 1),
                        child: AnimatedSlide(
                          duration: const Duration(milliseconds: 140),
                          curve: Curves.easeOut,
                          offset: selected == i ? const Offset(0, -0.18) : Offset.zero,
                          // 공격 가능한 카드(처음 받은 카드/조커)는 붉은 테두리로 구분 —
                          // 이 표시가 없으면 "아껴 쓴다"는 판단 자체를 할 수 없다.
                          child: DecoratedBox(
                            decoration: hand[i].canAttack
                                ? BoxDecoration(
                                    borderRadius: BorderRadius.circular(9),
                                    border: Border.all(color: AppColors.oppPrimary, width: 2),
                                    boxShadow: [
                                      BoxShadow(
                                          color: AppColors.oppPrimary.withValues(alpha: 0.45),
                                          blurRadius: 8),
                                    ],
                                  )
                                : const BoxDecoration(),
                            child: CardCell(
                              key: _handKey(i),
                              placed: PlacedCard(hand[i], me),
                              size: 50,
                              side: CellSide.me,
                              highlighted: selected == i,
                              onTap: () => _selectHand(i),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
    );
  }

  // ---- 선공 정하기(오프닝 딜링 연출) ----

  Widget _openingSequence(AppLocalizations l10n) {
    final oppPick = _oppRevealIndex();
    return OpeningSequence(
      myHand: state.hands[PlayerId.p0]!,
      oppHand: state.hands[PlayerId.p1]!,
      oppPick: oppPick,
      myName: l10n.player1,
      oppName: widget.persona?.name ?? l10n.player2,
      decideFirst: _decideFirst,
      onFinished: (myPick) {
        // 오픈 카드 2장은 버려진다 → 무덤에 쌓아 연출의 근거를 남긴다.
        final myOpen = state.hands[PlayerId.p0]![myPick];
        final oppOpen = state.hands[PlayerId.p1]![oppPick];
        setState(() {
          state.revealForFirstTurn(myPick, oppPick);
          _grave
            ..add(oppOpen)
            ..add(myOpen);
        });
        if (widget.persona != null) _personaSay(widget.persona!.lines.greeting);
        _maybeRunOpponent(); // 상대가 선공이면 바로 AI가 둔다
      },
    );
  }

  /// 상대(P2)는 가장 높은 숫자 카드를 오픈(선공을 노림).
  int _oppRevealIndex() {
    final h = state.hands[PlayerId.p1]!;
    var j = 0;
    for (var k = 1; k < h.length; k++) {
      if (h[k].rank > h[j].rank) j = k;
    }
    return j;
  }

  /// 두 오픈 카드로 선공 판정(도메인 revealForFirstTurn과 동일 규칙).
  PlayerId _decideFirst(PlayingCard mine, PlayingCard opp) {
    var cmp = mine.rank.compareTo(opp.rank);
    if (cmp == 0) cmp = mine.suit.order.compareTo(opp.suit.order);
    return cmp >= 0 ? PlayerId.p0 : PlayerId.p1;
  }

  // ---- 상호작용 ----

  List<PlayingCard> _cards(PlayerId p, int line) => [
        for (final c in state.fields[p]![line])
          if (c != null) c.card
      ];

  ({int mine, int opp}) _lineWins() {
    var m = 0, o = 0;
    for (var i = 0; i < kRows; i++) {
      final r = compareLine(_cards(viewer, i), _cards(viewer.other, i));
      if (r == LineOutcome.win) m++;
      if (r == LineOutcome.lose) o++;
    }
    return (mine: m, opp: o);
  }

  /// 내 필드에서 빼앗은 카드를 놓을 칸: 지금 보고 있는 줄부터, 없으면 위에서부터.
  ({int row, int col})? _stealDest(int preferredRow) {
    for (final r in [preferredRow, ...List.generate(kRows, (i) => i)]) {
      final c = _firstEmptyCol(me, r);
      if (c != null) return (row: r, col: c);
    }
    return null;
  }

  int? _firstEmptyCol(PlayerId p, int row) {
    for (var col = 0; col < kCols; col++) {
      if (state.fields[p]![row][col] == null) return col; // col0=가운데부터
    }
    return null;
  }

  void _selectHand(int i) {
    if (!_myTurn) return;
    if (_tokenMode == TokenKind.attack) {
      _useToken(TokenKind.attack, () => state.markAttacker(i));
      return;
    }
    // 쉴드 대기 중에 손패를 누르면 "그만두겠다"는 뜻으로 본다.
    if (_tokenMode != null) setState(() => _tokenMode = null);
    setState(() => selected = (selected == i) ? null : i);
  }

  void _onCellTap(PlayerId owner, int row, int col) => _handleCellTap(owner, row, col);

  Future<void> _handleCellTap(PlayerId owner, int row, int col) async {
    if (_animating || state.isFinished || state.current != me) return;
    // await 이후에 context를 만지지 않도록 미리 잡아둔다.
    final l10n = AppLocalizations.of(context);

    if (_tokenMode == TokenKind.shield) {
      if (owner != me) {
        _snack(l10n.tokenShieldPrompt); // 상대 카드는 대상이 아니다
        return;
      }
      _useToken(TokenKind.shield, () => state.declareShield(row, col));
      return;
    }
    // 표식 대기 중에 보드를 누르면 그만두겠다는 뜻.
    if (_tokenMode != null) setState(() => _tokenMode = null);

    try {
      if (selected == null) return;

      final handIndex = selected!;
      final card = state.hands[me]![handIndex];

      if (owner == me) {
        // 내 필드: 가운데부터 채움 (탭한 칸 무시, 가장 안쪽 빈 칸)
        final target = _firstEmptyCol(owner, row);
        if (target == null) {
          _snack(l10n.errLineFull);
          return;
        }
        if (card.isJoker) {
          final picked = await _showJokerPicker();
          if (picked == null) return;
          final display = card.designate(picked.$1, picked.$2);
          await _placeWithFly(
            handIndex: handIndex,
            targetOwner: owner,
            row: row,
            col: target,
            displayCard: display,
            commit: () => state.placeCard(handIndex, owner, row, target,
                jokerRank: picked.$1, jokerSuit: picked.$2),
          );
        } else {
          await _placeWithFly(
            handIndex: handIndex,
            targetOwner: owner,
            row: row,
            col: target,
            displayCard: card,
            commit: () => state.placeCard(handIndex, owner, row, target),
          );
        }
      } else {
        final cell = state.fields[owner]![row][col];
        if (cell == null) {
          if (card.isShield) {
            await _placeWithFly(
              handIndex: handIndex,
              targetOwner: owner,
              row: row,
              col: col,
              displayCard: card,
              commit: () => state.placeCard(handIndex, owner, row, col),
            );
          } else {
            _snack(l10n.errNormalOwnFieldOnly);
          }
        } else {
          if (state.pendingBonus) {
            _snack(l10n.errAttackOncePerTurn);
            return;
          }
          if (!card.canAttack) {
            _snack(l10n.errAttackerCardRequired);
            return;
          }
          final dest = _stealDest(row);
          if (dest == null) {
            _snack(l10n.errNeedEmptyCellForSteal);
            return;
          }
          await _attackWithFly(handIndex, owner, row, col, card, dest);
        }
      }
    } on IllegalMove catch (e) {
      _snack(moveErrorText(l10n, e.error));
    }
  }

  /// **빼앗기 연출**: 공격 카드가 날아가 타격 → 맞은 카드가 튕긴 뒤 **내 줄로 날아와**
  /// 쉴드로 박힌다 → 쓴 공격 카드는 무덤으로 → 보너스 배치 안내. 턴은 아직 내 것.
  Future<void> _attackWithFly(int handIndex, PlayerId owner, int row, int col, PlayingCard weapon,
      ({int row, int col}) dest) async {
    final from = _rectFor(_handKeys.length > handIndex ? _handKeys[handIndex] : null);
    final cellRect = _rectFor(_boardKey(owner, row, col));
    final victim = state.fields[owner]![row][col]?.card;
    if (from == null || cellRect == null || victim == null) {
      state.attack(handIndex, row, col, dest.row, dest.col);
      _grave.add(weapon);
      setState(() => selected = null);
      await _afterMyAction();
      return;
    }
    final overlay = Overlay.of(context);
    setState(() {
      _animating = true;
      _flyingHandIndex = handIndex;
    });
    // 1) 공격 카드가 타격 지점으로 돌진.
    await flyCard(
        overlay: overlay,
        vsync: this,
        from: from,
        to: cellRect,
        card: weapon,
        duration: const Duration(milliseconds: 300));
    if (!mounted) return;
    // 2) 규칙 반영 — 상대 칸이 비고, 그 카드가 내 칸에 쉴드로 박힌다.
    state.attack(handIndex, row, col, dest.row, dest.col);
    setState(() => _flyingHandIndex = null);
    // 3) 맞은 카드가 튕긴 뒤 내 칸으로 날아온다.
    await poofCard(
        overlay: overlay,
        vsync: this,
        rect: cellRect,
        card: victim,
        duration: const Duration(milliseconds: 220));
    if (!mounted) return;
    final myRect = _rectFor(_boardKey(me, dest.row, dest.col));
    if (myRect != null) {
      await flyCard(
        overlay: overlay,
        vsync: this,
        from: cellRect,
        to: myRect,
        card: state.lastStolen ?? victim,
        duration: const Duration(milliseconds: 440),
        spinTurns: 0.5,
      );
      if (!mounted) return;
    }
    // 4) 쓴 공격 카드는 무덤으로.
    final graveRect = _rectFor(_graveKey);
    if (graveRect != null) {
      await flyCard(
        overlay: overlay,
        vsync: this,
        from: cellRect,
        to: graveRect,
        card: weapon,
        duration: const Duration(milliseconds: 360),
        spinTurns: 0.75,
        endOpacity: 0.85,
      );
      if (!mounted) return;
    }
    setState(() {
      _grave.add(weapon);
      _animating = false;
      selected = null;
    });
    if (widget.persona != null) _personaSay(widget.persona!.lines.removed);
    await _afterMyAction();
  }

  /// 내 행동 뒤 처리: 보너스 배치가 남았으면 내 차례를 유지하고 안내만, 아니면 AI로 넘긴다.
  Future<void> _afterMyAction() async {
    if (state.pendingBonus && !state.isFinished) {
      if (mounted) _snack(AppLocalizations.of(context).bonusPlacePrompt);
      return;
    }
    await _maybeRunOpponent();
  }

  /// 손패[handIndex] → 보드 칸(targetOwner,row,col)으로 날아가 안착 후 [commit] 반영.
  Future<void> _placeWithFly({
    required int handIndex,
    required PlayerId targetOwner,
    required int row,
    required int col,
    required PlayingCard displayCard,
    required void Function() commit,
  }) async {
    final from = _rectFor(_handKeys.length > handIndex ? _handKeys[handIndex] : null);
    final to = _rectFor(_boardKey(targetOwner, row, col));
    if (from == null || to == null) {
      commit();
      setState(() => selected = null);
      return;
    }
    setState(() {
      _animating = true;
      _flyingHandIndex = handIndex;
    });
    await flyCard(overlay: Overlay.of(context), vsync: this, from: from, to: to, card: displayCard);
    if (!mounted) return;
    commit();
    setState(() {
      _animating = false;
      _flyingHandIndex = null;
      selected = null;
    });
    await _afterMyAction();
  }

  // ---- 상대(AI) ----

  /// 지금이 상대(AI) 차례면, 더 이상 상대 차례가 아닐 때까지 자동으로 둔다.
  Future<void> _maybeRunOpponent() async {
    while (mounted && !state.isFinished && state.current == ai) {
      setState(() => _animating = true);
      await Future<void>.delayed(const Duration(milliseconds: 480));
      if (!mounted) return;
      final moved = await _aiPlayOneMove();
      if (!mounted) return;
      if (!moved) break;
    }
    if (mounted) {
      setState(() => _animating = false);
      _maybeRecordResult();
    }
  }

  /// AI 한 수: 페르소나 전략이 고른 수를 연출과 함께 반영한다.
  Future<bool> _aiPlayOneMove() async {
    final lines = widget.persona?.lines;
    AiMove move;
    try {
      move = _ai.decide(state, ai);
    } on Object {
      move = const FoldMove();
    }

    try {
      switch (move) {
        case FoldMove():
          state.fold();
          setState(() {});
          return true;

        case PlaceMove(
            :final handIndex,
            :final target,
            :final row,
            :final col,
            :final jokerRank,
            :final jokerSuit
          ):
          final card = state.hands[ai]![handIndex];
          final display = card.isJoker ? card.designate(jokerRank!, jokerSuit!) : card;
          final from = _rectFor(_oppHandKey);
          final to = _rectFor(_boardKey(target, row, col));
          if (from != null && to != null) {
            await flyCard(
                overlay: Overlay.of(context), vsync: this, from: from, to: to, card: display);
            if (!mounted) return false;
          }
          if (card.isJoker) {
            state.placeCard(handIndex, ai, row, col, jokerRank: jokerRank, jokerSuit: jokerSuit);
            if (lines != null) _personaSay(lines.joker);
          } else {
            state.placeCard(handIndex, target, row, col);
            // 변칙: 내 필드에 쉴드를 꽂았을 때
            if (card.isShield && target == me && lines != null) {
              _personaSay(lines.shieldTrick);
            }
          }
          setState(() {});
          return true;

        case AttackMove(:final handIndex, :final row, :final col, :final myRow, :final myCol):
          final weapon = state.hands[ai]![handIndex];
          final victim = state.fields[me]![row][col]?.card;
          final from = _rectFor(_oppHandKey);
          final cellRect = _rectFor(_boardKey(me, row, col));
          if (from != null && cellRect != null) {
            await flyCard(
                overlay: Overlay.of(context),
                vsync: this,
                from: from,
                to: cellRect,
                card: weapon,
                duration: const Duration(milliseconds: 300));
            if (!mounted) return false;
          }
          state.attack(handIndex, row, col, myRow, myCol);
          if (victim != null && cellRect != null && mounted) {
            await poofCard(
                overlay: Overlay.of(context),
                vsync: this,
                rect: cellRect,
                card: victim,
                duration: const Duration(milliseconds: 220));
            // 빼앗긴 카드가 상대(AI) 줄로 날아간다.
            final toRect = _rectFor(_boardKey(ai, myRow, myCol));
            if (toRect != null && mounted) {
              await flyCard(
                  overlay: Overlay.of(context),
                  vsync: this,
                  from: cellRect,
                  to: toRect,
                  card: state.lastStolen ?? victim,
                  duration: const Duration(milliseconds: 440),
                  spinTurns: 0.5);
            }
          }
          if (!mounted) return false;
          _grave.add(weapon);
          if (lines != null) _personaSay(lines.removeMine);
          setState(() {});
          return true;
      }
    } on IllegalMove {
      // 전략이 계산한 수가 어긋나면(경합 등) 안전하게 폴드
      state.fold();
      setState(() {});
      return true;
    }
  }

  Rect? _rectFor(GlobalKey? key) {
    final box = key?.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  Future<void> _onFold() async {
    if (!_myTurn) return;
    final l10n = AppLocalizations.of(context);
    try {
      state.fold();
      setState(() => selected = null);
      await _maybeRunOpponent();
    } on IllegalMove catch (e) {
      _snack(moveErrorText(l10n, e.error));
    }
  }

  bool _isHighlighted(PlayerId owner, int row, int col) {
    if (state.current != me) return false;
    if (selected == null) return false;
    final card = state.hands[me]![selected!];
    final cell = state.fields[owner]![row][col];
    if (owner == me) {
      return !card.isShield && cell == null; // 내 줄 빈 칸(가운데부터)
    }
    if (cell == null) return card.isShield; // 상대 빈 칸: 쉴드만
    return !card.isShield; // 상대 카드: 제거 후보
  }

  // ---- 토큰(유료 아이템) ----

  /// 토큰 1개를 실제로 쓴다.
  ///
  /// 순서가 중요하다: **보유 확인 → 규칙 적용(실패하면 던진다) → 차감.**
  /// 차감을 먼저 하면 규칙 위반으로 튕겼을 때 토큰만 사라진다.
  Future<void> _useToken(TokenKind kind, void Function() apply) async {
    final m = MonetizationScope.maybeOf(context);
    if (m == null) return;
    final l10n = AppLocalizations.of(context);

    if (!m.wallet.has(kind)) {
      _snackWithShop(l10n.tokenEmpty(tokenName(l10n, kind)));
      return;
    }
    try {
      apply();
    } on IllegalMove catch (e) {
      _snack(moveErrorText(l10n, e.error));
      return;
    }
    await m.wallet.spend(kind);
    if (!mounted) return;
    setState(() => _tokenMode = null);
    _snack(kind == TokenKind.shield ? l10n.tokenShieldDone : l10n.tokenAttackDone);
  }

  /// 토큰 버튼. 남은 보유량을 배지로 보여주고, 누르면 대상 지정 모드로 들어간다.
  ///
  /// 지갑이 없는 환경(위젯 테스트·스크린샷)에서는 아예 그리지 않는다.
  Widget? _tokenButton(AppLocalizations l10n, TokenKind kind) {
    final m = MonetizationScope.maybeOf(context);
    if (m == null) return null;
    final color = tokenColor(kind);

    return AnimatedBuilder(
      animation: m.wallet,
      builder: (context, _) {
        final owned = m.wallet.balanceOf(kind);
        final left =
            kind == TokenKind.shield ? state.shieldDeclarationsLeft(me) : state.attackMarksLeft(me);
        final active = _tokenMode == kind && _myTurn;
        final usable = _myTurn && left > 0 && owned > 0;

        return Tooltip(
          message: tokenName(l10n, kind),
          child: OutlinedButton(
            onPressed: _myTurn ? () => _onTokenPressed(l10n, kind, left, owned) : null,
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
              minimumSize: Size.zero,
              backgroundColor: active ? color.withValues(alpha: 0.22) : null,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              side: BorderSide(
                color: color.withValues(alpha: active ? 1 : (usable ? 0.55 : 0.22)),
                width: active ? 1.8 : 1.4,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(tokenIcon(kind), size: 18, color: color.withValues(alpha: usable ? 1 : 0.4)),
                const SizedBox(width: 4),
                Text('$owned',
                    style: TextStyle(
                      color: color.withValues(alpha: usable ? 1 : 0.4),
                      fontWeight: FontWeight.w900,
                      fontSize: 12,
                    )),
              ],
            ),
          ),
        );
      },
    );
  }

  void _onTokenPressed(AppLocalizations l10n, TokenKind kind, int left, int owned) {
    // 판당 상한이 먼저다 — 토큰을 갖고 있어도 이 판에서 이미 썼으면 못 쓴다.
    if (left <= 0) {
      _snack(l10n.tokenUsedThisMatch(tokenName(l10n, kind)));
      return;
    }
    if (owned <= 0) {
      _snackWithShop(l10n.tokenEmpty(tokenName(l10n, kind)));
      return;
    }
    setState(() {
      _tokenMode = _tokenMode == kind ? null : kind;
      if (_tokenMode != null) selected = null; // 배치 선택과 겹치지 않게
    });
    if (_tokenMode == kind) {
      _snack(kind == TokenKind.shield ? l10n.tokenShieldPrompt : l10n.tokenAttackPrompt);
    }
  }

  /// "토큰이 없습니다" 안내 + 상점 바로가기. 게임을 끊지 않는 선에서의 유일한 판매 접점이다.
  void _snackWithShop(String msg) {
    final l10n = AppLocalizations.of(context);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(msg),
        duration: const Duration(seconds: 3),
        action: SnackBarAction(
          label: l10n.goToShop,
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const ShopScreen()),
          ),
        ),
      ));
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg), duration: const Duration(seconds: 2)));
  }

  Future<(int, Suit)?> _showJokerPicker() {
    final l10n = AppLocalizations.of(context);
    var rank = Ranks.all.first;
    var suit = Suit.spades;
    return showDialog<(int, Suit)>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.jokerPickTitle),
        content: StatefulBuilder(
          builder: (context, setLocal) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButton<int>(
                isExpanded: true,
                value: rank,
                items: [
                  for (final r in Ranks.all)
                    DropdownMenuItem(value: r, child: Text('${l10n.numberLabel}: ${rankLabel(r)}'))
                ],
                onChanged: (v) => setLocal(() => rank = v ?? rank),
              ),
              DropdownButton<Suit>(
                isExpanded: true,
                value: suit,
                items: [
                  for (final s in Suit.values)
                    DropdownMenuItem(value: s, child: Text('${l10n.suitLabel}: ${s.symbol}'))
                ],
                onChanged: (v) => setLocal(() => suit = v ?? suit),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(l10n.cancel)),
          FilledButton(
              onPressed: () => Navigator.pop(context, (rank, suit)), child: Text(l10n.confirm)),
        ],
      ),
    );
  }

  // ---- 결과 ----

  Widget _resultOverlay(AppLocalizations l10n) {
    final r = state.result(me);
    final (resultText, resultColor) = switch (r.outcome) {
      MatchOutcome.win => (l10n.resultWin, AppColors.win),
      MatchOutcome.lose => (l10n.resultLose, AppColors.lose),
      MatchOutcome.draw => (l10n.resultDraw, AppColors.tie),
    };
    final size = MediaQuery.sizeOf(context);
    final landscape = size.width > size.height;
    final compact = size.height < 560;
    final oppName = widget.persona?.name ?? l10n.player2;

    // 페르소나 마무리 대사(승패에 맞는 목록에서 결정적으로 한 줄).
    final personaLines = switch (r.outcome) {
      MatchOutcome.win => widget.persona?.lines.loseGame,
      MatchOutcome.lose => widget.persona?.lines.winGame,
      MatchOutcome.draw => widget.persona?.lines.drawGame,
    };
    final personaLine = (personaLines == null || personaLines.isEmpty)
        ? null
        : personaLines[(r.myTotal + r.opponentTotal) % personaLines.length];

    final header = Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Expanded(
              child: Text(l10n.resultMeLabel,
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                      color: AppColors.mePrimary,
                      fontWeight: FontWeight.w900,
                      fontSize: 12,
                      letterSpacing: 1))),
          const SizedBox(width: 56),
          Expanded(
              child: Text(oppName,
                  style: TextStyle(
                      color: widget.persona?.color ?? AppColors.oppPrimary,
                      fontWeight: FontWeight.w900,
                      fontSize: 12,
                      letterSpacing: 1))),
        ],
      ),
    );

    final lines = Column(
      mainAxisSize: MainAxisSize.min,
      children: [header, for (var i = 0; i < kRows; i++) _resultLine(l10n, i)],
    );

    final resultHead = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text('GAME OVER',
            style: TextStyle(
                fontSize: 12,
                color: AppColors.textMuted,
                letterSpacing: 3,
                fontWeight: FontWeight.w700)),
        SizedBox(height: compact ? 4 : 8),
        Text(resultText,
            style: TextStyle(
                fontSize: compact ? 26 : 34,
                fontWeight: FontWeight.w900,
                color: resultColor,
                letterSpacing: 1)),
        if (personaLine != null) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.cardBody,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.goldDeep),
            ),
            child: Text('“$personaLine”',
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: AppColors.ink, fontWeight: FontWeight.w700, fontSize: 12)),
          ),
        ],
      ],
    );

    final totalAndButton = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(height: 1, color: AppColors.stroke),
        SizedBox(height: compact ? 8 : 10),
        Row(
          children: [
            Expanded(
                child: Text('${r.myTotal}',
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                        color: AppColors.mePrimary, fontWeight: FontWeight.w900, fontSize: 20))),
            const SizedBox(width: 12),
            const Text('TOTAL',
                style: TextStyle(
                    color: AppColors.textMuted,
                    fontWeight: FontWeight.w700,
                    fontSize: 11,
                    letterSpacing: 1)),
            const SizedBox(width: 12),
            Expanded(
                child: Text('${r.opponentTotal}',
                    style: const TextStyle(
                        color: AppColors.oppPrimary, fontWeight: FontWeight.w900, fontSize: 20))),
          ],
        ),
        SizedBox(height: compact ? 12 : 20),
        FilledButton.icon(
            onPressed: () => setState(_start),
            icon: const Icon(Icons.refresh_rounded),
            label: Text(l10n.newGame)),
      ],
    );

    // 가로: [줄별 결과 | 요약] 2단 배치 — 세로 공간이 좁아도 아래가 잘리지 않는다.
    final content = landscape
        ? Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(child: lines),
              Container(
                  width: 1,
                  height: 168,
                  color: AppColors.stroke,
                  margin: const EdgeInsets.symmetric(horizontal: 18)),
              SizedBox(
                width: 250,
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  resultHead,
                  SizedBox(height: compact ? 10 : 14),
                  totalAndButton,
                ]),
              ),
            ],
          )
        : Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              resultHead,
              const SizedBox(height: 14),
              lines,
              const SizedBox(height: 10),
              totalAndButton,
            ],
          );

    return _scrim(compact: compact, child: content);
  }

  /// 줄별 결과 한 줄: 가운데 줄 번호 칩(승패 색 단색), 이긴 쪽에 하이라이트 + 체크.
  Widget _resultLine(AppLocalizations l10n, int i) {
    final my = _cards(me, i), op = _cards(ai, i);
    final myE = evaluateHand(my), opE = evaluateHand(op);
    final o = compareLine(my, op);
    final oc = switch (o) {
      LineOutcome.win => AppColors.win,
      LineOutcome.lose => AppColors.lose,
      LineOutcome.tie => AppColors.tie,
    };

    Widget side(HandResult e, {required bool winner, required bool alignRight}) {
      final texts = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: alignRight ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Text(handCategoryName(l10n, e.category),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: winner ? AppColors.textMain : AppColors.textMuted,
                fontWeight: winner ? FontWeight.w900 : FontWeight.w600,
                fontSize: 13.5,
              )),
          Text(l10n.scorePoints(e.score),
              style: const TextStyle(
                  color: AppColors.textMuted, fontSize: 11, fontWeight: FontWeight.w600)),
        ],
      );
      // 긴 족보명(영문 등)이 좁은 화면에서 넘치지 않게 유연 폭 + 줄임표.
      final child = Row(
        mainAxisSize: MainAxisSize.min,
        children: alignRight
            ? [
                Flexible(child: texts),
                if (winner) ...[
                  const SizedBox(width: 5),
                  Icon(Icons.check_circle_rounded, size: 15, color: oc),
                ],
              ]
            : [
                if (winner) ...[
                  Icon(Icons.check_circle_rounded, size: 15, color: oc),
                  const SizedBox(width: 5),
                ],
                Flexible(child: texts),
              ],
      );
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: winner
            ? BoxDecoration(
                color: Color.alphaBlend(oc.withValues(alpha: 0.20), AppColors.surface),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: oc, width: 1),
              )
            : null,
        child: child,
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
              child: Align(
                  alignment: Alignment.centerRight,
                  child: side(myE, winner: o == LineOutcome.win, alignRight: true))),
          Container(
            width: 40,
            margin: const EdgeInsets.symmetric(horizontal: 8),
            padding: const EdgeInsets.symmetric(vertical: 5),
            decoration: BoxDecoration(color: oc, borderRadius: BorderRadius.circular(9)),
            child: Text(l10n.lineN(i + 1),
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: AppColors.ink, fontWeight: FontWeight.w900, fontSize: 11.5)),
          ),
          Expanded(
              child: Align(
                  alignment: Alignment.centerLeft,
                  child: side(opE, winner: o == LineOutcome.lose, alignRight: false))),
        ],
      ),
    );
  }



  /// 어두운 배경 위 카드형 패널 오버레이(골드 테두리).
  /// 내용이 화면보다 크면 패널 안에서 스크롤한다(오버플로 방지).
  Widget _scrim({required Widget child, bool compact = false}) => Container(
        color: Colors.black.withValues(alpha: 0.55),
        alignment: Alignment.center,
        child: Container(
          margin: EdgeInsets.all(compact ? 14 : 28),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: AppColors.gold.withValues(alpha: 0.45), width: 1.2),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withValues(alpha: 0.5),
                  blurRadius: 30,
                  offset: const Offset(0, 12))
            ],
          ),
          child: SingleChildScrollView(
            padding:
                EdgeInsets.symmetric(horizontal: compact ? 22 : 28, vertical: compact ? 14 : 32),
            child: child,
          ),
        ),
      );
}

// ---- 작은 위젯들 ----

/// 이모트 말풍선: 아이보리 벌룬 안에서 로티 표정이 재생된다. 스케일 팝 등장.
class _EmoteBubble extends StatelessWidget {
  const _EmoteBubble({super.key, required this.asset});
  final String asset;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutBack,
        builder: (context, t, child) => Opacity(
            opacity: t.clamp(0.0, 1.0), child: Transform.scale(scale: 0.6 + 0.4 * t, child: child)),
        child: Container(
          padding: const EdgeInsets.all(9),
          decoration: BoxDecoration(
            color: AppColors.cardBody,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(20),
              topRight: Radius.circular(20),
              bottomRight: Radius.circular(20),
              bottomLeft: Radius.circular(6), // 꼬리 방향(아바타 쪽)
            ),
            border: Border.all(color: AppColors.goldDeep, width: 1.2),
            boxShadow: AppShapes.panelShadow,
          ),
          child: PersonaIcon(asset: asset, size: 52),
        ),
      ),
    );
  }
}

/// 페르소나 대사 말풍선: 아이보리 벌룬 + 잉크 텍스트, 스케일 팝 등장.
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
            opacity: t.clamp(0.0, 1.0), child: Transform.scale(scale: 0.7 + 0.3 * t, child: child)),
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
                  color: AppColors.ink, fontWeight: FontWeight.w700, fontSize: 13, height: 1.35)),
        ),
      ),
    );
  }
}

/// 현재 이기고 있는 줄 수를 골드 도트 3개로 표시(글자 없음).
class _WinsPill extends StatelessWidget {
  const _WinsPill({required this.count, required this.color});
  final int count;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < kRows; i++)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2.5),
              child: Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                  color: i < count ? color : color.withValues(alpha: 0.20),
                  shape: BoxShape.circle,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
