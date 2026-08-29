import 'dart:math';

import 'card.dart';
import 'game.dart';
import 'hand.dart';

/// AI 기풍. 페르소나(크로드/헷/제나…)와 1:1로 묶인다.
enum AiStyle {
  /// 크로드 — 침착한 수비형. 세 줄을 고르게 키우고, 공격·칩은 확실할 때만.
  clode,

  /// 헷 — 공격형. 기회가 보이면 쳐낸다. 칩을 일찍 태운다.
  het,

  /// 제나 — 변칙형. 배치가 튀고, 값어치 없는 카드도 숨겨 허세를 부린다.
  jenna,

  /// 딥시 — 계산형. 족보를 부수는 공격만 하고, 이득이 확실한 카드만 숨긴다.
  dipsy,

  /// 그록 — 도발형. 숨기고, 훔쳐보고, 방어막을 상대 줄에 즐겨 꽂는다.
  grok,

  /// 미스트 — 속공형. 두 줄에 빠르게 몰아주고 일찍 숨긴다.
  mist,
}

/// 기풍별 행동 계수. 룰은 하나지만 **행동이 다르면 다른 상대로 느껴진다**.
class AiProfile {
  const AiProfile({
    required this.sacrificeWeakRow,
    required this.balance,
    required this.noise,
    required this.attackThreshold,
    required this.hideMinGain,
    required this.bluffChance,
    required this.reserveForPeek,
    required this.peekChance,
    required this.harassBias,
  });

  /// 가장 약한 줄을 버리고 남은 두 줄에 몰아주는 정도(0~1).
  final double sacrificeWeakRow;

  /// 빈 칸이 많은 줄을 선호하는 정도(0~1) — 높을수록 세 줄이 고르게 찬다.
  final double balance;

  /// 배치 점수에 섞는 무작위성 — 높을수록 수를 읽기 어렵다.
  final double noise;

  /// 공격에 필요한 최소 파괴량(줄 세기 하락). 100 = "족보 등급을 떨어뜨릴 때만".
  /// 낮을수록 공격적이다.
  final double attackThreshold;

  /// 숨길 만한 최소 이득. 100 = "그 카드가 줄의 족보 등급을 올렸을 때만".
  final int hideMinGain;

  /// 이득이 없어도 숨겨서 허세를 부릴 확률.
  final double bluffChance;

  /// 훔쳐보기용으로 남겨 둘 칩 수(숨기기에 다 쓰지 않는다).
  final int reserveForPeek;

  /// 조건이 맞을 때 실제로 훔쳐볼 확률.
  final double peekChance;

  /// 방어막을 상대 줄에 꽂는 쪽으로 기우는 정도(0~1) — 괴롭히기 성향.
  final double harassBias;

  static const Map<AiStyle, AiProfile> byStyle = {
    AiStyle.clode: AiProfile(
      sacrificeWeakRow: 0.0,
      balance: 1.0,
      noise: 0.0,
      attackThreshold: 100,
      hideMinGain: 100,
      bluffChance: 0.0,
      reserveForPeek: 1,
      peekChance: 0.6,
      harassBias: 0.3,
    ),
    AiStyle.het: AiProfile(
      sacrificeWeakRow: 1.0,
      balance: 0.1,
      noise: 0.05,
      attackThreshold: 20,
      hideMinGain: 1,
      bluffChance: 0.15,
      reserveForPeek: 0,
      peekChance: 0.9,
      harassBias: 0.5,
    ),
    AiStyle.jenna: AiProfile(
      sacrificeWeakRow: 0.4,
      balance: 0.5,
      noise: 0.45,
      attackThreshold: 60,
      hideMinGain: 100,
      bluffChance: 0.5,
      reserveForPeek: 1,
      peekChance: 0.7,
      harassBias: 0.5,
    ),
    AiStyle.dipsy: AiProfile(
      sacrificeWeakRow: 0.6,
      balance: 0.6,
      noise: 0.1,
      attackThreshold: 100,
      hideMinGain: 100,
      bluffChance: 0.1,
      reserveForPeek: 1,
      peekChance: 0.8,
      harassBias: 0.4,
    ),
    AiStyle.grok: AiProfile(
      sacrificeWeakRow: 0.7,
      balance: 0.3,
      noise: 0.3,
      attackThreshold: 40,
      hideMinGain: 1,
      bluffChance: 0.35,
      reserveForPeek: 0,
      peekChance: 1.0,
      harassBias: 0.85,
    ),
    AiStyle.mist: AiProfile(
      sacrificeWeakRow: 0.8,
      balance: 0.2,
      noise: 0.15,
      attackThreshold: 70,
      hideMinGain: 50,
      bluffChance: 0.2,
      reserveForPeek: 0,
      peekChance: 0.5,
      harassBias: 0.4,
    ),
  };
}

