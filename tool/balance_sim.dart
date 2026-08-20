// 토큰 밸런스 검증 셀프플레이 (MONETIZATION.md §7).
//
// 질문: "쉴드 토큰 1개 + 공격 표식 토큰 1개(= GameRules.standard)를 쓸 수 있는
// 플레이어는, 못 쓰는 플레이어를 상대로 얼마나 더 이기는가?"
//
// 방법:
// - 같은 HeuristicAi 기풍끼리 대결. 한쪽만 GameRules.standard + 아래 토큰 정책.
// - 좌석(선공 배분) 편향 제거: 같은 시드로 좌석을 바꿔 2판씩(페어) 돌린다.
// - 대조군: 둘 다 토큰 없음 → 측정 자체의 노이즈/좌석 편향 크기 확인.
//
// 토큰 정책(합리적인 유저 근사):
// - 표식: 공격 불가능한 손패 카드가 상대 필드의 제거 가능한 카드와 숫자가 같고
//   내 빈 칸이 있으면, 그 대상 랭크가 9(=9) 이상이거나 종반(덱 ≤ 10장)일 때 붙인다.
// - 쉴드 선언: 내 필드의 제거 가능한 카드 중 페어 이상에 기여하는 랭크 J+ 카드가
//   생기면 즉시, 아니면 종반(덱 ≤ 10장)에 10+ 카드에 선언한다.
//
// 실행: dart run tool/balance_sim.dart [판수/조건, 기본 1000]

// ignore_for_file: avoid_print — CLI 도구라 print가 곧 출력이다.

import 'dart:math';

import 'package:score_poker/domain/ai_strategy.dart';
import 'package:score_poker/domain/card.dart';
import 'package:score_poker/domain/game.dart';
import 'package:score_poker/domain/hand.dart';
import 'package:score_poker/domain/scoring.dart';

void main(List<String> args) {
  final pairs = (args.isNotEmpty ? int.parse(args[0]) : 1000) ~/ 2;

  final styles = <String, AiStyle>{
    'clode(수비형)': AiStyle.clode,
    'jenna(중간형)': AiStyle.jenna,
    'het(공격형)': AiStyle.het,
  };

  print('시드 페어 수: $pairs (판수 ${pairs * 2}/조건, 좌석 스왑 포함)\n');

  // directed=true: 표식을 "명백히 이득인 공격"(내 페어 완성 또는 상대 페어 파괴)이
  // 가능할 때만 쓰고, 그 공격을 직접 지시한다 — 잘 쓰는 유저의 상한 추정.
  const conditions = <String, (GameRules, bool, bool)>{
    '대조군(무토큰)': (GameRules.none, false, false),
    '쉴드만': (GameRules(shieldDeclarations: 1), false, false),
    '표식만(AI 방임)': (GameRules(attackMarks: 1), false, false),
    '표식만(지향 공격)': (GameRules(attackMarks: 1), true, false),
    '표식만(지향·종반만)': (GameRules(attackMarks: 1), true, true),
    '둘 다(지향·종반)': (GameRules.standard, true, true),
  };

  for (final entry in styles.entries) {
    print('=== 기풍: ${entry.key} ===');
    _Tally? control;
    for (final cond in conditions.entries) {
      final t = _runCondition(
        label: cond.key,
        style: entry.value,
        pairs: pairs,
        tokenSideRules: cond.value.$1,
        directed: cond.value.$2,
        lateOnly: cond.value.$3,
      );
      control ??= t;
      _printRow(t);
      if (t != control) {
        final delta = t.winRate - control.winRate;
        print('   → 효과 ${_pct(delta)}p (±${_pct(1.96 * _seDiff(control, t))}p, 95% CI)');
      }
    }
    print('');
  }
}

class _Tally {
  _Tally(this.label);
  final String label;
  int win = 0, lose = 0, draw = 0, error = 0;
  int shieldUses = 0, markUses = 0, turnsTotal = 0, games = 0;
  int deckEmpty = 0; // 덱 소진 종료 판 수
  final Map<HandCategory, int> lineCats = {}; // 종료 시 전체 줄 족보 분포

