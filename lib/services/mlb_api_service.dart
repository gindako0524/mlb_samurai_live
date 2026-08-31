import 'dart:convert';
import 'package:http/http.dart' as http;

class MlbApiService {
  static const String baseUrl = 'https://statsapi.mlb.com/api/v1';

  // 本日の試合日程取得
  Future<Map<String, dynamic>> getTodaysSchedule() async {
    final now = DateTime.now();
    final dateStr = "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";
    final url = Uri.parse('$baseUrl/schedule?sportId=1&date=$dateStr&hydrate=probablePitcher,linescore');
    
    final response = await http.get(url);
    if (response.statusCode == 200) {
      return json.decode(response.body) as Map<String, dynamic>;
    } else {
      throw Exception('試合日程の取得に失敗しました');
    }
  }

  // 選手の直近試合ログ＆今季成績取得
  Future<Map<String, dynamic>> getPlayerGameLog(int playerId, {bool isPitcher = true}) async {
    final group = isPitcher ? 'pitching' : 'hitting';
    // 今季の全試合ログ(gameLog)と月別成績(byMonth)を取得
    final url = Uri.parse('$baseUrl/people/$playerId/stats?stats=gameLog,byMonth,season&group=$group');
    
    final response = await http.get(url);
    if (response.statusCode == 200) {
      return json.decode(response.body) as Map<String, dynamic>;
    } else {
      throw Exception('選手成績の取得に失敗しました');
    }
  }

  // 試合のリアルタイムライブフィード取得
  Future<Map<String, dynamic>> getLiveGameFeed(int gamePk) async {
    final url = Uri.parse('https://statsapi.mlb.com/api/v1.1/game/$gamePk/feed/live');
    final response = await http.get(url);
    if (response.statusCode == 200) {
      return json.decode(response.body) as Map<String, dynamic>;
    } else {
      throw Exception('ライブデータの取得に失敗しました');
    }
  }
}