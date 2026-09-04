// lib/views/vs_matchup_view.dart
//
// 「この選手とこの選手、対戦成績どうなってるんだろう」を調べるための画面。
// 球団→投手/打者→選手 の順に2人を選ぶと、通算の対戦成績（レギュラー＋
// ポストシーズン合算）を自動表示する。リアルタイム観戦中でなくても、
// 好きな2選手の組み合わせを自由に調べられる。

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/schedule_provider.dart';
import '../services/head_to_head_service.dart';

// ★ 大谷翔平は「投手」ロースター登録でも打者としての対戦成績があるため、
//   どちらのロースター区分にも例外的に含める
const int _ohtaniId = 660271;

class VsMatchupView extends ConsumerStatefulWidget {
  const VsMatchupView({super.key});

  @override
  ConsumerState<VsMatchupView> createState() => _VsMatchupViewState();
}

class _VsMatchupViewState extends ConsumerState<VsMatchupView> {
  bool _loadingTeams = true;
  List<Map<String, dynamic>> _allTeams = [];

  final _PersonSelection _p1 = _PersonSelection();
  final _PersonSelection _p2 = _PersonSelection();

  bool _loadingResult = false;
  HeadToHeadStats? _result;
  bool _attempted = false;

  @override
  void initState() {
    super.initState();
    _fetchTeams();
  }

  Future<void> _fetchTeams() async {
    try {
      final api = ref.read(apiServiceProvider);
      final data = await api.getAllTeams();
      final teams = (data['teams'] as List<dynamic>? ?? [])
          .cast<Map<String, dynamic>>()
          .map((t) => {'id': (t['id'] as num).toInt(), 'name': t['name'].toString()})
          .toList();
      teams.sort((a, b) => (a['name'] as String).compareTo(b['name'] as String));
      if (mounted) setState(() { _allTeams = teams; _loadingTeams = false; });
    } catch (_) {
      if (mounted) setState(() => _loadingTeams = false);
    }
  }

  Future<void> _fetchRoster(_PersonSelection p) async {
    setState(() { p.loadingRoster = true; p.pitchers = []; p.batters = []; p.playerId = null; p.playerName = null; });
    try {
      final api = ref.read(apiServiceProvider);
      final data = await api.getTeamRoster(p.teamId!);
      final roster = data['roster'] as List<dynamic>? ?? [];
      final pitchers = <Map<String, dynamic>>[];
      final batters = <Map<String, dynamic>>[];
      for (final r in roster) {
        final id = (r['person']?['id'] as num?)?.toInt();
        final name = r['person']?['fullName']?.toString();
        if (id == null || name == null) continue;
        final isPitcherPos = r['position']?['type']?.toString() == 'Pitcher';
        final entry = {'id': id, 'name': name};
        // ★ 大谷は例外：投手ロースターでも打者リストに、打者ロースターでも
        //   一応投手リストに含めておく（実際に登板があれば対戦データが出る）
        if (isPitcherPos || id == _ohtaniId) pitchers.add(entry);
        if (!isPitcherPos || id == _ohtaniId) batters.add(entry);
      }
      pitchers.sort((a, b) => (a['name'] as String).compareTo(b['name'] as String));
      batters.sort((a, b) => (a['name'] as String).compareTo(b['name'] as String));
      if (mounted) setState(() { p.pitchers = pitchers; p.batters = batters; p.loadingRoster = false; });
    } catch (_) {
      if (mounted) setState(() => p.loadingRoster = false);
    }
  }

  void _onTeamChanged(_PersonSelection p, int teamId, String teamName) {
    setState(() {
      p.teamId = teamId;
      p.teamName = teamName;
      p.role = null;
      p.playerId = null;
      p.playerName = null;
      p.pitchers = [];
      p.batters = [];
    });
    _fetchRoster(p);
    _maybeFetchResult();
  }

  void _onRoleChanged(_PersonSelection p, String role) {
    setState(() {
      p.role = role;
      p.playerId = null;
      p.playerName = null;
    });
    _maybeFetchResult();
  }

  void _onPlayerChanged(_PersonSelection p, int id, String name) {
    setState(() {
      p.playerId = id;
      p.playerName = name;
    });
    _maybeFetchResult();
  }

