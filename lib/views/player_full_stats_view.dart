// lib/views/player_full_stats_view.dart
//
// 選手の「WAR以外の全成績」と「対戦チーム別成績」を見るための画面。
// stats_view.dart（日本人選手）・mlb_player_detail_view.dart（一般選手）の
// 両方から遷移してくる、選手を問わない共通画面。

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/schedule_provider.dart';
import '../services/mlb_api_service.dart';
import '../utils/stat_field_labels.dart';
import '../utils/live_stat_calc.dart';

class PlayerFullStatsView extends ConsumerStatefulWidget {
  final int playerId;
  final String playerName;
  final bool isPitcher;
  final int? ownTeamId;

  const PlayerFullStatsView({
    super.key,
    required this.playerId,
    required this.playerName,
    required this.isPitcher,
    this.ownTeamId,
  });

  @override
  ConsumerState<PlayerFullStatsView> createState() => _PlayerFullStatsViewState();
}

class _PlayerFullStatsViewState extends ConsumerState<PlayerFullStatsView> {
  bool _isLoading = true;
  String? _error;
  Map<String, dynamic>? _fullStat;
  List<Map<String, dynamic>> _teamSplits = [];
  List<Map<String, dynamic>> _batterySplits = [];

  @override
  void initState() {
    super.initState();
    _fetchAll();
  }

  // ★ MLB公式APIの vsTeam は、投手(group=pitching)で取得しても
  //   「相手打者からの成績」（打数・被安打など打撃側の項目）で返ってくる
  //   （inningsPitchedやeraは含まれない）。打者の対戦量判定にのみ使う。
  int _volumeOf(Map<String, dynamic> stat) {
    return (stat['atBats'] as num?)?.toInt() ?? (stat['plateAppearances'] as num?)?.toInt() ?? 0;
  }

