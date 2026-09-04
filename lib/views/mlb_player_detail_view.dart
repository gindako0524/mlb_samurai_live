// lib/views/mlb_player_detail_view.dart

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import '../models/player.dart';
import '../services/schedule_provider.dart';
import '../utils/stat_glossary.dart';
import 'career_stats_view.dart';
import 'player_full_stats_view.dart';
import '../widgets/contract_info_card.dart';
import '../widgets/advanced_stats_card.dart';

/// メジャー全選手（日本人選手に限らない）向けの成績詳細画面。
/// 今シーズン成績・直近5試合に加え、既存の CareerStatsView
/// （通算・年度別成績、日本人選手画面で実装済み）へそのまま遷移できる。
/// CareerStatsView は JapanesePlayer の id/isPitcher/nameJa しか参照しないため、
/// 対象選手の情報を仮のJapanesePlayerとして渡すことで安全に再利用している。
class MlbPlayerDetailView extends ConsumerStatefulWidget {
  final int personId;
  final String fullName;
  final String teamName;
  final bool isPitcher;

  const MlbPlayerDetailView({
    super.key,
    required this.personId,
    required this.fullName,
    required this.teamName,
    required this.isPitcher,
  });

  @override
  ConsumerState<MlbPlayerDetailView> createState() => _MlbPlayerDetailViewState();
}

class _MlbPlayerDetailViewState extends ConsumerState<MlbPlayerDetailView> {
  bool _isLoading = true;
  String? _error;
  Map<String, dynamic> _seasonStats = {};
  List<Map<String, dynamic>> _recentGames = [];
  double _rwar = 0.0;
  double _rwarPitch = 0.0;
  bool _warFound = false;

  @override
  void initState() {
    super.initState();
    _fetch();
    _fetchWarData();
  }

  Future<void> _fetch() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final api = ref.read(apiServiceProvider);
      final data = await api.getPlayerGameLog(widget.personId, isPitcher: widget.isPitcher);
      final statsList = data['stats'] as List<dynamic>? ?? [];

      Map<String, dynamic> season = {};
      List<Map<String, dynamic>> gameLog = [];
      for (final s in statsList) {
        final typeName = s['type']?['displayName']?.toString().toLowerCase() ?? '';
        final splits = s['splits'] as List<dynamic>? ?? [];
        if (typeName == 'season' && splits.isNotEmpty) {
          season = splits.first['stat'] as Map<String, dynamic>? ?? {};
        }
        if (typeName == 'gamelog') {
          gameLog = splits.cast<Map<String, dynamic>>();
        }
      }
      // ★ 直近5試合（新しい順）
      final recent = gameLog.reversed.take(5).toList();

