// lib/views/team_detail_view.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/schedule_provider.dart';
import '../utils/stat_glossary.dart';
import 'mlb_player_detail_view.dart';

const List<Map<String, String>> _batterLeaderCats = [
  {'key': 'battingAverage', 'label': '打率', 'statKey': 'avg'},
  {'key': 'homeRuns', 'label': '本塁打', 'statKey': ''},
  {'key': 'onBasePlusSlugging', 'label': 'OPS', 'statKey': 'ops'},
];
const List<Map<String, String>> _pitcherLeaderCats = [
  {'key': 'earnedRunAverage', 'label': '防御率', 'statKey': 'era'},
  {'key': 'wins', 'label': '勝利', 'statKey': ''},
  {'key': 'strikeouts', 'label': '奪三振', 'statKey': ''},
];

/// 球団詳細画面：登録メンバー（今シーズン簡易成績付き）＋チーム成績TOP選手。
/// 選手名をタップすると MlbPlayerDetailView（今シーズン成績・通算成績）へ遷移する。
class TeamDetailView extends ConsumerStatefulWidget {
  final int teamId;
  final String teamName;

  const TeamDetailView({super.key, required this.teamId, required this.teamName});

  @override
  ConsumerState<TeamDetailView> createState() => _TeamDetailViewState();
}

class _TeamDetailViewState extends ConsumerState<TeamDetailView> {
  bool _isLoading = true;
  String? _error;
  List<Map<String, dynamic>> _roster = []; // {id, name, posAbbr, isPitcher, statLine}
  Map<String, List<Map<String, dynamic>>> _leaders = {}; // category key -> [{name, personId, value}]

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final api = ref.read(apiServiceProvider);

      final rosterData = await api.getTeamRoster(widget.teamId);
      final rosterRaw = rosterData['roster'] as List<dynamic>? ?? [];

      final List<int> batterIds = [];
      final List<int> pitcherIds = [];
      final Map<int, Map<String, dynamic>> baseInfo = {};

      for (final r in rosterRaw) {
        final personId = (r['person']?['id'] as num?)?.toInt();
        if (personId == null) continue;
        final posType = r['position']?['type']?.toString();
        final isPitcher = posType == 'Pitcher';
        baseInfo[personId] = {
          'id': personId,
          'name': r['person']?['fullName']?.toString() ?? '-',
          'posAbbr': r['position']?['abbreviation']?.toString() ?? '-',
          'isPitcher': isPitcher,
        };
        if (isPitcher) {
          pitcherIds.add(personId);
        } else {
          batterIds.add(personId);
        }
      }

      // ★ 打者・投手それぞれ一括hydrateで今シーズン成績を取得（選手ごとの個別リクエストを避ける）
      final results = await Future.wait([
        api.getBulkPlayerSeasonStats(batterIds, 'hitting'),
        api.getBulkPlayerSeasonStats(pitcherIds, 'pitching'),
        api.getTeamLeaders(widget.teamId, [..._batterLeaderCats, ..._pitcherLeaderCats].map((c) => c['key']!).toList()),
      ]);

      final batterStatsData = results[0];
      final pitcherStatsData = results[1];
      final leadersData = results[2];

      void applyStats(Map<String, dynamic> data, bool isPitcher) {
        final people = data['people'] as List<dynamic>? ?? [];
        for (final p in people) {
          final personId = (p['id'] as num?)?.toInt();
          if (personId == null || !baseInfo.containsKey(personId)) continue;
          final statsList = p['stats'] as List<dynamic>? ?? [];
          if (statsList.isEmpty) continue;
          final splits = statsList[0]['splits'] as List<dynamic>? ?? [];
          if (splits.isEmpty) continue;
          final stat = splits[0]['stat'] as Map<String, dynamic>?;
          if (stat == null) continue;
          baseInfo[personId]!['statLine'] = isPitcher
              ? '防御率 ${stat['era'] ?? '-'} / ${stat['gamesPitched'] ?? 0}試合登板'
              : '打率 ${_formatRate(stat['avg'])} / ${stat['homeRuns'] ?? 0}本 / OPS ${stat['ops'] ?? '-'}';
        }
      }

      applyStats(batterStatsData, false);
      applyStats(pitcherStatsData, true);

