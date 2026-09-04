// lib/services/mlb_api_service.dart

import 'dart:convert';
import 'package:http/http.dart' as http;

class MlbApiService {
  static const String _baseUrl = 'https://statsapi.mlb.com/api/v1';

  // 直近1週間のスケジュールを取得（今日を中心とした前後3日）
  Future<Map<String, dynamic>> getTodaySchedule() async {
    final now = DateTime.now();
    final start = now.subtract(const Duration(days: 3));
    final end = now.add(const Duration(days: 3));

    final startStr = '${start.year}-${start.month.toString().padLeft(2, '0')}-${start.day.toString().padLeft(2, '0')}';
    final endStr = '${end.year}-${end.month.toString().padLeft(2, '0')}-${end.day.toString().padLeft(2, '0')}';

    final url = Uri.parse('$_baseUrl/schedule?sportId=1&startDate=$startStr&endDate=$endStr&hydrate=probablePitcher,linescore,team');
    final res = await http.get(url);
    if (res.statusCode == 200) {
      return json.decode(utf8.decode(res.bodyBytes));
    }
    throw Exception('Failed to load schedule');
  }

  // ★ シーズン全体のスケジュールを取得（対象チームのみに絞ることで通信量を抑える）
  Future<Map<String, dynamic>> getSeasonScheduleForTeams(List<int> teamIds, {int season = 2026}) async {
    final teamIdParam = teamIds.toSet().join(',');
    final url = Uri.parse(
      '$_baseUrl/schedule?sportId=1&teamId=$teamIdParam&season=$season&gameType=R&hydrate=probablePitcher,linescore,team',
    );
    final res = await http.get(url);
    if (res.statusCode == 200) {
      return json.decode(utf8.decode(res.bodyBytes));
    }
    throw Exception('Failed to load season schedule');
  }

  // ★ MLB全30球団・シーズン全体のスケジュールを取得（チーム絞り込み無し）
  Future<Map<String, dynamic>> getSeasonScheduleAll({int season = 2026}) async {
    final url = Uri.parse(
      '$_baseUrl/schedule?sportId=1&season=$season&gameType=R&hydrate=probablePitcher,linescore,team',
    );
    final res = await http.get(url);
    if (res.statusCode == 200) {
      return json.decode(utf8.decode(res.bodyBytes));
    }
    throw Exception('Failed to load full season schedule');
  }

  // リアルタイム試合フィード
  Future<Map<String, dynamic>> getLiveGameFeed(int gamePk) async {
    final url = Uri.parse('https://statsapi.mlb.com/api/v1.1/game/$gamePk/feed/live');
    final res = await http.get(url);
    if (res.statusCode == 200) {
      return json.decode(utf8.decode(res.bodyBytes));
    }
    throw Exception('Failed to load live game feed');
  }

  // 選手の2026年レギュラーシーズン公式成績を取得
  Future<Map<String, dynamic>> getPlayerGameLog(int playerId, {required bool isPitcher}) async {
    final group = isPitcher ? 'pitching' : 'hitting';
    final url = Uri.parse(
      '$_baseUrl/people/$playerId/stats?stats=season,byMonth,gameLog&group=$group&season=2026&gameType=R',
    );
    final res = await http.get(url);
    if (res.statusCode == 200) {
      return json.decode(utf8.decode(res.bodyBytes));
    }
    throw Exception('Failed to load player stats');
  }

  // ★ 選手の通算成績(career) + 年度別成績(yearByYear)を取得
  Future<Map<String, dynamic>> getPlayerCareerAndYearByYear(int playerId, {required bool isPitcher}) async {
    final group = isPitcher ? 'pitching' : 'hitting';
    final url = Uri.parse(
      '$_baseUrl/people/$playerId/stats?stats=career,yearByYear&group=$group&gameType=R',
    );
    final res = await http.get(url);
    if (res.statusCode == 200) {
      return json.decode(utf8.decode(res.bodyBytes));
    }
    throw Exception('Failed to load career stats');
  }

  // ★ 選手の通算ポストシーズン成績（ワールドシリーズも含む全ポストシーズン合算値）
  Future<Map<String, dynamic>> getPlayerPostseasonCareer(int playerId, {required bool isPitcher}) async {
    final group = isPitcher ? 'pitching' : 'hitting';
    final url = Uri.parse(
      '$_baseUrl/people/$playerId/stats?stats=career&group=$group&gameType=P',
    );
    final res = await http.get(url);
    if (res.statusCode == 200) {
      return json.decode(utf8.decode(res.bodyBytes));
    }
    throw Exception('Failed to load postseason career stats');
  }

  // ★ 地区順位表（AL=103, NL=104）
  Future<Map<String, dynamic>> getStandings({int season = 2026}) async {
    final url = Uri.parse('$_baseUrl/standings?leagueId=103,104&season=$season');
    final res = await http.get(url);
    if (res.statusCode == 200) {
      return json.decode(utf8.decode(res.bodyBytes));
    }
    throw Exception('Failed to load standings');
  }

  // ★ 指定球団のアクティブロースター
  Future<Map<String, dynamic>> getTeamRoster(int teamId) async {
    final url = Uri.parse('$_baseUrl/teams/$teamId/roster?rosterType=active');
    final res = await http.get(url);
    if (res.statusCode == 200) {
      return json.decode(utf8.decode(res.bodyBytes));
    }
    throw Exception('Failed to load team roster');
  }

