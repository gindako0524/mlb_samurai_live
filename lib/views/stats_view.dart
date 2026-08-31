import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import '../models/player.dart';
import '../services/schedule_provider.dart';

class StatsView extends ConsumerStatefulWidget {
  const StatsView({super.key});

  @override
  ConsumerState<StatsView> createState() => _StatsViewState();
}

class _StatsViewState extends ConsumerState<StatsView> {
  int _selectedPlayerIndex = 0;
  bool _isLoading = false;
  String? _errorMessage;

  // 取得した詳細スタッツ
  Map<String, dynamic> _seasonStats = {};
  List<Map<String, dynamic>> _monthlyList = [];
  List<Map<String, dynamic>> _recentGames = [];
  List<FlSpot> _monthlySpots = [];
  List<String> _monthLabels = [];
  double _minY = 0.0;
  double _maxY = 5.0;

  @override
  void initState() {
    super.initState();
    _fetchPlayerStats();
  }

  Future<void> _fetchPlayerStats() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final targetPlayer = japanesePlayers[_selectedPlayerIndex];

    try {
      final api = ref.read(apiServiceProvider);
      final data = await api.getPlayerGameLog(targetPlayer.id, isPitcher: targetPlayer.isPitcher);
      final statsList = data['stats'] as List<dynamic>? ?? [];

      Map<String, dynamic> season = {};
      List<Map<String, dynamic>> rawMonthly = [];
      List<Map<String, dynamic>> recent = [];

      for (final s in statsList) {
        final typeName = s['type']?['displayName'];

        // 1. シーズン詳細成績
        if (typeName == 'season') {
          final splits = s['splits'] as List<dynamic>? ?? [];
          if (splits.isNotEmpty) {
            season = splits.first['stat'] as Map<String, dynamic>? ?? {};
          }
        }

        // 2. 月別成績
        if (typeName == 'byMonth') {
          final splits = s['splits'] as List<dynamic>? ?? [];
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

        // 3. 直近試合ログ
        if (typeName == 'gameLog') {
          final splits = s['splits'] as List<dynamic>? ?? [];
          for (final game in splits.reversed.take(5)) {
            final date = game['date']?.toString() ?? '';
            final opponent = game['opponent']?['name']?.toString() ?? '';
            final stat = game['stat'] as Map<String, dynamic>? ?? {};

            if (targetPlayer.isPitcher) {
              recent.add({
                'date': date.length >= 10 ? date.substring(5) : date,
                'opponent': opponent,
                'detail': '${stat['inningsPitched'] ?? '0'}回 ${stat['earnedRuns'] ?? '0'}自責 ${stat['strikeOuts'] ?? '0'}K ${stat['baseOnBalls'] ?? '0'}四球',
                'main': 'ERA ${stat['era'] ?? '-'}',
              });
            } else {
              recent.add({
                'date': date.length >= 10 ? date.substring(5) : date,
                'opponent': opponent,
                'detail': '${stat['hits'] ?? '0'}安打 ${stat['homeRuns'] ?? '0'}HR ${stat['rbi'] ?? '0'}打点 ${stat['baseOnBalls'] ?? '0'}四球',
                'main': 'AVG .${stat['avg'] ?? '-'}',
              });
            }
          }
        }
      }

      // ★ 月を昇順（3月→4月→5月...）に並び替える
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
        if (targetPlayer.isPitcher) {
          val = double.tryParse(stat['era']?.toString() ?? '') ?? 0.0;
        } else {
          val = double.tryParse(stat['avg']?.toString() ?? '') ?? 0.0;
        }

        spots.add(FlSpot(i.toDouble(), val));
        if (val < minYVal) minYVal = val;
        if (val > maxYVal) maxYVal = val;
      }

      // Y軸の表示範囲に適度な余白を設定
      double calcMinY = targetPlayer.isPitcher ? (minYVal - 0.5).clamp(0.0, 10.0) : (minYVal - 0.05).clamp(0.0, 1.0);
      double calcMaxY = targetPlayer.isPitcher ? (maxYVal + 0.8) : (maxYVal + 0.08);

      if (mounted) {
        setState(() {
          _seasonStats = season;
          _monthlyList = rawMonthly;
          _recentGames = recent;
          _monthlySpots = spots;
          _monthLabels = months;
          _minY = calcMinY;
          _maxY = calcMaxY > calcMinY ? calcMaxY : calcMinY + 1.0;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'データ取得エラー: $e';
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final player = japanesePlayers[_selectedPlayerIndex];

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
            // 選手切り替え
            SizedBox(
              height: 40,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: japanesePlayers.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final p = japanesePlayers[index];
                  final isSelected = index == _selectedPlayerIndex;
                  return ChoiceChip(
                    label: Text('${p.nameJa} (${p.teamName})'),
                    selected: isSelected,
                    onSelected: (selected) {
                      if (selected) {
                        setState(() => _selectedPlayerIndex = index);
                        _fetchPlayerStats();
                      }
                    },
                  );
                },
              ),
            ),
            const SizedBox(height: 16),

            if (_isLoading)
              const Center(child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator()))
            else if (_errorMessage != null)
              Center(child: Text(_errorMessage!, style: const TextStyle(color: Colors.redAccent)))
            else ...[
              // 1. 全項目スタッツグリッド
              Text('${player.nameJa} 2026年 シーズン主要指標', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.blueAccent)),
              const SizedBox(height: 10),
              if (player.isPitcher)
                _buildPitcherDetailedGrid()
              else
                _buildBatterDetailedGrid(),
              const SizedBox(height: 24),

              // 2. 月別推移グラフ（改善版）
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    player.isPitcher ? '月別 防御率 (ERA) の推移' : '月別 打率 (AVG) の推移',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.blueAccent),
                  ),
                  Text(
                    player.isPitcher ? '※低いほど好成績' : '※高いほど好成績',
                    style: const TextStyle(fontSize: 11, color: Colors.white54),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              _buildMonthlyGraphCard(player.isPitcher),
              const SizedBox(height: 24),

              // 3. 月別成績一覧テーブル
              const Text('月別 パフォーマンス詳細表', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.blueAccent)),
              const SizedBox(height: 10),
              _buildMonthlyTable(player.isPitcher),
              const SizedBox(height: 24),

              // 4. 直近試合リスト
              const Text('直近5試合の登板・出場結果', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.blueAccent)),
              const SizedBox(height: 10),
              _buildRecentGamesCard(),
            ],
          ],
        ),
      ),
    );
  }

  // 投手用詳細グリッド
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
                _StatCell(label: '防御率 (ERA)', val: _seasonStats['era']?.toString() ?? '-', highlight: true),
                _StatCell(label: '勝 - 敗', val: '${_seasonStats['wins'] ?? 0} - ${_seasonStats['losses'] ?? 0}'),
                _StatCell(label: 'WHIP', val: _seasonStats['whip']?.toString() ?? '-', highlight: true),
                _StatCell(label: '投球回 (IP)', val: _seasonStats['inningsPitched']?.toString() ?? '-'),
              ],
            ),
            const Divider(height: 20, color: Colors.white12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _StatCell(label: '奪三振 (SO)', val: '${_seasonStats['strikeOuts'] ?? 0}', highlight: true),
                _StatCell(label: '奪三振率 (K/9)', val: _seasonStats['strikeoutsPer9Inn']?.toString() ?? '-'),
                _StatCell(label: '与四球率 (BB/9)', val: _seasonStats['walksPer9Inn']?.toString() ?? '-'),
                _StatCell(label: 'K/BB 比率', val: _seasonStats['strikeoutWalkRatio']?.toString() ?? '-'),
              ],
            ),
            const Divider(height: 20, color: Colors.white12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _StatCell(label: '被打率 (BAA)', val: '.${_seasonStats['avg'] ?? '-'}'),
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

  // 打者用詳細グリッド
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
                _StatCell(label: '打率 (AVG)', val: '.${_seasonStats['avg'] ?? '-'}', highlight: true),
                _StatCell(label: '出塁率 (OBP)', val: '.${_seasonStats['obp'] ?? '-'}'),
                _StatCell(label: '長打率 (SLG)', val: '.${_seasonStats['slg'] ?? '-'}'),
                _StatCell(label: 'OPS', val: _seasonStats['ops']?.toString() ?? '-', highlight: true),
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

  // 月別折れ線グラフ（時系列ソート・数値ツールチップ・余白調整済み）
  Widget _buildMonthlyGraphCard(bool isPitcher) {
    if (_monthlySpots.isEmpty) {
      return const Card(
        color: Color(0xFF1E1E2C),
        child: Padding(padding: EdgeInsets.all(24), child: Center(child: Text('今季の月別データはありません'))),
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
                      final valStr = isPitcher ? spot.y.toStringAsFixed(2) : '.${(spot.y * 1000).toInt().toString().padLeft(3, '0')}';
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
                        isPitcher ? val.toStringAsFixed(1) : '.${(val * 1000).toInt()}',
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

  // 月別詳細表
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
                      _TableCell('.${s['avg'] ?? '-'}'),
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

  // 直近試合リスト
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
          return ListTile(
            dense: true,
            title: Text('${item['date']} vs ${item['opponent']}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            subtitle: Text(item['detail']!, style: const TextStyle(fontSize: 12, color: Colors.white70)),
            trailing: Text(
              item['main']!,
              style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold),
            ),
          );
        },
      ),
    );
  }
}

class _StatCell extends StatelessWidget {
  final String label;
  final String val;
  final bool highlight;

  const _StatCell({required this.label, required this.val, this.highlight = false});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(label, style: const TextStyle(fontSize: 11, color: Colors.white54)),
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