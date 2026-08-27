import 'dart:math';

import 'card.dart';
import 'game.dart';
import 'hand.dart';

/// AI 기풍. 페르소나(크로드/헷/제나)와 1:1로 묶인다.
enum AiStyle {
  /// 크로드 — 침착한 수비형. 세 줄을 고르게 채우고, 비공개권은 확실할 때만 쓴다.
  clode,

  /// 헷 — 공격형. 이길 두 줄에 몰아주고 약한 줄은 버린다. 비공개권을 일찍 태운다.
  het,

  /// 제나 — 변칙형. 배치가 튀고, 값어치 없는 카드도 숨겨 허세를 부린다.
  jenna,

  /// 딥시 — 계산형. 효율 우선: 이기는 두 줄을 굳히되 세 번째 줄도 버리지 않고,
  /// 이득이 확실한 카드만 숨기며 열어보기는 늦게, 정확하게.
  dipsy,

  /// 그록 — 도발형. 첫 라운드부터 숨기고 곧바로 열어본다. 비공개권을 아끼지 않는다.
  grok,

  /// 미스트 — 속공형. 두 줄에 빠르게 몰아주고 일찍 숨긴다. 열어보기엔 관심이 적다.
  mist,
}

/// 기풍별 행동 계수. 룰은 하나지만 **행동이 다르면 다른 상대로 느껴진다**.
class AiProfile {
  const AiProfile({
    required this.sacrificeWeakRow,
    required this.balance,
    required this.noise,
    required this.hideFromRound,
    required this.hideMinGain,
    required this.bluffChance,
    required this.reserveForPeek,
    required this.peekFromRound,
    required this.peekChance,
  });

  /// 가장 약한 줄을 버리고 남은 두 줄에 몰아주는 정도(0~1). 2줄만 이기면 되는 룰이라
  /// 높을수록 공격적이다.
  final double sacrificeWeakRow;

  /// 빈 칸이 많은 줄을 선호하는 정도(0~1) — 높을수록 세 줄이 고르게 찬다.
  final double balance;

  /// 배치 점수에 섞는 무작위성 — 높을수록 수를 읽기 어렵다.
  final double noise;

  /// 이 라운드(0-index)부터 숨기기를 쓴다.
  final int hideFromRound;

  /// 숨길 만한 최소 이득. 100 = "그 카드가 줄의 족보 등급을 올렸을 때만".
  final int hideMinGain;

  /// 이득이 없어도 숨겨서 허세를 부릴 확률.
  final double bluffChance;

  /// 열어보기용으로 남겨 둘 비공개권 수(숨기기에 다 쓰지 않는다).
  final int reserveForPeek;

  /// 이 라운드(0-index)부터 열어보기를 쓴다.
  final int peekFromRound;

  /// 조건이 맞을 때 실제로 열어볼 확률.
  final double peekChance;

  static const Map<AiStyle, AiProfile> byStyle = {
    AiStyle.clode: AiProfile(
      sacrificeWeakRow: 0.0,
      balance: 1.0,
      noise: 0.0,
      hideFromRound: 2,
      hideMinGain: 100,
      bluffChance: 0.0,
      reserveForPeek: 1,
      peekFromRound: 3,
      peekChance: 0.6,
    ),
    AiStyle.het: AiProfile(
      sacrificeWeakRow: 1.0,
      balance: 0.1,
      noise: 0.05,
      hideFromRound: 0,
      hideMinGain: 1,
      bluffChance: 0.15,
      reserveForPeek: 0,
      peekFromRound: 1,
      peekChance: 0.9,
    ),
    AiStyle.jenna: AiProfile(
      sacrificeWeakRow: 0.4,
      balance: 0.5,
      noise: 0.45,
      hideFromRound: 0,
      hideMinGain: 100,
      bluffChance: 0.5,
      reserveForPeek: 1,
      peekFromRound: 2,
      peekChance: 0.7,
    ),
    AiStyle.dipsy: AiProfile(
      sacrificeWeakRow: 0.6,
      balance: 0.6,
      noise: 0.1,
      hideFromRound: 1,
      hideMinGain: 100,
      bluffChance: 0.1,
      reserveForPeek: 1,
      peekFromRound: 2,
      peekChance: 0.8,
    ),
    AiStyle.grok: AiProfile(
      sacrificeWeakRow: 0.7,
      balance: 0.3,
      noise: 0.3,
      hideFromRound: 0,
      hideMinGain: 1,
      bluffChance: 0.35,
      reserveForPeek: 0,
      peekFromRound: 1,
      peekChance: 1.0,
    ),
    AiStyle.mist: AiProfile(
      sacrificeWeakRow: 0.8,
      balance: 0.2,
      noise: 0.15,
      hideFromRound: 0,
      hideMinGain: 50,
      bluffChance: 0.2,
      reserveForPeek: 0,
      peekFromRound: 1,
      peekChance: 0.5,
    ),
  };
}