  void _maybeFetchResult() {
    if (!_p1.isComplete || !_p2.isComplete) {
      setState(() { _result = null; _attempted = false; });
      return;
    }
    if (_p1.role == _p2.role) {
      // 投手同士・打者同士は対戦成績が定義できないので待機
      setState(() { _result = null; _attempted = false; });
      return;
    }
    final batter = _p1.role == 'batter' ? _p1 : _p2;
    final pitcher = _p1.role == 'pitcher' ? _p1 : _p2;
    setState(() { _loadingResult = true; _attempted = true; });
    fetchHeadToHead(batterId: batter.playerId!, pitcherId: pitcher.playerId!).then((r) {
      if (mounted) setState(() { _result = r; _loadingResult = false; });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('VS 対戦成績検索')),
      body: _loadingTeams
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _buildPersonCard('選手1', _p1, otherRole: _p2.role),
                const SizedBox(height: 8),
                const Center(
                  child: Text('VS', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.blueAccent)),
                ),
                const SizedBox(height: 8),
                _buildPersonCard('選手2', _p2, otherRole: _p1.role),
                const SizedBox(height: 20),
                _buildResult(),
              ],
            ),
    );
  }

  Widget _buildPersonCard(String label, _PersonSelection p, {String? otherRole}) {
    return Card(
      color: const Color(0xFF1E1E2C),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.blueAccent)),
            const SizedBox(height: 8),
            DropdownButtonFormField<int>(
              initialValue: p.teamId,
              isExpanded: true,
              decoration: const InputDecoration(labelText: '球団', border: OutlineInputBorder(), isDense: true),
              items: _allTeams
                  .map((t) => DropdownMenuItem<int>(value: t['id'] as int, child: Text(t['name'] as String)))
                  .toList(),
              onChanged: (v) {
                if (v == null) return;
                final name = _allTeams.firstWhere((t) => t['id'] == v)['name'] as String;
                _onTeamChanged(p, v, name);
              },
            ),
            if (p.teamId != null) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: ChoiceChip(
                      label: const Text('投手'),
                      selected: p.role == 'pitcher',
                      // ★ 相手が既に投手を選んでいる場合はこちらは投手を選べない
                      onSelected: otherRole == 'pitcher' ? null : (_) => _onRoleChanged(p, 'pitcher'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ChoiceChip(
                      label: const Text('打者'),
                      selected: p.role == 'batter',
                      onSelected: otherRole == 'batter' ? null : (_) => _onRoleChanged(p, 'batter'),
                    ),
                  ),
                ],
              ),
            ],
            if (p.role != null) ...[
              const SizedBox(height: 10),
              if (p.loadingRoster)
                const Center(child: Padding(padding: EdgeInsets.all(8), child: CircularProgressIndicator(strokeWidth: 2)))
              else
                DropdownButtonFormField<int>(
                  initialValue: p.playerId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: '選手', border: OutlineInputBorder(), isDense: true),
                  items: (p.role == 'pitcher' ? p.pitchers : p.batters)
                      .map((pl) => DropdownMenuItem<int>(value: pl['id'] as int, child: Text(pl['name'] as String)))
                      .toList(),
                  onChanged: (v) {
                    if (v == null) return;
                    final list = p.role == 'pitcher' ? p.pitchers : p.batters;
                    final name = list.firstWhere((pl) => pl['id'] == v)['name'] as String;
                    _onPlayerChanged(p, v, name);
                  },
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildResult() {
    if (!_attempted) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text('両方の選手を選ぶと対戦成績が表示されます', style: TextStyle(color: Colors.white38, fontSize: 12)),
        ),
      );
    }
    if (_loadingResult) {
      return const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()));
    }

    final batter = _p1.role == 'batter' ? _p1 : _p2;
    final pitcher = _p1.role == 'pitcher' ? _p1 : _p2;

    if (_result == null) {
      return Card(
        color: const Color(0xFF1E1E2C),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Text('${batter.playerName} vs ${pitcher.playerName}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.white)),
              const SizedBox(height: 10),
              const Text('対戦データなし', style: TextStyle(color: Colors.white38)),
            ],
          ),
        ),
      );
    }

    final r = _result!;
    return Card(
      color: const Color(0xFF1E1E2C),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Text('${batter.playerName} vs ${pitcher.playerName}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.white)),
            const SizedBox(height: 4),
            const Text('通算対戦成績（レギュラーシーズン＋ポストシーズン）', style: TextStyle(fontSize: 11, color: Colors.white38)),
            const SizedBox(height: 14),
            Text(
              '${r.atBats}-${r.hits} (${r.avg})',
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.amberAccent),
            ),
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _StatCell(label: '打数', val: '${r.atBats}'),
                _StatCell(label: '安打', val: '${r.hits}'),
                _StatCell(label: '本塁打', val: '${r.homeRuns}'),
                _StatCell(label: '四球', val: '${r.baseOnBalls}'),
                _StatCell(label: '三振', val: '${r.strikeOuts}'),
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

  const _StatCell({required this.label, required this.val});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(label, style: const TextStyle(fontSize: 11, color: Colors.white54)),
        const SizedBox(height: 4),
        Text(val, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
      ],
    );
  }
}

/// 1人分（球団→役割→選手）の選択状態を保持する。
class _PersonSelection {
  int? teamId;
  String? teamName;
  String? role; // 'pitcher' | 'batter'
  List<Map<String, dynamic>> pitchers = [];
  List<Map<String, dynamic>> batters = [];
  bool loadingRoster = false;
  int? playerId;
  String? playerName;

  bool get isComplete => teamId != null && role != null && playerId != null;
}