  double get winRate => games == 0 ? 0 : win / games;
}

double _seDiff(_Tally a, _Tally b) {
  double v(_Tally t) => t.winRate * (1 - t.winRate) / t.games;
  return sqrt(v(a) + v(b));
}

String _pct(double x) => '${(x * 100).toStringAsFixed(1)}%';

void _printRow(_Tally t) {
  print('${t.label.padRight(24)} 승 ${_pct(t.winRate)}  '
      '무 ${_pct(t.draw / t.games)}  패 ${_pct(t.lose / t.games)}  '
      '(n=${t.games}, 평균 ${(t.turnsTotal / t.games).toStringAsFixed(1)}턴, '
      '덱소진 ${_pct(t.deckEmpty / t.games)}, '
      '쉴드사용 ${_pct(t.shieldUses / t.games)}, 표식사용 ${_pct(t.markUses / t.games)}'
      '${t.error > 0 ? ', 오류 ${t.error}' : ''})');
  final totalLines = t.lineCats.values.fold(0, (a, b) => a + b);
  if (totalLines > 0) {
    final parts = HandCategory.values.reversed
        .where((c) => (t.lineCats[c] ?? 0) > 0)
        .map((c) => '${c.name} ${_pct((t.lineCats[c] ?? 0) / totalLines)}')
        .join(' / ');
    print('    줄 족보 분포: $parts');
  }
}

_Tally _runCondition({
  required String label,
  required AiStyle style,
  required int pairs,
  required GameRules tokenSideRules,
  required bool directed,
  required bool lateOnly,
}) {
  final tally = _Tally(label);
  for (var i = 0; i < pairs; i++) {
    // 같은 시드로 좌석을 바꿔 2판 — 선공/덱 운 편향 상쇄.
    for (final tokenSeat in PlayerId.values) {
      _playOne(
        seed: i,
        style: style,
        tokenSeat: tokenSeat,
        tokenRules: tokenSideRules,
        directed: directed,
        lateOnly: lateOnly,
        tally: tally,
      );
    }
  }
  return tally;
}

