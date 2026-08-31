import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../models/player.dart';
import '../models/schedule.dart';
import '../services/schedule_provider.dart';

class ScheduleView extends ConsumerStatefulWidget {
  final Function(GameScheduleItem game, JapanesePlayer player) onSelectGame;

  const ScheduleView({super.key, required this.onSelectGame});

  @override
  ConsumerState<ScheduleView> createState() => _ScheduleViewState();
}

class _ScheduleViewState extends ConsumerState<ScheduleView> {
  Timer? _countdownTimer;

  @override
  void initState() {
    super.initState();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    super.dispose();
  }

  String _formatPreciseCountdown(DateTime gameTimeJst, String status) {
    final now = DateTime.now();
    if (status == 'Live') return '試合進行中 (LIVE)';
    if (status == 'Final') return '試合終了';

    final diff = gameTimeJst.difference(now);
    if (diff.isNegative) {
      return status == 'Live' ? '試合中' : '試合中 / 終了間近';
    }

    final hours = diff.inHours;
    final minutes = diff.inMinutes % 60;
    final seconds = diff.inSeconds % 60;

    if (hours > 0) {
      return '開始まで あと $hours時間 $minutes分 $seconds秒';
    } else if (minutes > 0) {
      return '開始まで あと $minutes分 $seconds秒';
    } else {
      return 'まもなく開始! あと $seconds秒';
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheduleAsync = ref.watch(scheduleProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.sports_baseball, color: Colors.blueAccent),
            SizedBox(width: 8),
            Text('日本人選手 試合日程 & 予告先発', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ],
        ),
        actions: [
          IconButton(
            tooltip: '日程を最新に更新',
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.refresh(scheduleProvider),
          ),
        ],
      ),
      body: scheduleAsync.when(
        loading: () => const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 12),
              Text('MLB公式日程データを取得中...', style: TextStyle(color: Colors.white70)),
            ],
          ),
        ),
        error: (err, stack) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, color: Colors.redAccent, size: 40),
                const SizedBox(height: 12),
                Text('日程データの取得エラー\n$err', textAlign: TextAlign.center, style: const TextStyle(color: Colors.redAccent)),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  icon: const Icon(Icons.refresh),
                  label: const Text('再試行'),
                  onPressed: () => ref.refresh(scheduleProvider),
                ),
              ],
            ),
          ),
        ),
        data: (games) {
          if (games.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.event_busy, size: 48, color: Colors.white38),
                  const SizedBox(height: 12),
                  const Text('本日〜直近の日本人選手の試合予定はありません', style: TextStyle(color: Colors.white70, fontSize: 14)),
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.refresh),
                    label: const Text('再読み込み'),
                    onPressed: () => ref.refresh(scheduleProvider),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: games.length,
            itemBuilder: (context, index) {
              final game = games[index];
              final isLive = game.status == 'Live';
              final isFinal = game.status == 'Final';
              final timeStr = DateFormat('M/d (E)  HH:mm', 'ja').format(game.gameTimeJst);
              final countdown = _formatPreciseCountdown(game.gameTimeJst, game.status);

              return Card(
                margin: const EdgeInsets.only(bottom: 14),
                elevation: 4,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: BorderSide(
                    color: isLive ? Colors.redAccent : (isFinal ? Colors.white10 : Colors.blueAccent.withAlpha(80)),
                    width: isLive ? 2 : 1,
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.schedule, size: 16, color: Colors.blueAccent[100]),
                              const SizedBox(width: 6),
                              Text(timeStr, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                            ],
                          ),
                          if (isLive)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.redAccent,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Row(
                                children: [
                                  CircleAvatar(radius: 3, backgroundColor: Colors.white),
                                  SizedBox(width: 5),
                                  Text('LIVE', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                                ],
                              ),
                            )
                          else
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: isFinal ? Colors.white10 : Colors.blue.withAlpha(40),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                countdown,
                                style: TextStyle(
                                  color: isFinal ? Colors.white54 : Colors.lightBlueAccent,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const Divider(height: 20, color: Colors.white12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(game.awayTeam, style: const TextStyle(fontSize: 15)),
                                const SizedBox(height: 4),
                                Text(game.homeTeam, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                              ],
                            ),
                          ),
                          if (isLive || isFinal) ...[
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  '${game.awayScore} - ${game.homeScore}',
                                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white),
                                ),
                                Text(
                                  game.currentInning,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: isLive ? Colors.amberAccent : Colors.white54,
                                    fontWeight: isLive ? FontWeight.bold : FontWeight.normal,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                      if (game.probablePitcherJa != null) ...[
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.amber.withAlpha(30),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: Colors.amberAccent.withAlpha(80)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.sports, size: 14, color: Colors.amberAccent),
                              const SizedBox(width: 6),
                              Text(game.probablePitcherJa!, style: const TextStyle(fontSize: 11, color: Colors.amberAccent, fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: game.participatingJapanesePlayers.map((player) {
                          return ActionChip(
                            avatar: CircleAvatar(
                              backgroundColor: player.isPitcher ? Colors.greenAccent : Colors.orangeAccent,
                              child: Text(
                                player.isPitcher ? '投' : '打',
                                style: const TextStyle(fontSize: 10, color: Colors.black, fontWeight: FontWeight.bold),
                              ),
                            ),
                            label: Text('${player.nameJa} の観戦へ'),
                            labelStyle: const TextStyle(fontSize: 12),
                            onPressed: () => widget.onSelectGame(game, player),
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}