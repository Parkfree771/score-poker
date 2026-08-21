import 'package:flutter/material.dart';

import '../../domain/card.dart';
import '../../domain/game.dart';
import '../../domain/scoring.dart';
import '../theme.dart';
import 'card_back.dart';
import 'card_face.dart';
import 'table_decor.dart';

/// 보드 칸의 표시 방식.
///
/// 기본 게임은 전부 [face]. 가림 룰은 상대의 미공개 카드를 [back](뒷면)으로,
/// 그중 지금 코인으로 열어볼 수 있는 카드를 [backPeekable](뒷면 + 골드 코인 마커)로,
/// 나의 미공개 카드를 [peek](뒷면 + 들린 모서리로 나만 확인)으로,
/// 숨김 지정된 내 카드를 [sealed](peek + 브라스 봉인 도장)로 그린다.
enum CellLook { face, back, backPeekable, peek, sealed }

/// 게임 보드 — 방향 인식형.
///
/// **세로(기본)**: 레인 3개(각 레인 = 상대 5칸 위 / 점수 알약 / 내 5칸 아래)가 나란히.
///   카드는 세워서(숫자 바로 읽힘), 골드 중앙 가로선(◆캡)이 테이블을 가로지르고
///   레인 안팎 세로 구분선 4개가 테이블 프레임을 만든다.
/// **가로**: 상대 필드(왼쪽) | 골드 세로선+점수 열 | 내 필드(오른쪽). 카드 원비율.
///
/// 빈칸 = 파인 홈(불투명) + 모서리 브래킷. 다음에 놓일 칸만 밝은 원색,
/// 나머지는 가라앉은 단색(반투명 금지). 하이라이트는 골드.
class BoardView extends StatelessWidget {
  const BoardView({
    super.key,
    required this.cellAt,
    required this.viewer,
    required this.onCellTap,
    this.isHighlighted,
    this.isConcealed,
    this.lookOf,
    this.lineCardsOf,
    this.cellKeyFor,
    this.landscape = false,
  });

  /// 칸의 카드. 보드는 규칙 엔진을 모른다 — 기본 게임(GameState)과 가림 룰이
  /// 같은 보드를 쓰기 위한 유일한 접점이다.
  final PlacedCard? Function(PlayerId owner, int row, int col) cellAt;
  final PlayerId viewer;
  final void Function(PlayerId owner, int row, int col) onCellTap;
  final bool Function(PlayerId owner, int row, int col)? isHighlighted;

  /// 연출용 숨김: true인 칸은 카드가 있어도 빈 슬롯으로 그린다.
  /// (빼앗은 카드가 날아와 **안착하는 순간**에만 나타나야 두 장으로 안 보인다)
  final bool Function(PlayerId owner, int row, int col)? isConcealed;

  /// 칸 표시 방식(기본 [CellLook.face]).
  final CellLook Function(PlayerId owner, int row, int col)? lookOf;

  /// 점수 알약에 넣을 카드 목록. 가림 룰은 **공개된 카드만** 넘겨서
  /// 숨긴 정보가 점수로 새지 않게 한다. 기본은 칸 전체.
  final List<PlayingCard> Function(PlayerId p, int line)? lineCardsOf;
  final GlobalKey Function(PlayerId owner, int row, int col)? cellKeyFor;
  final bool landscape;

  static const double _cell = 58;
  static const double _portraitRatio = 1.26; // 세로: 폭 확보를 위해 살짝 낮은 비율
  static const double _landscapeRatio = 1.36; // 가로: 원비율
  static const double _centerW = 66; // 가로 모드 중앙 점수 열 폭
  static const double _slotPadV = 1; // _BoardSlot 세로 패딩(위/아래 각각)
  static const double _laneGap = 22; // 세로 모드에서 골드 선이 지나가는 틈

  // 보드 높이는 셀 크기에서 그대로 계산된다 → IntrinsicHeight(서브트리를 두 번
  // 레이아웃한다)를 쓸 이유가 없다. 아래 값이 IntrinsicHeight가 재던 값과 같다.
  static const double _portraitLaneH =
      2 * kCols * (_cell * _portraitRatio + _slotPadV * 2) + _laneGap;
  static const double _landscapeBoardH = kRows * (_cell * _landscapeRatio + _slotPadV * 2 + 2);

  @override
  Widget build(BuildContext context) {
    final content = landscape ? _landscapeBoard() : _portraitBoard();
    // SizedBox.expand 필수 — 느슨한 제약 아래의 FittedBox는 자식 크기를 그대로
    // 쓰기 때문에 축소만 되고 확대가 안 된다. 꽉 찬 박스를 줘야 남는 공간만큼
    // 보드가 커진다(가로 모드에서 카드가 작아 보이던 원인).
    return SizedBox.expand(
      child: FittedBox(
        fit: BoxFit.contain,
        child: Padding(padding: const EdgeInsets.all(8), child: content),
      ),
    );
  }

