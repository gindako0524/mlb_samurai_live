// lib/widgets/advanced_stats_card.dart
//
// 個人成績ページ向けの詳細指標カード。全MLB選手が対象(ランキングには載せない)。
//
// - wOBA / wRC / wRC+ / FIP / xFIP / ERA- / xBA / xSLG / xwOBA は
//   MLB公式APIの stats=sabermetrics・stats=expectedStatistics から取得(advancedStatsProvider)。
// - ISO / BABIP / K% / BB% / K-BB% は既に取得済みの基本成績(seasonStats)から単純計算。
// - OPS+ は30球団のチーム打撃成績を合算して算出したリーグ平均OPSとの比較(簡易版・
//   球場補正なし)。ERA+ はMLB公式のERA-(eraMinus、球場補正込み)から逆算。
// - Exit Velocity / Launch Angle / Barrel% / Hard Hit% / Sprint Speed / Whiff% / OAA は
//   Baseball Savantの公開リーダーボードCSV(league-wide、規定打席・投球回到達者のみ)
//   から一括取得し、選手IDでルックアップ(statcast_provider.dart)。
//
// ★ 以下は無料の公式APIでは取得できないため、このカードには含めていない:
//   UZR・DRS・BsR(FanGraphs/Baseball Info Solutions独自算出、非公開)、
//   CSW%(Baseball Savantのリーダーボードにも項目はあるが実測値が常に空)。

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/advanced_stats_provider.dart';
import '../services/statcast_provider.dart';

class AdvancedStatsCard extends ConsumerWidget {
  final int playerId;
  final bool isPitcher;
  final Map<String, dynamic> seasonStats;

  const AdvancedStatsCard({super.key, required this.playerId, required this.isPitcher, required this.seasonStats});

  double? _num(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString());
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (seasonStats.isEmpty) return const SizedBox.shrink();

    final asyncAdv = ref.watch(advancedStatsProvider(AdvancedStatsParams(personId: playerId, isPitcher: isPitcher)));
    final asyncLeague = ref.watch(leagueAveragesProvider);
    final asyncOaa = ref.watch(oaaLeaderboardProvider);
    final asyncBatterStatcast = isPitcher ? null : ref.watch(statcastBatterLeaderboardProvider);
    final asyncWhiff = isPitcher ? ref.watch(statcastPitcherWhiffProvider) : null;

    final List<MapEntry<String, String>> computed = [];
    if (isPitcher) {
      final so = _num(seasonStats['strikeOuts']);
      final bb = _num(seasonStats['baseOnBalls']);
      final bf = _num(seasonStats['battersFaced']);
      if (so != null && bf != null && bf > 0) {
        computed.add(MapEntry('K%', '${(so / bf * 100).toStringAsFixed(1)}%'));
      }
      if (bb != null && bf != null && bf > 0) {
        computed.add(MapEntry('BB%', '${(bb / bf * 100).toStringAsFixed(1)}%'));
      }
      if (so != null && bb != null && bf != null && bf > 0) {
        computed.add(MapEntry('K-BB%', '${((so - bb) / bf * 100).toStringAsFixed(1)}%'));
      }
    } else {
      final avg = _num(seasonStats['avg']);
      final slg = _num(seasonStats['slg']);
      if (avg != null && slg != null) {
        computed.add(MapEntry('ISO', (slg - avg).toStringAsFixed(3).replaceFirst('0.', '.')));
      }
      final babip = seasonStats['babip'];
      if (babip != null) {
        computed.add(MapEntry('BABIP', babip.toString()));
      }
    }

    // OPS+ / ERA+
    asyncLeague.whenData((league) {
      if (isPitcher) return;
      final ops = _num(seasonStats['ops']);
      if (ops != null && league.leagueOps != null && league.leagueOps! > 0) {
        computed.add(MapEntry('OPS+', (100 * ops / league.leagueOps!).round().toString()));
      }
    });

