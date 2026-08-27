import 'package:flutter_test/flutter_test.dart';
import 'package:score_poker/domain/records.dart';
import 'package:score_poker/domain/scoring.dart';

void main() {
  group('티어', () {
    test('RP 구간별 아이언 → 다이아', () {
      expect(RankingData.tierFor(0), RankTier.iron);
      expect(RankingData.tierFor(99), RankTier.iron);
      expect(RankingData.tierFor(100), RankTier.bronze);
      expect(RankingData.tierFor(200), RankTier.silver);
      expect(RankingData.tierFor(300), RankTier.gold);
      expect(RankingData.tierFor(450), RankTier.platinum);
      expect(RankingData.tierFor(650), RankTier.diamond);
      expect(RankingData.tierFor(9999), RankTier.diamond);
    });

    test('다음 티어 경계', () {
      expect(RankingData.nextTierAt(RankTier.iron), 100);
      expect(RankingData.nextTierAt(RankTier.platinum), 650);
      expect(RankingData.nextTierAt(RankTier.diamond), isNull);
    });
  });

  group('상위 %', () {
    test('0 RP는 100%, 오를수록 줄고 1% 밑으로는 안 내려간다', () {
      expect(RankingData.estimatedTopPercent(0), 100);
      expect(RankingData.estimatedTopPercent(120), 50);
      expect(RankingData.estimatedTopPercent(240), 25);
      expect(RankingData.estimatedTopPercent(2000), 1);
    });
  });

  group('기록 반영', () {
    GameRecord rec(MatchOutcome o, {int my = 100, int opp = 90}) => GameRecord(
        playedAt: DateTime(2026, 8, 16), myScore: my, oppScore: opp, outcome: o);

    test('승 +25 / 무 +5 / 패 -15, 0 밑으로 안 내려감', () {
      var d = RankingData.empty.addRecord(rec(MatchOutcome.win));
      expect(d.rating, 25);
      d = d.addRecord(rec(MatchOutcome.draw));
      expect(d.rating, 30);
      d = d.addRecord(rec(MatchOutcome.lose));
      expect(d.rating, 15);
      d = d.addRecord(rec(MatchOutcome.lose));
      expect(d.rating, 0);
    });

    test('전적·승률·최고 점수 집계', () {
      var d = RankingData.empty
          .addRecord(rec(MatchOutcome.win, my: 150))
          .addRecord(rec(MatchOutcome.lose, my: 220))
          .addRecord(rec(MatchOutcome.win, my: 180));
      expect((d.games, d.wins, d.losses, d.draws), (3, 2, 1, 0));
      expect(d.winRatePercent, 67);
      expect(d.bestScores(2).map((r) => r.myScore), [220, 180]);
    });

    test('직렬화 왕복', () {
      final r = rec(MatchOutcome.draw, my: 187, opp: 187);
      final back = GameRecord.fromJson(r.toJson());
      expect(back.playedAt, r.playedAt);
      expect(back.myScore, 187);
      expect(back.outcome, MatchOutcome.draw);
    });
  });
  group('상대 레벨', () {
    GameRecord rec(MatchOutcome o, {int lv = 3}) => GameRecord(
        playedAt: DateTime(2026, 8, 27), myScore: 100, oppScore: 90, outcome: o, opponentLevel: lv);

    test('승리 RP는 상대 레벨에 비례한다(1레벨 +15 … 5레벨 +35)', () {
      expect(RankingData.ratingDelta(MatchOutcome.win, opponentLevel: 1), 15);
      expect(RankingData.ratingDelta(MatchOutcome.win, opponentLevel: 5), 35);
      expect(RankingData.ratingDelta(MatchOutcome.lose, opponentLevel: 5), -15);
      expect(RankingData.empty.addRecord(rec(MatchOutcome.win, lv: 5)).rating, 35);
    });

    test('티어가 기본 레벨, 3연승마다 +1, 최대 5', () {
      expect(RankingData.opponentLevelFor(0, 0), 1);
      expect(RankingData.opponentLevelFor(0, 3), 2);
      expect(RankingData.opponentLevelFor(100, 0), 2);
      expect(RankingData.opponentLevelFor(200, 0), 3);
      expect(RankingData.opponentLevelFor(300, 0), 4);
      expect(RankingData.opponentLevelFor(450, 0), 5);
      expect(RankingData.opponentLevelFor(450, 9), 5);
    });

    test('연승은 최신 기록부터 세고 패배에서 끊긴다', () {
      var d = RankingData.empty
          .addRecord(rec(MatchOutcome.win))
          .addRecord(rec(MatchOutcome.lose))
          .addRecord(rec(MatchOutcome.win))
          .addRecord(rec(MatchOutcome.win));
      expect(d.winStreak, 2);
      d = d.addRecord(rec(MatchOutcome.win));
      expect(d.winStreak, 3);
      expect(d.opponentLevel, 2, reason: '아이언(1) + 3연승(+1)');
    });

    test('레벨 없는 옛 기록은 3으로 읽는다', () {
      final r = GameRecord.fromJson({'at': 0, 'my': 1, 'opp': 2, 'o': 0});
      expect(r.opponentLevel, 3);
      expect(GameRecord.fromJson(rec(MatchOutcome.win, lv: 5).toJson()).opponentLevel, 5);
    });
  });
}
