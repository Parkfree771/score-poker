import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../domain/card.dart';
import '../../domain/game.dart';
import '../../domain/hand.dart';
import '../../domain/scoring.dart';
import '../../l10n/app_localizations.dart';
import '../hand_text.dart';
import '../theme.dart';
import 'card_back.dart';
import 'card_face.dart';
import 'table_decor.dart';
import 'veil_chip.dart' show ChipBadge;
import 'veil_shimmer.dart';

/// 보드 칸의 표시 방식.
///
/// 기본 게임은 전부 [face]. 가림 룰은 상대의 미공개 카드를 [back](뒷면)으로,
/// 그중 지금 코인으로 열어볼 수 있는 카드를 [backPeekable](뒷면 + 골드 코인 마커)로,
/// 나의 미공개 카드를 [peek](뒷면 + 들린 모서리로 나만 확인)으로,
/// 숨김 지정된 내 카드를 [sealed](peek + 브라스 봉인 도장)로 그린다.
/// 칸의 표현 방식.
/// - [back] 이번 라운드에 놓여 아직 안 뒤집힌 상대 카드(곧 공개된다)
/// - [backVeiled] 상대가 **비공개권으로 덮어 둔** 카드 — 검은 일렁거림
/// - [backPeekable] 위와 같되 지금 내 코인으로 열어볼 수 있는 카드 — 어둠이 빨라지고
///   틈에서 불씨가 샌다(배지를 붙이지 않는다)
/// - [peek] 내 미공개 카드(홀카드 필) · [sealed] 내가 숨기기로 지정한 카드
enum CellLook { face, back, backVeiled, backPeekable, peek, sealed }

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
    this.chipOn,
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

  /// 칸 위에 **앉아 있는 칩**의 주인 색. 숨긴 카드(내 봉인·상대 뒷면)와 비공개권으로
  /// 열어본 카드에 붙는다 — "여기에 칩이 쓰였다"는 표시. null이면 없음.
  final Color? Function(PlayerId owner, int row, int col)? chipOn;
  final GlobalKey Function(PlayerId owner, int row, int col)? cellKeyFor;
  final bool landscape;

  static const double _cell = 58;
  static const double _portraitRatio = 1.26; // 세로: 폭 확보를 위해 살짝 낮은 비율
  static const double _landscapeRatio = 1.36; // 가로: 원비율
  static const double _centerW = 66; // 가로 모드 중앙 점수 열 폭
  static const double _slotPadV = 1; // _BoardSlot 세로 패딩(위/아래 각각)
  // 세로 모드에서 골드 선·점수 알약이 앉는 틈. 알약은 **이 안에만** 그려진다 —
  // 카드를 덮으면 안 되므로 알약을 키우고 싶으면 이 값을 키운다.
  static const double _laneGap = 54;
  static const double _pillW = 84;

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
      veilPhase: veilPhaseFor(row, col),
      chip: chipOn?.call(owner, row, col),
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
              const SizedBox(height: _laneGap), // 골드 선·점수 알약이 앉는 틈
              for (final i in [0, 1, 2, 3, 4]) _slot(viewer, l, i, ratio: _portraitRatio),
            ],
          ),
          // 레인이 위아래 대칭이라 Stack 중앙 = 틈 중앙. 알약이 골드 선 위에 얹힌다.
          // **IgnorePointer 필수** — 알약은 카드 위에 겹쳐 그려지므로, 이게 없으면
          // 알약에 가린 가운데 칸의 탭을 알약이 먹어버려 카드를 놓을 수 없다.
          IgnorePointer(
            child: SizedBox(
                width: _pillW,
                height: _laneGap - 4,
                child: FittedBox(fit: BoxFit.scaleDown, child: _pill(l))),
          ),
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
                    child: IgnorePointer(
                      child: SizedBox(
                        width: _centerW - 6,
                        height: _rowH - 8,
                        child: FittedBox(fit: BoxFit.scaleDown, child: _pill(l)),
                      ),
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
    this.veilPhase = 0,
    this.chip,
  });

  final PlacedCard? placed;
  final CellLook look;

  /// 카드 위에 앉힐 칩의 주인 색(null이면 칩 없음).
  final Color? chip;
  final double size;
  final double ratio;
  final bool mine;
  final bool isNext;
  final bool highlighted;

  /// 검은 일렁거림의 시작 위상(칸마다 어긋나게).
  final double veilPhase;

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
      final phase = veilPhase;
      final content = switch (look) {
        CellLook.face => cachedCardFace(placed!.card, size),
        CellLook.back => cachedCardBack(size),
        // 덮어 둔 카드는 그늘에 잠겨 일렁인다 — 아이콘으로 말하지 않는다.
        CellLook.backVeiled => Stack(
            fit: StackFit.expand,
            children: [
              cachedCardBack(size),
              VeilShimmer(radius: size * 0.16, phase: phase),
            ],
          ),
        // 열 수 있는 카드에는 **아무것도 붙이지 않는다**. 어둠이 빨라지고 틈에서
        // 불씨가 새는 것으로 "여기에 코인을 쓸 수 있다"를 말한다.
        CellLook.backPeekable => Stack(
            fit: StackFit.expand,
            children: [
              cachedCardBack(size),
              VeilShimmer(
                  radius: size * 0.16, phase: phase, mood: VeilMood.restless),
            ],
          ),
        CellLook.peek => PeekCardBack(card: placed!.card, size: size),
        // 봉인 = 카드가 어둠에 잠기고 그 위에 **칩이 앉는다**(아래 chip 오버레이).
        CellLook.sealed => PeekCardBack(
            card: placed!.card, size: size, veiled: true, veilPhase: phase),
      };
      // 표시 방식이 바뀔 때(뒷면→앞면 공개 등) 가로로 눌렸다 펴지는 플립.
      // 칸이 비어 있다 처음 채워질 때는 스위처가 새로 만들어져 애니메이션이 없다
      // (기존 게임의 배치 연출·골든에 영향을 주지 않는다).
      // peek↔sealed(봉인 지정/해제)는 카드가 뒤집히는 게 아니므로 플립 없이
      // 도장 자체의 등장 연출만 쓴다 — 키를 "앞면인가"로만 나눈 이유.
      // 열어본 카드(칩이 앉은 앞면)는 플립하지 않는다 — 뒷면이 쳐내져 날아가는
      // 오버레이가 이미 "드러남"을 말했다. 두 번 뒤집으면 촌스럽다.
      final peeked = chip != null && look == CellLook.face;
      final card = AnimatedSwitcher(
        duration: peeked ? Duration.zero : const Duration(milliseconds: 240),
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
      // 칩은 카드 오른쪽 위 모서리에 걸쳐 앉는다. 봉인 지정 순간은 위에서 내려와
      // 툭 안착(land), 그 외(지난 라운드 숨김·상대 뒷면·열어본 카드)는 그냥 놓여 있다.
      final chipped = chip == null
          ? card
          : Stack(
              fit: StackFit.expand,
              clipBehavior: Clip.none,
              children: [
                card,
                Align(
                  alignment: const Alignment(0.82, -0.74),
                  child: IgnorePointer(
                    child: ChipBadge(
                        key: ValueKey('chip-${look == CellLook.sealed}'),
                        size: size * 0.4,
                        ring: chip,
                        land: look == CellLook.sealed),
                  ),
                ),
              ],
            );
      inner = highlighted
          ? Stack(
              fit: StackFit.expand,
              children: [
                chipped,
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
          : chipped;
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
/// [filled]면 브라스 코인(잉크 마름모 각인), 아니면 **쓴 자리**(파인 소켓).
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
              child: Center(child: _CoinMark(size: size * 0.42)),
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
class SealStamp extends StatelessWidget {
  const SealStamp({super.key, required this.size});
  final double size;

  @override
  Widget build(BuildContext context) {
    final d = size * 0.46; // 도장 지름 — 들린 모서리(랭크)를 가리지 않을 만큼만
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutBack,
      builder: (context, t, child) {
        final scale = 1.7 - 0.7 * t; // 위에서 내려와 찍히는 느낌
        return Stack(
          fit: StackFit.expand,
          children: [
            // 카드를 감싸는 골드 링 (도장이 찍히며 함께 조여든다).
            // **글로우(boxShadow) 금지** — 속이 빈 상자의 그림자는 카드 안쪽까지
            // 금빛으로 덮어버려서, 정작 "덮어 뒀다"는 어둠을 지워버린다.
            IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(size * 0.16),
                  border: Border.all(
                      color: AppColors.gold, width: 1.6 + 1.2 * t),
                ),
              ),
            ),
            Align(
              alignment: const Alignment(-0.15, -0.28),
              child: 
              Opacity(
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
        child: Center(child: _CoinMark(size: d * 0.44)),
      ),
    );
  }
}

/// 브라스 각인 — 코인·봉인 도장에 새기는 마름모(테이블 프레임의 ◆와 같은 언어).
/// 눈 아이콘은 쓰지 않는다: "숨겼다"는 아이콘이 아니라 카드 위의 어둠이 말한다.
class _CoinMark extends StatelessWidget {
  const _CoinMark({required this.size});
  final double size;

  @override
  Widget build(BuildContext context) => Transform.rotate(
        angle: math.pi / 4,
        child: Container(
          width: size * 0.72,
          height: size * 0.72,
          decoration: BoxDecoration(
            color: AppColors.ink,
            borderRadius: BorderRadius.circular(size * 0.12),
          ),
        ),
      );
}

/// 라인 점수 알약 — **족보 이름 + 숫자값**을 위(상대)/아래(나)로 겹쳐 보여준다.
///
/// 숫자만 있으면 "42가 25를 이긴다"는 알아도 **무엇으로 이기는지**를 모른다.
/// 트리플로 앞서는 것과 하이카드로 앞서는 것은 남은 칸의 가치가 전혀 다르다.
/// 하이카드는 이름을 적지 않는다(알려주는 게 없고 알약만 좁아진다).
///
/// 가림 룰에서는 [BoardView.lineCardsOf]가 **공개된 카드만** 넘기므로,
/// 이 알약은 숨긴 정보를 절대 흘리지 않는다.
class _ScorePill extends StatelessWidget {
  const _ScorePill({required this.mine, required this.theirs});
  final List<PlayingCard> mine;
  final List<PlayingCard> theirs;

  @override
  Widget build(BuildContext context) {
    final o = compareLine(mine, theirs);
    final tint = switch (o) {
      LineOutcome.win => AppColors.win,
      LineOutcome.lose => AppColors.lose,
      LineOutcome.tie => AppColors.tie,
    };
    final myScore = lineScore(mine);
    final oppScore = lineScore(theirs);
    // 로컬라이제이션이 없는 환경(단독 위젯 테스트)에서는 이름 없이 숫자만 보여준다.
    final l10n = Localizations.of<AppLocalizations>(context, AppLocalizations);

    // 펠트 위의 브라스 명패. 흰 배경·네온 글로우는 판과 따로 놀았다 —
    // 표면은 판과 같은 어두운 초록, 테두리는 브라스, 승패는 점수 색과 가운데 눈금으로만.
    Widget side(List<PlayingCard> cards, int score, bool strong) {
      final name = (l10n == null || cards.isEmpty)
          ? null
          : handCategoryShort(l10n, evaluateHand(cards).category);
      return Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (name != null) ...[
            Text(name,
                style: const TextStyle(
                    color: AppColors.inkSoft,
                    fontWeight: FontWeight.w700,
                    fontSize: 8.5,
                    height: 1)),
            const SizedBox(width: 4),
          ],
          Text('$score',
              style: TextStyle(
                color: strong ? AppColors.goldSoft : AppColors.textMain,
                fontWeight: strong ? FontWeight.w900 : FontWeight.w700,
                fontSize: strong ? 13 : 11.5,
                height: 1,
                fontFeatures: const [FontFeature.tabularFigures()],
              )),
        ],
      );
    }

    return TweenAnimationBuilder<double>(
      // 점수/승패가 바뀌면 key가 바뀌어 0.7 → 1.0 탄성 스케일로 튕긴다.
      key: ValueKey('$myScore-$oppScore-$o'),
      tween: Tween(begin: 0.7, end: 1),
      duration: const Duration(milliseconds: 450),
      curve: Curves.elasticOut,
      builder: (context, v, child) => Transform.scale(scale: v, child: child),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: AppColors.gold.withValues(alpha: 0.85), width: 1.2),
          boxShadow: [
            BoxShadow(
                color: AppColors.ink.withValues(alpha: 0.5),
                blurRadius: 6,
                offset: const Offset(0, 2)),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 위가 상대, 아래가 나 — 세로 보드의 위아래 배치와 같은 순서다.
            side(theirs, oppScore, o == LineOutcome.lose),
            Container(
              margin: const EdgeInsets.symmetric(vertical: 2.5),
              width: 26,
              height: 2,
              decoration:
                  BoxDecoration(color: tint, borderRadius: BorderRadius.circular(2)),
            ),
            side(mine, myScore, o == LineOutcome.win),
          ],
        ),
      ),
    );
  }
}
