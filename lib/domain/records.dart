import 'dart:math' as math;

import 'scoring.dart';

/// 대국 기록/랭킹 점수(순수 Dart). 저장은 data/records_store.dart 담당.
///
/// 점수 시스템:
/// - 랭킹 점수(RP): 승 +15~+35(상대 레벨 1~5에 비례) / 무 +5 / 패 -15, 0 밑으로는 내려가지 않음.
/// - 상대 레벨(1~5): RP 티어 + 연승으로 정한다([RankingData.opponentLevel]) —
///   이기면 점점 잘 두는 상대가 나오고, 지면 내려온다.
/// - 티어: RP 구간별 아이언 → 브론즈 → 실버 → 골드 → 플래티넘 → 다이아.
/// - 상위 %: RP 기반 추정치(오프라인 고정 곡선 — 120 RP마다 절반으로 줄어드는 분포 가정).

/// 한 판의 결과 기록.
class GameRecord {
  const GameRecord({
    required this.playedAt,
    required this.myScore,
    required this.oppScore,
    required this.outcome,
    this.opponentLevel = 3,
  });

  final DateTime playedAt;
  final int myScore;
  final int oppScore;
  final MatchOutcome outcome;

  /// 상대 AI 레벨(1~5). 레벨 도입 전 기록은 3으로 읽는다.
  final int opponentLevel;

  Map<String, Object> toJson() => {
        'at': playedAt.millisecondsSinceEpoch,
        'my': myScore,
        'opp': oppScore,
        'o': outcome.index,
        'lv': opponentLevel,
      };

  factory GameRecord.fromJson(Map<String, dynamic> json) => GameRecord(
        playedAt: DateTime.fromMillisecondsSinceEpoch(json['at'] as int),
        myScore: json['my'] as int,
        oppScore: json['opp'] as int,
        outcome: MatchOutcome.values[json['o'] as int],
        opponentLevel: (json['lv'] as int?) ?? 3,
      );
}

enum RankTier { iron, bronze, silver, gold, platinum, diamond }

/// 랭킹 화면에 필요한 모든 데이터(누적 전적 + 최근 기록 + RP).
class RankingData {
  const RankingData({
    required this.rating,
    required this.games,
    required this.wins,
    required this.losses,
    required this.draws,
    required this.records,
  });

  static const empty = RankingData(
      rating: 0, games: 0, wins: 0, losses: 0, draws: 0, records: []);

  final int rating;
  final int games;
  final int wins;
  final int losses;
  final int draws;

  /// 최근 대국(최신순). 저장 상한은 store가 관리한다.
  final List<GameRecord> records;

  /// 승률(0~100, 기록 없으면 0).
  int get winRatePercent => games == 0 ? 0 : (wins * 100 / games).round();

  /// 내 점수 기준 최고 기록 TOP [n] (점수 내림차순).
  List<GameRecord> bestScores([int n = 10]) {
    final sorted = [...records]..sort((a, b) => b.myScore.compareTo(a.myScore));
    return sorted.take(n).toList();
  }

  RankTier get tier => tierFor(rating);

  /// 티어 시작 RP.
  static int tierFloor(RankTier t) => switch (t) {
        RankTier.iron => 0,
        RankTier.bronze => 100,
        RankTier.silver => 200,
        RankTier.gold => 300,
        RankTier.platinum => 450,
        RankTier.diamond => 650,
      };

  /// 다음 티어 시작 RP(다이아면 null).
  static int? nextTierAt(RankTier t) =>
      t == RankTier.diamond ? null : tierFloor(RankTier.values[t.index + 1]);

  static RankTier tierFor(int rating) {
    for (final t in RankTier.values.reversed) {
      if (rating >= tierFloor(t)) return t;
    }
    return RankTier.iron;
  }

  /// RP 기반 추정 상위 %(1~100). 120 RP마다 절반으로 줄어드는 분포 가정.
  int get topPercent => estimatedTopPercent(rating);

  static int estimatedTopPercent(int rating) =>
      (100 * math.pow(0.5, rating / 120)).round().clamp(1, 100);

  /// 결과에 따른 RP 증감. 승리는 상대 레벨에 비례한다(1레벨 +15 … 5레벨 +35).
  static int ratingDelta(MatchOutcome o, {int opponentLevel = 3}) => switch (o) {
        MatchOutcome.win => 10 + 5 * opponentLevel.clamp(1, 5),
        MatchOutcome.draw => 5,
        MatchOutcome.lose => -15,
      };

  /// 최근 기록에서 이어진 연승 수(최신부터 세다가 승리가 아니면 멈춘다).
  int get winStreak {
    var n = 0;
    for (final r in records) {
      if (r.outcome != MatchOutcome.win) break;
      n++;
    }
    return n;
  }

  /// 다음 판 상대 레벨(1~5) = 티어 기본값 + 연승 보너스.
  /// 아이언 1 · 브론즈 2 · 실버 3 · 골드 4 · 플래티넘+ 5, 3연승마다 +1(최대 5).
  int get opponentLevel => opponentLevelFor(rating, winStreak);

  static int opponentLevelFor(int rating, int winStreak) {
    final base = switch (tierFor(rating)) {
      RankTier.iron => 1,
      RankTier.bronze => 2,
      RankTier.silver => 3,
      RankTier.gold => 4,
      RankTier.platinum || RankTier.diamond => 5,
    };
    return (base + winStreak ~/ 3).clamp(1, 5);
  }

  /// 한 판 결과를 반영한 새 데이터.
  RankingData addRecord(GameRecord r, {int keepRecent = 200}) {
    final next = [r, ...records];
    if (next.length > keepRecent) next.removeRange(keepRecent, next.length);
    return RankingData(
      rating: (rating + ratingDelta(r.outcome, opponentLevel: r.opponentLevel))
          .clamp(0, 1 << 31),
      games: games + 1,
      wins: wins + (r.outcome == MatchOutcome.win ? 1 : 0),
      losses: losses + (r.outcome == MatchOutcome.lose ? 1 : 0),
      draws: draws + (r.outcome == MatchOutcome.draw ? 1 : 0),
      records: next,
    );
  }
}