  Future<void> _fetchAll() async {
    final group = widget.isPitcher ? 'pitching' : 'hitting';
    try {
      final api = ref.read(apiServiceProvider);

      final seasonData = await api.getPlayerFullSeasonStats(widget.playerId, group);
      final statsList = seasonData['stats'] as List<dynamic>? ?? [];
      Map<String, dynamic>? fullStat;
      if (statsList.isNotEmpty) {
        final splits = statsList[0]['splits'] as List<dynamic>? ?? [];
        if (splits.isNotEmpty) fullStat = splits[0]['stat'] as Map<String, dynamic>?;
      }

      List<Map<String, dynamic>> teamSplits;
      List<Map<String, dynamic>> batterySplits = [];

      if (widget.isPitcher) {
        // ★ 投手は vsTeam だと防御率・投球回が含まれないため、自チームの試合ログを
        //   相手球団ごとに集計して「本物の投手成績」として組み立てる
        //   （バッテリー別成績と同じ試合ログを使い回せるので効率も良い）
        final gameLogData = await api.getPlayerGameLogStats(widget.playerId, 'pitching');
        final logSplits = (gameLogData['stats'] as List<dynamic>? ?? []).isNotEmpty
            ? (gameLogData['stats'][0]['splits'] as List<dynamic>? ?? [])
            : <dynamic>[];
        teamSplits = _aggregateByOpponent(logSplits);
        batterySplits = await _fetchBatterySplits(api, logSplits);
      } else {
        final teamsData = await api.getAllTeams();
        final allTeams = (teamsData['teams'] as List<dynamic>? ?? [])
            .cast<Map<String, dynamic>>()
            .where((t) => (t['id'] as num?)?.toInt() != widget.ownTeamId)
            .toList();

        final vsTeamResults = await Future.wait(
          allTeams.map((t) async {
            try {
              return await api.getVsTeamStats(widget.playerId, group, (t['id'] as num).toInt());
            } catch (_) {
              return <String, dynamic>{};
            }
          }),
        );

        final splits = <Map<String, dynamic>>[];
        for (int i = 0; i < allTeams.length; i++) {
          final r = vsTeamResults[i];
          final sList = r['stats'] as List<dynamic>? ?? [];
          if (sList.isEmpty) continue;
          final sp = sList[0]['splits'] as List<dynamic>? ?? [];
          if (sp.isEmpty) continue;
          final stat = sp[0]['stat'] as Map<String, dynamic>?;
          if (stat == null) continue;
          if (_volumeOf(stat) <= 0) continue;
          splits.add({'teamId': allTeams[i]['id'], 'teamName': allTeams[i]['name'], 'stat': stat});
        }
        splits.sort((a, b) => _volumeOf(b['stat'] as Map<String, dynamic>).compareTo(_volumeOf(a['stat'] as Map<String, dynamic>)));
        teamSplits = splits;
      }

      if (mounted) {
        setState(() {
          _fullStat = fullStat;
          _teamSplits = teamSplits;
          _batterySplits = batterySplits;
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

  // ★ 投手の試合ログを相手球団ごとにグループ化し、本物の投球成績
  //   （投球回・自責点・防御率・勝敗など）として集計する。
  List<Map<String, dynamic>> _aggregateByOpponent(List<dynamic> logSplits) {
    final Map<int, _PitchingSplitAccumulator> byTeam = {};
    final Map<int, String> teamNames = {};

    for (final s in logSplits) {
      final teamId = (s['opponent']?['id'] as num?)?.toInt();
      final teamName = s['opponent']?['name']?.toString();
      final stat = s['stat'] as Map<String, dynamic>?;
      if (teamId == null || teamName == null || stat == null) continue;
      teamNames[teamId] = teamName;
      final acc = byTeam.putIfAbsent(teamId, () => _PitchingSplitAccumulator());
      acc.addFromGameStat(stat);
    }

    final result = byTeam.entries.map((e) => e.value.toDisplayMap(teamNames[e.key]!, keyField: 'teamName')).toList();
    result.sort((x, y) => (y['outs'] as int).compareTo(x['outs'] as int));
    return result;
  }

  // ★ 投手のバッテリー別（捕手別）成績を、試合ごとの成績＋各試合のボックススコアの
  //   捕手情報から集計する。MLB公式APIに直接の「バッテリー別成績」項目は無いため、
  //   1試合＝1人の捕手が受けた前提（先発マスクを外れる途中交代は考慮しない）で近似する。
  Future<List<Map<String, dynamic>>> _fetchBatterySplits(MlbApiService api, List<dynamic> logSplits) async {
    final games = <Map<String, dynamic>>[];
    for (final s in logSplits) {
      final gamePk = s['game']?['gamePk'] as int?;
      final teamId = (s['team']?['id'] as num?)?.toInt();
      final stat = s['stat'] as Map<String, dynamic>?;
      if (gamePk == null || teamId == null || stat == null) continue;
      games.add({'gamePk': gamePk, 'teamId': teamId, 'stat': stat});
    }
    if (games.isEmpty) return [];

    final boxscores = await Future.wait(
      games.map((g) async {
        try {
          return await api.getGameBoxscore(g['gamePk'] as int);
        } catch (_) {
          return <String, dynamic>{};
        }
      }),
    );

    final Map<String, _PitchingSplitAccumulator> byCatcher = {};
    for (int i = 0; i < games.length; i++) {
      final box = boxscores[i];
      final teamId = games[i]['teamId'] as int;
      final stat = games[i]['stat'] as Map<String, dynamic>;

      final homeId = (box['teams']?['home']?['team']?['id'] as num?)?.toInt();
      final awayId = (box['teams']?['away']?['team']?['id'] as num?)?.toInt();
      Map<String, dynamic>? teamPlayers;
      if (homeId == teamId) {
        teamPlayers = box['teams']?['home']?['players'] as Map<String, dynamic>?;
      } else if (awayId == teamId) {
        teamPlayers = box['teams']?['away']?['players'] as Map<String, dynamic>?;
      }
      if (teamPlayers == null) continue;

      // ★ その試合で先発マスクを付けていた（position=捕手 かつ 打順を持つ）選手を
      //   「この試合の捕手」とみなす
      String? catcherName;
      for (final entry in teamPlayers.entries) {
        final p = entry.value as Map<String, dynamic>?;
        final posCode = p?['position']?['code']?.toString();
        if (posCode == '2' && p?['battingOrder'] != null) {
          catcherName = p?['person']?['fullName']?.toString();
          break;
        }
      }
      catcherName ??= '不明';

      byCatcher.putIfAbsent(catcherName, () => _PitchingSplitAccumulator()).addFromGameStat(stat);
    }

    final result = byCatcher.entries.map((e) => e.value.toDisplayMap(e.key, keyField: 'catcherName')).toList();
    result.sort((x, y) => (y['outs'] as int).compareTo(x['outs'] as int));
    return result;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('${widget.playerName} の全成績')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!, style: const TextStyle(color: Colors.redAccent)))
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    const Text('シーズン全成績（WARを除く全項目）', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.blueAccent)),
                    const SizedBox(height: 10),
                    if (_fullStat == null || _fullStat!.isEmpty)
                      const Card(
                        color: Color(0xFF1E1E2C),
                        child: Padding(padding: EdgeInsets.all(20), child: Text('今シーズンの成績データがありません', style: TextStyle(color: Colors.white38))),
                      )
                    else
                      _FullStatGrid(stat: _fullStat!),
                    const SizedBox(height: 24),
                    const Text('対戦チーム別成績', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.blueAccent)),
                    const SizedBox(height: 4),
                    const Text('タップで全項目を展開表示', style: TextStyle(fontSize: 11, color: Colors.white38)),
                    const SizedBox(height: 10),
                    if (_teamSplits.isEmpty)
                      const Card(
                        color: Color(0xFF1E1E2C),
                        child: Padding(padding: EdgeInsets.all(20), child: Text('対戦記録のある球団がありません', style: TextStyle(color: Colors.white38))),
                      )
                    else
                      ..._teamSplits.map((s) => _TeamSplitTile(
                            teamName: s['teamName'] as String,
                            stat: s['stat'] as Map<String, dynamic>,
                            isPitcher: widget.isPitcher,
                          )),
                    if (widget.isPitcher) ...[
                      const SizedBox(height: 24),
                      const Text('バッテリー別成績（捕手別）', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.blueAccent)),
                      const SizedBox(height: 4),
                      const Text(
                        '各試合の先発捕手ごとに集計（試合途中の捕手交代は考慮していません）',
                        style: TextStyle(fontSize: 11, color: Colors.white38),
                      ),
                      const SizedBox(height: 10),
                      if (_batterySplits.isEmpty)
                        const Card(
                          color: Color(0xFF1E1E2C),
                          child: Padding(padding: EdgeInsets.all(20), child: Text('バッテリーを組んだ試合の記録がありません', style: TextStyle(color: Colors.white38))),
                        )
                      else
                        ..._batterySplits.map((s) => _BatterySplitTile(split: s)),
                    ],
                  ],
                ),
    );
  }
}