/// AI **레벨**(1~5) — 기풍이 "어떻게"라면 레벨은 "얼마나 잘".
///
/// - [blunder]: 최선이 아닌 수를 고를 무작위 폭. 레벨 5는 0.
/// - [valueAttack]: true면 족보를 부수는 공격만 한다. 낮은 레벨은 아무 매치나 때린다.
/// - [smartShield]: true면 방어막을 "내 이득 vs 상대 잠재력 파괴" 비교로 놓는다.
///   false면 무조건 자기 필드(시뮬에서 29% 승률의 초보 습관).
/// - [readsOpponent]: false면 상대 줄을 안 보고 자기 줄만 키운다.
class AiStrength {
  const AiStrength({
    required this.blunder,
    required this.valueAttack,
    required this.smartShield,
    this.readsOpponent = true,
  });

  static const int minLevel = 1;
  static const int maxLevel = 5;

  final double blunder;
  final bool valueAttack;
  final bool smartShield;
  final bool readsOpponent;

  static AiStrength forLevel(int level) => switch (level.clamp(minLevel, maxLevel)) {
        1 => const AiStrength(
            blunder: 0.9, valueAttack: false, smartShield: false, readsOpponent: false),
        2 => const AiStrength(blunder: 0.5, valueAttack: false, smartShield: false),
        3 => const AiStrength(blunder: 0.15, valueAttack: true, smartShield: false),
        4 => const AiStrength(blunder: 0.05, valueAttack: true, smartShield: true),
        _ => const AiStrength(blunder: 0.0, valueAttack: true, smartShield: true),
      };
}

/// AI의 한 수 — 화면이 한 스텝씩 실행·연출한다.
sealed class TurnMove {
  const TurnMove();
}

class MovePlace extends TurnMove {
  const MovePlace(this.handIndex, this.row, {required this.hidden, this.wildAs});
  final int handIndex;
  final int row;
  final bool hidden;

  /// 조커 와일드로 놓을 때 지정하는 카드.
  final PlayingCard? wildAs;
}

class MoveAttack extends TurnMove {
  const MoveAttack(this.handIndex, this.row, this.col);
  final int handIndex, row, col;
}

class MovePeek extends TurnMove {
  const MovePeek(this.row, this.col);
  final int row, col;
}

class MoveShield extends TurnMove {
  const MoveShield(this.ownField, this.row);
  final bool ownField;
  final int row;
}

class MoveBurnShield extends TurnMove {
  const MoveBurnShield();
}

class MoveDiscard extends TurnMove {
  const MoveDiscard(this.handIndex);
  final int handIndex;
}

/// 스트라이크 룰 AI — 시뮬(strike_sim.py)의 '가치 공격 + 잠재력 방어막' 봇에
/// 기풍·레벨 계수를 얹은 것.
class VeiledAi {
  VeiledAi(this.style, {this.level = 3, int? seed}) : _rng = Random(seed);

  final AiStyle style;

  /// 1~5. [AiStrength.forLevel] 참고.
  final int level;
  final Random _rng;

  AiProfile get profile => AiProfile.byStyle[style]!;
  AiStrength get strength => AiStrength.forLevel(level);

  /// 기풍의 무작위성은 레벨이 오르면 줄지만 0이 되진 않는다 — 제나는 5레벨이어도 제나다.
  double get _styleNoise =>
      profile.noise * 0.6 * (0.4 + 0.6 * (AiStrength.maxLevel - level) / 4);

