// lib/views/standings_view.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/schedule_provider.dart';
import '../utils/mlb_divisions.dart';
import 'team_detail_view.dart';

/// MLB全30球団の地区順位表。地区ごとにブロックで表示し、
/// チームをタップするとそのチームの詳細（ロースター・成績TOP選手）へ遷移する。
class StandingsView extends ConsumerStatefulWidget {
  const StandingsView({super.key});

  @override
  ConsumerState<StandingsView> createState() => _StandingsViewState();
}

class _StandingsViewState extends ConsumerState<StandingsView> {
  bool _isLoading = true;
  String? _error;
  // divisionId -> チーム成績リスト（既にdivisionRank順ではないため後でソートする）
  Map<int, List<Map<String, dynamic>>> _byDivision = {};

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
      final data = await api.getStandings();
      final records = data['records'] as List<dynamic>? ?? [];
      final Map<int, List<Map<String, dynamic>>> result = {};
      for (final r in records) {
        final divisionId = (r['division']?['id'] as num?)?.toInt();
        if (divisionId == null) continue;
        final teamRecords = (r['teamRecords'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
        teamRecords.sort((a, b) {
          final ra = int.tryParse(a['divisionRank']?.toString() ?? '') ?? 99;
          final rb = int.tryParse(b['divisionRank']?.toString() ?? '') ?? 99;
          return ra.compareTo(rb);
        });
        result[divisionId] = teamRecords;
      }
      if (mounted) {
        setState(() {
          _byDivision = result;
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.leaderboard, color: Colors.blueAccent),
            SizedBox(width: 8),
            Text('順位表', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ],
        ),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _fetch),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!, style: const TextStyle(color: Colors.redAccent)))
              : ListView(
                  padding: const EdgeInsets.all(12),
                  children: mlbDivisionDisplayOrder.map((divId) {
                    final teams = _byDivision[divId] ?? [];
                    if (teams.isEmpty) return const SizedBox.shrink();
                    return _DivisionBlock(
                      title: mlbDivisionNames[divId] ?? '地区',
                      teams: teams,
                      onTapTeam: (teamId, teamName) {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => TeamDetailView(teamId: teamId, teamName: teamName)),
                        );
                      },
                    );
                  }).toList(),
                ),
    );
  }
}

class _DivisionBlock extends StatelessWidget {
  final String title;
  final List<Map<String, dynamic>> teams;
  final void Function(int teamId, String teamName) onTapTeam;

  const _DivisionBlock({required this.title, required this.teams, required this.onTapTeam});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      color: const Color(0xFF1E1E2C),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.blueAccent)),
            const SizedBox(height: 8),
            // --- ヘッダー行 ---
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 4, horizontal: 4),
              child: Row(
                children: [
                  SizedBox(width: 24, child: Text('順', style: TextStyle(fontSize: 11, color: Colors.white38))),
                  Expanded(child: Text('チーム', style: TextStyle(fontSize: 11, color: Colors.white38))),
                  SizedBox(width: 44, child: Text('勝', textAlign: TextAlign.center, style: TextStyle(fontSize: 11, color: Colors.white38))),
                  SizedBox(width: 44, child: Text('敗', textAlign: TextAlign.center, style: TextStyle(fontSize: 11, color: Colors.white38))),
                  SizedBox(width: 54, child: Text('勝率', textAlign: TextAlign.center, style: TextStyle(fontSize: 11, color: Colors.white38))),
                  SizedBox(width: 44, child: Text('差', textAlign: TextAlign.center, style: TextStyle(fontSize: 11, color: Colors.white38))),
                ],
              ),
            ),
            const Divider(height: 12, color: Colors.white12),
            ...teams.map((t) {
              final team = t['team'] as Map<String, dynamic>?;
              final teamId = (team?['id'] as num?)?.toInt();
              final teamName = team?['name']?.toString() ?? '-';
              final rank = t['divisionRank']?.toString() ?? '-';
              final wins = t['wins']?.toString() ?? '-';
              final losses = t['losses']?.toString() ?? '-';
              final pct = t['winningPercentage']?.toString() ?? '-';
              final gb = t['gamesBack']?.toString() ?? '-';
              final isLeader = rank == '1';

              return InkWell(
                onTap: teamId == null ? null : () => onTapTeam(teamId, teamName),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 24,
                        child: Text(
                          rank,
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: isLeader ? Colors.amberAccent : Colors.white70),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          teamName,
                          style: TextStyle(fontSize: 13, fontWeight: isLeader ? FontWeight.bold : FontWeight.normal, color: Colors.white),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      SizedBox(width: 44, child: Text(wins, textAlign: TextAlign.center, style: const TextStyle(fontSize: 13, color: Colors.white))),
                      SizedBox(width: 44, child: Text(losses, textAlign: TextAlign.center, style: const TextStyle(fontSize: 13, color: Colors.white))),
                      SizedBox(width: 54, child: Text(pct, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, color: Colors.white70))),
                      SizedBox(width: 44, child: Text(gb, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, color: Colors.white70))),
                    ],
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}
