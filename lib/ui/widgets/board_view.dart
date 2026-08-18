import 'package:flutter/material.dart';

import '../../domain/card.dart';
import '../../domain/game.dart';
import '../../domain/scoring.dart';
import '../theme.dart';
import 'card_face.dart';
import 'table_decor.dart';

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
    required this.state,
    required this.viewer,
    required this.onCellTap,
    this.isHighlighted,
    this.cellKeyFor,
    this.landscape = false,
  });

  final GameState state;
  final PlayerId viewer;
  final void Function(PlayerId owner, int row, int col) onCellTap;
  final bool Function(PlayerId owner, int row, int col)? isHighlighted;
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
      [for (final c in state.fields[p]![line]) if (c != null) c.card];

  /// 다음에 카드가 놓일 칸(가운데부터 채움). 꽉 찼으면 -1.
  int _nextCol(PlayerId p, int row) {
    for (var col = 0; col < kCols; col++) {
      if (state.fields[p]![row][col] == null) return col;
    }
    return -1;
  }

  Widget _slot(PlayerId owner, int row, int col, {required double ratio}) {
    return _BoardSlot(
      key: cellKeyFor?.call(owner, row, col),
      placed: state.fields[owner]![row][col],
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
  });

  final PlacedCard? placed;
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
      final card = FittedBox(
        fit: BoxFit.fill, // 원비율 카드를 칸 비율로 살짝 스트레치(세로 공간 확보)
        child: SizedBox(
          width: size,
          height: CardFace.heightFor(size),
          child: cachedCardFace(placed!.card, size),
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