    return Card(
      color: const Color(0xFF1E2430),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: Colors.tealAccent, width: 1)),
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.analytics_outlined, color: Colors.tealAccent, size: 18),
                SizedBox(width: 6),
                Text('詳細指標', style: TextStyle(fontSize: 12, color: Colors.tealAccent, fontWeight: FontWeight.bold)),
              ],
            ),
            const Divider(height: 20, color: Colors.white12),
            Wrap(
              spacing: 20,
              runSpacing: 10,
              children: [
                for (final c in computed) _MiniField(label: c.key, val: c.value),
                asyncAdv.when(
                  data: (adv) {
                    final fields = <MapEntry<String, String>>[];
                    if (isPitcher) {
                      if (adv.fip != null) fields.add(MapEntry('FIP', adv.fip!.toStringAsFixed(2)));
                      if (adv.xfip != null) fields.add(MapEntry('xFIP', adv.xfip!.toStringAsFixed(2)));
                      if (adv.eraMinus != null) {
                        fields.add(MapEntry('ERA-', adv.eraMinus!.toStringAsFixed(0)));
                        fields.add(MapEntry('ERA+', (10000 / adv.eraMinus!).round().toString()));
                      }
                    } else {
                      if (adv.woba != null) fields.add(MapEntry('wOBA', adv.woba!.toStringAsFixed(3)));
                      if (adv.wRc != null) fields.add(MapEntry('wRC', adv.wRc!.toStringAsFixed(1)));
                      if (adv.wRcPlus != null) fields.add(MapEntry('wRC+', adv.wRcPlus!.toStringAsFixed(0)));
                    }
                    if (adv.xba != null) fields.add(MapEntry('xBA', adv.xba!));
                    if (adv.xslg != null) fields.add(MapEntry('xSLG', adv.xslg!));
                    if (adv.xwoba != null) fields.add(MapEntry('xwOBA', adv.xwoba!));
                    if (fields.isEmpty) return const SizedBox.shrink();
                    return Wrap(
                      spacing: 20,
                      runSpacing: 10,
                      children: [for (final f in fields) _MiniField(label: f.key, val: f.value)],
                    );
                  },
                  loading: () => const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.tealAccent)),
                  error: (_, __) => const SizedBox.shrink(),
                ),
                if (isPitcher && asyncWhiff != null)
                  asyncWhiff.when(
                    data: (whiffMap) {
                      final v = whiffMap[playerId];
                      if (v == null) return const SizedBox.shrink();
                      return _MiniField(label: 'Whiff%', val: '${v.toStringAsFixed(1)}%');
                    },
                    loading: () => const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.tealAccent)),
                    error: (_, __) => const SizedBox.shrink(),
                  ),
                if (!isPitcher && asyncBatterStatcast != null)
                  asyncBatterStatcast.when(
                    data: (map) {
                      final row = map[playerId];
                      if (row == null) return const SizedBox.shrink();
                      final fields = <MapEntry<String, String>>[];
                      if (row.exitVelocityAvg != null) fields.add(MapEntry('Exit Velocity', '${row.exitVelocityAvg!.toStringAsFixed(1)} mph'));
                      if (row.launchAngleAvg != null) fields.add(MapEntry('Launch Angle', '${row.launchAngleAvg!.toStringAsFixed(1)}°'));
                      if (row.barrelRate != null) fields.add(MapEntry('Barrel%', '${row.barrelRate!.toStringAsFixed(1)}%'));
                      if (row.hardHitPercent != null) fields.add(MapEntry('Hard Hit%', '${row.hardHitPercent!.toStringAsFixed(1)}%'));
                      if (row.sprintSpeed != null) fields.add(MapEntry('Sprint Speed', '${row.sprintSpeed!.toStringAsFixed(1)} ft/s'));
                      if (fields.isEmpty) return const SizedBox.shrink();
                      return Wrap(
                        spacing: 20,
                        runSpacing: 10,
                        children: [for (final f in fields) _MiniField(label: f.key, val: f.value)],
                      );
                    },
                    loading: () => const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.tealAccent)),
                    error: (_, __) => const SizedBox.shrink(),
                  ),
                asyncOaa.when(
                  data: (map) {
                    final v = map[playerId];
                    if (v == null) return const SizedBox.shrink();
                    return _MiniField(label: 'OAA', val: v > 0 ? '+${v.toStringAsFixed(0)}' : v.toStringAsFixed(0));
                  },
                  loading: () => const SizedBox.shrink(),
                  error: (_, __) => const SizedBox.shrink(),
                ),
              ],
            ),
            const SizedBox(height: 10),
            const Text(
              'wOBA/wRC/wRC+/FIP/xFIP/ERA-/ERA+/xBA/xSLG/xwOBAはMLB公式APIの算出値。'
              'ISO/BABIP/K%/BB%/K-BB%は基本成績からの単純計算。'
              'OPS+は簡易版(球場補正なし、30球団合算のリーグ平均との比較)。'
              'Exit Velocity/Launch Angle/Barrel%/Hard Hit%/Sprint Speed/Whiff%/OAAは'
              'Baseball Savant公式リーダーボード(規定打席・投球回到達者のみ集計)。'
              'UZR・DRS・BsR・CSW%は無料の公式ソースが無いため未対応です。',
              style: TextStyle(fontSize: 10, color: Colors.white38),
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniField extends StatelessWidget {
  final String label;
  final String val;

  const _MiniField({required this.label, required this.val});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 10, color: Colors.white54)),
        const SizedBox(height: 2),
        Text(val, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white)),
      ],
    );
  }
}