      // ★ チームリーダー（TOP選手）の整理
      // ★ このAPIはカテゴリごとに statGroup（hitting/pitching/catching等）別の
      //   複数エントリを返す（例：battingAverageでも投手自身の打率や捕手区分が別途混ざる）。
      //   打者カテゴリはhitting、投手カテゴリはpitchingのグループだけを採用する。
      final batterCatKeys = _batterLeaderCats.map((c) => c['key']).toSet();
      final pitcherCatKeys = _pitcherLeaderCats.map((c) => c['key']).toSet();
      final Map<String, List<Map<String, dynamic>>> leaders = {};
      final teamLeadersRaw = leadersData['teamLeaders'] as List<dynamic>? ?? [];
      for (final tl in teamLeadersRaw) {
        final category = tl['leaderCategory']?.toString();
        final statGroup = tl['statGroup']?.toString();
        if (category == null) continue;
        if (batterCatKeys.contains(category) && statGroup != 'hitting') continue;
        if (pitcherCatKeys.contains(category) && statGroup != 'pitching') continue;
        final leadersList = tl['leaders'] as List<dynamic>? ?? [];
        leaders[category] = leadersList.take(3).map((l) {
          return {
            'personId': (l['person']?['id'] as num?)?.toInt(),
            'name': l['person']?['fullName']?.toString() ?? '-',
            'value': l['value']?.toString() ?? '-',
          };
        }).toList();
      }

      final rosterList = baseInfo.values.toList()
        ..sort((a, b) => (a['name'] as String).compareTo(b['name'] as String));

      if (mounted) {
        setState(() {
          _roster = rosterList;
          _leaders = leaders;
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

  String _formatRate(dynamic val) {
    if (val == null) return '-';
    String s = val.toString().trim();
    if (s.startsWith('.') || s.startsWith('-')) return s;
    final d = double.tryParse(s);
    if (d != null && d < 1.0) return '.${(d * 1000).toInt().toString().padLeft(3, '0')}';
    return s;
  }

  void _openPlayer(int personId, String name, bool isPitcher) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MlbPlayerDetailView(
          personId: personId,
          fullName: name,
          teamName: widget.teamName,
          isPitcher: isPitcher,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.teamName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
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
                    const Text('チーム成績TOP選手 (2026年)', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.amberAccent)),
                    const SizedBox(height: 8),
                    _buildLeadersSection('打者', _batterLeaderCats, false),
                    const SizedBox(height: 12),
                    _buildLeadersSection('投手', _pitcherLeaderCats, true),
                    const SizedBox(height: 24),
                    Text('登録メンバー (${_roster.length}名)', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.blueAccent)),
                    const SizedBox(height: 8),
                    ..._roster.map((p) => _RosterRow(
                          player: p,
                          onTap: () => _openPlayer(p['id'] as int, p['name'] as String, p['isPitcher'] as bool),
                        )),
                  ],
                ),
    );
  }

  Widget _buildLeadersSection(String groupLabel, List<Map<String, String>> cats, bool isPitcher) {
    return Card(
      color: const Color(0xFF1E1E2C),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(groupLabel, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white70)),
            const SizedBox(height: 6),
            ...cats.map((cat) {
              final entries = _leaders[cat['key']] ?? [];
              if (entries.isEmpty) return const SizedBox.shrink();
              final top = entries.first;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    SizedBox(
                      width: 70,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(cat['label']!, style: const TextStyle(fontSize: 12, color: Colors.white54)),
                          if (cat['statKey'] != null && cat['statKey']!.isNotEmpty) StatInfoIcon(cat['statKey']),
                        ],
                      ),
                    ),
                    Expanded(
                      child: InkWell(
                        onTap: top['personId'] == null
                            ? null
                            : () => _openPlayer(top['personId'] as int, top['name'] as String, isPitcher),
                        child: Text(
                          '${top['name']}  ${top['value']}',
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.amberAccent),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}

class _RosterRow extends StatelessWidget {
  final Map<String, dynamic> player;
  final VoidCallback onTap;

  const _RosterRow({required this.player, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isPitcher = player['isPitcher'] as bool;
    final statLine = player['statLine'] as String?;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: const Color(0xFF1E1E2C),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              CircleAvatar(
                radius: 14,
                backgroundColor: isPitcher ? Colors.greenAccent : Colors.orangeAccent,
                child: Text(
                  player['posAbbr']?.toString() ?? '-',
                  style: const TextStyle(fontSize: 9, color: Colors.black, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(player['name']?.toString() ?? '-', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white)),
                    if (statLine != null)
                      Text(statLine, style: const TextStyle(fontSize: 11, color: Colors.white54)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, size: 18, color: Colors.white38),
            ],
          ),
        ),
      ),
    );
  }
}
