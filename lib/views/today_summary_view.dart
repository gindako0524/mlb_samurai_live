// lib/views/today_summary_view.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/player.dart';
import '../services/schedule_provider.dart';
import '../utils/jst_time.dart';
import '../services/pinned_players_provider.dart';

class TodaySummaryView extends ConsumerStatefulWidget {
  const TodaySummaryView({super.key});

  @override
  ConsumerState<TodaySummaryView> createState() => _TodaySummaryViewState();
}

class _TodaySummaryViewState extends ConsumerState<TodaySummaryView> {
  bool _isLoading = true;
  String? _error;
  List<Map<String, dynamic>> _summaries = [];

  @override
  void initState() {
    super.initState();
    _fetchAll();
  }

  DateTime _dateOnly(DateTime dt) => DateTime(dt.year, dt.month, dt.day);

  /// ボックススコアから該当選手の成績(batting/pitching)を抽出する
  Map<String, dynamic>? _extractBoxscoreStat(Map<String, dynamic> feed, int personId, bool isPitcher) {
    final teams = feed['liveData']?['boxscore']?['teams'] as Map<String, dynamic>?;
    if (teams == null) return null;
    for (final side in ['home', 'away']) {
      final players = teams[side]?['players'] as Map<String, dynamic>?;
      final playerData = players?['ID$personId'] as Map<String, dynamic>?;
      if (playerData == null) continue;
      final stats = playerData['stats'] as Map<String, dynamic>?;
      dynamic group;
      if (isPitcher) {
        group = stats?['pitching'];
      } else {
        group = stats?['batting'];
      }
      if (group is Map<String, dynamic> && group.isNotEmpty) return group;
    }
    return null;
  }

  String? _opponentName(Map<String, dynamic> feed, int personId) {
    final teams = feed['liveData']?['boxscore']?['teams'] as Map<String, dynamic>?;
    if (teams == null) return null;
    final homePlayers = teams['home']?['players'] as Map<String, dynamic>?;
    final isHome = homePlayers?.containsKey('ID$personId') == true;
    final oppSide = isHome ? 'away' : 'home';
    return feed['gameData']?['teams']?[oppSide]?['name']?.toString();
  }

  Future<void> _fetchAll() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final api = ref.read(apiServiceProvider);

      // ★ すでにJST変換済みのシーズンスケジュールから「今日」の試合だけを抽出する
      final games = await ref.read(seasonScheduleProvider.future);
      final today = _dateOnly(nowJst());
      final todaysGames = games.where((g) => _dateOnly(g.gameTimeJst) == today).toList();

      final List<Map<String, dynamic>> results = [];

      await Future.wait(todaysGames.map((game) async {
        if (game.status != 'Live' && game.status != 'Final') return; // 試合前はまだ成績が無い
        try {
          final feed = await api.getLiveGameFeed(game.gamePk);
          for (final p in game.participatingJapanesePlayers) {
            final isOhtani = p.id == 660271;
            final rolesToCheck = isOhtani ? [false, true] : [p.isPitcher];

            for (final isPitcherRole in rolesToCheck) {
              final stat = _extractBoxscoreStat(feed, p.id, isPitcherRole);
              if (stat == null) continue;

              String summary;
              if (isPitcherRole) {
                final ip = stat['inningsPitched'];
                if (ip == null || ip == '0.0') continue;
                summary =
                    '$ip回 ${stat['earnedRuns'] ?? '0'}自責 ${stat['strikeOuts'] ?? '0'}奪三振 ${stat['baseOnBalls'] ?? '0'}四球 / 被安打${stat['hits'] ?? '0'} 被本塁打${stat['homeRuns'] ?? '0'}';
              } else {
                final ab = stat['atBats'] ?? 0;
                if (ab == 0) continue;
                final h = stat['hits'] ?? 0;
                summary = '$ab打数$h安打 ${stat['homeRuns'] ?? '0'}本塁打 ${stat['rbi'] ?? '0'}打点 ${stat['baseOnBalls'] ?? '0'}四球';
              }

              results.add({
                'player': p,
                'isPitcher': isPitcherRole,
                'opponent': _opponentName(feed, p.id) ?? '-',
                'summary': summary,
              });
            }
          }
        } catch (_) {
          // 個別試合の取得失敗はスキップ
        }
      }));

      if (mounted) {
        final pinnedIds = ref.read(pinnedPlayersProvider);
        results.sort((a, b) {
          final aPinned = pinnedIds.contains((a['player'] as JapanesePlayer).id);
          final bPinned = pinnedIds.contains((b['player'] as JapanesePlayer).id);
          if (aPinned == bPinned) return 0;
          return aPinned ? -1 : 1;
        });
        setState(() {
          _summaries = results;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '取得エラー: $e';
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final todayLabel = nowJst();
    final dateLabel = '${todayLabel.year}/${todayLabel.month}/${todayLabel.day}';

    return Scaffold(
      appBar: AppBar(
        title: const Text('本日の日本人選手成績', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _fetchAll),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!, style: const TextStyle(color: Colors.redAccent)))
              : Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          const Icon(Icons.today, size: 18, color: Colors.amberAccent),
                          const SizedBox(width: 8),
                          Text('$dateLabel (JST)', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.amberAccent)),
                        ],
                      ),
                    ),
                    Expanded(
                      child: _summaries.isEmpty
                          ? const Center(
                              child: Text('本日出場・登板した日本人選手はいません\n(試合前の場合もここには表示されません)', textAlign: TextAlign.center, style: TextStyle(color: Colors.white54)),
                            )
                          : ListView.separated(
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                              itemCount: _summaries.length,
                              separatorBuilder: (_, _) => const SizedBox(height: 10),
                              itemBuilder: (context, index) {
                                final item = _summaries[index];
                                final JapanesePlayer p = item['player'];
                                final bool isPitcher = item['isPitcher'];
                                return Card(
                                  color: const Color(0xFF1E1E2C),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  child: Padding(
                                    padding: const EdgeInsets.all(14),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            CircleAvatar(
                                              radius: 12,
                                              backgroundColor: isPitcher ? Colors.greenAccent : Colors.orangeAccent,
                                              child: Text(
                                                isPitcher ? '投' : '打',
                                                style: const TextStyle(fontSize: 10, color: Colors.black, fontWeight: FontWeight.bold),
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Text(
                                              '${p.nameJa} (${p.teamName})',
                                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.blueAccent),
                                            ),
                                            if (ref.watch(pinnedPlayersProvider).contains(p.id)) ...[
                                              const SizedBox(width: 4),
                                              const Icon(Icons.push_pin, size: 12, color: Colors.amberAccent),
                                            ],
                                            const Spacer(),
                                            Flexible(
                                              child: Text(
                                                'vs ${item['opponent']}',
                                                style: const TextStyle(fontSize: 11, color: Colors.white54),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 8),
                                        Text(item['summary'] as String, style: const TextStyle(fontSize: 13, color: Colors.white)),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
    );
  }
}