/// AI **레벨**(1~5). 기풍([AiStyle])이 "어떻게 두는가"라면 레벨은 "얼마나 잘 두는가"다 —
/// 같은 크로드여도 레벨이 오르면 실수가 줄고 최선의 수에 가까워진다.
///
/// - [samples] 0이면 눈앞의 카드만 본다(현재 족보 + 빈 칸 보정). 0보다 크면 **남은 덱에서
///   빈 칸이 채워지는 경우를 그 수만큼 시뮬**해 "이 줄이 이길 확률"을 세는데, 이때 상대의
///   숨긴 카드·빈 칸도 함께 돌린다 — 플러시·스트레이트 드로우, 페어 붙을 가능성 같은
///   **포커 지식**이 여기서 나온다.
/// - [blunder]는 최선이 아닌 수를 고를 여지(값에 섞는 무작위 폭). 레벨 5는 0.
/// - [smartPeek]이면 열어보기를 "숨김이 몰린 줄"이 아니라 **승패가 갈리는 줄**에 쓴다.
class AiStrength {
  const AiStrength({
    required this.samples,
    required this.shortlist,
    required this.blunder,
    required this.smartPeek,
    this.readsOpponent = true,
    this.pickFrom = 1,
  });

  static const int minLevel = 1;
  static const int maxLevel = 5;

  final int samples;

  /// 시뮬은 비싸다 — 공개 정보 값이 높은 상위 [shortlist]개 조합만 시뮬로 다시 잰다.
  final int shortlist;
  final double blunder;
  final bool smartPeek;

  /// false면 상대 줄을 보지 않고 **자기 줄만** 키운다(초보의 흔한 실수).
  final bool readsOpponent;

  /// 시뮬에서 내 빈 칸 하나를 채울 때 덱에서 몇 장을 보고 고르는가. 실제로는 손패 6장 중
  /// 3장을 골라 놓으므로 "랜덤 1장"(1)보다 "몇 장 중 그 줄에 제일 좋은 것"이 현실에 가깝다 —
  /// 이 값이 커야 플러시·스트레이트 드로우를 제대로 쳐준다.
  final int pickFrom;

  static AiStrength forLevel(int level) => switch (level.clamp(minLevel, maxLevel)) {
        1 => const AiStrength(
            samples: 0, shortlist: 0, blunder: 0.8, smartPeek: false, readsOpponent: false),
        2 => const AiStrength(samples: 0, shortlist: 0, blunder: 0.4, smartPeek: false),
        3 => const AiStrength(
            samples: 24, shortlist: 16, blunder: 0.10, smartPeek: false, pickFrom: 2),
        4 => const AiStrength(
            samples: 48, shortlist: 32, blunder: 0.04, smartPeek: true, pickFrom: 2),
        _ => const AiStrength(
            samples: 96, shortlist: 48, blunder: 0.0, smartPeek: true, pickFrom: 2),
      };
}