  /// [p]의 다음 수. [ScoreGame.phase]가 shield면 방어막 배치를 정한다.
  TurnMove chooseTurn(ScoreGame g, PlayerId p) {
    if (g.phase == TurnPhase.shield) return _chooseShield(g, p);
    final str = strength;
    final hand = g.hands[p]!;

    // 1) 공격 — 가치 기준(레벨 3+) 또는 아무 매치나(레벨 1~2).
    (double, int, int, int)? atk;
    if (str.readsOpponent) {
      for (var h = 0; h < hand.length; h++) {
        if (hand[h].isJoker) continue;
        for (final (r, c) in g.attackTargets(p, hand[h].rank)) {
          final worth = _attackWorth(g, p, r, c);
          if (atk == null || worth > atk.$1) atk = (worth, h, r, c);
        }
      }
    }
    if (atk != null) {
      final threshold = str.valueAttack ? profile.attackThreshold : 0.0;
      final impulsive = !str.valueAttack && _rng.nextDouble() < 0.75;
      if (atk.$1 >= threshold || impulsive) {
        return MoveAttack(atk.$2, atk.$3, atk.$4);
      }
    }

    // 2) 훔쳐보기 — 칩 여유가 있고 상대 뒷면이 있으면(턴 소모 없음).
    if (g.veilLeft[p]! > profile.reserveForPeek &&
        _rng.nextDouble() < profile.peekChance) {
      final hidden = [
        for (var r = 0; r < ScoreGame.rowsN; r++)
          for (var c = 0; c < ScoreGame.colsN; c++)
            if (g.fields[p.other]![r][c] case final s?
                when !s.faceUp && !s.peeked && !s.shield)
              (r, c),
      ];
      if (hidden.isNotEmpty) {
        final (r, c) = hidden[_rng.nextInt(hidden.length)];
        return MovePeek(r, c);
      }
    }

    // 3) 배치 — (카드, 줄)마다 줄 세기 증가 + 기풍 항 + 무작위.
    final open = g.openRows(p);
    if (open.isEmpty) {
      // 만석 — 제일 값없는 카드를 버린다.
      var worst = 0;
      for (var h = 1; h < hand.length; h++) {
        if (!hand[h].isJoker && hand[h].rank < hand[worst].rank) worst = h;
      }
      return MoveDiscard(worst);
    }
    (double, int, int)? best;
    for (var h = 0; h < hand.length; h++) {
      if (hand[h].isJoker) continue;
      for (final r in open) {
        var v = _placeValue(g, p, hand[h], r);
        v += (_styleNoise + str.blunder) * 60 * _rng.nextDouble();
        if (best == null || v > best.$1) best = (v, h, r);
      }
    }
    // 조커 와일드 — 실제 카드보다 이득이 크게 앞설 때(낮은 레벨은 받자마자 쓴다).
    final ji = hand.indexWhere((c) => c.isJoker);
    if (ji >= 0) {
      (double, int, PlayingCard)? wild;
      for (final r in open) {
        for (final suit in Suit.values) {
          for (final rank in Ranks.all) {
            final c = PlayingCard(rank, suit);
            final v = _placeValue(g, p, c, r);
            if (wild == null || v > wild.$1) wild = (v, r, c);
          }
        }
      }
      if (wild != null) {
        final eager = level <= 2;
        final margin = best == null ? 1e9 : wild.$1 - best.$1;
        if (eager || margin >= 80 || g.deckRemaining < 6) {
          final hide = _shouldHide(g, p, wild.$3, wild.$2);
          return MovePlace(ji, wild.$2, hidden: hide, wildAs: wild.$3);
        }
      }
    }
    if (best != null) {
      final card = hand[best.$2];
      return MovePlace(best.$2, best.$3,
          hidden: _shouldHide(g, p, card, best.$3));
    }
    // 손에 조커뿐인데 와일드 판단이 안 섰다 — 그냥 최선 와일드로.
    if (ji >= 0) {
      final r = open.first;
      return MovePlace(ji, r, hidden: false, wildAs: const PlayingCard(14, Suit.spades));
    }
    return const MoveDiscard(0);
  }

  /// 공격 가치 — 그 카드를 빼면 상대 줄 세기가 얼마나 떨어지는가.
  double _attackWorth(ScoreGame g, PlayerId p, int row, int col) {
    final opp = p.other;
    final all = <PlayingCard>[];
    final without = <PlayingCard>[];
    for (var c = 0; c < ScoreGame.colsN; c++) {
      final s = g.fields[opp]![row][c];
      if (s == null) continue;
      all.add(s.card);
      if (c != col) without.add(s.card);
    }
    return _strength(all) - _strength(without);
  }

  /// 배치 가치 — 줄 세기 증가 + 기풍(몰아주기/고르게).
  double _placeValue(ScoreGame g, PlayerId p, PlayingCard card, int row) {
    final cards = [
      for (var c = 0; c < ScoreGame.colsN; c++)
        if (g.fields[p]![row][c] case final s?) s.card,
    ];
    final before = _strength(cards);
    cards.add(card);
    var v = _strength(cards) - before;
    // 고르게 성향: 빈 줄 선호. 몰아주기 성향: 이미 센 줄 선호.
    final fill = cards.length - 1;
    v += profile.balance * (ScoreGame.colsN - fill) * 3;
    v += profile.sacrificeWeakRow * before * 0.06;
    return v;
  }

