import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/player.dart';
import '../models/schedule.dart';
import '../services/mlb_api_service.dart';
import '../services/schedule_provider.dart';
import '../widgets/strike_zone.dart';
import '../widgets/inning_pitch_meter.dart';

class LiveView extends ConsumerStatefulWidget {
  final JapanesePlayer? initialPlayer;
  final GameScheduleItem? initialGame;

  const LiveView({super.key, this.initialPlayer, this.initialGame});

  @override
  ConsumerState<LiveView> createState() => _LiveViewState();
}

class _LiveViewState extends ConsumerState<LiveView> {
  Timer? _timer;
  bool _isLoading = false;
  bool _useDemoMode = false; // 試合がない時間用のデモ切替フラグ

  // 画面表示用ステート
  String _matchupHeader = '対戦カード読込中...';
  String _inningCountText = '-';
  String _currentBatter = '打者: -';
  String _countText = 'カウント: -';
  String _liveEra = '-';
  String _eraDiff = '';
  String _todaySummary = '-';
  
  List<PitchData> _currentPitches = [];
  List<InningPitchData> _innings = [];

  @override
  void initState() {
    super.initState();
    _fetchLiveData();
    // 10秒ごとにMLB APIを自動ポーリング
    _timer = Timer.periodic(const Duration(seconds: 10), (_) => _fetchLiveData());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  // MLB公式APIから最新の投球・カウント・スタッツを抽出
  Future<void> _fetchLiveData() async {
    if (_useDemoMode) {
      _loadDemoData();
      return;
    }

    final gamePk = widget.initialGame?.gamePk;
    if (gamePk == null) {
      // 試合が未選択の場合は自動でデモモードへフォールバック
      _loadDemoData();
      return;
    }

    setState(() => _isLoading = true);

    try {
      final api = ref.read(apiServiceProvider);
      final liveData = await api.getLiveGameFeed(gamePk);

      final gameData = liveData['gameData'] as Map<String, dynamic>?;
      final liveFeed = liveData['liveData'] as Map<String, dynamic>?;
      final linescore = liveFeed?['linescore'] as Map<String, dynamic>?;
      final plays = liveFeed?['plays'] as Map<String, dynamic>?;
      final currentPlay = plays?['currentPlay'] as Map<String, dynamic>?;

      // 1. スコア・イニング情報
      final awayTeam = gameData?['teams']?['away']?['name'] ?? 'Away';
      final homeTeam = gameData?['teams']?['home']?['name'] ?? 'Home';
      final awayScore = linescore?['teams']?['away']?['runs'] ?? 0;
      final homeScore = linescore?['teams']?['home']?['runs'] ?? 0;
      final inningHalf = linescore?['isTopInning'] == true ? '表' : '裏';
      final inningNum = linescore?['currentInning'] ?? 1;
      final outs = linescore?['outs'] ?? 0;

      _matchupHeader = '$awayTeam $awayScore - $homeScore $homeTeam';
      _inningCountText = '$inningNum回$inningHalf $outsアウト';

      // 2. 打者・カウント情報
      final batterName = currentPlay?['matchup']?['batter']?['fullName'] ?? '打者';
      final balls = currentPlay?['count']?['balls'] ?? 0;
      final strikes = currentPlay?['count']?['strikes'] ?? 0;
      _currentBatter = '打者: $batterName';
      _countText = 'B:$balls S:$strikes ($outsアウト)';

      // 3. 現在の打席の配球（9分割プロット用）
      final playEvents = currentPlay?['playEvents'] as List<dynamic>? ?? [];
      List<PitchData> parsedPitches = [];
      int pitchIdx = 1;

      for (final event in playEvents) {
        if (event['isPitch'] == true) {
          final pitchData = event['pitchData'] as Map<String, dynamic>?;
          final coords = pitchData?['coordinates'] as Map<String, dynamic>?;
          final details = event['details'] as Map<String, dynamic>?;

          final px = (coords?['pX'] as num?)?.toDouble() ?? 0.0;
          final pz = (coords?['pZ'] as num?)?.toDouble() ?? 2.5;
          final mph = (pitchData?['startSpeed'] as num?)?.toDouble() ?? 90.0;
          final kmh = mph * 1.60934; // km/h 変換

          parsedPitches.add(PitchData(
            pitchNumber: pitchIdx++,
            pitchName: details?['type']?['description'] ?? '球種不明',
            speedKmh: kmh,
            x: px,
            y: pz,
            callResult: details?['description'] ?? '',
          ));
        }
      }

      // 4. イニング別球数メーターの集計
      final allPlays = plays?['allPlays'] as List<dynamic>? ?? [];
      Map<int, int> pitchPerInning = {};
      for (final p in allPlays) {
        final inn = (p['about']?['inning'] as num?)?.toInt() ?? 1;
        final events = p['playEvents'] as List<dynamic>? ?? [];
        for (final e in events) {
          if (e['isPitch'] == true) {
            pitchPerInning[inn] = (pitchPerInning[inn] ?? 0) + 1;
          }
        }
      }

      List<InningPitchData> parsedInnings = [];
      pitchPerInning.forEach((inn, count) {
        parsedInnings.add(InningPitchData(
          inning: inn,
          pitchCount: count,
          isCurrent: inn == inningNum,
        ));
      });

      // 5. ボックススコアから日本人投手の成績抽出
      final boxscore = liveFeed?['boxscore'] as Map<String, dynamic>?;
      final targetPlayerId = widget.initialPlayer?.id ?? 808967; // デフォルト山本由伸
      final pitcherStats = _findPitcherStats(boxscore, targetPlayerId);

      if (mounted) {
        setState(() {
          _currentPitches = parsedPitches;
          _innings = parsedInnings.isNotEmpty ? parsedInnings : _innings;
          if (pitcherStats != null) {
            _liveEra = pitcherStats['era'] ?? '2.15';
            _todaySummary = '本日: ${pitcherStats['ip']}回 ${pitcherStats['np']}球 被安打${pitcherStats['h']} 奪三振${pitcherStats['k']} 自責点${pitcherStats['er']}';
          }
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Map<String, String>? _findPitcherStats(Map<String, dynamic>? boxscore, int playerId) {
    if (boxscore == null) return null;
    final teams = ['away', 'home'];
    for (final t in teams) {
      final pitchers = boxscore['teams']?[t]?['pitchers'] as List<dynamic>? ?? [];
      if (pitchers.contains(playerId)) {
        final pData = boxscore['teams']?[t]?['players']?['ID$playerId']?['stats']?['pitching'];
        if (pData != null) {
          return {
            'ip': pData['inningsPitched']?.toString() ?? '0.0',
            'np': pData['numberOfPitches']?.toString() ?? '0',
            'h': pData['hits']?.toString() ?? '0',
            'k': pData['strikeOuts']?.toString() ?? '0',
            'er': pData['earnedRuns']?.toString() ?? '0',
            'era': pData['era']?.toString() ?? '2.15',
          };
        }
      }
    }
    return null;
  }

  void _loadDemoData() {
    setState(() {
      _matchupHeader = 'パドレス 1 - 3 ドジャース';
      _inningCountText = '6回表 2アウト (走者1塁)';
      _currentBatter = '打者: 3番 タティスJr. (右打)';
      _countText = 'B:2 S:2 (5球目)';
      _liveEra = '2.15';
      _eraDiff = '(-0.15)';
      _todaySummary = '本日: 5.2回 84球 被安打3 奪三振8 自責点1';
      _currentPitches = const [
        PitchData(pitchNumber: 1, pitchName: '4-Seam Fastball', speedKmh: 157.8, x: -0.4, y: 3.2, callResult: 'ボール'),
        PitchData(pitchNumber: 2, pitchName: 'Curveball', speedKmh: 125.4, x: 0.3, y: 1.8, callResult: '見逃しストライク'),
        PitchData(pitchNumber: 3, pitchName: 'Splitter', speedKmh: 146.2, x: 0.1, y: 1.2, callResult: '空振りストライク'),
        PitchData(pitchNumber: 4, pitchName: '4-Seam Fastball', speedKmh: 158.5, x: 0.6, y: 2.8, callResult: 'ファウル'),
        PitchData(pitchNumber: 5, pitchName: 'Splitter', speedKmh: 147.0, x: -0.2, y: 0.9, callResult: '空振り三振！'),
      ];
      _innings = const [
        InningPitchData(inning: 1, pitchCount: 12),
        InningPitchData(inning: 2, pitchCount: 19),
        InningPitchData(inning: 3, pitchCount: 11),
        InningPitchData(inning: 4, pitchCount: 14),
        InningPitchData(inning: 5, pitchCount: 13),
        InningPitchData(inning: 6, pitchCount: 15, isCurrent: true),
      ];
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final playerName = widget.initialPlayer?.nameJa ?? '山本 由伸';
    final teamName = widget.initialPlayer?.teamName ?? 'LAD';

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const CircleAvatar(radius: 4, backgroundColor: Colors.redAccent),
            const SizedBox(width: 8),
            Text('$playerName ライブ観戦', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ],
        ),
        actions: [
          // デモ/本番切り替えスイッチ（試合がない時間用）
          Row(
            children: [
              Text(_useDemoMode ? 'デモ' : 'API連動', style: const TextStyle(fontSize: 11, color: Colors.white70)),
              Switch(
                value: _useDemoMode,
                onChanged: (val) {
                  setState(() => _useDemoMode = val);
                  _fetchLiveData();
                },
              ),
            ],
          ),
          IconButton(
            icon: _isLoading
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.refresh),
            onPressed: _fetchLiveData,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. ヘッダー：対戦カード & リアルタイム防御率
            Card(
              color: const Color(0xFF1E1E2C),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('$playerName ($teamName)', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                            Text('$_matchupHeader ($_inningCountText)', style: const TextStyle(color: Colors.white70, fontSize: 13)),
                          ],
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.green.withAlpha(40),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.greenAccent),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              const Text('リアルタイム防御率', style: TextStyle(fontSize: 10, color: Colors.greenAccent)),
                              Row(
                                children: [
                                  Text(_liveEra, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.greenAccent)),
                                  if (_eraDiff.isNotEmpty) ...[
                                    const Icon(Icons.arrow_downward, color: Colors.greenAccent, size: 16),
                                    Text(_eraDiff, style: const TextStyle(fontSize: 11, color: Colors.greenAccent)),
                                  ],
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: 20, color: Colors.white12),
                    Text(_todaySummary, style: const TextStyle(fontSize: 13, color: Colors.white)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),

            // 2. 対戦打者・カウント
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white10,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(_currentBatter, style: const TextStyle(fontWeight: FontWeight.bold)),
                  Text(_countText, style: const TextStyle(color: Colors.amberAccent, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // 3. 配球ゾーン & イニング球数メーター
            SizedBox(
              height: 280,
              child: Row(
                children: [
                  StrikeZoneWidget(pitches: _currentPitches),
                  const SizedBox(width: 10),
                  Expanded(
                    child: InningPitchMeterWidget(innings: _innings),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // 4. 今の打席の全球ログ
            Card(
              color: const Color(0xFF1E1E2C),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('現在の打席 配球ログ', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    const SizedBox(height: 8),
                    if (_currentPitches.isEmpty)
                      const Text('投球待機中...', style: TextStyle(color: Colors.white54, fontSize: 12))
                    else
                      ..._currentPitches.map((p) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 9,
                              backgroundColor: Colors.blueAccent,
                              child: Text('${p.pitchNumber}', style: const TextStyle(fontSize: 10, color: Colors.white)),
                            ),
                            const SizedBox(width: 8),
                            Expanded(child: Text(p.pitchName, style: const TextStyle(fontSize: 12))),
                            Text('${p.speedKmh.toStringAsFixed(1)} km/h', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                            const SizedBox(width: 8),
                            Text(
                              p.callResult,
                              style: TextStyle(
                                fontSize: 12,
                                color: p.callResult.contains('三振')
                                    ? Colors.cyanAccent
                                    : (p.callResult.contains('ストライク')
                                        ? Colors.amberAccent
                                        : Colors.white70),
                              ),
                            ),
                          ],
                        ),
                      )),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}