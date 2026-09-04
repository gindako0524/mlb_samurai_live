import 'player.dart';

class GameScheduleItem {
  final int gamePk;
  final String status; // 'Preview', 'Live', 'Final'
  final DateTime gameTimeJst; // 日本時間
  final String awayTeam;
  final String homeTeam;
  final int? awayTeamId;
  final int? homeTeamId;
  final int awayScore;
  final int homeScore;
  final String currentInning;
  final List<JapanesePlayer> participatingJapanesePlayers;
  final String? probablePitcherJa; // 日本人先発予告
  final bool isPredicted; // 登板予想かどうか

  GameScheduleItem({
    required this.gamePk,
    required this.status,
    required this.gameTimeJst,
    required this.awayTeam,
    required this.homeTeam,
    this.awayTeamId,
    this.homeTeamId,
    required this.awayScore,
    required this.homeScore,
    required this.currentInning,
    required this.participatingJapanesePlayers,
    this.probablePitcherJa,
    this.isPredicted = false,
  });

  // 試合開始までのカウントダウン文字列
  String get countdownText {
    final now = DateTime.now();
    if (now.isAfter(gameTimeJst)) {
      return status == 'Live' ? '試合中' : '試合終了';
    }
    final diff = gameTimeJst.difference(now);
    final hours = diff.inHours;
    final minutes = diff.inMinutes % 60;
    if (hours > 0) {
      return 'あと $hours 時間 $minutes 分';
    } else {
      return 'あと $minutes 分';
    }
  }
}