  // ---- 공통 ----

  List<PlayingCard> _cards(PlayerId p, int line) =>
      lineCardsOf?.call(p, line) ??
      [
        for (var col = 0; col < kCols; col++)
          if (cellAt(p, line, col) case final c?) c.card,
      ];

  /// 다음에 카드가 놓일 칸(가운데부터 채움). 꽉 찼으면 -1.
  int _nextCol(PlayerId p, int row) {
    for (var col = 0; col < kCols; col++) {
      if (cellAt(p, row, col) == null) return col;
    }
    return -1;
  }

  Widget _slot(PlayerId owner, int row, int col, {required double ratio}) {
    final concealed = isConcealed?.call(owner, row, col) ?? false;
    return _BoardSlot(
      key: cellKeyFor?.call(owner, row, col),
      placed: concealed ? null : cellAt(owner, row, col),
      look: lookOf?.call(owner, row, col) ?? CellLook.face,
      size: _cell,
      ratio: ratio,
      mine: owner == viewer,
      isNext: col == _nextCol(owner, row),
      highlighted: isHighlighted?.call(owner, row, col) ?? false,
      onTap: () => onCellTap(owner, row, col),
    );
  }

  Widget _pill(int line) =>
      _ScorePill(mine: _cards(viewer, line), theirs: _cards(viewer.other, line));

  // ---- 세로: 레인 보드 ----