void _playOne({
  required int seed,
  required AiStyle style,
  required PlayerId tokenSeat,
  required GameRules tokenRules,
  required bool directed,
  required bool lateOnly,
  required _Tally tally,
}) {
  final s = GameState.deal(seed: seed, rules: {tokenSeat: tokenRules});
  final ais = {
    // AI 내부 난수 시드도 좌석과 무관하게 재현되도록 고정.
    PlayerId.p0: HeuristicAi(style, seed: seed * 2 + 1),
    PlayerId.p1: HeuristicAi(style, seed: seed * 2 + 2),
  };

  // 오픈: 조커가 아닌 카드 중 가장 높은 것 (양쪽 동일 정책).
  int reveal(PlayerId p) {
    final hand = s.hands[p]!;
    var best = 0;
    for (var i = 1; i < hand.length; i++) {
      if (hand[i].isJoker) continue;
      if (hand[best].isJoker || hand[i].rank > hand[best].rank) best = i;
    }
    return best;
  }

  s.revealForFirstTurn(reveal(PlayerId.p0), reveal(PlayerId.p1));

  var turns = 0;
  var usedShield = false, usedMark = false;
  while (!s.isFinished && turns < 500) {
    turns++;
    final p = s.current;

    // ---- 토큰 정책 (턴을 소모하지 않으므로 decide 전에 시도) ----
    if (p == tokenSeat && !s.pendingBonus) {
      if (!usedShield && s.shieldDeclarationsLeft(p) > 0 && _tryShield(s, p)) {
        usedShield = true;
        tally.shieldUses++;
      }
      if (!usedMark && s.attackMarksLeft(p) > 0 && (!lateOnly || s.deckRemaining <= 14)) {
        if (directed) {
          if (_tryDirectedMarkAttack(s, p)) {
            usedMark = true;
            tally.markUses++;
            continue; // 공격까지 지시했으므로 이 반복에서는 decide를 건너뛴다.
          }
        } else if (_tryMark(s, p)) {
          usedMark = true;
          tally.markUses++;
        }
      }
    }

    AiMove move;
    try {
      move = ais[p]!.decide(s, p);
    } on Object {
      move = const FoldMove();
    }
    try {
      switch (move) {
        case PlaceMove(
            :final handIndex,
            :final target,
            :final row,
            :final col,
            :final jokerRank,
            :final jokerSuit
          ):
          s.placeCard(handIndex, target, row, col, jokerRank: jokerRank, jokerSuit: jokerSuit);
        case AttackMove(:final handIndex, :final row, :final col, :final myRow, :final myCol):
          s.attack(handIndex, row, col, myRow, myCol);
        case FoldMove():
          if (s.pendingBonus) {
            s.passBonus();
          } else {
            s.fold();
          }
      }
    } on IllegalMove {
      // AI가 비합법 수를 내면(버그) 그 판은 폴드 처리하고 오류로 센다.
      tally.error++;
      try {
        s.fold();
      } on Object {
        break;
      }
    }
  }

  final r = s.result(tokenSeat);
  tally.games++;
  tally.turnsTotal += turns;
  if (s.deckRemaining == 0) tally.deckEmpty++;
  for (final p in PlayerId.values) {
    for (final row in s.fields[p]!) {
      final cards = [for (final c in row) if (c != null) c.card];
      final cat = evaluateHand(cards).category;
      tally.lineCats[cat] = (tally.lineCats[cat] ?? 0) + 1;
    }
  }
  switch (r.outcome) {
    case MatchOutcome.win:
      tally.win++;
    case MatchOutcome.lose:
      tally.lose++;
    case MatchOutcome.draw:
      tally.draw++;
  }
}

/// 표식 정책: 상대의 제거 가능한 카드와 숫자가 같은 배치 전용 손패 카드가 있고
/// 내 빈 칸이 있으면 표식. 대상 랭크 9+ 또는 종반(덱 ≤ 10)일 때만.
bool _tryMark(GameState s, PlayerId p) {
  if (!_hasEmptyCell(s, p)) return false;
  final oppField = s.fields[p.other]!;
  final hand = s.hands[p]!;

  var bestIdx = -1, bestRank = -1;
  for (var i = 0; i < hand.length; i++) {
    final c = hand[i];
    if (c.canAttack || c.isShield || c.isJoker) continue;
    // 이 랭크로 칠 수 있는 상대 카드가 있는가?
    var hit = false;
    for (final row in oppField) {
      for (final cell in row) {
        if (cell != null && cell.removableByNormal && cell.card.rank == c.rank) hit = true;
      }
    }
    if (hit && c.rank > bestRank) {
      bestRank = c.rank;
      bestIdx = i;
    }
  }
  if (bestIdx < 0) return false;
  final endgame = s.deckRemaining <= 10;
  if (bestRank < 9 && !endgame) return false;
  s.markAttacker(bestIdx);
  return true;
}

/// 쉴드 정책: 페어 이상에 기여하는 J+ 카드가 생기면 즉시,
/// 아니면 종반(덱 ≤ 10)에 10+ 카드에 선언.
bool _tryShield(GameState s, PlayerId p) {
  final field = s.fields[p]!;
  final endgame = s.deckRemaining <= 10;

  int bestRow = -1, bestCol = -1, bestRank = -1;
  for (var r = 0; r < kRows; r++) {
    // 이 줄의 랭크 분포(페어 판정용).
    final counts = <int, int>{};
    for (final cell in field[r]) {
      if (cell != null) counts[cell.card.rank] = (counts[cell.card.rank] ?? 0) + 1;
    }
    for (var c = 0; c < kCols; c++) {
      final cell = field[r][c];
      if (cell == null || !cell.removableByNormal) continue;
      final rank = cell.card.rank;
      final inPair = (counts[rank] ?? 0) >= 2;
      final eligible = (inPair && rank >= Ranks.jack) || (endgame && rank >= 10);
      if (eligible && rank > bestRank) {
        bestRank = rank;
        bestRow = r;
        bestCol = c;
      }
    }
  }
  if (bestRow < 0) return false;
  s.declareShield(bestRow, bestCol);
  return true;
}