/// AI의 조커 결정. [strike]면 상대 판 ([row],[col])의 카드를 [card]로 바꾸고,
/// 아니면 내 빈 칸 ([row],[col])에 [card]로 놓는다.
class JokerMove {
  const JokerMove({
    required this.handIndex,
    required this.strike,
    required this.row,
    required this.col,
    required this.card,
  });
  final int handIndex;
  final bool strike;
  final int row;
  final int col;
  final PlayingCard card;
}

/// 가림 룰 AI.
///
/// 손패에서 **이번 라운드에 낼 카드**(남은 배치 수만큼)를 고른다: (카드 × 줄) 배정을
/// 한꺼번에 탐색해 **판 전체 값어치**([_boardValue] — 상대의 공개 카드를 보고 "두 줄을
/// 이길 확률")가 가장 높은 조합을 택한다. 기풍 계수는 그 위에 얹힌다. 반환된 handIndex는
/// **현재 손패 기준**이므로, 실행할 때는 인덱스가 밀리지 않게 내림차순으로 배치해야 한다.
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

  List<({int handIndex, int row, int col})> plan(ScoreGame g, PlayerId p) {
    final rows = g.allRows(p);
    // 상대는 **공개된 카드만** 안다 — 숨긴 카드는 "한 장 더 있다"로만 친다.
    final str = strength;
    final opp = [
      for (var r = 0; r < ScoreGame.rowsN; r++)
        str.readsOpponent ? g.publicRow(p.other, r) : <PlayingCard>[],
    ];
    final oppHidden = [
      for (var r = 0; r < ScoreGame.rowsN; r++)
        str.readsOpponent ? g.allRows(p.other)[r].length - opp[r].length : 0,
    ];
    final free = [
      for (var r = 0; r < ScoreGame.rowsN; r++) ScoreGame.colsN - rows[r].length,
    ];
    final hand = g.hands[p]!;
    final n = min(g.leftToPlace(p), hand.where((c) => !c.isJoker).length);
    if (n == 0) return const [];

    // (카드, 줄) 배정 n개를 **한꺼번에** 탐색한다 — 손패의 페어·같은 무늬가 한 줄에
    // 모이려면 한 장씩 탐욕으로 고르면 안 된다. 6장·3배치면 ~3천 가지, 충분히 싸다.
    // 1차: 공개 정보 값([_boardValue])으로 전부 잰다. 2차(레벨 3+): 상위 몇 개만 시뮬.
    final candidates = <(List<(int, int)>, double)>[];
    final assign = <(int, int)>[];
    final used = <int>{};

    void search(int k) {
      if (k == n) {
        candidates.add((List.of(assign), _boardValue(rows, opp, oppHidden, free)));
        return;
      }
      for (var i = 0; i < hand.length; i++) {
        if (used.contains(i) || hand[i].isJoker) continue; // 조커는 jokerMove가 다룬다
        // 카드 순서 중복만 잘라낸다: 인덱스 오름차순으로만 고른다.
        if (assign.isNotEmpty && i < assign.last.$1) continue;
        for (var r = 0; r < ScoreGame.rowsN; r++) {
          if (free[r] <= 0) continue;
          used.add(i);
          assign.add((i, r));
          rows[r].add(hand[i]);
          free[r]--;
          search(k + 1);
          free[r]++;
          rows[r].removeLast();
          assign.removeLast();
          used.remove(i);
        }
      }
    }

    search(0);
    candidates.sort((a, b) => b.$2.compareTo(a.$2));

    var bestValue = -1e18;
    List<(int, int)> best = const [];
    if (str.samples > 0) {
      // 같은 무작위 덱 순서(공통 난수)로 모든 후보를 재서 비교가 흔들리지 않게 한다 —
      // 후보마다 다른 덱을 뽑으면 표본 잡음이 실제 차이를 덮는다.
      final draws = _drawSets(_unseen(g, p), str.samples);
      for (final (a, heur) in candidates.take(str.shortlist)) {
        for (final (i, r) in a) {
          rows[r].add(hand[i]);
          free[r]--;
        }
        // 이번에 안 놓는 손패는 다음 라운드에 놓을 수 있는 **아는 카드**다 — 시뮬에서
        // 덱보다 먼저 후보로 친다(하트 4장 중 3장을 놓고 1장을 남기면 플러시가 살아 있다).
        final leftover = [
          for (var i = 0; i < hand.length; i++)
            if (!hand[i].isJoker && !a.any((m) => m.$1 == i)) hand[i],
        ];
        final sim = _simValue(rows, opp, free, draws, leftover);
        for (final (_, r) in a) {
          rows[r].removeLast();
          free[r]++;
        }
        // 시뮬(완성될 족보)과 공개 정보 값(숨긴 카드는 값어치가 있다는 사전 지식)을 섞는다.
        var v = 0.7 * sim + 0.3 * heur;
        v += (_styleNoise + str.blunder * 0.5) * _rng.nextDouble();
        if (v > bestValue) {
          bestValue = v;
          best = a;
        }
      }
    } else {
      for (final (a, heur) in candidates) {
        final v = heur + (_styleNoise + str.blunder * 0.5) * _rng.nextDouble();
        if (v > bestValue) {
          bestValue = v;
          best = a;
        }
      }
    }

    final plan = <({int handIndex, int row, int col})>[];
    for (final (i, r) in best) {
      var col = 0;
      while (g.fields[p]![r][col] != null ||
          plan.any((m) => m.row == r && m.col == col)) {
        col++;
      }
      plan.add((handIndex: i, row: r, col: col));
    }
    return plan;
  }

  /// [p]가 **보지 못한** 카드 — 52장에서 내 손패·내 필드·상대의 공개 카드를 뺀 것.
  /// 상대의 숨긴 카드와 덱에 남은 카드가 여기 섞여 있다.
  List<PlayingCard> _unseen(ScoreGame g, PlayerId p) {
    final known = <PlayingCard>{...g.hands[p]!};
    for (var r = 0; r < ScoreGame.rowsN; r++) {
      for (var c = 0; c < ScoreGame.colsN; c++) {
        final mine = g.fields[p]![r][c];
        if (mine != null) known.add(mine.card);
        final theirs = g.fields[p.other]![r][c];
        if (theirs != null && theirs.faceUp) known.add(theirs.card);
      }
    }
    return [
      for (final suit in Suit.values)
        for (final rank in Ranks.all)
          if (!known.contains(PlayingCard(rank, suit))) PlayingCard(rank, suit),
    ];
  }

  /// 시뮬용 덱 순서 [samples]개 — [unseen]을 섞은 앞부분(최대 필요 장수: 내 빈 칸 15 +
  /// 상대 미공개 15). 모든 후보가 같은 순서를 쓴다(공통 난수).
  List<List<PlayingCard>> _drawSets(List<PlayingCard> unseen, int samples) {
    // 내 빈 칸(최대 15)×후보 수 + 상대 미공개(최대 15).
    final need = ScoreGame.rowsN * ScoreGame.colsN * (strength.pickFrom + 1);
    final pool = List.of(unseen);
    return [
      for (var s = 0; s < samples; s++)
        () {
          final take = min(need, pool.length);
          for (var i = 0; i < take; i++) {
            final j = i + _rng.nextInt(pool.length - i);
            final t = pool[i];
            pool[i] = pool[j];
            pool[j] = t;
          }
          return pool.sublist(0, take);
        }(),
    ];
  }

  /// 시뮬 값어치(레벨 3+): 빈 칸과 상대의 숨긴 카드를 [draws]의 덱 순서대로 채워 본 뒤
  /// 줄마다 이긴 비율을 승률로 쓴다. 눈앞의 족보가 아니라 **완성될 족보**를 본다 —
  /// 플러시·스트레이트 드로우, 페어가 붙을 가능성이 여기서 값이 된다.
  double _simValue(List<List<PlayingCard>> mine, List<List<PlayingCard>> opp,
      List<int> free, List<List<PlayingCard>> draws, List<PlayingCard> leftover) {
    final wins = List.filled(mine.length, 0.0);
    final pickFrom = strength.pickFrom;
    final myRow = <PlayingCard>[];
    final oppRow = <PlayingCard>[];
    final avail = <PlayingCard>[];
    for (final deck in draws) {
      var cursor = 0;
      avail
        ..clear()
        ..addAll(leftover);
      // 덱이 모자라면(후반엔 미공개 카드가 필요 장수보다 적다) 처음부터 다시 쓴다.
      PlayingCard next() {
        if (cursor >= deck.length) cursor = 0;
        return deck[cursor++];
      }

      for (var r = 0; r < mine.length; r++) {
        myRow
          ..clear()
          ..addAll(mine[r]);
        for (var k = 0; k < free[r]; k++) {
          // 후보 pickFrom장 중 이 줄에 가장 좋은 카드를 고른다(손패에서 골라 놓는 것의 근사).
          var pick = next();
          if (pickFrom > 1 || avail.isNotEmpty) {
            myRow.add(pick);
            var bestV = _strength(myRow);
            myRow.removeLast();
            int? fromAvail;
            for (var j = 1; j < pickFrom; j++) {
              final cand = next();
              myRow.add(cand);
              final v = _strength(myRow);
              myRow.removeLast();
              if (v > bestV) {
                bestV = v;
                pick = cand;
              }
            }
            for (var j = 0; j < avail.length; j++) {
              myRow.add(avail[j]);
              final v = _strength(myRow);
              myRow.removeLast();
              if (v > bestV) {
                bestV = v;
                pick = avail[j];
                fromAvail = j;
              }
            }
            if (fromAvail != null) avail.removeAt(fromAvail);
          }
          myRow.add(pick);
        }
        oppRow
          ..clear()
          ..addAll(opp[r]);
        final oppFill = ScoreGame.colsN - opp[r].length; // 숨긴 것 + 빈 칸
        for (var k = 0; k < oppFill; k++) {
          oppRow.add(next());
        }
        final c = evaluateHand(myRow).compareTo(evaluateHand(oppRow));
        wins[r] += c > 0 ? 1 : (c == 0 ? 0.5 : 0);
      }
    }
    final ps = [for (final w in wins) w / draws.length];
    return _combine(ps, free, styleWeight: 0.12);
  }

  /// 줄별 승률 → 판의 값. 상위 두 줄을 크게, 세 번째 줄은 기풍(sacrificeWeakRow)만큼 작게.
  /// 이미 굳은 줄(확실히 이김/짐)에 카드를 더 부어도 값이 오르지 않는다 —
  /// 확률이라 자연히 접전인 줄로 카드가 간다.
  ///
  /// [styleWeight]는 기풍(몰아주기/고르게)이 값에 끼치는 폭. 시뮬 값은 조합마다 차이가
  /// 커서 같은 폭이면 기풍이 묻힌다 — 시뮬 경로는 더 크게 준다. 그래도 승률 차이가
  /// 그보다 크면 승률이 이긴다: 레벨이 높을수록 "기풍은 남되 손해는 안 본다".
  double _combine(List<double> ps, List<int> free, {double styleWeight = 0.04}) {
    var evenness = 0.0;
    var maxFill = 0, minFill = ScoreGame.colsN;
    for (final f in free) {
      evenness += f == 0 ? 0 : 1;
      final fill = ScoreGame.colsN - f;
      if (fill > maxFill) maxFill = fill;
      if (fill < minFill) minFill = fill;
    }
    final sorted = [...ps]..sort((a, b) => b.compareTo(a));
    final weakWeight = 0.55 - 0.45 * profile.sacrificeWeakRow;
    var v = sorted[0] + sorted[1] + weakWeight * sorted[2];
    // 두 줄이 모두 반반이면 몰아주기가 낫다: 둘 다 이길 확률(곱)도 조금 센다.
    v += 0.5 * sorted[0] * sorted[1];
    v += profile.balance * styleWeight * evenness;
    // 편중도(가장 찬 줄 − 가장 빈 줄): 공격형은 좋아하고 수비형은 싫어한다.
    final skew = (maxFill - minFill) / ScoreGame.colsN;
    v += (profile.sacrificeWeakRow - profile.balance) * styleWeight * 2.5 * skew;
    return v;
  }

  /// 판 전체의 값어치 — "세 줄 중 두 줄을 이길 확률"에 가깝게.
  ///
  /// 줄마다 내 세기 − 상대 세기(공개분 + 숨긴 장수만큼의 잠재력)를 승률로 바꾼 뒤,
  /// 상위 두 줄을 크게, 세 번째 줄은 기풍(sacrificeWeakRow)만큼 작게 센다.
  /// 이미 굳은 줄(확실히 이김/짐)에 카드를 더 부어도 값이 오르지 않는다 —
  /// 시그모이드라 자연히 접전인 줄로 카드가 간다.
  double _boardValue(List<List<PlayingCard>> mine, List<List<PlayingCard>> opp,
      List<int> oppHidden, List<int> free) {
    final ps = <double>[];
    for (var r = 0; r < mine.length; r++) {
      ps.add(_publicWinChance(mine[r], opp[r], oppHidden[r], free[r]));
    }
    return _combine(ps, free);
  }

  /// 공개 정보만으로 본 줄 승률(시그모이드). 빈 칸 = 아직 오를 여지, 숨긴 카드 = 값어치 있는
  /// 카드일 확률이 높다고 친다.
  double _publicWinChance(
      List<PlayingCard> mine, List<PlayingCard> opp, int oppHidden, int free) {
    final my = _strength(mine) + free * 14;
    final theirs = _strength(opp) +
        oppHidden * 22 +
        (ScoreGame.colsN - opp.length - oppHidden) * 14;
    return 1 / (1 + exp(-(my - theirs) / 55));
  }

  /// 줄의 세기: 등급 ×100 + 점수 + **드로우 잠재력**(아직 빈 칸이 있을 때).
  ///
  /// 5장 족보(플러시·스트레이트)는 완성 전까지 하이카드로 보이기 때문에, 이 항이 없으면
  /// 같은 무늬 3장을 한 줄에 모으는 후보가 1차 선별에서 잘려 시뮬까지 못 간다.
  double _strength(List<PlayingCard> cards) {
    if (cards.isEmpty) return 0;
    final h = evaluateHand(cards);
    var v = h.category.index * 100.0 + h.score;
    if (cards.length < ScoreGame.colsN) v += _drawPotential(cards);
    return v;
  }

  /// 미완성 줄의 플러시·스트레이트 가능성. 무늬가 다 같으면 장수에 따라 10/45/120,
  /// 서로 다른 랭크가 5칸 폭 안에 들면 30/80(A는 14 또는 1).
  double _drawPotential(List<PlayingCard> cards) {
    var v = 0.0;
    final n = cards.length;
    if (n >= 2 && cards.every((c) => c.suit == cards.first.suit)) {
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


  /// 손에 조커가 있으면 어떻게 쓸지 정한다. null이면 이번 라운드는 아낀다.
  ///
  /// - **와일드**: 내 줄 하나에 가장 값이 오르는 카드로 놓는다(3장 배치의 하나).
  /// - **강타**: 상대 카드 하나를 가장 값이 떨어지는 카드로 바꾼다. 레벨 4+는 상대의
  ///   **숨긴 카드**도 노린다("숨겼다 = 값어치 있다"로 치고 그 줄이 갈리는 줄이면).
  /// 레벨 1~2는 강타를 쓸 줄 모르고 조커를 받자마자 와일드로 쓴다.
  JokerMove? jokerMove(ScoreGame g, PlayerId p) {
    final hand = g.hands[p]!;
    final hi = hand.indexWhere((c) => c.isJoker);
    if (hi < 0 || g.revealDone) return null;
    final rows = g.allRows(p);
    final opp = [for (var r = 0; r < ScoreGame.rowsN; r++) g.publicRow(p.other, r)];
    final oppHidden = [
      for (var r = 0; r < ScoreGame.rowsN; r++) g.allRows(p.other)[r].length - opp[r].length,
    ];
    final free = [for (var r = 0; r < ScoreGame.rowsN; r++) ScoreGame.colsN - rows[r].length];
    final base = _boardValue(rows, opp, oppHidden, free);
    final deck = [
      for (final suit in Suit.values)
        for (final rank in Ranks.all) PlayingCard(rank, suit),
    ];

    // 한 줄에 카드 하나를 넣었을 때의 판 값. 조커의 값어치는 "내 진짜 카드 중 제일 좋은 것"
    // 대비 얼마나 더 좋아지느냐로 잰다 — 빈 칸 자체가 잠재력으로 세어지기 때문에
    // 절대값(base와의 차)으로는 언제나 손해로 보인다.
    double withCard(int r, PlayingCard c) {
      rows[r].add(c);
      free[r]--;
      final v = _boardValue(rows, opp, oppHidden, free);
      free[r]++;
      rows[r].removeLast();
      return v;
    }

    JokerMove? wild;
    var wildGain = -1.0;
    if (g.leftToPlace(p) > 0) {
      for (var r = 0; r < ScoreGame.rowsN; r++) {
        if (free[r] <= 0) continue;
        var bestReal = -1e9;
        var bestRealStrength = 0.0;
        for (final h in hand) {
          if (h.isJoker) continue;
          final v = withCard(r, h);
          if (v > bestReal) {
            bestReal = v;
            rows[r].add(h);
            bestRealStrength = _strength(rows[r]);
            rows[r].removeLast();
          }
        }
        for (final c in deck) {
          var gain = withCard(r, c) - bestReal;
          // 줄 자체가 얼마나 세지느냐도 센다(시그모이드가 굳은 줄에서 무뎌지는 것을 보정).
          rows[r].add(c);
          final s = _strength(rows[r]);
          rows[r].removeLast();
          gain += 0.5 * ((s - bestRealStrength) / 400).clamp(0.0, 1.0);
          if (gain > wildGain) {
            wildGain = gain;
            var col = 0;
            while (g.fields[p]![r][col] != null) {
              col++;
            }
            wild = JokerMove(handIndex: hi, strike: false, row: r, col: col, card: c);
          }
        }
      }
    }
    if (level <= 2) return wild;

    JokerMove? strike;
    var strikeGain = 0.0;
    final taken = g.pendingStrikes[p]!;
    for (var r = 0; r < ScoreGame.rowsN; r++) {
      for (var c = 0; c < ScoreGame.colsN; c++) {
        final slot = g.fields[p.other]![r][c];
        if (slot == null || taken.any((t) => t.row == r && t.col == c)) continue;
        if (!slot.faceUp && !strength.smartPeek) continue;
        // 상대 줄에서 그 카드를 빼고 후보 카드를 넣었을 때 내 값이 가장 오르는 조합.
        final pub = List.of(opp[r]);
        var hiddenN = oppHidden[r];
        if (slot.faceUp) {
          pub.remove(slot.card);
        } else {
          hiddenN--;
        }
        final before = _strength(opp[r]) + oppHidden[r] * 22;
        for (final cand in deck) {
          pub.add(cand);
          final savedPub = opp[r];
          final savedHidden = oppHidden[r];
          opp[r] = pub;
          oppHidden[r] = hiddenN;
          var gain = _boardValue(rows, opp, oppHidden, free) - base;
          // 상대 줄이 얼마나 무너지느냐(족보 등급 하락)도 직접 센다.
          gain += 0.5 * ((before - (_strength(pub) + hiddenN * 22)) / 400).clamp(0.0, 1.0);
          opp[r] = savedPub;
          oppHidden[r] = savedHidden;
          pub.removeLast();
          // 숨긴 카드는 보이는 것보다 값어치가 있을 확률이 높다 — 그만큼 얹어 준다.
          if (!slot.faceUp) gain += 0.08;
          if (gain > strikeGain) {
            strikeGain = gain;
            strike = JokerMove(handIndex: hi, strike: true, row: r, col: c, card: cand);
          }
        }
      }
    }
    final lastRound = g.round >= ScoreGame.totalRounds - 1;
    const threshold = 0.12;
    if (strike != null && strikeGain >= wildGain && (strikeGain >= threshold || lastRound)) {
      return strike;
    }
    if (wild != null && (wildGain >= threshold || lastRound)) return wild;
    return null;
  }

  /// 공개 직전의 숨기기 선택. 이번 라운드에 놓은 카드 중 한 장까지만 숨긴다
  /// (숨길수록 상대의 열어보기 표적이 늘어난다).
  Set<(int, int)> hides(ScoreGame g, PlayerId p) {
    final budget = g.veilLeft[p]! - profile.reserveForPeek;
    if (budget <= 0 || g.round < profile.hideFromRound) return const {};

    (int, int)? best;
    var bestGain = 0;
    for (final (r, c) in g.placedThisRound(p)) {
      final gain = _cardGain(g, p, r, c);
      if (gain > bestGain) {
        bestGain = gain;
        best = (r, c);
      }
    }
    if (best != null && bestGain >= profile.hideMinGain) return {best};

    // 허세: 값어치 없는 카드를 숨겨 상대의 비공개권을 헛되이 태우게 만든다.
    final placed = g.placedThisRound(p);
    if (placed.isNotEmpty && _rng.nextDouble() < profile.bluffChance) {
      return {placed[_rng.nextInt(placed.length)]};
    }
    return const {};
  }

  /// 그 카드가 자기 줄에 얼마나 기여했는가(등급 상승 ×100 + 점수 상승).
  int _cardGain(ScoreGame g, PlayerId p, int row, int col) {
    final all = <PlayingCard>[];
    final without = <PlayingCard>[];
    for (var c = 0; c < ScoreGame.colsN; c++) {
      final s = g.fields[p]![row][c];
      if (s == null) continue;
      all.add(s.card);
      if (c != col) without.add(s.card);
    }
    final a = evaluateHand(all);
    final b = evaluateHand(without);
    return (a.category.index - b.category.index) * 100 + (a.score - b.score);
  }

  /// 열어보기: 상대가 **지난 라운드에 숨긴** 카드가 있으면 기풍에 따라 하나를 연다.
  /// 표적은 숨김이 몰린 줄 — 상대가 밀어붙이는 줄일 확률이 높다.
  (int, int)? peek(ScoreGame g, PlayerId p) {
    if (g.veilLeft[p]! <= 0 || g.round < profile.peekFromRound) return null;
    if (_rng.nextDouble() >= profile.peekChance) return null;
    final hidden = [
      for (final pos in g.hiddenOf(p.other))
        if (g.fields[p.other]![pos.$1][pos.$2]!.round < g.round || g.revealDone) pos,
    ];
    if (hidden.isEmpty) return null;
    if (strength.smartPeek) {
      // 승패가 갈리는 줄(승률이 반반에 가까운 줄)의 숨긴 카드를 연다. 이미 굳은 줄은
      // 열어봐야 얻는 게 없으니 비공개권을 아낀다.
      final rows = g.allRows(p);
      (int, int)? best;
      var bestGap = 1.0;
      for (final pos in hidden) {
        final r = pos.$1;
        final oppPublic = g.publicRow(p.other, r);
        final oppHiddenN = g.allRows(p.other)[r].length - oppPublic.length;
        final pr = _publicWinChance(
            rows[r], oppPublic, oppHiddenN, ScoreGame.colsN - rows[r].length);
        final gap = (pr - 0.5).abs();
        if (gap < bestGap) {
          bestGap = gap;
          best = pos;
        }
      }
      return bestGap < 0.38 ? best : null;
    }
    final byRow = <int, int>{};
    for (final (r, _) in hidden) {
      byRow[r] = (byRow[r] ?? 0) + 1;
    }
    final targetRow =
        byRow.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
    return hidden.firstWhere((h) => h.$1 == targetRow);
  }
}
