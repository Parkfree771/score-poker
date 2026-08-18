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
}
