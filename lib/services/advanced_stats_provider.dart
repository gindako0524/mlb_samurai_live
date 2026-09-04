// lib/services/advanced_stats_provider.dart
//
// 個人成績ページ向けの詳細指標(セイバーメトリクス系)。
// MLB公式API(statsapi.mlb.com)が算出済みの値をそのまま返す stats=sabermetrics /
// stats=expectedStatistics を使うため、自前での計算・外部サイトのスクレイピングは
// 一切不要。ISO・BABIP・K%・BB%・K-BB% は既に取得済みの基本成績から単純計算できる
// ため、ここでは sabermetrics / expectedStatistics の2種類のみを追加取得する。

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'schedule_provider.dart' show apiServiceProvider;

class AdvancedStatsParams {
  final int personId;
  final bool isPitcher;
  final int season;

  const AdvancedStatsParams({required this.personId, required this.isPitcher, this.season = 2026});

  @override
  bool operator ==(Object other) =>
      other is AdvancedStatsParams && other.personId == personId && other.isPitcher == isPitcher && other.season == season;

  @override
  int get hashCode => Object.hash(personId, isPitcher, season);
}

class AdvancedStats {
  // --- セイバーメトリクス(MLB公式算出) ---
  final double? woba;
  final double? wRc;
  final double? wRcPlus;
  final double? fip;
  final double? xfip;
  final double? eraMinus; // 数値が低いほど良い(100=平均)。ERA+の逆スケール相当。
  // --- 期待値指標(Statcast由来、MLB公式算出) ---
  final String? xba;
  final String? xslg;
  final String? xwoba;

  const AdvancedStats({
    this.woba,
    this.wRc,
    this.wRcPlus,
    this.fip,
    this.xfip,
    this.eraMinus,
    this.xba,
    this.xslg,
    this.xwoba,
  });

  bool get isEmpty =>
      woba == null && wRc == null && wRcPlus == null && fip == null && xfip == null && eraMinus == null && xba == null && xslg == null && xwoba == null;
}

double? _numFrom(dynamic v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString());
}

final advancedStatsProvider = FutureProvider.family<AdvancedStats, AdvancedStatsParams>((ref, params) async {
  final api = ref.read(apiServiceProvider);
  final group = params.isPitcher ? 'pitching' : 'hitting';

  Map<String, dynamic>? saberStat;
  Map<String, dynamic>? expectedStat;

  try {
    final saberRes = await api.getPlayerSabermetrics(params.personId, group, season: params.season);
    final statsList = saberRes['stats'] as List?;
    if (statsList != null && statsList.isNotEmpty) {
      final splits = statsList.first['splits'] as List?;
      if (splits != null && splits.isNotEmpty) {
        saberStat = splits.first['stat'] as Map<String, dynamic>?;
      }
    }
  } catch (_) {}

  try {
    final expRes = await api.getPlayerExpectedStats(params.personId, group, season: params.season);
    final statsList = expRes['stats'] as List?;
    if (statsList != null && statsList.isNotEmpty) {
      final splits = statsList.first['splits'] as List?;
      if (splits != null && splits.isNotEmpty) {
        expectedStat = splits.first['stat'] as Map<String, dynamic>?;
      }
    }
  } catch (_) {}

  return AdvancedStats(
    woba: _numFrom(saberStat?['woba']),
    wRc: _numFrom(saberStat?['wRc']),
    wRcPlus: _numFrom(saberStat?['wRcPlus']),
    fip: _numFrom(saberStat?['fip']),
    xfip: _numFrom(saberStat?['xfip']),
    eraMinus: _numFrom(saberStat?['eraMinus']),
    xba: expectedStat?['avg']?.toString(),
    xslg: expectedStat?['slg']?.toString(),
    xwoba: expectedStat?['woba']?.toString(),
  );
});

// ★ OPS+ はMLB公式APIに直接の項目が無いため、球団別成績(30球団)を合算して
//   リーグ平均OPSを算出し、簡易的に 100×選手OPS/リーグ平均OPS で算出する。
//   ※本来のOPS+は球場補正(パークファクター)を含むが、無料公式APIには
//   パークファクターの項目が無いため、この実装では球場補正を行っていない
//   (=簡易版であることをUI上で明示する)。
//   ERA+はMLB公式のeraMinus(ERA-、球場補正込み・公式算出値)から
//   10000/eraMinus で逆算して求めるため、こちらはOPS+と異なり公式の
//   球場補正が反映されている。
class LeagueAverages {
  final double? leagueOps;

  const LeagueAverages({this.leagueOps});
}

final leagueAveragesProvider = FutureProvider<LeagueAverages>((ref) async {
  final api = ref.read(apiServiceProvider);
  try {
    final res = await api.getAllTeamsHittingStats(season: 2026);
    final splits = (res['stats'] as List?)?.firstOrNullOrEmptySplits();
    if (splits == null) return const LeagueAverages();

    int sumH = 0, sumBb = 0, sumHbp = 0, sumAb = 0, sumSf = 0, sumTb = 0;
    for (final s in splits) {
      final stat = s['stat'] as Map<String, dynamic>?;
      if (stat == null) continue;
      sumH += ((stat['hits'] as num?) ?? 0).toInt();
      sumBb += ((stat['baseOnBalls'] as num?) ?? 0).toInt();
      sumHbp += ((stat['hitByPitch'] as num?) ?? 0).toInt();
      sumAb += ((stat['atBats'] as num?) ?? 0).toInt();
      sumSf += ((stat['sacFlies'] as num?) ?? 0).toInt();
      sumTb += ((stat['totalBases'] as num?) ?? 0).toInt();
    }
    final obDenom = sumAb + sumBb + sumHbp + sumSf;
    if (obDenom <= 0 || sumAb <= 0) return const LeagueAverages();
    final leagueObp = (sumH + sumBb + sumHbp) / obDenom;
    final leagueSlg = sumTb / sumAb;
    return LeagueAverages(leagueOps: leagueObp + leagueSlg);
  } catch (_) {
    return const LeagueAverages();
  }
});

extension _FirstSplits on List<dynamic> {
  List<dynamic>? firstOrNullOrEmptySplits() {
    if (isEmpty) return null;
    return (first['splits'] as List?);
  }
}
