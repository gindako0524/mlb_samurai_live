// lib/views/stats_view.dart

import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:http/http.dart' as http;
import 'package:table_calendar/table_calendar.dart';
import '../models/player.dart';
import '../services/schedule_provider.dart';
import '../utils/jst_time.dart';
import 'compare_view.dart';
import '../services/head_to_head_service.dart';
import 'career_stats_view.dart';
import '../widgets/player_picker_sheet.dart';
import '../services/pinned_players_provider.dart';
import '../services/language_provider.dart';
import '../widgets/language_toggle_button.dart';
import '../utils/mlb_translations.dart';
import '../utils/stat_glossary.dart';
import 'player_full_stats_view.dart';
import '../widgets/contract_info_card.dart';
import '../widgets/season_projection_card.dart';
import '../widgets/advanced_stats_card.dart';

class StatsView extends ConsumerStatefulWidget {
  const StatsView({super.key});

  @override
  ConsumerState<StatsView> createState() => _StatsViewState();
}

class _StatsViewState extends ConsumerState<StatsView> {
  int _selectedPlayerIndex = 0;
  bool _isLoading = false;
  String? _errorMessage;

  // 大谷選手用の二刀流表示切り替え（true: 投手, false: 打者）
  bool _ohtaniPitcherMode = false;

  // 公認WARデータ
  double _fwar = 0.0;
  double _rwar = 0.0;
  double _fwarPitch = 0.0;
  double _rwarPitch = 0.0;

  // 取得した詳細スタッツ
  Map<String, dynamic> _seasonStats = {};
  List<Map<String, dynamic>> _monthlyList = [];
  List<Map<String, dynamic>> _recentGames = [];
  Map<int, List<Map<String, dynamic>>> _allGamesByMonth = {}; // ★ 過去試合ドリルダウン用
  List<FlSpot> _monthlySpots = [];
  List<String> _monthLabels = [];
  double _minY = 0.0;
  double _maxY = 5.0;

  // ★ プロフィール情報（生年月日・年齢など）
  String? _birthDateLabel;
  int? _age;

  // ★ シーズン終了予想成績の計算に使う「所属チームの消化試合数」。
  //   選手個人の出場試合数ではなくチームの消化試合数を分母にすることで、
  //   シーズン途中出場の選手でも過大なペース換算にならないようにする
  //   （投手は特に「登板数」と「チーム試合数」が大きく異なるため必須）
  int? _teamGamesPlayed;

  // ★ シーズン終了予想成績（ペース換算）は試合数が増えるたびに変わるため、
  //   開いたまま放置していても自動で最新の成績を反映できるよう定期的に再取得する
  Timer? _pollingTimer;

  @override
  void initState() {
    super.initState();
    _fetchPlayerStats();
    _pollingTimer = Timer.periodic(const Duration(minutes: 2), (_) => _fetchPlayerStats(isAutoRefresh: true));
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    super.dispose();
  }

  // 打率・防御率・数値の安全なフォーマッター
  String _formatRate(dynamic val) {
    if (val == null) return '-';
    String s = val.toString().trim();
    if (s.startsWith('.')) return s;
    final d = double.tryParse(s);
    if (d != null) {
      if (d < 1.0) {
        return '.${(d * 1000).toInt().toString().padLeft(3, '0')}';
      }
      return d.toStringAsFixed(2);
    }
    return s;
  }

  // 米国日付文字列を日本時間 (JST) の MM/dd 形式に変換
  /// 試合の表示用日付(M/d形式)を取得。
  /// gamePkが渡され、かつ試合日程データ(正確なJSTタイムスタンプ)に該当があればそちらを優先。
  /// 無い場合のみ「米国現地日付+1日」の簡易補正にフォールバックする。
  String _formatToJstDate(String dateStr, {int? gamePk, Map<int, DateTime>? gamePkToJst}) {
    if (gamePk != null && gamePkToJst != null && gamePkToJst.containsKey(gamePk)) {
      final d = gamePkToJst[gamePk]!;
      return '${d.month}/${d.day}';
    }
    try {
      if (dateStr.length >= 10) {
        // ★ フォールバック: MLBの試合ログ日付は米国現地日付。米国の試合はほぼ全て現地夕方〜夜開始のため、
        //   日本時間に変換すると必ず「+1日」になる（例: 米国8/31夜 → 日本時間9/1）
        final parsed = DateTime.parse(dateStr).add(const Duration(days: 1));
        return '${parsed.month}/${parsed.day}';
      }
    } catch (_) {}
    return dateStr.length >= 10 ? dateStr.substring(5) : dateStr;
  }

  /// 試合の正確な日付(DateTime)を取得。上記と同じ優先順位。
  DateTime? _resolveGameDate(String dateStr, {int? gamePk, Map<int, DateTime>? gamePkToJst}) {
    if (gamePk != null && gamePkToJst != null && gamePkToJst.containsKey(gamePk)) {
      return gamePkToJst[gamePk];
    }
    try {
      return DateTime.parse(dateStr).add(const Duration(days: 1));
    } catch (_) {
      return null;
    }
  }

  // WARデータ取得（GitHub main ブランチ完全対応）
  Future<void> _fetchWarData(int playerId) async {
    final timestamp = DateTime.now().millisecondsSinceEpoch;

    final urls = [
      'https://raw.githubusercontent.com/gindako0524/mlb_samurai_live/main/war_data.json?t=$timestamp',
      'https://cdn.jsdelivr.net/gh/gindako0524/mlb_samurai_live@main/war_data.json?t=$timestamp',
      'https://api.github.com/repos/gindako0524/mlb_samurai_live/contents/war_data.json?ref=main&t=$timestamp',
    ];

    for (final url in urls) {
      try {
        final response = await http.get(
          Uri.parse(url),
          headers: {'Accept': 'application/vnd.github.v3.raw+json'},
        );

        if (response.statusCode == 200) {
          Map<String, dynamic> data;
          final decoded = json.decode(utf8.decode(response.bodyBytes));

          if (decoded is Map<String, dynamic> && decoded.containsKey('content')) {
            final contentStr = decoded['content'].toString().replaceAll('\n', '').replaceAll('\r', '');
            final decodedBody = utf8.decode(base64.decode(contentStr));
            data = json.decode(decodedBody) as Map<String, dynamic>;
          } else {
            data = decoded as Map<String, dynamic>;
          }

          final playerMap = data['players']?[playerId.toString()];
          if (playerMap != null && mounted) {
            setState(() {
              _fwar = (playerMap['fwar'] as num?)?.toDouble() ?? 0.0;
              _rwar = (playerMap['rwar'] as num?)?.toDouble() ?? 0.0;
              _fwarPitch = (playerMap['fwar_pitch'] as num?)?.toDouble() ?? 0.0;
              _rwarPitch = (playerMap['rwar_pitch'] as num?)?.toDouble() ?? 0.0;
            });
            return;
          }
        }
      } catch (e) {
        debugPrint('WAR取得エラー: $e');
      }
    }
  }

