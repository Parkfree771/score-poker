import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/records.dart';

/// 대국 기록/랭킹 점수의 로컬 저장소(shared_preferences).
class RecordsStore {
  static const _kData = 'ranking.v1';

  static Future<RankingData> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kData);
    if (raw == null) return RankingData.empty;
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      return RankingData(
        rating: json['rating'] as int,
        games: json['games'] as int,
        wins: json['wins'] as int,
        losses: json['losses'] as int,
        draws: json['draws'] as int,
        records: [
          for (final r in json['records'] as List)
            GameRecord.fromJson(r as Map<String, dynamic>)
        ],
      );
    } on Object {
      return RankingData.empty; // 손상된 데이터는 초기화
    }
  }

  static Future<RankingData> addRecord(GameRecord record) async {
    final data = (await load()).addRecord(record);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _kData,
        jsonEncode({
          'rating': data.rating,
          'games': data.games,
          'wins': data.wins,
          'losses': data.losses,
          'draws': data.draws,
          'records': [for (final r in data.records) r.toJson()],
        }));
    return data;
  }
}