  // ★ 指定球団内でのカテゴリ別TOP選手（成績順に並んで返る）
  Future<Map<String, dynamic>> getTeamLeaders(int teamId, List<String> leaderCategories, {int season = 2026}) async {
    final categoriesParam = leaderCategories.join(',');
    final url = Uri.parse(
      '$_baseUrl/teams/$teamId/leaders?leaderCategories=$categoriesParam&season=$season&leaderGameTypes=R',
    );
    final res = await http.get(url);
    if (res.statusCode == 200) {
      return json.decode(utf8.decode(res.bodyBytes));
    }
    throw Exception('Failed to load team leaders');
  }

  // ★ 複数選手の今シーズン成績を1リクエストでまとめて取得（ロースター一覧の簡易成績表示用）
  Future<Map<String, dynamic>> getBulkPlayerSeasonStats(List<int> personIds, String group, {int season = 2026}) async {
    if (personIds.isEmpty) return {'people': []};
    final idsParam = personIds.join(',');
    final url = Uri.parse(
      '$_baseUrl/people?personIds=$idsParam&hydrate=stats(group=[$group],type=[season],season=$season)',
    );
    final res = await http.get(url);
    if (res.statusCode == 200) {
      return json.decode(utf8.decode(res.bodyBytes));
    }
    throw Exception('Failed to load bulk player stats');
  }

  // ★ MLB全30球団の一覧（対戦チーム別成績を出す際の相手チームリストとして使う）
  Future<Map<String, dynamic>> getAllTeams() async {
    final url = Uri.parse('$_baseUrl/teams?sportId=1&activeStatus=Yes');
    final res = await http.get(url);
    if (res.statusCode == 200) {
      return json.decode(utf8.decode(res.bodyBytes));
    }
    throw Exception('Failed to load teams');
  }

  // ★ 選手の「特定の相手球団に対する通算成績」（対戦チーム別成績の1球団分）
  Future<Map<String, dynamic>> getVsTeamStats(int personId, String group, int opposingTeamId, {int season = 2026}) async {
    final url = Uri.parse(
      '$_baseUrl/people/$personId/stats?stats=vsTeam&group=$group&opposingTeamId=$opposingTeamId&season=$season',
    );
    final res = await http.get(url);
    if (res.statusCode == 200) {
      return json.decode(utf8.decode(res.bodyBytes));
    }
    throw Exception('Failed to load vsTeam stats');
  }

  // ★ 選手の今シーズン成績を「持っている項目を全部」取得する（WAR以外の全成績閲覧用）
  Future<Map<String, dynamic>> getPlayerFullSeasonStats(int personId, String group, {int season = 2026}) async {
    final url = Uri.parse(
      '$_baseUrl/people/$personId/stats?stats=season&group=$group&season=$season',
    );
    final res = await http.get(url);
    if (res.statusCode == 200) {
      return json.decode(utf8.decode(res.bodyBytes));
    }
    throw Exception('Failed to load full season stats');
  }

  // ★ 選手の試合ごとの成績一覧（バッテリー別成績を出す際、各試合のgamePkと
  //   その試合の成績を取得するために使う）
  Future<Map<String, dynamic>> getPlayerGameLogStats(int personId, String group, {int season = 2026}) async {
    final url = Uri.parse(
      '$_baseUrl/people/$personId/stats?stats=gameLog&group=$group&season=$season&gameType=R',
    );
    final res = await http.get(url);
    if (res.statusCode == 200) {
      return json.decode(utf8.decode(res.bodyBytes));
    }
    throw Exception('Failed to load game log stats');
  }

  // ★ 1試合のボックススコア（バッテリー別成績を出す際、その試合の捕手を特定するために使う）
  Future<Map<String, dynamic>> getGameBoxscore(int gamePk) async {
    final url = Uri.parse('$_baseUrl/game/$gamePk/boxscore');
    final res = await http.get(url);
    if (res.statusCode == 200) {
      return json.decode(utf8.decode(res.bodyBytes));
    }
    throw Exception('Failed to load game boxscore');
  }

  // ★ セイバーメトリクス指標(wOBA/wRC/wRC+/FIP/xFIP/ERA-等)。MLB公式APIが直接算出済みの値を返す。
  Future<Map<String, dynamic>> getPlayerSabermetrics(int personId, String group, {int season = 2026}) async {
    final url = Uri.parse(
      '$_baseUrl/people/$personId/stats?stats=sabermetrics&group=$group&season=$season',
    );
    final res = await http.get(url);
    if (res.statusCode == 200) {
      return json.decode(utf8.decode(res.bodyBytes));
    }
    throw Exception('Failed to load sabermetrics');
  }

  // ★ 全30球団分のチーム打撃成績(リーグ平均OPS算出=OPS+の簡易計算に使用)。
  Future<Map<String, dynamic>> getAllTeamsHittingStats({int season = 2026}) async {
    final url = Uri.parse('$_baseUrl/teams/stats?stats=season&group=hitting&season=$season&sportIds=1');
    final res = await http.get(url);
    if (res.statusCode == 200) {
      return json.decode(utf8.decode(res.bodyBytes));
    }
    throw Exception('Failed to load league hitting stats');
  }

  // ★ 期待値指標(xBA/xSLG/xwOBA)。MLB公式APIのStatcast由来の値を返す。
  Future<Map<String, dynamic>> getPlayerExpectedStats(int personId, String group, {int season = 2026}) async {
    final url = Uri.parse(
      '$_baseUrl/people/$personId/stats?stats=expectedStatistics&group=$group&season=$season',
    );
    final res = await http.get(url);
    if (res.statusCode == 200) {
      return json.decode(utf8.decode(res.bodyBytes));
    }
    throw Exception('Failed to load expected statistics');
  }
}