  // ★ 選手プロフィール（生年月日・年齢）を取得
  Future<void> _fetchPlayerProfile(int playerId) async {
    try {
      final url = Uri.parse('https://statsapi.mlb.com/api/v1/people/$playerId');
      final res = await http.get(url);
      if (res.statusCode == 200) {
        final data = json.decode(utf8.decode(res.bodyBytes));
        final people = data['people'] as List<dynamic>? ?? [];
        if (people.isNotEmpty) {
          final person = people.first as Map<String, dynamic>;
          final birthDateStr = person['birthDate']?.toString();
          final age = person['currentAge'] as int?;
          String? label;
          if (birthDateStr != null) {
            try {
              final d = DateTime.parse(birthDateStr);
              label = '${d.year}/${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}';
            } catch (_) {
              label = birthDateStr;
            }
          }
          if (mounted) {
            setState(() {
              _birthDateLabel = label;
              _age = age;
            });
          }
        }
      }
    } catch (e) {
      debugPrint('プロフィール取得エラー: $e');
    }
  }

  // ★ シーズン終了予想成績のペース換算に使う「所属チームの消化試合数」を取得
  Future<void> _fetchTeamGamesPlayed(int teamId) async {
    try {
      final api = ref.read(apiServiceProvider);
      final data = await api.getStandings();
      final records = data['records'] as List<dynamic>? ?? [];
      for (final r in records) {
        final teamRecords = r['teamRecords'] as List<dynamic>? ?? [];
        for (final tr in teamRecords) {
          if ((tr['team']?['id'] as num?)?.toInt() == teamId) {
            final gp = (tr['gamesPlayed'] as num?)?.toInt();
            if (gp != null && mounted) {
              setState(() => _teamGamesPlayed = gp);
            }
            return;
          }
        }
      }
    } catch (e) {
      debugPrint('チーム消化試合数取得エラー: $e');
    }
  }

  Future<void> _fetchPlayerStats({bool isAutoRefresh = false}) async {
    if (!isAutoRefresh) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }

    final targetPlayer = japanesePlayers[_selectedPlayerIndex];
    final bool isPitcherMode = (targetPlayer.id == 660271) ? _ohtaniPitcherMode : targetPlayer.isPitcher;

    // ★ await で確実に WAR データの取得完了を待つ
    await _fetchWarData(targetPlayer.id);
    await _fetchPlayerProfile(targetPlayer.id);
    await _fetchTeamGamesPlayed(targetPlayer.teamId);

    // ★ 試合日程で使っている「正確にJST変換済みのタイムスタンプ」を gamePk 単位で引けるようにする
    //   （試合ログの date は時刻情報のない米国現地日付のため、これで正確な日本時間に置き換える）
    Map<int, DateTime> gamePkToJst = {};
    try {
      final scheduleGames = await ref.read(seasonScheduleProvider.future);
      gamePkToJst = {for (final g in scheduleGames) g.gamePk: g.gameTimeJst};
    } catch (_) {
      // 取得できなくても後段のフォールバック(+1日補正)で動作継続
    }