/// シーズン全成績を「項目名: 値」の2列グリッドで表示するカード。
class _FullStatGrid extends StatelessWidget {
  final Map<String, dynamic> stat;

  const _FullStatGrid({required this.stat});

  @override
  Widget build(BuildContext context) {
    final entries = stat.entries.toList();
    return Card(
      color: const Color(0xFF1E1E2C),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Wrap(
          spacing: 16,
          runSpacing: 12,
          children: entries.map((e) {
            return SizedBox(
              width: 150,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(formatStatFieldLabel(e.key), style: const TextStyle(fontSize: 11, color: Colors.white54)),
                  const SizedBox(height: 2),
                  Text('${e.value}', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white)),
                ],
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}

/// 対戦チーム1球団分の成績。要約行をタップすると全項目に展開できる。
class _TeamSplitTile extends StatelessWidget {
  final String teamName;
  final Map<String, dynamic> stat;
  final bool isPitcher;

  const _TeamSplitTile({required this.teamName, required this.stat, required this.isPitcher});

  @override
  Widget build(BuildContext context) {
    // ★ 投手は試合ログを相手球団ごとに集計した本物の投球成績（防御率・投球回など）、
    //   打者は公式vsTeamの打撃成績をそのまま使う
    final summary = isPitcher
        ? '${stat['wins'] ?? 0}勝${stat['losses'] ?? 0}敗  防御率 ${stat['era'] ?? '-'}  ${stat['inningsPitched'] ?? '-'}回  奪三振 ${stat['strikeOuts'] ?? 0}'
        : '${stat['hits'] ?? 0}-${stat['atBats'] ?? 0}  打率 ${stat['avg'] ?? '-'}  OPS ${stat['ops'] ?? '-'}';

    return Card(
      color: const Color(0xFF1E1E2C),
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: ExpansionTile(
        title: Text(teamName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.white)),
        subtitle: Text(summary, style: const TextStyle(fontSize: 12, color: Colors.amberAccent)),
        collapsedIconColor: Colors.white54,
        iconColor: Colors.white54,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
            child: _FullStatGrid(stat: stat),
          ),
        ],
      ),
    );
  }
}

/// 投手成績（試合ログの1試合分）を、相手球団別・バッテリー（捕手）別など
/// 任意のキーで積み上げて本物の防御率・投球回に変換するための集計器。
class _PitchingSplitAccumulator {
  int games = 0;
  int outs = 0;
  int earnedRuns = 0;
  int hits = 0;
  int baseOnBalls = 0;
  int strikeOuts = 0;
  int homeRuns = 0;
  int wins = 0;
  int losses = 0;

