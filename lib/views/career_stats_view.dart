// lib/views/career_stats_view.dart

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import '../models/player.dart';
import '../services/schedule_provider.dart';
import '../utils/stat_glossary.dart';
import '../widgets/contract_info_card.dart';

/// 1つの成績項目の定義（ラベル・JSONキー・表示形式）
class _StatDef {
  final String label;
  final String key;
  final bool isRate;
  final int decimals;
  final bool ascendingIsBetter; // ERA, WHIP 等は「低いほど良い」

  const _StatDef(this.label, this.key, {this.isRate = false, this.decimals = 0, this.ascendingIsBetter = false});
}

// ★ 打者：要求された全項目
const List<_StatDef> _batterStatDefs = [
  _StatDef('打率', 'avg', isRate: true),
  _StatDef('試合', 'gamesPlayed'),
  _StatDef('打数', 'atBats'),
  _StatDef('安打', 'hits'),
  _StatDef('二塁打', 'doubles'),
  _StatDef('三塁打', 'triples'),
  _StatDef('本塁打', 'homeRuns'),
  _StatDef('塁打', 'totalBases'),
  _StatDef('打点', 'rbi'),
  _StatDef('得点', 'runs'),
  _StatDef('三振', 'strikeOuts'),
  _StatDef('四球', 'baseOnBalls'),
  _StatDef('死球', 'hitByPitch'),
  _StatDef('犠打', 'sacBunts'),
  _StatDef('犠飛', 'sacFlies'),
  _StatDef('盗塁', 'stolenBases'),
  _StatDef('出塁率', 'obp', isRate: true),
  _StatDef('長打率', 'slg', isRate: true),
  _StatDef('OPS', 'ops', decimals: 3),
];

// ★ 投手：要求された全項目
const List<_StatDef> _pitcherStatDefs = [
  _StatDef('防御率', 'era', decimals: 2, ascendingIsBetter: true),
  _StatDef('登板', 'gamesPitched'),
  _StatDef('完投', 'completeGames'),
  _StatDef('完封', 'shutouts'),
  _StatDef('勝利', 'wins'),
  _StatDef('敗戦', 'losses'),
  _StatDef('ホールド', 'holds'),
  _StatDef('セーブ', 'saves'),
  _StatDef('勝率', 'winPercentage', isRate: true),
  _StatDef('投球回', 'inningsPitched', decimals: 1),
  _StatDef('被安打', 'hits'),
  _StatDef('被本塁打', 'homeRuns'),
  _StatDef('奪三振', 'strikeOuts'),
  _StatDef('奪三振率', 'strikeoutsPer9Inn', decimals: 2),
  _StatDef('与四球', 'baseOnBalls'),
  _StatDef('与死球', 'hitBatsmen'),
  _StatDef('暴投', 'wildPitches'),
  _StatDef('ボーク', 'balks'),
  _StatDef('失点', 'runs'),
  _StatDef('自責点', 'earnedRuns'),
  _StatDef('被打率', 'avg', isRate: true, ascendingIsBetter: true),
  _StatDef('K/BB', 'strikeoutWalkRatio', decimals: 2),
  _StatDef('WHIP', 'whip', decimals: 2, ascendingIsBetter: true),
];

// タイトル判定（MLB全体1位相当）に使う代表項目。全項目チェックはAPI負荷が大きいため主要指標に絞る。
const List<Map<String, String>> _batterTitleCats = [
  {'key': 'avg', 'leader': 'battingAverage'},
  {'key': 'homeRuns', 'leader': 'homeRuns'},
  {'key': 'rbi', 'leader': 'runsBattedIn'},
  {'key': 'ops', 'leader': 'onBasePlusSlugging'},
];
const List<Map<String, String>> _pitcherTitleCats = [
  {'key': 'era', 'leader': 'earnedRunAverage'},
  {'key': 'wins', 'leader': 'wins'},
  {'key': 'strikeOuts', 'leader': 'strikeouts'},
  {'key': 'saves', 'leader': 'saves'},
];

class CareerStatsView extends ConsumerStatefulWidget {
  final JapanesePlayer player;

  const CareerStatsView({super.key, required this.player});

  @override
  ConsumerState<CareerStatsView> createState() => _CareerStatsViewState();
}

class _CareerStatsViewState extends ConsumerState<CareerStatsView> {
  bool _isLoading = true;
  String? _error;
  bool _pitcherMode = false;