      if (mounted) {
        setState(() {
          _seasonStats = season;
          _recentGames = recent;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'データ取得エラー: $e';
          _isLoading = false;
        });
      }
    }
  }

  // ★ war_data.json（WARデータ）を取得する。日本人選手専用画面(stats_view.dart)と
  //   同じ取得方式（3つのURLでフォールバック）を使う。全選手対応後のデータであれば
  //   日本人選手以外もここでヒットする。
  Future<void> _fetchWarData() async {
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

          final playerMap = data['players']?[widget.personId.toString()];
          if (playerMap != null && mounted) {
            setState(() {
              _rwar = (playerMap['rwar'] as num?)?.toDouble() ?? 0.0;
              _rwarPitch = (playerMap['rwar_pitch'] as num?)?.toDouble() ?? 0.0;
              _warFound = true;
            });
            return;
          }
        }
      } catch (_) {
        // 次のURLへフォールバック
      }
    }
  }

  String _formatRate(dynamic val) {
    if (val == null) return '-';
    String s = val.toString().trim();
    if (s.startsWith('.') || s.startsWith('-')) return s;
    final d = double.tryParse(s);
    if (d != null) {
      if (d < 1.0) return '.${(d * 1000).toInt().toString().padLeft(3, '0')}';
      return d.toStringAsFixed(2);
    }
    return s;
  }

  void _openCareerStats() {
    // ★ CareerStatsView は id/isPitcher/nameJa のみ参照するため、仮のJapanesePlayerで再利用する
    final syntheticPlayer = JapanesePlayer(
      id: widget.personId,
      nameJa: widget.fullName,
      nameEn: widget.fullName,
      teamName: widget.teamName,
      teamId: 0,
      isPitcher: widget.isPitcher,
    );
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => CareerStatsView(player: syntheticPlayer)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.fullName} (${widget.teamName})', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _fetch),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!, style: const TextStyle(color: Colors.redAccent)))
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    OutlinedButton.icon(
                      icon: const Icon(Icons.history),
                      label: const Text('通算・年度別成績を見る'),
                      style: OutlinedButton.styleFrom(foregroundColor: Colors.greenAccent, side: const BorderSide(color: Colors.greenAccent)),
                      onPressed: _openCareerStats,
                    ),
                    const SizedBox(height: 16),
                    ContractInfoCard(playerId: widget.personId),
                    AdvancedStatsCard(playerId: widget.personId, isPitcher: widget.isPitcher, seasonStats: _seasonStats),
                    if (_warFound) ...[
                      _buildWarCard(),
                      const SizedBox(height: 16),
                    ],
                    Text(
                      '${widget.fullName} 2026年 シーズン公式成績',
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.blueAccent),
                    ),
                    const SizedBox(height: 8),
                    widget.isPitcher ? _buildPitcherGrid() : _buildBatterGrid(),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => PlayerFullStatsView(
                              playerId: widget.personId,
                              playerName: widget.fullName,
                              isPitcher: widget.isPitcher,
                            ),
                          ),
                        ),
                        icon: const Icon(Icons.table_chart, size: 18),
                        label: const Text('全成績・対戦チーム別成績を見る'),
                        style: OutlinedButton.styleFrom(foregroundColor: Colors.blueAccent, side: const BorderSide(color: Colors.blueAccent)),
                      ),
                    ),
                    const SizedBox(height: 24),
                    const Text('直近5試合', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.blueAccent)),
                    const SizedBox(height: 8),
                    if (_recentGames.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Text('試合データがまだありません', style: TextStyle(color: Colors.white38, fontSize: 12)),
                      )
                    else
                      ..._recentGames.map((g) => _buildRecentGameRow(g)),
                  ],
                ),
    );
  }

  Widget _buildWarCard() {
    final totalRwar = widget.isPitcher ? _rwarPitch : _rwar;
    return Card(
      color: const Color(0xFF1E2638),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Colors.blueAccent, width: 1.2),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                const Icon(Icons.analytics, color: Colors.amberAccent, size: 20),
                const SizedBox(width: 6),
                const Text(
                  '今シーズン rWAR',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.amberAccent),
                ),
                const StatInfoIcon('war'),
              ],
            ),
            Text(
              totalRwar.toStringAsFixed(1),
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 24, color: Colors.amberAccent),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecentGameRow(Map<String, dynamic> g) {
    final dateStr = g['date']?.toString() ?? '';
    String displayDate = dateStr;
    final parsed = DateTime.tryParse(dateStr);
    if (parsed != null) displayDate = DateFormat('M/d').format(parsed);
    final opponent = g['opponent']?['name']?.toString() ?? '-';
    final isHome = g['isHome'] == true;
    final stat = g['stat'] as Map<String, dynamic>? ?? {};

    final String line;
    if (widget.isPitcher) {
      final ip = stat['inningsPitched']?.toString() ?? '0.0';
      final er = stat['earnedRuns']?.toString() ?? '0';
      final so = stat['strikeOuts']?.toString() ?? '0';
      final bb = stat['baseOnBalls']?.toString() ?? '0';
      final h = stat['hits']?.toString() ?? '0';
      line = '$ip回 $h安打 $er自責点 $so奪三振 $bb四球';
    } else {
      final ab = stat['atBats']?.toString() ?? '0';
      final hits = stat['hits']?.toString() ?? '0';
      final hr = (stat['homeRuns'] as num?)?.toInt() ?? 0;
      final rbi = (stat['rbi'] as num?)?.toInt() ?? 0;
      line = '$ab打数$hits安打${hr > 0 ? ' $hr本塁打' : ''}${rbi > 0 ? ' $rbi打点' : ''}';
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: const Color(0xFF1E1E2C),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            SizedBox(width: 44, child: Text(displayDate, style: const TextStyle(fontSize: 12, color: Colors.white54))),
            Expanded(
              child: Text(
                '${isHome ? '対' : '@'} $opponent',
                style: const TextStyle(fontSize: 12, color: Colors.white70),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Text(line, style: const TextStyle(fontSize: 12, color: Colors.white, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  Widget _buildBatterGrid() {
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
                _StatCell(label: '打率 (AVG)', val: _formatRate(_seasonStats['avg']), statKey: 'avg'),
                _StatCell(label: '出塁率 (OBP)', val: _formatRate(_seasonStats['obp']), statKey: 'obp'),
                _StatCell(label: '長打率 (SLG)', val: _formatRate(_seasonStats['slg']), statKey: 'slg'),
                _StatCell(label: 'OPS', val: _seasonStats['ops']?.toString() ?? '-', statKey: 'ops'),
              ],
            ),
            const Divider(height: 20, color: Colors.white12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _StatCell(label: '本塁打 (HR)', val: '${_seasonStats['homeRuns'] ?? 0}'),
                _StatCell(label: '打点 (RBI)', val: '${_seasonStats['rbi'] ?? 0}'),
                _StatCell(label: '安打数 (H)', val: '${_seasonStats['hits'] ?? 0}'),
                _StatCell(label: '得点 (R)', val: '${_seasonStats['runs'] ?? 0}'),
              ],
            ),
            const Divider(height: 20, color: Colors.white12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _StatCell(label: '四球 (BB)', val: '${_seasonStats['baseOnBalls'] ?? 0}'),
                _StatCell(label: '三振 (SO)', val: '${_seasonStats['strikeOuts'] ?? 0}'),
                _StatCell(label: '盗塁 (SB)', val: '${_seasonStats['stolenBases'] ?? 0}'),
                _StatCell(label: '試合 (G)', val: '${_seasonStats['gamesPlayed'] ?? 0}'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPitcherGrid() {
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
                _StatCell(label: '防御率 (ERA)', val: _seasonStats['era']?.toString() ?? '-', statKey: 'era'),
                _StatCell(label: '勝 - 敗', val: '${_seasonStats['wins'] ?? 0} - ${_seasonStats['losses'] ?? 0}'),
                _StatCell(label: 'WHIP', val: _seasonStats['whip']?.toString() ?? '-', statKey: 'whip'),
                _StatCell(label: '投球回 (IP)', val: _seasonStats['inningsPitched']?.toString() ?? '-'),
              ],
            ),
            const Divider(height: 20, color: Colors.white12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _StatCell(label: '奪三振 (SO)', val: '${_seasonStats['strikeOuts'] ?? 0}'),
                _StatCell(label: '奪三振率 (K/9)', val: _seasonStats['strikeoutsPer9Inn']?.toString() ?? '-', statKey: 'strikeoutsPer9Inn'),
                _StatCell(label: '与四球率 (BB/9)', val: _seasonStats['walksPer9Inn']?.toString() ?? '-', statKey: 'walksPer9Inn'),
                _StatCell(label: 'セーブ (SV)', val: '${_seasonStats['saves'] ?? 0}'),
              ],
            ),
            const Divider(height: 20, color: Colors.white12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _StatCell(label: '登板 (G)', val: '${_seasonStats['gamesPitched'] ?? 0}'),
                _StatCell(label: '先発 (GS)', val: '${_seasonStats['gamesStarted'] ?? 0}'),
                _StatCell(label: '被安打', val: '${_seasonStats['hits'] ?? 0}'),
                _StatCell(label: '被本塁打', val: '${_seasonStats['homeRuns'] ?? 0}'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StatCell extends StatelessWidget {
  final String label;
  final String val;
  final String? statKey;

  const _StatCell({required this.label, required this.val, this.statKey});

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
        Text(val, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white)),
      ],
    );
  }
}