  Widget _portraitBoard() {
    return Stack(
      alignment: Alignment.center,
      clipBehavior: Clip.none,
      children: [
        // 골드 중앙 가로선(◆ 캡) — 덱과 무덤을 잇는 운명의 선
        Positioned(
          left: -44,
          right: -44,
          child: Row(
            children: [
              const DiamondCap(),
              Expanded(child: Container(height: 2.6, color: AppColors.gold)),
              const DiamondCap(),
            ],
          ),
        ),
        SizedBox(
          height: _portraitLaneH,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const LaneSeparator(), // 바깥 프레임 선
              for (var l = 0; l < kRows; l++) ...[
                _lane(l),
                const LaneSeparator(),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _lane(int l) {
    final opp = viewer.other;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final i in [4, 3, 2, 1, 0]) _slot(opp, l, i, ratio: _portraitRatio),
              const SizedBox(height: 22), // 골드 선이 지나가는 틈
              for (final i in [0, 1, 2, 3, 4]) _slot(viewer, l, i, ratio: _portraitRatio),
            ],
          ),
          // 레인이 위아래 대칭이라 Stack 중앙 = 틈 중앙. 알약이 골드 선 위에 얹힌다.
          SizedBox(width: 50, child: FittedBox(fit: BoxFit.scaleDown, child: _pill(l))),
        ],
      ),
    );
  }

  // ---- 가로: 상대(왼쪽) | 중앙 열 | 나(오른쪽) ----

  double get _rowH => _cell * _landscapeRatio + 2 * 2; // 셀 높이 + 세로 패딩

  Widget _landscapeBoard() {
    final opp = viewer.other;
    return SizedBox(
      height: _landscapeBoardH,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _sideRows(opp, reversed: true), // 상대: col0이 오른쪽(중앙)에 붙음
          _centerColumn(),
          _sideRows(viewer, reversed: false), // 나: col0이 왼쪽(중앙)에 붙음
        ],
      ),
    );
  }

  Widget _sideRows(PlayerId p, {required bool reversed}) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var row = 0; row < kRows; row++)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final col in reversed ? [4, 3, 2, 1, 0] : [0, 1, 2, 3, 4])
                _slot(p, row, col, ratio: _landscapeRatio),
            ],
          ),
      ],
    );
  }

  Widget _centerColumn() {
    return SizedBox(
      width: _centerW,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          // 골드 중앙 세로선(◆ 캡)
          Positioned(
            top: -14,
            bottom: -14,
            child: Column(
              children: [
                const DiamondCap(),
                Expanded(child: Container(width: 2.6, color: AppColors.gold)),
                const DiamondCap(),
              ],
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var l = 0; l < kRows; l++)
                SizedBox(
                  height: _rowH,
                  child: Center(
                    child: SizedBox(
                      width: _centerW - 6,
                      child: FittedBox(fit: BoxFit.scaleDown, child: _pill(l)),
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

/// 보드 한 칸: 카드(비율 맞춰 표시) 또는 파인 홈 + 브래킷.
class _BoardSlot extends StatelessWidget {
  const _BoardSlot({
    super.key,
    required this.placed,
    required this.size,
    required this.ratio,
    required this.mine,
    required this.isNext,
    required this.highlighted,
    required this.onTap,
    this.look = CellLook.face,
  });

  final PlacedCard? placed;
  final CellLook look;
  final double size;
  final double ratio;
  final bool mine;
  final bool isNext;
  final bool highlighted;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final w = size, h = size * ratio;
    Widget inner;
    if (placed == null) {
      final base = mine ? AppColors.mePrimary : AppColors.oppPrimary;
      final bracket = highlighted
          ? AppColors.gold
          : isNext
              ? base
              : Color.lerp(base, AppColors.slotRecess, 0.62)!;
      inner = Stack(
        fit: StackFit.expand,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: (highlighted || isNext) ? AppColors.slotNext : AppColors.slotRecess,
              borderRadius: BorderRadius.circular(w * 0.14),
              boxShadow: highlighted
                  ? [BoxShadow(color: AppColors.gold.withValues(alpha: 0.45), blurRadius: 10)]
                  : null,
            ),
          ),
          CustomPaint(
            painter: BracketPainter(bracket, strokeWidth: highlighted ? 2.8 : (isNext ? 2.6 : 1.8)),
          ),
        ],
      );
    } else {
      final content = switch (look) {
        CellLook.face => cachedCardFace(placed!.card, size),
        CellLook.back => cachedCardBack(size),
        CellLook.backPeekable => Stack(
            fit: StackFit.expand,
            children: [
              cachedCardBack(size),
              // "여기에 코인을 쓸 수 있다" — 우상단 골드 코인. 솔리드(희미 금지).
              Positioned(
                right: size * 0.06,
                top: size * 0.06,
                child: VeilCoin(size: size * 0.34, filled: true),
              ),
            ],
          ),
        CellLook.peek => PeekCardBack(card: placed!.card, size: size),
        CellLook.sealed => Stack(
            fit: StackFit.expand,
            children: [
              PeekCardBack(card: placed!.card, size: size),
              _SealStamp(size: size),
            ],
          ),
      };
      // 표시 방식이 바뀔 때(뒷면→앞면 공개 등) 가로로 눌렸다 펴지는 플립.
      // 칸이 비어 있다 처음 채워질 때는 스위처가 새로 만들어져 애니메이션이 없다
      // (기존 게임의 배치 연출·골든에 영향을 주지 않는다).
      // peek↔sealed(봉인 지정/해제)는 카드가 뒤집히는 게 아니므로 플립 없이
      // 도장 자체의 등장 연출만 쓴다 — 키를 "앞면인가"로만 나눈 이유.
      final card = AnimatedSwitcher(
        duration: const Duration(milliseconds: 240),
        transitionBuilder: (child, anim) => AnimatedBuilder(
          animation: anim,
          builder: (context, _) => Transform(
            alignment: Alignment.center,
            transform: Matrix4.diagonal3Values(anim.value.clamp(0.0, 1.0), 1, 1),
            child: child,
          ),
        ),
        layoutBuilder: (current, previous) => Stack(
          fit: StackFit.expand,
          children: [...previous, if (current != null) current],
        ),
        child: FittedBox(
          key: ValueKey('${look == CellLook.face}-${placed!.card.label}'),
          fit: BoxFit.fill, // 원비율 카드를 칸 비율로 살짝 스트레치(세로 공간 확보)
          child: SizedBox(
            width: size,
            height: CardFace.heightFor(size),
            child: content,
          ),
        ),
      );
      inner = highlighted
          ? Stack(
              fit: StackFit.expand,
              children: [
                card,
                IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(w * 0.16),
                      border: Border.all(color: AppColors.gold, width: 2.6),
                      boxShadow: [
                        BoxShadow(color: AppColors.gold.withValues(alpha: 0.5), blurRadius: 12),
                      ],
                    ),
                  ),
                ),
              ],
            )
          : card;
    }
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
        child: SizedBox(width: w, height: h, child: inner),
      ),
    );
  }
}

/// 비공개권 코인 — "숨기거나 열어볼 기회"의 물성 있는 표현.
///
/// [filled]면 브라스 코인(잉크 눈감김 각인), 아니면 **쓴 자리**(파인 소켓).
/// 전부 불투명 단색 — 이 게임의 UI 원칙(반투명 금지)을 따른다.
class VeilCoin extends StatelessWidget {
  const VeilCoin({super.key, required this.size, required this.filled, this.ring});

  final double size;
  final bool filled;