bool _hasEmptyCell(GameState s, PlayerId p) {
  for (final row in s.fields[p]!) {
    for (final cell in row) {
      if (cell == null) return true;
    }
  }
  return false;
}

/// 지향 공격: "명백히 이득"일 때만 표식을 쓰고 그 공격을 직접 실행한다.
///
/// 이득 판정(둘 중 하나 이상):
/// - (a) 빼앗은 카드를 내 필드의 같은 숫자 옆에 둘 수 있다 → 내 페어/트리플 완성.
/// - (b) 대상이 상대 줄의 페어 이상에 기여 중이다 → 상대 족보 파괴.
bool _tryDirectedMarkAttack(GameState s, PlayerId p) {
  final hand = s.hands[p]!;
  final myField = s.fields[p]!;
  final oppField = s.fields[p.other]!;

  // 내 필드 줄별 랭크 분포 / 빈 칸.
  final myCounts = List.generate(kRows, (r) {
    final m = <int, int>{};
    for (final cell in myField[r]) {
      if (cell != null) m[cell.card.rank] = (m[cell.card.rank] ?? 0) + 1;
    }
    return m;
  });
  final oppCounts = List.generate(kRows, (r) {
    final m = <int, int>{};
    for (final cell in oppField[r]) {
      if (cell != null) m[cell.card.rank] = (m[cell.card.rank] ?? 0) + 1;
    }
    return m;
  });

  (int, int)? emptyInRow(int r) {
    for (var c = 0; c < kCols; c++) {
      if (myField[r][c] == null) return (r, c);
    }
    return null;
  }

  var bestScore = 0;
  int? weaponIdx;
  (int, int)? target;
  (int, int)? dest;

  for (var i = 0; i < hand.length; i++) {
    final w = hand[i];
    if (w.canAttack || w.isShield || w.isJoker) continue; // 표식 대상만
    for (var tr = 0; tr < kRows; tr++) {
      for (var tc = 0; tc < kCols; tc++) {
        final cell = oppField[tr][tc];
        if (cell == null || !cell.removableByNormal) continue;
        if (cell.card.rank != w.rank) continue;
        final rank = cell.card.rank;

        var score = 0;
        (int, int)? myDest;
        // (a) 내 페어 완성: 같은 랭크가 이미 있는 줄의 빈 칸.
        for (var mr = 0; mr < kRows; mr++) {
          if ((myCounts[mr][rank] ?? 0) >= 1) {
            final e = emptyInRow(mr);
            if (e != null) {
              score += 2 + rank ~/ 5;
              myDest = e;
              break;
            }
          }
        }
        // (b) 상대 페어 파괴.
        if ((oppCounts[tr][rank] ?? 0) >= 2) score += 2;
        if (score <= 1) continue;

        // 목적지가 없으면(페어 완성 불가) 아무 빈 칸 — 단 (b)가 성립할 때만 온 경로.
        myDest ??= () {
          for (var mr = 0; mr < kRows; mr++) {
            final e = emptyInRow(mr);
            if (e != null) return e;
          }
          return null;
        }();
        if (myDest == null) continue;

        if (score > bestScore) {
          bestScore = score;
          weaponIdx = i;
          target = (tr, tc);
          dest = myDest;
        }
      }
    }
  }

  if (weaponIdx == null) return false;
  s.markAttacker(weaponIdx);
  s.attack(weaponIdx, target!.$1, target.$2, dest!.$1, dest.$2);
  return true;
}