  void addFromGameStat(Map<String, dynamic> stat) {
    games++;
    outs += inningsPitchedToOuts(stat['inningsPitched']);
    earnedRuns += (stat['earnedRuns'] as num?)?.toInt() ?? 0;
    hits += (stat['hits'] as num?)?.toInt() ?? 0;
    baseOnBalls += (stat['baseOnBalls'] as num?)?.toInt() ?? 0;
    strikeOuts += (stat['strikeOuts'] as num?)?.toInt() ?? 0;
    homeRuns += (stat['homeRuns'] as num?)?.toInt() ?? 0;
    wins += (stat['wins'] as num?)?.toInt() ?? 0;
    losses += (stat['losses'] as num?)?.toInt() ?? 0;
  }

  /// [keyField]に[name]（相手球団名や捕手名）を入れ、集計済みの投球成績を
  /// 'stat'キーの下にまとめて返す。'outs'は並べ替え用に外側にも残す。
  Map<String, dynamic> toDisplayMap(String name, {required String keyField}) {
    final ip = outs / 3.0;
    final era = ip > 0 ? (earnedRuns * 9.0 / ip) : 0.0;
    final whip = ip > 0 ? ((hits + baseOnBalls) / ip) : 0.0;
    return {
      keyField: name,
      'outs': outs,
      'stat': {
        'gamesPlayed': games,
        'wins': wins,
        'losses': losses,
        'inningsPitched': outsToInningsPitched(outs),
        'earnedRuns': earnedRuns,
        'era': era.toStringAsFixed(2),
        'whip': whip.toStringAsFixed(2),
        'hits': hits,
        'baseOnBalls': baseOnBalls,
        'strikeOuts': strikeOuts,
        'homeRuns': homeRuns,
      },
    };
  }
}

class _BatterySplitTile extends StatelessWidget {
  final Map<String, dynamic> split;

  const _BatterySplitTile({required this.split});

  @override
  Widget build(BuildContext context) {
    final stat = split['stat'] as Map<String, dynamic>;
    return Card(
      color: const Color(0xFF1E1E2C),
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${split['catcherName']}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.white)),
            const SizedBox(height: 4),
            Text(
              '${stat['gamesPlayed']}試合  防御率 ${stat['era']}  WHIP ${stat['whip']}  ${stat['inningsPitched']}回',
              style: const TextStyle(fontSize: 12, color: Colors.amberAccent),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 16,
              runSpacing: 8,
              children: [
                _MiniStat(label: '自責点', val: '${stat['earnedRuns']}'),
                _MiniStat(label: '被安打', val: '${stat['hits']}'),
                _MiniStat(label: '与四球', val: '${stat['baseOnBalls']}'),
                _MiniStat(label: '奪三振', val: '${stat['strikeOuts']}'),
                _MiniStat(label: '被本塁打', val: '${stat['homeRuns']}'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  final String label;
  final String val;

  const _MiniStat({required this.label, required this.val});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 10, color: Colors.white54)),
        const SizedBox(height: 2),
        Text(val, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white)),
      ],
    );
  }
}