  Map<String, dynamic> _careerStats = {};
  List<Map<String, dynamic>> _yearByYear = [];
  Map<String, double> _warByYear = {}; // 年度(String) -> rWAR
  double _careerWar = 0.0;
  Set<String> _titleYears = {}; // タイトルを獲得した年度のSet
  Map<String, dynamic> _postseasonStats = {}; // 通算ポストシーズン成績（ワールドシリーズ含む）

  @override
  void initState() {
    super.initState();
    _pitcherMode = widget.player.id == 660271 ? false : widget.player.isPitcher;
    _fetchData();
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

  List<_StatDef> get _defs => _pitcherMode ? _pitcherStatDefs : _batterStatDefs;

  String _formatValue(_StatDef def, dynamic raw) {
    if (raw == null) return '-';
    if (def.isRate) return _formatRate(raw);
    final d = double.tryParse(raw.toString());
    if (d == null) return raw.toString();
    return d.toStringAsFixed(def.decimals);
  }

  Future<void> _fetchData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final api = ref.read(apiServiceProvider);
      final data = await api.getPlayerCareerAndYearByYear(widget.player.id, isPitcher: _pitcherMode);

      Map<String, dynamic> career = {};
      List<Map<String, dynamic>> years = [];

      final statsList = data['stats'] as List<dynamic>? ?? [];
      for (final s in statsList) {
        final typeName = s['type']?['displayName']?.toString().toLowerCase() ?? '';
        final splits = s['splits'] as List<dynamic>? ?? [];

        if (typeName == 'career') {
          if (splits.isNotEmpty) {
            career = splits.first['stat'] as Map<String, dynamic>? ?? {};
          }
        }

        if (typeName == 'yearbyyear') {
          for (final sp in splits) {
            final season = sp['season']?.toString() ?? '';
            final team = sp['team']?['name']?.toString() ?? '';
            final stat = sp['stat'] as Map<String, dynamic>? ?? {};
            years.add({'season': season, 'team': team, 'stat': stat});
          }
        }
      }

      years.sort((a, b) => (a['season'] as String).compareTo(b['season'] as String));

      // ★ WARデータ(GitHub上のwar_data.json)を取得
      final warJson = await _fetchWarJson();
      Map<String, double> warByYear = {};
      double careerWar = 0.0;
      if (warJson != null) {
        final playerMap = warJson['players']?[widget.player.id.toString()] as Map<String, dynamic>?;
        if (playerMap != null) {
          final rawMap = _pitcherMode ? playerMap['war_by_year_pitch'] : playerMap['war_by_year'];
          if (rawMap is Map) {
            warByYear = rawMap.map((k, v) => MapEntry(k.toString(), (v as num?)?.toDouble() ?? 0.0));
          }
          careerWar = (_pitcherMode ? playerMap['career_rwar_pitch'] : playerMap['career_rwar'])?.toDouble() ?? 0.0;
        }
      }

      // ★ タイトル獲得年の判定（主要4項目、MLB全体1位相当で簡易判定）
      final titleYears = await _detectTitleYears(years);

      // ★ 通算ポストシーズン成績（ワールドシリーズ含む）。プレーオフ未経験の選手も多いため、
      //   取得失敗・空データはエラー扱いにせず静かに空のまま表示しない
      Map<String, dynamic> postseason = {};
      try {
        final psData = await api.getPlayerPostseasonCareer(widget.player.id, isPitcher: _pitcherMode);
        final psStatsList = psData['stats'] as List<dynamic>? ?? [];
        if (psStatsList.isNotEmpty) {
          final psSplits = psStatsList.first['splits'] as List<dynamic>? ?? [];
          if (psSplits.isNotEmpty) {
            postseason = psSplits.first['stat'] as Map<String, dynamic>? ?? {};
          }
        }
      } catch (_) {
        // ポストシーズンデータが無い/取得できない選手は多いため無視する
      }

      if (mounted) {
        setState(() {
          _careerStats = career;
          _yearByYear = years;
          _warByYear = warByYear;
          _careerWar = careerWar;
          _titleYears = titleYears;
          _postseasonStats = postseason;
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

  Future<Map<String, dynamic>?> _fetchWarJson() async {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final urls = [
      'https://raw.githubusercontent.com/gindako0524/mlb_samurai_live/main/war_data.json?t=$timestamp',
      'https://cdn.jsdelivr.net/gh/gindako0524/mlb_samurai_live@main/war_data.json?t=$timestamp',
      'https://api.github.com/repos/gindako0524/mlb_samurai_live/contents/war_data.json?ref=main&t=$timestamp',
    ];
    for (final url in urls) {
      try {
        final response = await http.get(Uri.parse(url), headers: {'Accept': 'application/vnd.github.v3.raw+json'});
        if (response.statusCode == 200) {
          final decoded = json.decode(utf8.decode(response.bodyBytes));
          if (decoded is Map<String, dynamic> && decoded.containsKey('content')) {
            final contentStr = decoded['content'].toString().replaceAll('\n', '').replaceAll('\r', '');
            return json.decode(utf8.decode(base64.decode(contentStr))) as Map<String, dynamic>;
          }
          return decoded as Map<String, dynamic>;
        }
      } catch (_) {}
    }
    return null;
  }

  /// 各年度について、主要4項目がMLB全体1位相当だったかを判定する
  Future<Set<String>> _detectTitleYears(List<Map<String, dynamic>> years) async {
    final titleCats = _pitcherMode ? _pitcherTitleCats : _batterTitleCats;
    final group = _pitcherMode ? 'pitching' : 'hitting';
    final Set<String> result = {};

    await Future.wait(years.map((y) async {
      final season = y['season'] as String;
      final stat = y['stat'] as Map<String, dynamic>;

      for (final cat in titleCats) {
        final playerRaw = stat[cat['key']];
        final playerVal = double.tryParse(playerRaw?.toString() ?? '');
        if (playerVal == null || playerVal == 0) continue;

        try {
          final url = Uri.parse(
            'https://statsapi.mlb.com/api/v1/stats/leaders?leaderCategories=${cat['leader']}&statGroup=$group&season=$season&sportId=1&limit=1',
          );
          final res = await http.get(url);
          if (res.statusCode != 200) continue;
          final data = json.decode(utf8.decode(res.bodyBytes));
          final leagueLeaders = data['leagueLeaders'] as List<dynamic>? ?? [];
          if (leagueLeaders.isEmpty) continue;
          final leaders = leagueLeaders.first['leaders'] as List<dynamic>? ?? [];
          if (leaders.isEmpty) continue;
          final leaderVal = double.tryParse(leaders.first['value']?.toString() ?? '');
          if (leaderVal == null) continue;

          if ((playerVal - leaderVal).abs() < 0.0005) {
            result.add(season);
          }
        } catch (_) {}
      }
    }));

    return result;
  }

  @override
  Widget build(BuildContext context) {
    final isOhtani = widget.player.id == 660271;

    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.player.nameJa} 通算・年度別成績', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _fetchData),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (isOhtani) ...[
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(color: const Color(0xFF1E1E2C), borderRadius: BorderRadius.circular(10)),
                child: Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () {
                          if (_pitcherMode) {
                            setState(() => _pitcherMode = false);
                            _fetchData();
                          }
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          decoration: BoxDecoration(
                            color: !_pitcherMode ? Colors.blueAccent : Colors.transparent,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          alignment: Alignment.center,
                          child: const Text('🏏 打撃成績', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                        ),
                      ),
                    ),
                    Expanded(
                      child: GestureDetector(
                        onTap: () {
                          if (!_pitcherMode) {
                            setState(() => _pitcherMode = true);
                            _fetchData();
                          }
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          decoration: BoxDecoration(
                            color: _pitcherMode ? Colors.blueAccent : Colors.transparent,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          alignment: Alignment.center,
                          child: const Text('⚾ 投手成績', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
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
            else if (_error != null)
              Center(child: Text(_error!, style: const TextStyle(color: Colors.redAccent)))
            else ...[
              Row(
                children: const [
                  Icon(Icons.emoji_events, size: 14, color: Colors.amberAccent),
                  SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '黄色背景の年度は主要指標でMLB全体1位相当だった年（簡易判定）',
                      style: TextStyle(fontSize: 11, color: Colors.white38),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ContractInfoCard(playerId: widget.player.id),
              const Text('MLB通算成績', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.blueAccent)),
              const SizedBox(height: 10),
              _buildCareerCard(),
              if (_postseasonStats.isNotEmpty) ...[
                const SizedBox(height: 16),
                const Text('通算成績（ポストシーズン・ワールドシリーズ含む）', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.blueAccent)),
                const SizedBox(height: 10),
                _buildPostseasonCard(),
              ],
              const SizedBox(height: 24),
              const Text('年度別成績', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.blueAccent)),
              const SizedBox(height: 10),
              _buildYearByYearTable(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildCareerCard() {
    if (_careerStats.isEmpty) {
      return const Card(
        color: Color(0xFF1E1E2C),
        child: Padding(padding: EdgeInsets.all(24), child: Center(child: Text('通算成績データがありません'))),
      );
    }

    return Card(
      color: const Color(0xFF1E2638),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: Colors.blueAccent, width: 1)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.analytics, color: Colors.amberAccent, size: 18),
                const SizedBox(width: 6),
                const Text('通算 rWAR (Baseball-Reference)', style: TextStyle(fontSize: 12, color: Colors.amberAccent, fontWeight: FontWeight.bold)),
                const StatInfoIcon('war'),
                const Spacer(),
                Text(
                  _careerWar != 0.0 ? _careerWar.toStringAsFixed(1) : '取得できません',
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.amberAccent),
                ),
              ],
            ),
            const Divider(height: 20, color: Colors.white12),
            Wrap(
              spacing: 16,
              runSpacing: 14,
              children: _defs.map((def) {
                return SizedBox(
                  width: 90,
                  child: _StatCell(label: def.label, val: _formatValue(def, _careerStats[def.key]), statKey: def.key),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  // ★ 通算ポストシーズン成績カード（ワールドシリーズ含む全ポストシーズン合算値）。
  //   rWARはBaseball-Referenceのデータがレギュラーシーズン限定のため、ここには含めない。
  Widget _buildPostseasonCard() {
    return Card(
      color: const Color(0xFF261E2C),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: Colors.purpleAccent, width: 1)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Wrap(
          spacing: 16,
          runSpacing: 14,
          children: _defs.map((def) {
            return SizedBox(
              width: 90,
              child: _StatCell(label: def.label, val: _formatValue(def, _postseasonStats[def.key]), statKey: def.key),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildYearByYearTable() {
    if (_yearByYear.isEmpty) {
      return const Card(
        color: Color(0xFF1E1E2C),
        child: Padding(padding: EdgeInsets.all(24), child: Center(child: Text('年度別データがありません'))),
      );
    }

    return Card(
      color: const Color(0xFF1E1E2C),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Table(
          border: TableBorder.symmetric(inside: const BorderSide(color: Colors.white12, width: 1)),
          defaultColumnWidth: const IntrinsicColumnWidth(),
          children: [
            TableRow(
              decoration: const BoxDecoration(color: Colors.white10),
              children: [
                const _TableCell('年度', isHeader: true),
                const _TableCell('チーム', isHeader: true),
                ..._defs.map((d) => _TableCell(d.label, isHeader: true)),
                const _TableCell('rWAR', isHeader: true),
              ],
            ),
            ..._yearByYear.map((y) {
              final s = y['stat'] as Map<String, dynamic>;
              final season = y['season'] as String;
              final isTitle = _titleYears.contains(season);
              final warVal = _warByYear[season];

              return TableRow(
                decoration: isTitle ? BoxDecoration(color: Colors.amberAccent.withAlpha(35)) : null,
                children: [
                  _TableCell(season, highlight: isTitle),
                  _TableCell(y['team'] as String),
                  ..._defs.map((d) => _TableCell(_formatValue(d, s[d.key]))),
                  _TableCell(warVal != null ? warVal.toStringAsFixed(1) : '-'),
                ],
              );
            }),
          ],
        ),
      ),
    );
  }
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
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, style: const TextStyle(fontSize: 10, color: Colors.white54)),
            StatInfoIcon(statKey, size: 11),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          val,
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: highlight ? Colors.amberAccent : Colors.white),
        ),
      ],
    );
  }
}

class _TableCell extends StatelessWidget {
  final String text;
  final bool isHeader;
  final bool highlight;

  const _TableCell(this.text, {this.isHeader = false, this.highlight = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
      child: Center(
        child: Text(
          text,
          style: TextStyle(
            fontSize: 11,
            fontWeight: (isHeader || highlight) ? FontWeight.bold : FontWeight.normal,
            color: isHeader ? Colors.blueAccent : (highlight ? Colors.amberAccent : Colors.white70),
          ),
        ),
      ),
    );
  }
}