  /// 코인 가장자리 링 색(내/상대 구분). null이면 브라스.
  final Color? ring;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 240),
      transitionBuilder: (child, anim) =>
          ScaleTransition(scale: anim, child: child),
      child: filled
          ? Container(
              key: const ValueKey('coin'),
              width: size,
              height: size,
              decoration: BoxDecoration(
                color: AppColors.gold,
                shape: BoxShape.circle,
                border: Border.all(color: ring ?? AppColors.goldSoft, width: 2),
                boxShadow: [
                  BoxShadow(
                      color: AppColors.ink.withValues(alpha: 0.45),
                      blurRadius: 4,
                      offset: const Offset(0, 1.5)),
                ],
              ),
              child: Icon(Icons.visibility_off_rounded,
                  color: AppColors.ink, size: size * 0.58),
            )
          : Container(
              key: const ValueKey('socket'),
              width: size,
              height: size,
              decoration: BoxDecoration(
                color: AppColors.slotRecess,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.stroke, width: 1.6),
              ),
            ),
    );
  }
}

/// 봉인 도장 — 숨김 지정의 시각 언어.
///
/// 지정하는 순간 브라스 실링 도장이 **쿵 찍히고**(1.7배에서 오버슛으로 안착),
/// 골드 테두리가 카드를 감싼다. "이 카드는 공개 때 덮인 채 남는다"를 도장 하나로
/// 말한다. 해제하면 도장째 사라진다(스위처가 즉시 제거).
class _SealStamp extends StatelessWidget {
  const _SealStamp({required this.size});
  final double size;

  @override
  Widget build(BuildContext context) {
    final d = size * 0.56; // 도장 지름
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutBack,
      builder: (context, t, child) {
        final scale = 1.7 - 0.7 * t; // 위에서 내려와 찍히는 느낌
        return Stack(
          fit: StackFit.expand,
          children: [
            // 카드를 감싸는 골드 링 + 글로우 (도장이 찍히며 함께 조여든다)
            IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(size * 0.16),
                  border: Border.all(
                      color: AppColors.gold, width: 1.6 + 1.2 * t),
                  boxShadow: [
                    BoxShadow(
                        color: AppColors.gold.withValues(alpha: 0.45 * t),
                        blurRadius: 12),
                  ],
                ),
              ),
            ),
            Center(
              child: Opacity(
                opacity: t.clamp(0.0, 1.0),
                child: Transform.rotate(
                  angle: -0.12 * (1 - t) - 0.06, // 살짝 비스듬히 찍힌 도장
                  child: Transform.scale(scale: scale, child: child),
                ),
              ),
            ),
          ],
        );
      },
      child: Container(
        width: d,
        height: d,
        decoration: BoxDecoration(
          color: AppColors.gold,
          shape: BoxShape.circle,
          border: Border.all(color: AppColors.goldSoft, width: 2),
          boxShadow: [
            BoxShadow(
                color: AppColors.ink.withValues(alpha: 0.5),
                blurRadius: 6,
                offset: const Offset(0, 2)),
          ],
        ),
        child: Icon(Icons.visibility_off_rounded,
            color: AppColors.ink, size: d * 0.55),
      ),
    );
  }
}

/// 라인 점수 알약: [상대 | 승패 바 | 나]. 점수/승패가 바뀔 때 탄성 있게 튕긴다.
class _ScorePill extends StatelessWidget {
  const _ScorePill({required this.mine, required this.theirs});
  final List<PlayingCard> mine;
  final List<PlayingCard> theirs;

  @override
  Widget build(BuildContext context) {
    final o = compareLine(mine, theirs);
    final color = switch (o) {
      LineOutcome.win => AppColors.win,
      LineOutcome.lose => AppColors.lose,
      LineOutcome.tie => AppColors.tie,
    };
    final myScore = lineScore(mine);
    final oppScore = lineScore(theirs);

    Widget num(int v, Color c, bool strong) => Text('$v',
        style: TextStyle(
          color: c,
          fontWeight: strong ? FontWeight.w900 : FontWeight.w700,
          fontSize: strong ? 17 : 14,
          height: 1,
        ));

    return TweenAnimationBuilder<double>(
      // 점수/승패가 바뀌면 key가 바뀌어 0.7 → 1.0 탄성 스케일로 튕긴다.
      key: ValueKey('$myScore-$oppScore-$o'),
      tween: Tween(begin: 0.7, end: 1),
      duration: const Duration(milliseconds: 450),
      curve: Curves.elasticOut,
      builder: (context, v, child) => Transform.scale(scale: v, child: child),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color, width: 2),
          boxShadow: [BoxShadow(color: color.withValues(alpha: 0.45), blurRadius: 10)],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            num(oppScore, AppColors.oppPrimary, o == LineOutcome.lose),
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 6),
              width: 3,
              height: 12,
              decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2)),
            ),
            num(myScore, AppColors.mePrimary, o == LineOutcome.win),
          ],
        ),
      ),
    );
  }
}
