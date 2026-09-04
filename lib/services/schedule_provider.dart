import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/schedule.dart';
import '../models/player.dart';
import 'mlb_api_service.dart';
import '../utils/jst_time.dart';

final apiServiceProvider = Provider<MlbApiService>((ref) => MlbApiService());

/// レスポンスJSONから GameScheduleItem のリストへ変換する共通処理
/// （直近3日版・シーズン全体版の両方から利用する）
/// includeAllGames=true の場合、日本人選手が出場しない試合も含めて全件返す
/// （「MLB全体」表示スコープ用）。falseの場合は従来通り日本人選手が
/// 出場する試合のみに絞る。
List<GameScheduleItem> _parseSchedule(Map<String, dynamic> responseData, {bool includeAllGames = false}) {
  List<GameScheduleItem> allGames = [];

  try {
    final dates = responseData['dates'] as List<dynamic>? ?? [];
    for (final dateObj in dates) {
      final gamesList = dateObj['games'] as List<dynamic>? ?? [];

      for (final game in gamesList) {
        final gamePk = game['gamePk'] as int? ?? 0;
        final statusMap = game['status'] as Map<String, dynamic>?;
        final abstractState = statusMap?['abstractGameState']?.toString() ?? 'Preview';
        final detailedState = statusMap?['detailedState']?.toString() ?? 'Scheduled';

        final gameDateStr = game['gameDate']?.toString();
        final gameTimeJst = gameDateStr != null
            ? parseToJst(gameDateStr)
            : nowJst();

        final teamsMap = game['teams'] as Map<String, dynamic>?;
        final awayTeamMap = teamsMap?['away'] as Map<String, dynamic>?;
        final homeTeamMap = teamsMap?['home'] as Map<String, dynamic>?;

        final awayName = awayTeamMap?['team']?['name']?.toString() ?? 'Away';
        final homeName = homeTeamMap?['team']?['name']?.toString() ?? 'Home';

        final awayScore = (awayTeamMap?['score'] as num?)?.toInt() ?? 0;
        final homeScore = (homeTeamMap?['score'] as num?)?.toInt() ?? 0;

        final linescore = game['linescore'] as Map<String, dynamic>?;
        final currentInning = linescore?['currentInningOrdinal']?.toString() ?? '';
        final isTop = linescore?['isTopInning'] == true ? '表' : '裏';

        List<JapanesePlayer> participants = [];
        String? probablePitcherName;

        final awayProbableId = awayTeamMap?['probablePitcher']?['id'] as int?;
        final homeProbableId = homeTeamMap?['probablePitcher']?['id'] as int?;

        // ★ チーム名の部分一致ではなく、MLB公式チームID(teamId)で厳密に判定
        final awayTeamId = awayTeamMap?['team']?['id'] as int?;
        final homeTeamId = homeTeamMap?['team']?['id'] as int?;

        for (final jp in japanesePlayers) {
          final isAway = jp.teamId == awayTeamId;
          final isHome = jp.teamId == homeTeamId;

          if (isAway || isHome) {
            participants.add(jp);
          }

          if (jp.id == awayProbableId || jp.id == homeProbableId) {
            probablePitcherName = '${jp.nameJa} (予告先発)';
          }
        }

        if (participants.isNotEmpty || includeAllGames) {
          allGames.add(GameScheduleItem(
            gamePk: gamePk,
            status: abstractState,
            gameTimeJst: gameTimeJst,
            awayTeam: awayName,
            homeTeam: homeName,
            awayTeamId: awayTeamId,
            homeTeamId: homeTeamId,
            awayScore: awayScore,
            homeScore: homeScore,
            currentInning: abstractState == 'Live' ? '$currentInning$isTop' : detailedState,
            participatingJapanesePlayers: participants,
            probablePitcherJa: probablePitcherName,
          ));
        }
      }
    }
  } catch (_) {}

  allGames.sort((a, b) => a.gameTimeJst.compareTo(b.gameTimeJst));
  return allGames;
}

/// 直近3日分（前後）の試合日程（ライブ観戦画面などが軽量に使う用）
final scheduleProvider = FutureProvider<List<GameScheduleItem>>((ref) async {
  final api = ref.watch(apiServiceProvider);
  final responseData = await api.getTodaySchedule();
  return _parseSchedule(responseData);
});

/// ★ シーズン全体の試合日程（カレンダー表示用）。対象チームのみに絞って取得するため軽量。
final seasonScheduleProvider = FutureProvider<List<GameScheduleItem>>((ref) async {
  final api = ref.watch(apiServiceProvider);
  final teamIds = japanesePlayers.map((p) => p.teamId).toSet().toList();
  final responseData = await api.getSeasonScheduleForTeams(teamIds);
  return _parseSchedule(responseData);
});

/// ★ MLB全30球団・シーズン全体の試合日程。「MLB全体」表示スコープを選んだ時のみ
///   参照されるので（Riverpodは遅延評価のため）、日本人選手所属チームのみを見ている
///   限りは取得されない。
final allMlbSeasonScheduleProvider = FutureProvider<List<GameScheduleItem>>((ref) async {
  final api = ref.watch(apiServiceProvider);
  final responseData = await api.getSeasonScheduleAll();
  return _parseSchedule(responseData, includeAllGames: true);
});