  /// 이 배치를 칩으로 숨길까 — 족보 코어(랭크 겹침)나 고랭크를 가린다.
  bool _shouldHide(ScoreGame g, PlayerId p, PlayingCard card, int row) {
    final budget = g.veilLeft[p]! - profile.reserveForPeek;
    if (budget <= 0) return false;
    final core = [
      for (var r = 0; r < ScoreGame.rowsN; r++)
        for (var c = 0; c < ScoreGame.colsN; c++)
          if (g.fields[p]![r][c] case final s? when s.card.rank == card.rank) s,
    ].isNotEmpty;
    final gain = core || card.rank >= Ranks.jack ? 100 : 0;
    if (gain >= profile.hideMinGain) return true;
    return _rng.nextDouble() < profile.bluffChance * 0.3;
  }

  /// 방어막 — 내 이득 vs 상대 잠재력 파괴(시뮬 71:29의 스킬 포인트).
  TurnMove _chooseShield(ScoreGame g, PlayerId p) {
    final s = g.pendingShield!;
    final myRows = g.openRows(p);
    final oppRows = g.openRows(p.other);
    if (myRows.isEmpty && oppRows.isEmpty) return const MoveBurnShield();

    (double, int)? bestSelf;
    for (final r in myRows) {
      final v = _placeValue(g, p, s, r);
      if (bestSelf == null || v > bestSelf.$1) bestSelf = (v, r);
    }
    if (!strength.smartShield) {
      // 초보 습관: 무조건 자기 필드(없으면 상대).
      if (bestSelf != null) return MoveShield(true, bestSelf.$2);
      return MoveShield(false, oppRows.first);
    }
    (double, int)? bestHarass;
    for (final r in oppRows) {
      final cut = _rowPotential(g, p.other, r) -
          _rowPotential(g, p.other, r, extra: s);
      if (bestHarass == null || cut > bestHarass.$1) bestHarass = (cut, r);
    }
    final harassBoost = 1 + profile.harassBias;
    if (bestHarass != null &&
        (bestSelf == null || bestHarass.$1 * harassBoost > bestSelf.$1)) {
      return MoveShield(false, bestHarass.$2);
    }
    if (bestSelf != null) return MoveShield(true, bestSelf.$2);
    return MoveShield(false, bestHarass!.$2);
  }

  /// 줄의 낙관적 잠재력(그룹 위주 근사) — 방어막 투기 판단용.
  double _rowPotential(ScoreGame g, PlayerId p, int row, {PlayingCard? extra}) {
    final cards = [
      for (var c = 0; c < ScoreGame.colsN; c++)
        if (g.fields[p]![row][c] case final s?) s.card,
      if (extra != null) extra,
    ];
    final free = ScoreGame.colsN - cards.length;
    if (free < 0) return _strength(cards);
    final counts = <int, int>{};
    for (final c in cards) {
      counts[c.rank] = (counts[c.rank] ?? 0) + 1;
    }
    var top = 0;
    counts.forEach((_, n) => top = max(top, n));
    final ach = min(4, top + free);
    final cat = ach >= 4
        ? HandCategory.fourOfAKind
        : ach == 3
            ? HandCategory.threeOfAKind
            : ach == 2
                ? HandCategory.onePair
                : HandCategory.highCard;
    var v = cat.index * 100.0 + cards.fold(0, (a, c) => a + c.value);
    v += _drawPotential(cards) * (free > 0 ? 1 : 0);
    return v;
  }

  /// 줄의 세기: 등급 ×100 + 점수 + **드로우 잠재력**(아직 빈 칸이 있을 때).
  double _strength(List<PlayingCard> cards) {
    if (cards.isEmpty) return 0;
    final h = evaluateHand(cards);
    var v = h.category.index * 100.0 + h.score;
    if (cards.length < ScoreGame.colsN) v += _drawPotential(cards);
    return v;
  }

  /// 미완성 줄의 플러시·스트레이트 가능성.
  double _drawPotential(List<PlayingCard> cards) {
    var v = 0.0;
    final n = cards.length;
    if (n < 2 || n > 4) return 0;
    if (cards.every((c) => c.suit == cards.first.suit)) {
      v += const [0, 0, 10, 45, 120][n];
    }
    if (n >= 3) {
      final ranks = cards.map((c) => c.rank).toSet();
      if (ranks.length == n) {
        bool within(Iterable<int> rs) {
          var lo = 99, hi = 0;
          for (final r in rs) {
            if (r < lo) lo = r;
            if (r > hi) hi = r;
          }
          return hi - lo <= 4;
        }

        final low = ranks.map((r) => r == Ranks.ace ? 1 : r);
        if (within(ranks) || within(low)) v += const [0, 0, 0, 30, 80][n];
      }
    }
    return v;
  }
}
