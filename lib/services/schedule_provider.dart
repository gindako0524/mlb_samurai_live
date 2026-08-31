import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/schedule.dart';
import '../models/player.dart';
import 'mlb_api_service.dart';

final apiServiceProvider = Provider<MlbApiService>((ref) => MlbApiService());

final scheduleProvider = FutureProvider<List<GameScheduleItem>>((ref) async {
  final api = ref.watch(apiServiceProvider);
  
  final responseData = await api.getTodaysSchedule();
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
            ? DateTime.parse(gameDateStr).toLocal()
            : DateTime.now();

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

        for (final jp in japanesePlayers) {
          final isAway = awayName.contains(jp.teamName) || awayName.contains(jp.teamName.replaceAll(' ', ''));
          final isHome = homeName.contains(jp.teamName) || homeName.contains(jp.teamName.replaceAll(' ', ''));

          if (isAway || isHome) {
            participants.add(jp);
          }

          if (jp.id == awayProbableId || jp.id == homeProbableId) {
            probablePitcherName = '${jp.nameJa} (予告先発)';
          }
        }

        if (participants.isNotEmpty) {
          allGames.add(GameScheduleItem(
            gamePk: gamePk,
            status: abstractState,
            gameTimeJst: gameTimeJst,
            awayTeam: awayName,
            homeTeam: homeName,
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
});