    try {
      final api = ref.read(apiServiceProvider);
      final data = await api.getPlayerGameLog(targetPlayer.id, isPitcher: isPitcherMode);
      final statsList = data['stats'] as List<dynamic>? ?? [];

      Map<String, dynamic> season = {};
      List<Map<String, dynamic>> rawMonthly = [];
      List<Map<String, dynamic>> recent = [];
      Map<int, List<Map<String, dynamic>>> allGamesByMonthLocal = {};

      for (final s in statsList) {
        final typeName = s['type']?['displayName']?.toString().toLowerCase() ?? '';
        final splits = s['splits'] as List<dynamic>? ?? [];

        if (typeName == 'season') {
          if (splits.isNotEmpty) {
            season = splits.first['stat'] as Map<String, dynamic>? ?? {};
          }
        }

        if (typeName == 'bymonth') {
          for (final m in splits) {
            final monthInt = int.tryParse(m['month']?.toString() ?? '') ?? 0;
            final stat = m['stat'] as Map<String, dynamic>? ?? {};
            if (monthInt > 0) {
              rawMonthly.add({
                'monthInt': monthInt,
                'monthLabel': '$monthInt月',
                'stat': stat,
              });
            }
          }
        }

        if (typeName == 'gamelog') {
          // ★ 直近5試合（詳細情報を拡充）
          for (final game in splits.reversed.take(5)) {
            final rawDate = game['date']?.toString() ?? '';
            final gamePk = game['game']?['gamePk'] as int?;
            final jstDate = _formatToJstDate(rawDate, gamePk: gamePk, gamePkToJst: gamePkToJst);
            final opponent = game['opponent']?['name']?.toString() ?? '';
            final stat = game['stat'] as Map<String, dynamic>? ?? {};

            if (isPitcherMode) {
              recent.add({
                'gamePk': gamePk,
                'date': jstDate,
                'opponent': opponent,
                'detail':
                    '${stat['inningsPitched'] ?? '0'}回 ${stat['earnedRuns'] ?? '0'}自責 ${stat['strikeOuts'] ?? '0'}K ${stat['baseOnBalls'] ?? '0'}四球 / 被安打${stat['hits'] ?? '0'} 被本塁打${stat['homeRuns'] ?? '0'}',
                'main': 'ERA ${stat['era'] ?? '-'}',
                'isPitcher': true,
                'playerId': targetPlayer.id,
              });
            } else {
              final avgStr = _formatRate(stat['avg']);
              final ab = stat['atBats'] ?? 0;
              final hitCount = stat['hits'] ?? 0;
              recent.add({
                'gamePk': gamePk,
                'date': jstDate,
                'opponent': opponent,
                'detail': '$ab打数$hitCount安打 ${stat['homeRuns'] ?? '0'}HR ${stat['rbi'] ?? '0'}打点 ${stat['baseOnBalls'] ?? '0'}四球',
                'main': 'AVG $avgStr',
                'isPitcher': false,
                'playerId': targetPlayer.id,
              });
            }
          }

          // ★ 全登板・全出場試合を月別にグルーピングして保持（過去試合ドリルダウン用）
          final Map<int, List<Map<String, dynamic>>> byMonth = {};
          for (final game in splits) {
            final rawDate = game['date']?.toString() ?? '';
            if (rawDate.length < 7) continue;

            final opponent = game['opponent']?['name']?.toString() ?? '';
            final stat = game['stat'] as Map<String, dynamic>? ?? {};
            final gamePk = game['game']?['gamePk'] as int?;
            final fullDate = _resolveGameDate(rawDate, gamePk: gamePk, gamePkToJst: gamePkToJst);
            if (fullDate == null) continue;

            // ★ 月の振り分けも、米国日付ではなく日本時間換算後の月を基準にする
            final monthInt = fullDate.month;

            final String resultSummary = isPitcherMode
                ? '${stat['inningsPitched'] ?? '0'}回 ${stat['earnedRuns'] ?? '0'}自責 ${stat['strikeOuts'] ?? '0'}K'
                : '${stat['atBats'] ?? '0'}打数${stat['hits'] ?? '0'}安打 ${stat['homeRuns'] ?? '0'}HR';

            byMonth.putIfAbsent(monthInt, () => []).add({
              'gamePk': gamePk,
              'fullDate': fullDate,
              'dateLabel': _formatToJstDate(rawDate, gamePk: gamePk, gamePkToJst: gamePkToJst),
              'opponent': opponent,
              'resultSummary': resultSummary,
              'isPitcher': isPitcherMode,
              'playerId': targetPlayer.id,
            });
          }
          allGamesByMonthLocal = byMonth;
        }
      }

      rawMonthly.sort((a, b) => (a['monthInt'] as int).compareTo(b['monthInt'] as int));

      List<FlSpot> spots = [];
      List<String> months = [];
      double minYVal = 999.0;
      double maxYVal = 0.0;

      for (int i = 0; i < rawMonthly.length; i++) {
        final m = rawMonthly[i];
        final stat = m['stat'] as Map<String, dynamic>;
        months.add(m['monthLabel'] as String);

        double val = 0.0;
        if (isPitcherMode) {
          val = double.tryParse(stat['era']?.toString() ?? '') ?? 0.0;
        } else {
          val = double.tryParse(stat['avg']?.toString() ?? '') ?? 0.0;
        }

        spots.add(FlSpot(i.toDouble(), val));
        if (val < minYVal) minYVal = val;
        if (val > maxYVal) maxYVal = val;
      }

      double calcMinY = isPitcherMode ? (minYVal - 0.5).clamp(0.0, 10.0) : (minYVal - 0.05).clamp(0.0, 1.0);
      double calcMaxY = isPitcherMode ? (maxYVal + 0.8) : (maxYVal + 0.08);

      if (mounted) {
        setState(() {
          _seasonStats = season;
          _monthlyList = rawMonthly;
          _recentGames = recent;
          _allGamesByMonth = allGamesByMonthLocal;
          _monthlySpots = spots;
          _monthLabels = months;
          _minY = calcMinY;
          _maxY = calcMaxY > calcMinY ? calcMaxY : calcMinY + 1.0;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted && !isAutoRefresh) {
        setState(() {
          _errorMessage = 'データ取得エラー: $e';
          _isLoading = false;
        });
      }
    }
  }

  void _showGamePlayByPlayModal(BuildContext context, Map<String, dynamic> gameItem) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF161622),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return _GamePlayByPlaySheet(
          gameItem: gameItem,
        );
      },
    );
  }

  // ★ 選手選択をボトムシートで開く（スマホでの操作性向上のため横スクロールチップから変更）
  Future<void> _openPlayerPicker() async {
    final currentId = japanesePlayers[_selectedPlayerIndex].id;
    final selected = await showPlayerPickerSheet(
      context,
      candidates: japanesePlayers,
      currentPlayerId: currentId,
    );

    if (selected != null && selected.id != currentId) {
      setState(() {
        _selectedPlayerIndex = japanesePlayers.indexWhere((p) => p.id == selected.id);
        _ohtaniPitcherMode = false;
      });
      _fetchPlayerStats();
    }
  }

  @override
  Widget build(BuildContext context) {
    final player = japanesePlayers[_selectedPlayerIndex];
    final isOhtani = player.id == 660271;
    final isPitcherCurrent = isOhtani ? _ohtaniPitcherMode : player.isPitcher;

    return Scaffold(
      appBar: AppBar(
        title: const Text('公式詳細スタッツ & セイバー分析', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _fetchPlayerStats,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // --- 選手選択（タップでボトムシート） ---
            InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: _openPlayerPicker,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E1E2C),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.blueAccent.withAlpha(80)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.person, size: 18, color: Colors.blueAccent),
                        const SizedBox(width: 8),
                        Text(
                          '${player.nameJa} (${player.teamName})',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.blueAccent),
                        ),
                        if (ref.watch(pinnedPlayersProvider).contains(player.id)) ...[
                          const SizedBox(width: 6),
                          const Icon(Icons.push_pin, size: 14, color: Colors.amberAccent),
                        ],
                      ],
                    ),
                    const Icon(Icons.unfold_more, size: 20, color: Colors.white54),
                  ],
                ),
              ),
            ),

            if (_birthDateLabel != null) ...[
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  '生年月日: $_birthDateLabel${_age != null ? ' ($_age歳)' : ''}',
                  style: const TextStyle(fontSize: 11, color: Colors.white54),
                ),
              ),
            ],

            const SizedBox(height: 10),

            // --- 選手比較ボタン ---
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.compare_arrows, size: 18),
                label: const Text('⚔️ 選手を比較する'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.amberAccent,
                  side: const BorderSide(color: Colors.amberAccent),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                ),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const CompareView()),
                  );
                },
              ),
            ),

            const SizedBox(height: 8),

            // --- 通算・年度別成績ボタン ---
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.history, size: 18),
                label: const Text('📈 通算・年度別成績を見る'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.greenAccent,
                  side: const BorderSide(color: Colors.greenAccent),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                ),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => CareerStatsView(player: player)),
                  );
                },
              ),
            ),

            const SizedBox(height: 16),

            if (isOhtani) ...[
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E1E2C),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () {
                          if (_ohtaniPitcherMode) {
                            setState(() => _ohtaniPitcherMode = false);
                            _fetchPlayerStats();
                          }
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          decoration: BoxDecoration(
                            color: !_ohtaniPitcherMode ? Colors.blueAccent : Colors.transparent,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          alignment: Alignment.center,
                          child: const Text('🏏 打撃成績 (DH)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                        ),
                      ),
                    ),
                    Expanded(
                      child: GestureDetector(
                        onTap: () {
                          if (!_ohtaniPitcherMode) {
                            setState(() => _ohtaniPitcherMode = true);
                            _fetchPlayerStats();
                          }
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          decoration: BoxDecoration(
                            color: _ohtaniPitcherMode ? Colors.blueAccent : Colors.transparent,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          alignment: Alignment.center,
                          child: const Text('⚾ 投手成績 (Pitcher)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],

            if (_isLoading)
              const Center(child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator()))
            else if (_errorMessage != null)
              Center(child: Text(_errorMessage!, style: const TextStyle(color: Colors.redAccent)))
            else ...[
              ContractInfoCard(playerId: player.id),
              SeasonProjectionCard(seasonStats: _seasonStats, isPitcher: isPitcherCurrent, teamGamesPlayed: _teamGamesPlayed),
              AdvancedStatsCard(playerId: player.id, isPitcher: isPitcherCurrent, seasonStats: _seasonStats),
              _buildWarCard(player.nameJa, isOhtani, isPitcherCurrent),
              const SizedBox(height: 16),

              Text(
                '${player.nameJa} 2026年 シーズン公式成績 ${isOhtani ? (_ohtaniPitcherMode ? "(投手)" : "(打撃)") : ""}',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.blueAccent),
              ),
              const SizedBox(height: 10),
              if (isPitcherCurrent)
                _buildPitcherDetailedGrid()
              else
                _buildBatterDetailedGrid(),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => PlayerFullStatsView(
                        playerId: player.id,
                        playerName: player.nameJa,
                        isPitcher: isPitcherCurrent,
                        ownTeamId: player.teamId,
                      ),
                    ),
                  ),
                  icon: const Icon(Icons.table_chart, size: 18),
                  label: const Text('全成績・対戦チーム別成績を見る'),
                  style: OutlinedButton.styleFrom(foregroundColor: Colors.blueAccent, side: const BorderSide(color: Colors.blueAccent)),
                ),
              ),
              const SizedBox(height: 24),

              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    isPitcherCurrent ? '月別 防御率 (ERA) の推移' : '月別 打率 (AVG) の推移',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.blueAccent),
                  ),
                  Text(
                    isPitcherCurrent ? '※低いほど好成績' : '※高いほど好成績',
                    style: const TextStyle(fontSize: 11, color: Colors.white54),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              _buildMonthlyGraphCard(isPitcherCurrent),
              const SizedBox(height: 24),

              const Text('月別 パフォーマンス詳細表', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.blueAccent)),
              const SizedBox(height: 10),
              _buildMonthlyTable(isPitcherCurrent),
              const SizedBox(height: 24),

              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: const [
                  Text('直近5試合の登板・出場結果 (JST)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.blueAccent)),
                  Text('※タップで全配球・ゾーン確認', style: TextStyle(fontSize: 11, color: Colors.amberAccent)),
                ],
              ),
              const SizedBox(height: 10),
              _buildRecentGamesCard(),
              const SizedBox(height: 24),

              const Text('過去の登板・出場をもっと見る', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.blueAccent)),
              const SizedBox(height: 10),
              _buildMonthDrilldownList(isPitcherCurrent),
            ],
          ],
        ),
      ),
    );
  }

  // WARカード表示ウィジェット（rWAR単独表示・大谷二刀流合算対応）
  Widget _buildWarCard(String playerName, bool isOhtani, bool isPitcherCurrent) {
    // 大谷選手の場合は 打撃 + 投手を合算。それ以外は表示中の打者/投手区分に対応する方を使う
    // （war_data.jsonは rwar=打撃, rwar_pitch=投手 で常に固定のため、ここで正しく選ぶ必要がある）
    final totalRwar = isOhtani ? (_rwar + _rwarPitch) : (isPitcherCurrent ? _rwarPitch : _rwar);

    return Card(
      color: const Color(0xFF1E2638),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Colors.blueAccent, width: 1.2),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: const [
                    Icon(Icons.analytics, color: Colors.amberAccent, size: 20),
                    SizedBox(width: 6),
                    Text(
                      'セイバーメトリクス総合貢献度 (rWAR)',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.amberAccent),
                    ),
                  ],
                ),
                Text(
                  isOhtani ? '二刀流 投打合算値' : 'Baseball-Reference 公認値',
                  style: const TextStyle(fontSize: 10, color: Colors.white54),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              statGlossary['war']!,
              style: const TextStyle(fontSize: 11, color: Colors.white54),
            ),
            const SizedBox(height: 10),
            Text(
              totalRwar.toStringAsFixed(1),
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 32, color: Colors.amberAccent),
            ),
            if (isOhtani) ...[
              const SizedBox(height: 8),
              const Divider(color: Colors.white10, height: 1),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    '【内訳】 打撃 rWAR: ${_rwar.toStringAsFixed(1)} / 投手 rWAR: ${_rwarPitch.toStringAsFixed(1)}',
                    style: const TextStyle(fontSize: 11, color: Colors.white70),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildPitcherDetailedGrid() {
    return Card(
      color: const Color(0xFF1E1E2C),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _StatCell(label: '防御率 (ERA)', val: _seasonStats['era']?.toString() ?? '-', highlight: true, statKey: 'era'),
                _StatCell(label: '勝 - 敗', val: '${_seasonStats['wins'] ?? 0} - ${_seasonStats['losses'] ?? 0}'),
                _StatCell(label: 'WHIP', val: _seasonStats['whip']?.toString() ?? '-', highlight: true, statKey: 'whip'),
                _StatCell(label: '投球回 (IP)', val: _seasonStats['inningsPitched']?.toString() ?? '-'),
              ],
            ),
            const Divider(height: 20, color: Colors.white12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _StatCell(label: '奪三振 (SO)', val: '${_seasonStats['strikeOuts'] ?? 0}', highlight: true),
                _StatCell(label: '奪三振率 (K/9)', val: _seasonStats['strikeoutsPer9Inn']?.toString() ?? '-', statKey: 'strikeoutsPer9Inn'),
                _StatCell(label: '与四球率 (BB/9)', val: _seasonStats['walksPer9Inn']?.toString() ?? '-', statKey: 'walksPer9Inn'),
                _StatCell(label: 'K/BB 比率', val: _seasonStats['strikeoutWalkRatio']?.toString() ?? '-', statKey: 'strikeoutWalkRatio'),
              ],
            ),
            const Divider(height: 20, color: Colors.white12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _StatCell(label: '被打率 (BAA)', val: _formatRate(_seasonStats['avg']), statKey: 'avg'),
                _StatCell(label: '被本塁打', val: '${_seasonStats['homeRuns'] ?? 0}'),
                _StatCell(label: 'セーブ/ホールド', val: '${_seasonStats['saves'] ?? 0} / ${_seasonStats['holds'] ?? 0}'),
                _StatCell(label: '総投球数 (NP)', val: '${_seasonStats['numberOfPitches'] ?? 0}'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBatterDetailedGrid() {
    final doubles = _seasonStats['doubles'] ?? 0;
    final triples = _seasonStats['triples'] ?? 0;
    final hr = _seasonStats['homeRuns'] ?? 0;
    final extraBases = (doubles as int) + (triples as int) + (hr as int);

    return Card(
      color: const Color(0xFF1E1E2C),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _StatCell(label: '打率 (AVG)', val: _formatRate(_seasonStats['avg']), highlight: true, statKey: 'avg'),
                _StatCell(label: '出塁率 (OBP)', val: _formatRate(_seasonStats['obp']), statKey: 'obp'),
                _StatCell(label: '長打率 (SLG)', val: _formatRate(_seasonStats['slg']), statKey: 'slg'),
                _StatCell(label: 'OPS', val: _seasonStats['ops']?.toString() ?? '-', highlight: true, statKey: 'ops'),
              ],
            ),
            const Divider(height: 20, color: Colors.white12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _StatCell(label: '本塁打 (HR)', val: '$hr', highlight: true),
                _StatCell(label: '打点 (RBI)', val: '${_seasonStats['rbi'] ?? 0}', highlight: true),
                _StatCell(label: '安打数 (H)', val: '${_seasonStats['hits'] ?? 0}'),
                _StatCell(label: '得点 (R)', val: '${_seasonStats['runs'] ?? 0}'),
              ],
            ),
            const Divider(height: 20, color: Colors.white12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _StatCell(label: '二塁打 / 三塁打', val: '$doubles / $triples'),
                _StatCell(label: '長打合計 (XBH)', val: '$extraBases'),
                _StatCell(label: '四球 (BB) / 三振', val: '${_seasonStats['baseOnBalls'] ?? 0} / ${_seasonStats['strikeOuts'] ?? 0}'),
                _StatCell(label: '盗塁 (SB)', val: '${_seasonStats['stolenBases'] ?? 0}'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMonthlyGraphCard(bool isPitcher) {
    if (_monthlySpots.isEmpty) {
      return const Card(
        color: Color(0xFF1E1E2C),
        child: Padding(padding: EdgeInsets.all(24), child: Center(child: Text('月別データはありません'))),
      );
    }

    return Card(
      color: const Color(0xFF1E1E2C),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 28, 20, 14),
        child: SizedBox(
          height: 210,
          child: LineChart(
            LineChartData(
              minY: _minY,
              maxY: _maxY,
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                getDrawingHorizontalLine: (val) => const FlLine(color: Colors.white10, strokeWidth: 1),
              ),
              lineTouchData: LineTouchData(
                enabled: true,
                touchTooltipData: LineTouchTooltipData(
                  getTooltipColor: (_) => const Color(0xFF2C2C3E),
                  getTooltipItems: (touchedSpots) {
                    return touchedSpots.map((spot) {
                      final month = _monthLabels[spot.x.toInt()];
                      final valStr = isPitcher ? spot.y.toStringAsFixed(2) : _formatRate(spot.y);
                      return LineTooltipItem(
                        '$month\n$valStr',
                        const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                      );
                    }).toList();
                  },
                ),
              ),
              titlesData: FlTitlesData(
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 34,
                    getTitlesWidget: (val, meta) {
                      if (val == meta.min || val == meta.max) return const SizedBox();
                      return Text(
                        isPitcher ? val.toStringAsFixed(1) : _formatRate(val),
                        style: const TextStyle(fontSize: 10, color: Colors.white54),
                      );
                    },
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    interval: 1,
                    getTitlesWidget: (val, meta) {
                      final idx = val.toInt();
                      if (idx >= 0 && idx < _monthLabels.length) {
                        return Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            _monthLabels[idx],
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white70),
                          ),
                        );
                      }
                      return const SizedBox();
                    },
                  ),
                ),
              ),
              borderData: FlBorderData(show: false),
              lineBarsData: [
                LineChartBarData(
                  spots: _monthlySpots,
                  isCurved: true,
                  curveSmoothness: 0.25,
                  color: isPitcher ? Colors.greenAccent : Colors.orangeAccent,
                  barWidth: 3.5,
                  belowBarData: BarAreaData(
                    show: true,
                    color: (isPitcher ? Colors.greenAccent : Colors.orangeAccent).withAlpha(35),
                  ),
                  dotData: FlDotData(
                    show: true,
                    getDotPainter: (spot, percent, barData, index) {
                      return FlDotCirclePainter(
                        radius: 5,
                        color: Colors.white,
                        strokeWidth: 2.5,
                        strokeColor: isPitcher ? Colors.greenAccent : Colors.orangeAccent,
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMonthlyTable(bool isPitcher) {
    if (_monthlyList.isEmpty) return const SizedBox();

    return Card(
      color: const Color(0xFF1E1E2C),
      child: Table(
        border: TableBorder.symmetric(inside: const BorderSide(color: Colors.white12, width: 1)),
        children: [
          TableRow(
            decoration: const BoxDecoration(color: Colors.white10),
            children: isPitcher
                ? const [
                    _TableCell('月', isHeader: true),
                    _TableCell('防御率', isHeader: true),
                    _TableCell('勝敗', isHeader: true),
                    _TableCell('投球回', isHeader: true),
                    _TableCell('奪三振', isHeader: true),
                    _TableCell('WHIP', isHeader: true),
                  ]
                : const [
                    _TableCell('月', isHeader: true),
                    _TableCell('打率', isHeader: true),
                    _TableCell('本塁打', isHeader: true),
                    _TableCell('打点', isHeader: true),
                    _TableCell('OPS', isHeader: true),
                    _TableCell('安打', isHeader: true),
                  ],
          ),
          ..._monthlyList.map((m) {
            final s = m['stat'] as Map<String, dynamic>;
            return TableRow(
              children: isPitcher
                  ? [
                      _TableCell(m['monthLabel']),
                      _TableCell(s['era']?.toString() ?? '-'),
                      _TableCell('${s['wins'] ?? 0}-${s['losses'] ?? 0}'),
                      _TableCell(s['inningsPitched']?.toString() ?? '-'),
                      _TableCell('${s['strikeOuts'] ?? 0}'),
                      _TableCell(s['whip']?.toString() ?? '-'),
                    ]
                  : [
                      _TableCell(m['monthLabel']),
                      _TableCell(_formatRate(s['avg'])),
                      _TableCell('${s['homeRuns'] ?? 0}本'),
                      _TableCell('${s['rbi'] ?? 0}'),
                      _TableCell(s['ops']?.toString() ?? '-'),
                      _TableCell('${s['hits'] ?? 0}'),
                    ],
            );
          }),
        ],
      ),
    );
  }

  // ★ 「過去の登板・出場をもっと見る」：月ごとの試合数一覧（タップで詳細モーダルを開く）
  Widget _buildMonthDrilldownList(bool isPitcher) {
    if (_allGamesByMonth.isEmpty) {
      return const Card(
        color: Color(0xFF1E1E2C),
        child: Padding(padding: EdgeInsets.all(24), child: Center(child: Text('データがありません'))),
      );
    }

    final months = _allGamesByMonth.keys.toList()..sort();

    return Card(
      color: const Color(0xFF1E1E2C),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: months.length,
        separatorBuilder: (_, _) => const Divider(height: 1, color: Colors.white12),
        itemBuilder: (context, index) {
          final month = months[index];
          final games = _allGamesByMonth[month]!;
          return ListTile(
            leading: const Icon(Icons.calendar_month, color: Colors.blueAccent, size: 20),
            title: Text('$month月', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            subtitle: Text(
              isPitcher ? '${games.length}試合登板' : '${games.length}試合出場',
              style: const TextStyle(fontSize: 12, color: Colors.white54),
            ),
            trailing: const Icon(Icons.chevron_right, color: Colors.white38),
            onTap: () => _showMonthGamesModal(month, games, isPitcher),
          );
        },
      ),
    );
  }

  void _showMonthGamesModal(int month, List<Map<String, dynamic>> games, bool isPitcher) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF161622),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.75,
          minChildSize: 0.4,
          maxChildSize: 0.95,
          expand: false,
          builder: (context, scrollController) {
            return Column(
              children: [
                const SizedBox(height: 10),
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
                ),
                Padding(
                  padding: const EdgeInsets.all(14),
                  child: Text(
                    '$month月の${isPitcher ? '登板' : '出場'}試合',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.amberAccent),
                  ),
                ),
                const Divider(height: 1, color: Colors.white12),
                Expanded(
                  child: isPitcher
                      ? _buildMonthGameListView(scrollController, games)
                      : _buildMonthGameCalendarView(month, games),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // 投手向け：登板数が少ないので日付リスト形式
  Widget _buildMonthGameListView(ScrollController scrollController, List<Map<String, dynamic>> games) {
    return ListView.separated(
      controller: scrollController,
      padding: const EdgeInsets.all(12),
      itemCount: games.length,
      separatorBuilder: (_, _) => const Divider(height: 1, color: Colors.white12),
      itemBuilder: (context, index) {
        final g = games[index];
        return ListTile(
          title: Text('${g['dateLabel']} vs ${g['opponent']}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          subtitle: Text(g['resultSummary'] as String, style: const TextStyle(fontSize: 12, color: Colors.white70)),
          trailing: const Icon(Icons.arrow_forward_ios, size: 14, color: Colors.amberAccent),
          onTap: () {
            Navigator.pop(context);
            _showGamePlayByPlayModal(context, {
              'gamePk': g['gamePk'],
              'date': g['dateLabel'],
              'opponent': g['opponent'],
              'isPitcher': g['isPitcher'],
              'playerId': g['playerId'],
            });
          },
        );
      },
    );
  }

  // 打者向け：試合数が多いのでカレンダー形式（試合がある日をマーク）
  Widget _buildMonthGameCalendarView(int month, List<Map<String, dynamic>> games) {
    final Map<DateTime, Map<String, dynamic>> gameByDate = {};
    for (final g in games) {
      final d = g['fullDate'] as DateTime?;
      if (d == null) continue;
      gameByDate[DateTime(d.year, d.month, d.day)] = g;
    }

    final firstDay = DateTime(2026, month, 1);
    final lastDay = DateTime(2026, month + 1, 0);

    return Column(
      children: [
        TableCalendar(
          firstDay: firstDay,
          lastDay: lastDay,
          focusedDay: firstDay,
          headerVisible: false,
          daysOfWeekHeight: 22,
          eventLoader: (day) {
            final key = DateTime(day.year, day.month, day.day);
            return gameByDate.containsKey(key) ? [key] : [];
          },
          calendarStyle: const CalendarStyle(
            outsideDaysVisible: false,
            markerDecoration: BoxDecoration(color: Colors.greenAccent, shape: BoxShape.circle),
            markersMaxCount: 1,
            defaultTextStyle: TextStyle(color: Colors.white),
            weekendTextStyle: TextStyle(color: Colors.white70),
          ),
          daysOfWeekStyle: const DaysOfWeekStyle(
            weekdayStyle: TextStyle(color: Colors.white54, fontSize: 11),
            weekendStyle: TextStyle(color: Colors.white38, fontSize: 11),
          ),
          onDaySelected: (selectedDay, focusedDay) {
            final key = DateTime(selectedDay.year, selectedDay.month, selectedDay.day);
            final g = gameByDate[key];
            if (g == null) return;
            Navigator.pop(context);
            _showGamePlayByPlayModal(context, {
              'gamePk': g['gamePk'],
              'date': g['dateLabel'],
              'opponent': g['opponent'],
              'isPitcher': g['isPitcher'],
              'playerId': g['playerId'],
            });
          },
        ),
        const SizedBox(height: 12),
        const Text('緑マークの日をタップすると試合詳細が見られます', style: TextStyle(fontSize: 11, color: Colors.white38)),
      ],
    );
  }

  Widget _buildRecentGamesCard() {
    return Card(
      color: const Color(0xFF1E1E2C),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: _recentGames.length,
        separatorBuilder: (_, _) => const Divider(height: 1, color: Colors.white12),
        itemBuilder: (context, index) {
          final item = _recentGames[index];
          return InkWell(
            onTap: () => _showGamePlayByPlayModal(context, item),
            borderRadius: BorderRadius.circular(12),
            child: ListTile(
              dense: true,
              title: Text('${item['date']} vs ${item['opponent']}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              subtitle: Text(item['detail']!, style: const TextStyle(fontSize: 12, color: Colors.white70)),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    item['main']!,
                    style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(width: 4),
                  const Icon(Icons.arrow_forward_ios, size: 14, color: Colors.amberAccent),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

// 全球配球・打席詳細を展開するボトムシートウィジェット
class _GamePlayByPlaySheet extends ConsumerStatefulWidget {
  final Map<String, dynamic> gameItem;

  const _GamePlayByPlaySheet({required this.gameItem});

  @override
  ConsumerState<_GamePlayByPlaySheet> createState() => _GamePlayByPlaySheetState();
}

class _GamePlayByPlaySheetState extends ConsumerState<_GamePlayByPlaySheet> {
  bool _isLoading = true;
  String? _error;
  List<Map<String, dynamic>> _matchupList = [];

  // ★ 打者用: この試合の簡易成績サマリー（◯打数◯安打◯四球）
  int _ab = 0;
  int _hits = 0;
  int _bb = 0;
  int _so = 0;

  @override
  void initState() {
    super.initState();
    _fetchPlayByPlay();
  }

  Future<void> _fetchPlayByPlay() async {
    final gamePk = widget.gameItem['gamePk'] as int?;
    final isPitcher = widget.gameItem['isPitcher'] as bool;
    final playerId = widget.gameItem['playerId'] as int;

    if (gamePk == null) {
      setState(() {
        _isLoading = false;
        _error = '該当試合のデータが見つかりませんでした';
      });
      return;
    }

    try {
      final api = ref.read(apiServiceProvider);
      final feed = await api.getLiveGameFeed(gamePk);
      final plays = feed['liveData']?['plays']?['allPlays'] as List<dynamic>? ?? [];

      List<Map<String, dynamic>> matchups = [];
      int ab = 0, hits = 0, bb = 0, so = 0;

      for (final play in plays) {
        final pitcherId = play['matchup']?['pitcher']?['id'];
        final batterId = play['matchup']?['batter']?['id'];

        final bool isTargetMatch = isPitcher ? (pitcherId == playerId) : (batterId == playerId);

        if (isTargetMatch) {
          final opponentName = isPitcher
              ? (play['matchup']?['batter']?['fullName'] ?? '相手打者')
              : (play['matchup']?['pitcher']?['fullName'] ?? '相手投手');
          final opponentId = isPitcher ? batterId as int? : pitcherId as int?;

          final inning = play['about']?['inning'] ?? 1;
          final isTopInning = play['about']?['isTopInning'] == true;
          final resultDescRaw = play['result']?['description']?.toString();
          final eventType = play['result']?['event']?.toString() ?? '';

          // ★ 打者の場合のみ、打席結果を◯打数◯安打◯四球に集計する
          if (!isPitcher) {
            const hitEvents = ['Single', 'Double', 'Triple', 'Home Run'];
            const walkEvents = ['Walk', 'Intent Walk'];
            const noAbEvents = ['Walk', 'Intent Walk', 'Hit By Pitch', 'Sac Fly', 'Sac Bunt', 'Catcher Interference'];

            if (hitEvents.contains(eventType)) hits++;
            if (walkEvents.contains(eventType)) bb++;
            if (eventType.contains('Strikeout')) so++;
            if (!noAbEvents.contains(eventType)) ab++;
          }

          final playEvents = play['playEvents'] as List<dynamic>? ?? [];
          List<Map<String, dynamic>> pitches = [];
          Map<String, dynamic>? hitData;

          for (final event in playEvents) {
            if (event['isPitch'] == true) {
              final speedMph = (event['pitchData']?['startSpeed'] as num?)?.toDouble() ?? 0.0;
              final speedKmh = speedMph * 1.60934;
              // ★ type/callは翻訳前の原文(英語)のまま保持し、表示時(build内)にlangに応じて翻訳する
              final type = event['details']?['type']?['description']?.toString();
              final call = event['details']?['description']?.toString() ?? '';
              final count = '${event['count']?['balls'] ?? 0}-${event['count']?['strikes'] ?? 0}';

              // 空間座標 (pX, pZ) の取得
              final pX = (event['pitchData']?['coordinates']?['pX'] as num?)?.toDouble();
              final pZ = (event['pitchData']?['coordinates']?['pZ'] as num?)?.toDouble();

              // コールに応じた色判定（翻訳前の原文で判定する）
              final isStrike = call.contains('Strike') || call.contains('Foul') || call.contains('In play');

              pitches.add({
                'pitchNumber': event['pitchNumber'] ?? (pitches.length + 1),
                'type': type,
                'speedMph': speedMph,
                'speedKmh': speedKmh,
                'call': call,
                'count': count,
                'pX': pX,
                'pZ': pZ,
                'isStrike': isStrike,
              });
            }
            if (event['hitData'] != null) {
              hitData = event['hitData'] as Map<String, dynamic>;
            }
          }

          matchups.add({
            'inning': inning,
            'isTopInning': isTopInning,
            'opponent': opponentName,
            'opponentId': opponentId,
            'resultDescRaw': resultDescRaw,
            'resultEventRaw': eventType,
            'pitches': pitches,
            'hitData': hitData,
          });
        }
      }

      if (mounted) {
        setState(() {
          _matchupList = matchups;
          _ab = ab;
          _hits = hits;
          _bb = bb;
          _so = so;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '詳細データ取得エラー: $e';
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final game = widget.gameItem;
    final isPitcher = game['isPitcher'] as bool;
    final lang = ref.watch(appLanguageProvider);

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      '${game['date']} vs ${game['opponent']} 配球・対戦詳細',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.amberAccent),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const LanguageToggleButton(),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white54),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      isPitcher ? '【全打者との勝負内容・球種配球 ＆ ゾーン軌跡】' : '【全打席・相手投手との全球対戦 ＆ ゾーン軌跡】',
                      style: const TextStyle(fontSize: 12, color: Colors.white70),
                    ),
                  ),
                  if (!isPitcher && !_isLoading && _error == null)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.blueAccent.withAlpha(30),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Colors.blueAccent.withAlpha(80)),
                      ),
                      child: Text(
                        '$_ab打数$_hits安打$_bb四球${_so > 0 ? ' $_so三振' : ''}',
                        style: const TextStyle(fontSize: 11, color: Colors.lightBlueAccent, fontWeight: FontWeight.bold),
                      ),
                    ),
                ],
              ),
              const Divider(color: Colors.white12, height: 20),
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : _error != null
                        ? Center(child: Text(_error!, style: const TextStyle(color: Colors.redAccent)))
                        : _matchupList.isEmpty
                            ? const Center(child: Text('該当の投球・打席ログがありません', style: TextStyle(color: Colors.white54)))
                            : ListView.separated(
                                controller: scrollController,
                                itemCount: _matchupList.length,
                                separatorBuilder: (_, _) => const SizedBox(height: 14),
                                itemBuilder: (context, idx) {
                                  final m = _matchupList[idx];
                                  final pitches = m['pitches'] as List<Map<String, dynamic>>;
                                  final hit = m['hitData'] as Map<String, dynamic>?;

                                  final double? launchSpeed = (hit?['launchSpeed'] as num?)?.toDouble();
                                  final double? launchAngle = (hit?['launchAngle'] as num?)?.toDouble();
                                  final double? totalDistance = (hit?['totalDistance'] as num?)?.toDouble();
                                  final bool isBarrel = launchSpeed != null && launchAngle != null && launchSpeed >= 98.0 && launchAngle >= 24.0 && launchAngle <= 34.0;

                                  return Card(
                                    color: const Color(0xFF1E1E2C),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                    child: Padding(
                                      padding: const EdgeInsets.all(14),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                            children: [
                                              Text(
                                                '第${idx + 1}打席（${m['inning']}回${translateHalf(m['isTopInning'] as bool, lang)}） vs ${m['opponent']}',
                                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.blueAccent),
                                              ),
                                              if (isBarrel)
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                  decoration: BoxDecoration(color: Colors.redAccent, borderRadius: BorderRadius.circular(4)),
                                                  child: const Text('🔥 BARREL', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10, color: Colors.white)),
                                                ),
                                            ],
                                          ),
                                          const SizedBox(height: 6),
                                          Text(
                                            '結果: ${translateAtBatResult(m['resultDescRaw'] as String?, m['resultEventRaw'] as String?, lang)}',
                                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white),
                                          ),
                                          const SizedBox(height: 6),
                                          if (m['opponentId'] != null)
                                            HeadToHeadBadge(
                                              batterId: isPitcher ? m['opponentId'] as int : game['playerId'] as int,
                                              pitcherId: isPitcher ? game['playerId'] as int : m['opponentId'] as int,
                                            ),
                                          const Divider(height: 16, color: Colors.white12),

                                          // 配球テキスト ＆ ミニストライクゾーンの横並びレイアウト
                                          Row(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              // 左側：配球推移テキスト
                                              Expanded(
                                                flex: 6,
                                                child: Column(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  children: [
                                                    const Text('【配球推移】', style: TextStyle(fontSize: 11, color: Colors.white54)),
                                                    const SizedBox(height: 6),
                                                    ...pitches.map((p) {
                                                      final isStrike = p['isStrike'] as bool;
                                                      return Padding(
                                                        padding: const EdgeInsets.symmetric(vertical: 3),
                                                        child: Row(
                                                          children: [
                                                            Container(
                                                              width: 18,
                                                              height: 18,
                                                              decoration: BoxDecoration(
                                                                color: isStrike ? Colors.redAccent : Colors.blueAccent,
                                                                borderRadius: BorderRadius.circular(9),
                                                              ),
                                                              alignment: Alignment.center,
                                                              child: Text('${p['pitchNumber']}', style: const TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.bold)),
                                                            ),
                                                            const SizedBox(width: 6),
                                                            Text('[${p['count']}]', style: const TextStyle(fontSize: 11, color: Colors.amberAccent, fontWeight: FontWeight.bold)),
                                                            const SizedBox(width: 6),
                                                            Expanded(
                                                              child: Text(
                                                                '${translatePitchType(p['type'] as String?, lang)}\n${(p['speedMph'] as double).toStringAsFixed(1)} mph (${(p['speedKmh'] as double).toStringAsFixed(0)}km/h)',
                                                                style: const TextStyle(fontSize: 11, color: Colors.white),
                                                              ),
                                                            ),
                                                            Text(
                                                              translateCall(p['call'] as String?, lang),
                                                              style: TextStyle(fontSize: 10, color: isStrike ? Colors.orangeAccent : Colors.lightBlueAccent),
                                                            ),
                                                          ],
                                                        ),
                                                      );
                                                    }),
                                                  ],
                                                ),
                                              ),
                                              const SizedBox(width: 12),
                                              // 右側：ミニストライクゾーン
                                              Expanded(
                                                flex: 4,
                                                child: Column(
                                                  children: [
                                                    const Text('【ゾーン通過位置】', style: TextStyle(fontSize: 11, color: Colors.white54)),
                                                    const SizedBox(height: 6),
                                                    Container(
                                                      height: 140,
                                                      width: 120,
                                                      decoration: BoxDecoration(
                                                        color: const Color(0xFF14141E),
                                                        borderRadius: BorderRadius.circular(8),
                                                        border: Border.all(color: Colors.white12),
                                                      ),
                                                      child: CustomPaint(
                                                        painter: _MiniStrikeZonePainter(pitches: pitches),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ],
                                          ),

                                          if (hit != null && (launchSpeed != null || totalDistance != null)) ...[
                                            const Divider(height: 14, color: Colors.white12),
                                            Row(
                                              mainAxisAlignment: MainAxisAlignment.spaceAround,
                                              children: [
                                                Text('初速: ${launchSpeed?.toStringAsFixed(1) ?? "-"} mph', style: const TextStyle(fontSize: 11, color: Colors.orangeAccent)),
                                                Text('角度: ${launchAngle?.toStringAsFixed(0) ?? "-"}°', style: const TextStyle(fontSize: 11, color: Colors.white70)),
                                                Text('飛距離: ${totalDistance?.toStringAsFixed(0) ?? "-"} ft', style: const TextStyle(fontSize: 11, color: Colors.orangeAccent)),
                                              ],
                                            ),
                                          ],
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
      },
    );
  }
}

// ★ 打席ごとのストライクゾーン描画ペインター
class _MiniStrikeZonePainter extends CustomPainter {
  final List<Map<String, dynamic>> pitches;

  _MiniStrikeZonePainter({required this.pitches});

  @override
  void paint(Canvas canvas, Size size) {
    final zoneWidth = size.width * 0.6;
    final zoneHeight = size.height * 0.65;
    final zoneLeft = (size.width - zoneWidth) / 2;
    final zoneTop = (size.height - zoneHeight) / 2;
    final zoneRect = Rect.fromLTWH(zoneLeft, zoneTop, zoneWidth, zoneHeight);

    // ゾーン背景
    final bgPaint = Paint()..color = const Color(0xFF222232);
    canvas.drawRect(zoneRect, bgPaint);

    // ゾーン外枠
    final borderPaint = Paint()
      ..color = Colors.white70
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawRect(zoneRect, borderPaint);

    // 3x3 グリッド線
    final gridPaint = Paint()
      ..color = Colors.white24
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;

    for (int i = 1; i <= 2; i++) {
      // 縦線
      canvas.drawLine(
        Offset(zoneLeft + (zoneWidth / 3) * i, zoneTop),
        Offset(zoneLeft + (zoneWidth / 3) * i, zoneTop + zoneHeight),
        gridPaint,
      );
      // 横線
      canvas.drawLine(
        Offset(zoneLeft, zoneTop + (zoneHeight / 3) * i),
        Offset(zoneLeft + zoneWidth, zoneTop + (zoneHeight / 3) * i),
        gridPaint,
      );
    }

    // 各投球のプロット
    for (final p in pitches) {
      final double? pX = p['pX'];
      final double? pZ = p['pZ'];
      if (pX == null || pZ == null) continue;

      // MLB座標系 (pX: -2.0 ~ 2.0 ft, pZ: 0.5 ~ 4.5 ft) を Canvas 座標にマッピング
      // Strike Zone: X: -0.83 ~ 0.83 ft, Z: 1.5 ~ 3.5 ft
      final double normalizedX = (pX + 0.83) / (0.83 * 2);
      final double normalizedY = 1.0 - ((pZ - 1.5) / (3.5 - 1.5));

      final double cx = zoneLeft + (normalizedX * zoneWidth);
      final double cy = zoneTop + (normalizedY * zoneHeight);

      final isStrike = p['isStrike'] as bool;
      final ballColor = isStrike ? Colors.redAccent : Colors.blueAccent;

      // 球の円
      final ballPaint = Paint()..color = ballColor;
      canvas.drawCircle(Offset(cx, cy), 8, ballPaint);

      final strokePaint = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0;
      canvas.drawCircle(Offset(cx, cy), 8, strokePaint);

      // 球番号テキスト
      final textSpan = TextSpan(
        text: '${p['pitchNumber']}',
        style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
      );
      final textPainter = TextPainter(
        text: textSpan,
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
      )..layout();

      textPainter.paint(
        canvas,
        Offset(cx - (textPainter.width / 2), cy - (textPainter.height / 2)),
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class _StatCell extends StatelessWidget {
  final String label;
  final String val;
  final bool highlight;
  final String? statKey;

  const _StatCell({required this.label, required this.val, this.highlight = false, this.statKey});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, style: const TextStyle(fontSize: 11, color: Colors.white54)),
            StatInfoIcon(statKey),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          val,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: highlight ? Colors.amberAccent : Colors.white,
          ),
        ),
      ],
    );
  }
}

class _TableCell extends StatelessWidget {
  final String text;
  final bool isHeader;

  const _TableCell(this.text, {this.isHeader = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      child: Center(
        child: Text(
          text,
          style: TextStyle(
            fontSize: 11,
            fontWeight: isHeader ? FontWeight.bold : FontWeight.normal,
            color: isHeader ? Colors.blueAccent : Colors.white70,
          ),
        ),
      ),
    );
  }
}