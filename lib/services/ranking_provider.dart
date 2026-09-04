// lib/services/ranking_provider.dart

import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import '../models/player.dart';

enum RankingScope { japan, league, mlb, team }

enum LeagueSide { al, nl }

enum PlayerType { batter, pitcher }

enum TeamRankMode { aggregate, topPlayer }

/// 左右フィルター。ALL=全体, R=右, L=左
enum HandFilter { all, right, left }

/// 1つの成績カテゴリの定義
class StatCategory {
  final String label;
  final String statKey; // MLB GameLog（選手個別成績）側のJSONキー
  final String group; // 'hitting' | 'pitching'
  final bool isRate;
  final bool ascending; // 値が低いほど良い成績か（ERA, WHIP, BB/9など）
  final int decimals;
  final String specialType; // 'normal' | 'risp' | 'qsRate' | 'hqs'
  final String? leaderCategory; // MLB公式 stats/leaders API の公式カテゴリ名（通算リーダーボード取得に使用）

  const StatCategory({
    required this.label,
    required this.statKey,
    required this.group,
    this.isRate = false,
    this.ascending = false,
    this.decimals = 0,
    this.specialType = 'normal',
    this.leaderCategory,
  });
}

// ★ 関連する項目が近くに並ぶようグルーピングして整理
const List<StatCategory> batterCategories = [
  // 率系
  StatCategory(label: '打率 (AVG)', statKey: 'avg', group: 'hitting', isRate: true, leaderCategory: 'battingAverage'),
  StatCategory(label: '出塁率 (OBP)', statKey: 'obp', group: 'hitting', isRate: true, leaderCategory: 'onBasePercentage'),
  StatCategory(label: '長打率 (SLG)', statKey: 'slg', group: 'hitting', isRate: true, leaderCategory: 'sluggingPercentage'),
  StatCategory(label: 'OPS', statKey: 'ops', group: 'hitting', decimals: 3, leaderCategory: 'onBasePlusSlugging'),
  StatCategory(label: '得点圏打率 (RISP)', statKey: 'avg', group: 'hitting', isRate: true, specialType: 'risp'),
  // 得点関連
  StatCategory(label: '本塁打 (HR)', statKey: 'homeRuns', group: 'hitting', leaderCategory: 'homeRuns'),
  StatCategory(label: '打点 (RBI)', statKey: 'rbi', group: 'hitting', leaderCategory: 'runsBattedIn'),
  StatCategory(label: '得点 (R)', statKey: 'runs', group: 'hitting', leaderCategory: 'runsScored'),
  StatCategory(label: '安打数 (H)', statKey: 'hits', group: 'hitting', leaderCategory: 'hits'),
  StatCategory(label: '二塁打 (2B)', statKey: 'doubles', group: 'hitting', leaderCategory: 'doubles'),
  StatCategory(label: '三塁打 (3B)', statKey: 'triples', group: 'hitting', leaderCategory: 'triples'),
  // 出場量
  StatCategory(label: '打数 (AB)', statKey: 'atBats', group: 'hitting', leaderCategory: 'atBats'),
  StatCategory(label: '打席 (PA)', statKey: 'plateAppearances', group: 'hitting', leaderCategory: 'plateAppearances'),
  // 選球眼
  StatCategory(label: '四球 (BB)', statKey: 'baseOnBalls', group: 'hitting', leaderCategory: 'baseOnBalls'),
  StatCategory(label: '三振 (SO)', statKey: 'strikeOuts', group: 'hitting', leaderCategory: 'strikeouts'),
  StatCategory(label: '死球 (HBP)', statKey: 'hitByPitch', group: 'hitting', leaderCategory: 'hitByPitch'),
  // 走塁・小技・守備
  StatCategory(label: '盗塁 (SB)', statKey: 'stolenBases', group: 'hitting', leaderCategory: 'stolenBases'),
  StatCategory(label: '犠打 (SAC)', statKey: 'sacBunts', group: 'hitting', leaderCategory: 'sacBunts'),
  StatCategory(label: '犠飛 (SF)', statKey: 'sacFlies', group: 'hitting', leaderCategory: 'sacFlies'),
  StatCategory(label: '失策 (E)', statKey: 'errors', group: 'fielding', leaderCategory: 'errors'),
];

const List<StatCategory> pitcherCategories = [
  // 率系（質）
  StatCategory(label: '防御率 (ERA)', statKey: 'era', group: 'pitching', ascending: true, decimals: 2, leaderCategory: 'earnedRunAverage'),
  StatCategory(label: 'WHIP', statKey: 'whip', group: 'pitching', ascending: true, decimals: 2, leaderCategory: 'walksAndHitsPerInningPitched'),
  StatCategory(label: '被打率 (BAA)', statKey: 'avg', group: 'pitching', isRate: true, ascending: true),
  StatCategory(label: '奪三振率 (K/9)', statKey: 'strikeoutsPer9Inn', group: 'pitching', decimals: 2, leaderCategory: 'strikeoutsPer9Inn'),
  StatCategory(label: '与四球率 (BB/9)', statKey: 'walksPer9Inn', group: 'pitching', ascending: true, decimals: 2, leaderCategory: 'walksPer9Inn'),
  StatCategory(label: 'K/BB 比率', statKey: 'strikeoutWalkRatio', group: 'pitching', decimals: 2, leaderCategory: 'strikeoutWalkRatio'),
  // 勝敗・登板記録
  StatCategory(label: '勝利数 (W)', statKey: 'wins', group: 'pitching', leaderCategory: 'wins'),
  StatCategory(label: '敗戦数 (L)', statKey: 'losses', group: 'pitching', leaderCategory: 'losses'),
  StatCategory(label: '勝率', statKey: 'winPercentage', group: 'pitching', isRate: true, leaderCategory: 'winPercentage'),
  StatCategory(label: 'セーブ (SV)', statKey: 'saves', group: 'pitching', leaderCategory: 'saves'),
  StatCategory(label: '先発登板数 (GS)', statKey: 'gamesStarted', group: 'pitching', leaderCategory: 'gamesStarted'),
  StatCategory(label: '完投数 (CG)', statKey: 'completeGames', group: 'pitching', leaderCategory: 'completeGames'),
  StatCategory(label: '完封数 (SHO)', statKey: 'shutouts', group: 'pitching', leaderCategory: 'shutouts'),
  // クオリティスタート系
  StatCategory(label: 'QS数', statKey: 'qs', group: 'pitching', specialType: 'qs'),
  StatCategory(label: 'QS率', statKey: 'qs', group: 'pitching', specialType: 'qsRate'),
  StatCategory(label: 'HQS数 (7回2失点以下)', statKey: 'hqs', group: 'pitching', specialType: 'hqs'),
  // 出場量
  StatCategory(label: '投球回 (IP)', statKey: 'inningsPitched', group: 'pitching', decimals: 1, leaderCategory: 'inningsPitched'),
  StatCategory(label: '奪三振 (SO)', statKey: 'strikeOuts', group: 'pitching', leaderCategory: 'strikeouts'),
  // 被弾・与四死球など
  StatCategory(label: '被安打数 (H)', statKey: 'hits', group: 'pitching', leaderCategory: 'hits'),
  StatCategory(label: '被本塁打数 (HR)', statKey: 'homeRuns', group: 'pitching', leaderCategory: 'homeRuns'),
  StatCategory(label: '与四球数 (BB)', statKey: 'baseOnBalls', group: 'pitching', leaderCategory: 'baseOnBalls'),
  StatCategory(label: '与死球 (HBP)', statKey: 'hitBatsmen', group: 'pitching', leaderCategory: 'hitBatsmen'),
  StatCategory(label: 'ボーク (BK)', statKey: 'balks', group: 'pitching', leaderCategory: 'balks'),
  StatCategory(label: '暴投 (WP)', statKey: 'wildPitches', group: 'pitching', leaderCategory: 'wildPitches'),
  // 失点
  StatCategory(label: '自責点 (ER)', statKey: 'earnedRuns', group: 'pitching', leaderCategory: 'earnedRuns'),
  StatCategory(label: '失点 (R)', statKey: 'runs', group: 'pitching', leaderCategory: 'runs'),
];

/// ランキング一覧の1行分
class RankingEntry {
  final int rank;
  final String name;
  final String? nameJa;
  final String team;
  final String displayValue;
  final bool isJapanese;
  final int? personId;
  final String? handCode;

  RankingEntry({
    required this.rank,
    required this.name,
    this.nameJa,
    required this.team,
    required this.displayValue,
    required this.isJapanese,
    this.personId,
    this.handCode,
  });

  RankingEntry copyWithHand(String? hand) => RankingEntry(
        rank: rank,
        name: name,
        nameJa: nameJa,
        team: team,
        displayValue: displayValue,
        isJapanese: isJapanese,
        personId: personId,
        handCode: hand,
      );
}

String _categoryUniqueKey(StatCategory c) => c.specialType == 'normal' ? c.statKey : '${c.statKey}#${c.specialType}';

class RankingParams {
  final RankingScope scope;
  final LeagueSide leagueSide;
  final PlayerType playerType;
  final String categoryKey;
  final TeamRankMode teamMode; // scope==team の時のみ使用
  final bool allTeams; // scope==team の時のみ使用。true=全30球団、false=leagueSideに従う
  final bool isCareer; // true=通算成績、false=今シーズン成績
  final bool activeOnly; // isCareer==true の時のみ意味を持つ。true=現役選手のみ、false=歴代全選手

  const RankingParams({
    required this.scope,
    required this.leagueSide,
    required this.playerType,
    required this.categoryKey,
    this.teamMode = TeamRankMode.aggregate,
    this.allTeams = true,
    this.isCareer = false,
    this.activeOnly = false,
  });

  @override
  bool operator ==(Object other) =>
      other is RankingParams &&
      other.scope == scope &&
      other.leagueSide == leagueSide &&
      other.playerType == playerType &&
      other.categoryKey == categoryKey &&
      other.teamMode == teamMode &&
      other.allTeams == allTeams &&
      other.isCareer == isCareer &&
      other.activeOnly == activeOnly;

  @override
  int get hashCode =>
      Object.hash(scope, leagueSide, playerType, categoryKey, teamMode, allTeams, isCareer, activeOnly);
}

class TotalWarParams {
  final RankingScope scope;
  final LeagueSide leagueSide;

  const TotalWarParams({required this.scope, required this.leagueSide});

  @override
  bool operator ==(Object other) =>
      other is TotalWarParams && other.scope == scope && other.leagueSide == leagueSide;

  @override
  int get hashCode => Object.hash(scope, leagueSide);
}

String _formatRateStr(dynamic val) {
  if (val == null) return '-';
  final d = double.tryParse(val.toString());
  if (d == null) return val.toString();
  if (d < 1.0 && d > -1.0) {
    final sign = d < 0 ? '-' : '';
    return '$sign.${(d.abs() * 1000).round().toString().padLeft(3, '0')}';
  }
  return d.toStringAsFixed(3);
}

// MLB全30球団のチームID → リーグ（AL/NL）対応表
const Map<int, String> _teamLeagueMap = {
  108: 'AL', 109: 'NL', 110: 'AL', 111: 'AL', 112: 'NL', 113: 'NL', 114: 'AL', 115: 'NL',
  116: 'AL', 117: 'AL', 118: 'AL', 119: 'NL', 120: 'NL', 121: 'NL', 133: 'AL', 134: 'NL',
  135: 'NL', 136: 'AL', 137: 'NL', 138: 'NL', 139: 'AL', 140: 'AL', 141: 'AL', 142: 'AL',
  143: 'NL', 144: 'NL', 145: 'AL', 146: 'NL', 147: 'AL', 158: 'NL',
};

// MLB全30球団のチームID → 略称対応表（表示用）
const Map<int, String> _teamAbbrevMap = {
  108: 'LAA', 109: 'ARI', 110: 'BAL', 111: 'BOS', 112: 'CHC', 113: 'CIN', 114: 'CLE', 115: 'COL',
  116: 'DET', 117: 'HOU', 118: 'KC', 119: 'LAD', 120: 'WSH', 121: 'NYM', 133: 'OAK', 134: 'PIT',
  135: 'SD', 136: 'SEA', 137: 'SF', 138: 'STL', 139: 'TB', 140: 'TEX', 141: 'TOR', 142: 'MIN',
  143: 'PHI', 144: 'ATL', 145: 'CWS', 146: 'MIA', 147: 'NYY', 158: 'MIL',
};

/// QS（Quality Start）判定: 6回以上・自責点3以下
int countQs(List<Map<String, dynamic>> gameLog) {
  int count = 0;
  for (final g in gameLog) {
    final ip = double.tryParse(g['inningsPitched']?.toString() ?? '') ?? 0.0;
    final er = double.tryParse(g['earnedRuns']?.toString() ?? '') ?? 0.0;
    if (ip >= 6.0 && er <= 3.0) count++;
  }
  return count;
}

/// HQS（High Quality Start）判定: 7回以上・自責点2以下
int countHqs(List<Map<String, dynamic>> gameLog) {
  int count = 0;
  for (final g in gameLog) {
    final ip = double.tryParse(g['inningsPitched']?.toString() ?? '') ?? 0.0;
    final er = double.tryParse(g['earnedRuns']?.toString() ?? '') ?? 0.0;
    if (ip >= 7.0 && er <= 2.0) count++;
  }
  return count;
}

// ============================================================
// 成績カテゴリランキング
// ============================================================

final rankingProvider = FutureProvider.family<List<RankingEntry>, RankingParams>((ref, params) async {
  final categories = params.playerType == PlayerType.pitcher ? pitcherCategories : batterCategories;
  final category = categories.firstWhere(
    (c) => _categoryUniqueKey(c) == params.categoryKey,
    orElse: () => categories.first,
  );

  final List<RankingEntry> raw;
  if (params.scope == RankingScope.japan) {
    raw = await _fetchJapaneseStatRanking(ref, params, category);
  } else if (params.scope == RankingScope.team) {
    raw = params.teamMode == TeamRankMode.aggregate
        ? await _fetchTeamAggregateRanking(params, category)
        : await _fetchTeamTopPlayerRanking(params, category);
  } else {
    raw = await _fetchWideStatRanking(params, category);
  }
  return _attachHandedness(raw, isPitcher: params.playerType == PlayerType.pitcher);
});

/// 選手個人の "season" または "career"（通算）成績マップを取得
Future<Map<String, dynamic>?> _fetchSeasonStatMap(int playerId, String group, {bool isCareer = false}) async {
  final url = isCareer
      ? Uri.parse('https://statsapi.mlb.com/api/v1/people/$playerId/stats?stats=career&group=$group&gameType=R')
      : Uri.parse('https://statsapi.mlb.com/api/v1/people/$playerId/stats?stats=season&group=$group&season=2026&gameType=R');
  try {
    final res = await http.get(url);
    if (res.statusCode != 200) return null;
    final data = json.decode(utf8.decode(res.bodyBytes));
    final statsList = data['stats'] as List<dynamic>? ?? [];
    for (final s in statsList) {
      final splits = s['splits'] as List<dynamic>? ?? [];
      if (splits.isNotEmpty) return splits.first['stat'] as Map<String, dynamic>?;
    }
  } catch (_) {}
  return null;
}

Future<Map<String, dynamic>?> _fetchRispStatMap(int playerId) async {
  final url = Uri.parse(
    'https://statsapi.mlb.com/api/v1/people/$playerId/stats?stats=statSplits&group=hitting&sitCodes=risp&season=2026&gameType=R',
  );
  try {
    final res = await http.get(url);
    if (res.statusCode != 200) return null;
    final data = json.decode(utf8.decode(res.bodyBytes));
    final statsList = data['stats'] as List<dynamic>? ?? [];
    for (final s in statsList) {
      final splits = s['splits'] as List<dynamic>? ?? [];
      if (splits.isNotEmpty) return splits.first['stat'] as Map<String, dynamic>?;
    }
  } catch (_) {}
  return null;
}

/// 選手の全登板ログを取得（QS/HQS集計用）
Future<List<Map<String, dynamic>>> _fetchFullGameLog(int playerId, String group) async {
  final url = Uri.parse(
    'https://statsapi.mlb.com/api/v1/people/$playerId/stats?stats=gameLog&group=$group&season=2026&gameType=R',
  );
  try {
    final res = await http.get(url);
    if (res.statusCode != 200) return [];
    final data = json.decode(utf8.decode(res.bodyBytes));
    final statsList = data['stats'] as List<dynamic>? ?? [];
    for (final s in statsList) {
      final splits = s['splits'] as List<dynamic>? ?? [];
      return splits.map((g) => (g['stat'] as Map<String, dynamic>?) ?? {}).toList();
    }
  } catch (_) {}
  return [];
}

Future<List<RankingEntry>> _fetchJapaneseStatRanking(Ref ref, RankingParams params, StatCategory category) async {
  final isPitcher = params.playerType == PlayerType.pitcher;

  // ★ 大谷選手は player.dart 上 isPitcher=false 登録だが、投手ランキングにも対象として含める
  final targets = japanesePlayers.where((p) => p.isPitcher == isPitcher || (isPitcher && p.id == 660271)).toList();

  List<MapEntry<JapanesePlayer, double>> results = [];

  await Future.wait(targets.map((p) async {
    try {
      double val;
      bool hasPlayed;

      if (category.specialType == 'qs' || category.specialType == 'qsRate' || category.specialType == 'hqs' || category.specialType == 'risp') {
        if (params.isCareer) {
          // ★ 通算版はキャリア全登板ログが必要で現実的でないため非対応
          hasPlayed = false;
          val = 0.0;
        } else if (category.specialType == 'risp') {
          final stat = await _fetchRispStatMap(p.id);
          final ab = double.tryParse(stat?['atBats']?.toString() ?? '') ?? 0.0;
          hasPlayed = ab > 0;
          val = double.tryParse(stat?['avg']?.toString() ?? '') ?? 0.0;
        } else {
          final gameLog = await _fetchFullGameLog(p.id, 'pitching');
          hasPlayed = gameLog.isNotEmpty;

          if (category.specialType == 'qs') {
            val = countQs(gameLog).toDouble();
          } else if (category.specialType == 'hqs') {
            val = countHqs(gameLog).toDouble();
          } else {
            final gs = gameLog.length.toDouble();
            final qs = countQs(gameLog).toDouble();
            val = gs > 0 ? (qs / gs * 100) : 0.0;
          }
        }
      } else {
        final stat = await _fetchSeasonStatMap(p.id, category.group, isCareer: params.isCareer);

        final volumeKey = category.group == 'pitching'
            ? 'inningsPitched'
            : (category.group == 'fielding' ? 'chances' : 'plateAppearances');
        final volume = double.tryParse(stat?[volumeKey]?.toString() ?? '') ?? 0.0;
        hasPlayed = volume > 0;
        val = double.tryParse(stat?[category.statKey]?.toString() ?? '') ?? 0.0;
      }

      // ★ 該当期間に出場実績が無い選手（例: 未登板のダルビッシュ）は除外
      if (hasPlayed) {
        results.add(MapEntry(p, val));
      }
    } catch (_) {
      // 個別選手の取得失敗はスキップ
    }
  }));

  results.sort((a, b) => category.ascending ? a.value.compareTo(b.value) : b.value.compareTo(a.value));

  return List.generate(results.length, (i) {
    final p = results[i].key;
    final val = results[i].value;
    final String displayValue;
    if (category.specialType == 'qsRate') {
      displayValue = '${val.toStringAsFixed(1)}%';
    } else if (category.isRate) {
      displayValue = _formatRateStr(val);
    } else {
      displayValue = val.toStringAsFixed(category.decimals);
    }
    return RankingEntry(
      rank: i + 1,
      name: p.nameEn,
      nameJa: p.nameJa,
      team: p.teamName,
      displayValue: displayValue,
      isJapanese: true,
      personId: p.id,
    );
  });
}

/// 正しい「全選手一括取得」エンドポイント: /api/v1/stats (playerPool省略時は既定で「規定到達選手」のみ返す)
/// ※ /teams/{id}/stats はチーム単位の"合計"しか返さず選手別の内訳が無いため使用しない
/// ※ このエンドポイントは成績順に並ばないため通算(career)には使わない（→ _fetchCareerLeaders を使用）
Future<List<Map<String, dynamic>>> _fetchQualifiedLeagueWide(String group) async {
  final url = Uri.parse('https://statsapi.mlb.com/api/v1/stats?stats=season&sportId=1&season=2026&group=$group&gameType=R&limit=3000');
  try {
    final res = await http.get(url);
    if (res.statusCode != 200) return [];
    final data = json.decode(utf8.decode(res.bodyBytes));
    final statsList = data['stats'] as List<dynamic>? ?? [];
    final List<Map<String, dynamic>> entries = [];
    for (final s in statsList) {
      final splits = s['splits'] as List<dynamic>? ?? [];
      for (final sp in splits) {
        final player = sp['player'] as Map<String, dynamic>?;
        final team = sp['team'] as Map<String, dynamic>?;
        final stat = sp['stat'] as Map<String, dynamic>?;
        if (player == null || stat == null) continue;
        entries.add({
          'personId': player['id'],
          'name': player['fullName'],
          'teamId': team?['id'],
          'stat': stat,
        });
      }
    }
    return entries;
  } catch (_) {
    return [];
  }
}

/// 指定した選手ID群について、MLB公式の「現役(active)」フラグで絞り込む。
/// 「今シーズン出場したか」ではなく、引退していない選手を正しく判定するために
/// /people エンドポイントの公式activeフラグを直接参照する（故障で長期離脱中でも
/// 引退していなければ現役として扱われる）。
/// 指定した選手ID群について「引退していないか」を判定する。
/// MLB公式の /people の active フラグは「今この瞬間 故障者リスト等に入っていないか」に近い
/// 厳しめのステータスで、離脱中の選手まで弾いてしまうため単独では使わない。
/// まず「今シーズン在籍した選手一覧」（広め、離脱中でも載る）を主軸にし、
/// そこに含まれない選手だけ念のため active フラグで拾う、の二段構えにする。
Future<Set<int>> _fetchActivePlayerIds(Iterable<int> personIds) async {
  final Set<int> result = {};

  // 1. 今シーズン在籍した選手一覧（広め）
  try {
    final url = Uri.parse('https://statsapi.mlb.com/api/v1/sports/1/players?season=2026');
    final res = await http.get(url);
    if (res.statusCode == 200) {
      final data = json.decode(utf8.decode(res.bodyBytes));
      final people = data['people'] as List<dynamic>? ?? [];
      for (final p in people) {
        final id = (p['id'] as num?)?.toInt();
        if (id != null) result.add(id);
      }
    }
  } catch (_) {
    // 失敗しても2.のフォールバックで一部は拾える
  }

  // 2. 1.に含まれない候補だけ、念のため active フラグで確認
  final remaining = personIds.toSet().difference(result).toList();
  const chunkSize = 150; // URL長すぎ防止のため分割
  for (var i = 0; i < remaining.length; i += chunkSize) {
    final end = (i + chunkSize > remaining.length) ? remaining.length : i + chunkSize;
    final chunk = remaining.sublist(i, end);
    final url = Uri.parse('https://statsapi.mlb.com/api/v1/people?personIds=${chunk.join(',')}');
    try {
      final res = await http.get(url);
      if (res.statusCode != 200) continue;
      final data = json.decode(utf8.decode(res.bodyBytes));
      final people = data['people'] as List<dynamic>? ?? [];
      for (final p in people) {
        final id = p['id'] as int?;
        if (id != null && p['active'] == true) result.add(id);
      }
    } catch (_) {
      // 一部チャンクの失敗は無視して続行
    }
  }
  return result;
}

/// 通算(career)ランキング専用：MLB公式の正式なリーダーボードAPI(/stats/leaders?statType=career)
/// を優先して使用する。実測の結果、leaderCategoryが定義されている項目は
/// 正しく成績順・資格条件込みで返ってくることを確認済み（1回の軽量リクエストで済む）。
/// leaderCategoryが無い項目（被打率(BAA)・得点圏打率など特殊項目）のみ、
/// 全選手一括取得(playerPool=All)から自前で集計するフォールバックを使う。
Future<List<Map<String, dynamic>>> _fetchCareerLeaders(StatCategory category, {int limit = 10000}) async {
  if (category.leaderCategory != null) {
    final officialResult = await _fetchCareerLeadersOfficial(category);
    if (officialResult.isNotEmpty) return officialResult;
  }
  return _fetchCareerLeadersFallback(category, limit: limit);
}

/// /stats/leaders?statType=career から通算リーダーボードを取得する。
/// 既に成績順・資格条件込みでソートされて返ってくるため、そのまま採用できる。
Future<List<Map<String, dynamic>>> _fetchCareerLeadersOfficial(StatCategory category, {int limit = 200}) async {
  final url = Uri.parse(
    'https://statsapi.mlb.com/api/v1/stats/leaders?leaderCategories=${category.leaderCategory}&statGroup=${category.group}&statType=career&sportId=1&limit=$limit',
  );
  try {
    final res = await http.get(url);
    if (res.statusCode != 200) return [];
    final data = json.decode(utf8.decode(res.bodyBytes));
    final leagueLeaders = data['leagueLeaders'] as List<dynamic>? ?? [];
    if (leagueLeaders.isEmpty) return [];
    final leaders = leagueLeaders[0]['leaders'] as List<dynamic>? ?? [];
    final List<Map<String, dynamic>> entries = [];
    for (final l in leaders) {
      final person = l['person'] as Map<String, dynamic>?;
      final team = l['team'] as Map<String, dynamic>?;
      if (person == null) continue;
      final val = double.tryParse(l['value']?.toString() ?? '');
      if (val == null) continue;
      entries.add({
        'personId': person['id'],
        'name': person['fullName'],
        'teamId': team?['id'],
        'value': val,
      });
    }
    return entries;
  } catch (_) {
    return [];
  }
}

/// フォールバック: /stats?stats=career&limit=... から全選手分を取得し、自前でソートする。
Future<List<Map<String, dynamic>>> _fetchCareerLeadersFallback(StatCategory category, {int limit = 10000}) async {
  // ★ 率系・カウント系ともにplayerPool=Allを使う（既定の規定値ロジックが
  //   通算(career)コンテキストで機能せず空になるケースがあったため）。
  //   率系は下の足切りフィルターで極端な少サンプルを除外する。
  final url = Uri.parse(
    'https://statsapi.mlb.com/api/v1/stats?stats=career&sportId=1&group=${category.group}&gameType=R&limit=$limit&playerPool=All',
  );
  try {
    final res = await http.get(url);
    if (res.statusCode != 200) return [];
    final data = json.decode(utf8.decode(res.bodyBytes));
    final statsList = data['stats'] as List<dynamic>? ?? [];
    final List<Map<String, dynamic>> entries = [];
    for (final s in statsList) {
      final splits = s['splits'] as List<dynamic>? ?? [];
      for (final sp in splits) {
        final player = sp['player'] as Map<String, dynamic>?;
        final team = sp['team'] as Map<String, dynamic>?;
        final stat = sp['stat'] as Map<String, dynamic>?;
        if (player == null || stat == null) continue;

        // ★ 率系はplayerPool=Allを使っていないため通常は規定到達者のみだが、
        //   念のため極端に少ないサンプルの選手を除外する保険を入れる
        //   (isRateは「.xxx表記かどうか」の意味なので、ERA・WHIP等の
        //   小数点表示の率系項目もdecimals > 0で拾う)
        if (category.isRate || category.decimals > 0) {
          final isPitcher = category.group == 'pitching';
          final volume = double.tryParse(
                (isPitcher ? stat['inningsPitched'] : stat['atBats'])?.toString() ?? '',
              ) ??
              0.0;
          final threshold = isPitcher ? 300.0 : 1000.0; // 通算での目安の最低ライン
          if (volume < threshold) continue;
        }

        final val = double.tryParse(stat[category.statKey]?.toString() ?? '');
        if (val == null) continue;
        entries.add({
          'personId': player['id'],
          'name': player['fullName'],
          'teamId': team?['id'],
          'value': val,
        });
      }
    }
    // 値の良い順に並べ替えておく（呼び出し元でも並べ替えるため、ここは念のため）
    entries.sort((a, b) => category.ascending
        ? (a['value'] as double).compareTo(b['value'] as double)
        : (b['value'] as double).compareTo(a['value'] as double));
    return entries;
  } catch (_) {
    return [];
  }
}

/// 今シーズン(MLB公式が「在籍」とみなす)選手のID一覧を取得する。
/// 離脱中でも今シーズン出場実績があれば含まれる広めのリスト。
/// 通算成績が存在しうる「現役選手」の候補母集団として使う。
Future<Set<int>> _fetchSeasonRosterPlayerIds() async {
  try {
    final url = Uri.parse('https://statsapi.mlb.com/api/v1/sports/1/players?season=2026');
    final res = await http.get(url);
    if (res.statusCode != 200) return {};
    final data = json.decode(utf8.decode(res.bodyBytes));
    final people = data['people'] as List<dynamic>? ?? [];
    final Set<int> result = {};
    for (final p in people) {
      final id = (p['id'] as num?)?.toInt();
      if (id != null) result.add(id);
    }
    return result;
  } catch (_) {
    return {};
  }
}

/// 指定した選手ID群について、各自の通算成績(career)を一括hydrateで取得する。
/// /people?personIds=...&hydrate=stats(...) は複数選手分の成績を1リクエストで
/// 返せるため、選手ごとに個別リクエストするより大幅に少ない回数で済む。
Future<List<Map<String, dynamic>>> _fetchCareerStatsBulk(List<int> ids, String group) async {
  if (ids.isEmpty) return [];
  final url = Uri.parse(
    'https://statsapi.mlb.com/api/v1/people?personIds=${ids.join(',')}&hydrate=stats(group=[$group],type=[career]),currentTeam',
  );
  try {
    final res = await http.get(url);
    if (res.statusCode != 200) return [];
    final data = json.decode(utf8.decode(res.bodyBytes));
    final people = data['people'] as List<dynamic>? ?? [];
    final List<Map<String, dynamic>> result = [];
    for (final p in people) {
      final personId = (p['id'] as num?)?.toInt();
      final teamId = (p['currentTeam'] as Map<String, dynamic>?)?['id'] as int?;
      final statsList = p['stats'] as List<dynamic>? ?? [];
      if (personId == null || statsList.isEmpty) continue;
      final splits = statsList[0]['splits'] as List<dynamic>? ?? [];
      if (splits.isEmpty) continue;
      final stat = splits[0]['stat'] as Map<String, dynamic>?;
      if (stat == null) continue;
      result.add({
        'personId': personId,
        'name': p['fullName'],
        'teamId': teamId,
        'stat': stat,
      });
    }
    return result;
  } catch (_) {
    return [];
  }
}

/// 「現役選手のみ」の通算ランキング：歴代ランキングを絞り込む方式だと
/// 母集団が不完全で現役選手がほぼ載らないため、先に現役選手を確定してから
/// 一人ずつ（一括hydrateで）通算成績を取得する方式にする。
Future<List<RankingEntry>> _fetchActiveCareerRanking(
  RankingParams params,
  StatCategory category,
  bool Function(int?) inLeagueScope,
) async {
  final japaneseIds = japanesePlayers.map((p) => p.id).toSet();
  final japaneseLookup = {for (final p in japanesePlayers) p.id: p.nameJa};

  final rosterIds = (await _fetchSeasonRosterPlayerIds()).toList();
  if (rosterIds.isEmpty) return [];

  const chunkSize = 150;
  final chunks = <List<int>>[];
  for (var i = 0; i < rosterIds.length; i += chunkSize) {
    final end = (i + chunkSize > rosterIds.length) ? rosterIds.length : i + chunkSize;
    chunks.add(rosterIds.sublist(i, end));
  }
  final chunkResults = await Future.wait(
    chunks.map((chunk) => _fetchCareerStatsBulk(chunk, category.group)),
  );

  final List<Map<String, dynamic>> entries = [];
  for (final list in chunkResults) {
    for (final e in list) {
      final stat = e['stat'] as Map<String, dynamic>;
      final val = double.tryParse(stat[category.statKey]?.toString() ?? '');
      if (val == null) continue;
      entries.add({...e, 'value': val, 'stat': stat});
    }
  }

  final valid = entries.where((e) {
    final teamId = e['teamId'] as int?;
    if (!inLeagueScope(teamId)) return false;
    // ★ isRateは「.xxx表記かどうか」の意味で、ERA・WHIP・OPS・K/9等の率系項目は
    //   falseのまま。少ないサンプルで極端な値が出ないよう、小数点表示の項目
    //   (decimals > 0)もあわせて最低ラインフィルターの対象にする。
    if (category.isRate || category.decimals > 0) {
      final stat = e['stat'] as Map<String, dynamic>;
      final isPitcher = category.group == 'pitching';
      final volume = double.tryParse(
            (isPitcher ? stat['inningsPitched'] : stat['atBats'])?.toString() ?? '',
          ) ??
          0.0;
      final threshold = isPitcher ? 300.0 : 1000.0; // 通算での目安の最低ライン
      if (volume < threshold) return false;
    }
    return true;
  }).toList();

  valid.sort((a, b) => category.ascending
      ? (a['value'] as double).compareTo(b['value'] as double)
      : (b['value'] as double).compareTo(a['value'] as double));
  final top = valid.take(30).toList();

  return List.generate(top.length, (i) {
    final e = top[i];
    final personId = e['personId'] as int?;
    final isJp = personId != null && japaneseIds.contains(personId);
    final val = e['value'] as double;
    return RankingEntry(
      rank: i + 1,
      name: e['name']?.toString() ?? '-',
      nameJa: isJp ? japaneseLookup[personId] : null,
      team: _teamAbbrevMap[e['teamId'] as int?] ?? '-',
      displayValue: category.isRate ? _formatRateStr(val) : val.toStringAsFixed(category.decimals),
      isJapanese: isJp,
      personId: personId,
    );
  });
}

/// QS数・QS率・HQS数のリーグ内/MLB全体ランキング。
/// 「規定投球回に達した投手」を母集団とし、一人ずつ全登板ログを取得して算出する（TOP20想定）。
Future<List<RankingEntry>> _fetchWideQsHqsRanking(
  RankingParams params,
  StatCategory category,
  bool Function(int?) inLeagueScope,
) async {
  final japaneseIds = japanesePlayers.map((p) => p.id).toSet();
  final japaneseLookup = {for (final p in japanesePlayers) p.id: p.nameJa};

  final qualifiedPitchers = await _fetchQualifiedLeagueWide('pitching');
  final targets = qualifiedPitchers.where((e) => inLeagueScope(e['teamId'] as int?)).toList();

  final results = await Future.wait(targets.map((e) async {
    final personId = e['personId'] as int?;
    if (personId == null) return null;
    final gameLog = await _fetchFullGameLog(personId, 'pitching');
    if (gameLog.isEmpty) return null;

    double val;
    if (category.specialType == 'qs') {
      val = countQs(gameLog).toDouble();
    } else if (category.specialType == 'hqs') {
      val = countHqs(gameLog).toDouble();
    } else {
      final gs = gameLog.length.toDouble();
      final qs = countQs(gameLog).toDouble();
      val = gs > 0 ? (qs / gs * 100) : 0.0;
    }

    return {
      'personId': personId,
      'name': e['name'],
      'teamId': e['teamId'],
      'value': val,
    };
  }));

  final valid = results.whereType<Map<String, dynamic>>().where((e) => (e['value'] as double) > 0).toList();
  valid.sort((a, b) => (b['value'] as double).compareTo(a['value'] as double));
  final top = valid.take(20).toList();

  return List.generate(top.length, (i) {
    final e = top[i];
    final personId = e['personId'] as int?;
    final isJp = personId != null && japaneseIds.contains(personId);
    final val = e['value'] as double;
    final displayValue = category.specialType == 'qsRate' ? '${val.toStringAsFixed(1)}%' : val.toStringAsFixed(0);
    return RankingEntry(
      rank: i + 1,
      name: e['name']?.toString() ?? '-',
      nameJa: isJp ? japaneseLookup[personId] : null,
      team: _teamAbbrevMap[e['teamId'] as int?] ?? '-',
      displayValue: displayValue,
      isJapanese: isJp,
      personId: personId,
    );
  });
}

/// 得点圏打率(RISP)のリーグ内/MLB全体ランキング。
/// QS/HQSと同じ考え方で、「規定打席数に達した打者」を母集団とし、
/// 一人ずつ得点圏成績を取得して算出する（TOP20想定）。
Future<List<RankingEntry>> _fetchWideRispRanking(
  RankingParams params,
  bool Function(int?) inLeagueScope,
) async {
  final japaneseIds = japanesePlayers.map((p) => p.id).toSet();
  final japaneseLookup = {for (final p in japanesePlayers) p.id: p.nameJa};

  final qualifiedBatters = await _fetchQualifiedLeagueWide('hitting');
  final targets = qualifiedBatters.where((e) => inLeagueScope(e['teamId'] as int?)).toList();

  final results = await Future.wait(targets.map((e) async {
    final personId = e['personId'] as int?;
    if (personId == null) return null;
    final stat = await _fetchRispStatMap(personId);
    final ab = double.tryParse(stat?['atBats']?.toString() ?? '') ?? 0.0;
    if (ab <= 0) return null;
    final avg = double.tryParse(stat?['avg']?.toString() ?? '') ?? 0.0;
    return {
      'personId': personId,
      'name': e['name'],
      'teamId': e['teamId'],
      'value': avg,
    };
  }));

  final valid = results.whereType<Map<String, dynamic>>().toList();
  valid.sort((a, b) => (b['value'] as double).compareTo(a['value'] as double));
  final top = valid.take(20).toList();

  return List.generate(top.length, (i) {
    final e = top[i];
    final personId = e['personId'] as int?;
    final isJp = personId != null && japaneseIds.contains(personId);
    final val = e['value'] as double;
    return RankingEntry(
      rank: i + 1,
      name: e['name']?.toString() ?? '-',
      nameJa: isJp ? japaneseLookup[personId] : null,
      team: _teamAbbrevMap[e['teamId'] as int?] ?? '-',
      displayValue: _formatRateStr(val),
      isJapanese: isJp,
      personId: personId,
    );
  });
}

Future<List<RankingEntry>> _fetchWideStatRanking(RankingParams params, StatCategory category) async {
  final japaneseIds = japanesePlayers.map((p) => p.id).toSet();
  final japaneseLookup = {for (final p in japanesePlayers) p.id: p.nameJa};

  bool inLeagueScope(int? teamId) {
    if (params.scope != RankingScope.league) return true;
    final side = params.leagueSide == LeagueSide.al ? 'AL' : 'NL';
    return teamId != null && _teamLeagueMap[teamId] == side;
  }

  // ★ QS数・QS率・HQS数は「規定投球回に達した投手」を母集団に、一人ずつ全登板ログを取得して算出する
  if (category.specialType == 'qs' || category.specialType == 'qsRate' || category.specialType == 'hqs') {
    return _fetchWideQsHqsRanking(params, category, inLeagueScope);
  }

  // ★ 得点圏打率(RISP)は、QS/HQSと同様に「規定打席数に達した打者」を母集団に、
  //   一人ずつ得点圏成績を取得して算出する
  if (category.specialType == 'risp') {
    return _fetchWideRispRanking(params, inLeagueScope);
  }

  // --- 通算(career)の場合 ---
  if (params.isCareer) {
    if (params.activeOnly) {
      // ★ 「現役選手のみ」は、歴代ランキングを絞り込む方式だと現役選手がほぼ載らないため、
      //   現役選手を先に決めてから一人ずつ通算成績を取得する方式にする
      return _fetchActiveCareerRanking(params, category, inLeagueScope);
    }

    // 歴代（引退選手も含む）：正式なリーダーボードAPIを使用（成績順に並んでいるため確実）
    final leaders = await _fetchCareerLeaders(category, limit: 10000);

    List<Map<String, dynamic>> filtered = leaders.where((e) {
      final teamId = e['teamId'] as int?;
      if (!inLeagueScope(teamId)) return false;
      return e['value'] != null;
    }).toList();

    filtered.sort((a, b) => category.ascending
        ? (a['value'] as double).compareTo(b['value'] as double)
        : (b['value'] as double).compareTo(a['value'] as double));
    final topLeaders = filtered.take(30).toList();

    return List.generate(topLeaders.length, (i) {
      final e = topLeaders[i];
      final personId = e['personId'] as int?;
      final isJp = personId != null && japaneseIds.contains(personId);
      final val = e['value'] as double;
      return RankingEntry(
        rank: i + 1,
        name: e['name']?.toString() ?? '-',
        nameJa: isJp ? japaneseLookup[personId] : null,
        team: _teamAbbrevMap[e['teamId'] as int?] ?? '-',
        displayValue: category.isRate ? _formatRateStr(val) : val.toStringAsFixed(category.decimals),
        isJapanese: isJp,
        personId: personId,
      );
    });
  }

  // --- 通常カテゴリ（今シーズン）：MLB公式の「規定到達選手」一括エンドポイントを使用 ---
  // playerPoolを指定しない場合、デフォルトで規定投球回・規定打席に達した選手のみが返る
  final entries = await _fetchQualifiedLeagueWide(category.group);

  List<MapEntry<Map<String, dynamic>, double>> computed = [];
  for (final e in entries) {
    final teamId = e['teamId'] as int?;
    if (!inLeagueScope(teamId)) continue;
    final stat = e['stat'] as Map<String, dynamic>;

    final raw = stat[category.statKey];
    final val = double.tryParse(raw?.toString() ?? '');
    if (val == null) continue;
    computed.add(MapEntry(e, val));
  }

  computed.sort((a, b) => category.ascending ? a.value.compareTo(b.value) : b.value.compareTo(a.value));
  final top = computed.take(30).toList();

  return List.generate(top.length, (i) {
    final e = top[i].key;
    final personId = e['personId'] as int?;
    final entryTeamId = e['teamId'] as int?;
    final isJp = personId != null && japaneseIds.contains(personId);
    final displayValue = category.isRate ? _formatRateStr(top[i].value) : top[i].value.toStringAsFixed(category.decimals);
    return RankingEntry(
      rank: i + 1,
      name: e['name']?.toString() ?? '-',
      nameJa: isJp ? japaneseLookup[personId] : null,
      team: _teamAbbrevMap[entryTeamId] ?? '-',
      displayValue: displayValue,
      isJapanese: isJp,
      personId: personId,
    );
  });
}

// ============================================================
// チームごとランキング（チーム成績 / チームTOP成績）
// ============================================================

/// 対象チームIDリストを算出（allTeams=true なら全30球団、falseならAL/NLで絞る）
List<int> _resolveTeamIds(RankingParams params) {
  if (params.allTeams) return _teamLeagueMap.keys.toList();
  final side = params.leagueSide == LeagueSide.al ? 'AL' : 'NL';
  return _teamLeagueMap.entries.where((e) => e.value == side).map((e) => e.key).toList();
}

/// チーム成績：各チームの合計値（チーム打率・チームHR数など）でランキング
Future<List<RankingEntry>> _fetchTeamAggregateRanking(RankingParams params, StatCategory category) async {
  // ★ チーム成績の「通算」は年度別データの正しい合算(特に防御率等の比率項目)が困難なため非対応
  if (params.isCareer) return [];

  final teamIds = _resolveTeamIds(params);

  final results = await Future.wait(teamIds.map((teamId) async {
    final url = Uri.parse(
      'https://statsapi.mlb.com/api/v1/teams/$teamId/stats?stats=season&group=${category.group}&season=2026&gameType=R',
    );
    try {
      final res = await http.get(url);
      if (res.statusCode != 200) return null;
      final data = json.decode(utf8.decode(res.bodyBytes));
      final statsList = data['stats'] as List<dynamic>? ?? [];
      for (final s in statsList) {
        final splits = s['splits'] as List<dynamic>? ?? [];
        for (final sp in splits) {
          final stat = sp['stat'] as Map<String, dynamic>?;
          if (stat == null) continue;
          final raw = stat[category.statKey];
          final val = double.tryParse(raw?.toString() ?? '');
          if (val == null) continue;
          return {'teamId': teamId, 'val': val};
        }
      }
      return null;
    } catch (_) {
      return null;
    }
  }));

  final valid = results.whereType<Map<String, dynamic>>().toList();
  valid.sort((a, b) => category.ascending
      ? (a['val'] as double).compareTo(b['val'] as double)
      : (b['val'] as double).compareTo(a['val'] as double));

  return List.generate(valid.length, (i) {
    final teamId = valid[i]['teamId'] as int;
    final val = valid[i]['val'] as double;
    final abbrev = _teamAbbrevMap[teamId] ?? '-';
    return RankingEntry(
      rank: i + 1,
      name: abbrev,
      team: abbrev,
      displayValue: category.isRate ? _formatRateStr(val) : val.toStringAsFixed(category.decimals),
      isJapanese: false,
    );
  });
}

/// チームTOP成績：各チームで最も良い数字を残した選手だけを抜き出し、チーム同士を比較する
Future<List<RankingEntry>> _fetchTeamTopPlayerRanking(RankingParams params, StatCategory category) async {
  if (category.specialType != 'normal') return [];

  final japaneseIds = japanesePlayers.map((p) => p.id).toSet();
  final japaneseLookup = {for (final p in japanesePlayers) p.id: p.nameJa};
  final validTeamIds = _resolveTeamIds(params).toSet();

  if (params.isCareer) {
    // ★ 通算：正式なリーダーボード(既に成績順)から、チームごとに最初に出てきた選手＝そのチームのトップ選手を採用
    final leaders = await _fetchCareerLeaders(category, limit: 10000);
    final activeIds = params.activeOnly
        ? await _fetchActivePlayerIds(leaders.map((e) => e['personId'] as int?).whereType<int>())
        : null;

    final Map<int, Map<String, dynamic>> bestByTeam = {};
    for (final e in leaders) {
      final teamId = e['teamId'] as int?;
      if (teamId == null || !validTeamIds.contains(teamId)) continue;
      if (activeIds != null && !activeIds.contains(e['personId'] as int?)) continue;
      if (e['value'] == null) continue;
      bestByTeam.putIfAbsent(teamId, () => e); // 既に成績順なので最初の1件がそのチームの最上位
    }

    final list = bestByTeam.values.toList();
    list.sort((a, b) => category.ascending
        ? (a['value'] as double).compareTo(b['value'] as double)
        : (b['value'] as double).compareTo(a['value'] as double));

    return List.generate(list.length, (i) {
      final e = list[i];
      final personId = e['personId'] as int?;
      final teamId = e['teamId'] as int?;
      final isJp = personId != null && japaneseIds.contains(personId);
      final val = e['value'] as double;
      return RankingEntry(
        rank: i + 1,
        name: e['name']?.toString() ?? '-',
        nameJa: isJp ? japaneseLookup[personId] : null,
        team: _teamAbbrevMap[teamId] ?? '-',
        displayValue: category.isRate ? _formatRateStr(val) : val.toStringAsFixed(category.decimals),
        isJapanese: isJp,
        personId: personId,
      );
    });
  }

  final entries = await _fetchQualifiedLeagueWide(category.group);

  final Map<int, Map<String, dynamic>> bestByTeam = {};
  for (final e in entries) {
    final teamId = e['teamId'] as int?;
    if (teamId == null || !validTeamIds.contains(teamId)) continue;
    final stat = e['stat'] as Map<String, dynamic>;
    final raw = stat[category.statKey];
    final val = double.tryParse(raw?.toString() ?? '');
    if (val == null) continue;

    final current = bestByTeam[teamId];
    if (current == null) {
      bestByTeam[teamId] = {...e, 'val': val};
    } else {
      final currentVal = current['val'] as double;
      final better = category.ascending ? val < currentVal : val > currentVal;
      if (better) bestByTeam[teamId] = {...e, 'val': val};
    }
  }

  final list = bestByTeam.values.toList();
  list.sort((a, b) => category.ascending
      ? (a['val'] as double).compareTo(b['val'] as double)
      : (b['val'] as double).compareTo(a['val'] as double));

  return List.generate(list.length, (i) {
    final e = list[i];
    final personId = e['personId'] as int?;
    final teamId = e['teamId'] as int?;
    final isJp = personId != null && japaneseIds.contains(personId);
    final val = e['val'] as double;
    return RankingEntry(
      rank: i + 1,
      name: e['name']?.toString() ?? '-',
      nameJa: isJp ? japaneseLookup[personId] : null,
      team: _teamAbbrevMap[teamId] ?? '-',
      displayValue: category.isRate ? _formatRateStr(val) : val.toStringAsFixed(category.decimals),
      isJapanese: isJp,
      personId: personId,
    );
  });
}

/// personId を持つエントリに対して、MLB公式 people API から利き打席／投球腕を一括取得して付与する
Future<List<RankingEntry>> _attachHandedness(List<RankingEntry> entries, {required bool isPitcher}) async {
  final ids = entries.map((e) => e.personId).whereType<int>().toSet().toList();
  if (ids.isEmpty) return entries;

  try {
    final url = Uri.parse('https://statsapi.mlb.com/api/v1/people?personIds=${ids.join(',')}');
    final res = await http.get(url);
    if (res.statusCode != 200) return entries;
    final data = json.decode(utf8.decode(res.bodyBytes));
    final people = data['people'] as List<dynamic>? ?? [];

    final handMap = <int, String>{};
    for (final p in people) {
      final id = p['id'] as int?;
      if (id == null) continue;
      String? code;
      if (isPitcher) {
        code = p['pitchHand']?['code'];
      } else {
        code = p['batSide']?['code'];
      }
      if (code != null) handMap[id] = code.toString();
    }

    return entries.map((e) {
      if (e.personId == null) return e;
      return e.copyWithHand(handMap[e.personId]);
    }).toList();
  } catch (_) {
    return entries;
  }
}

// ============================================================
// 総合WARランキング（投手・打者の区別をせず、二刀流は合算値で評価）
// ============================================================

final totalWarRankingProvider = FutureProvider.family<List<RankingEntry>, TotalWarParams>((ref, params) async {
  final data = await _fetchWarJson();
  if (data == null) return [];

  if (params.scope == RankingScope.japan) {
    final playersMap = data['players'] as Map<String, dynamic>? ?? {};
    List<MapEntry<JapanesePlayer, double>> list = [];

    for (final p in japanesePlayers) {
      final entry = playersMap[p.id.toString()] as Map<String, dynamic>?;
      if (entry == null) continue;
      final total = ((entry['rwar'] as num?)?.toDouble() ?? 0.0) + ((entry['rwar_pitch'] as num?)?.toDouble() ?? 0.0);
      list.add(MapEntry(p, total));
    }
    list.sort((a, b) => b.value.compareTo(a.value));

    return List.generate(list.length, (i) {
      final p = list[i].key;
      return RankingEntry(
        rank: i + 1,
        name: p.nameEn,
        nameJa: p.nameJa,
        team: p.teamName,
        displayValue: list[i].value.toStringAsFixed(1),
        isJapanese: true,
      );
    });
  }

  final leaders = data['war_leaders'] as Map<String, dynamic>? ?? {};
  final batters = leaders['batters'] as Map<String, dynamic>? ?? {};
  final pitchers = leaders['pitchers'] as Map<String, dynamic>? ?? {};

  final key = params.scope == RankingScope.mlb
      ? 'mlb_top'
      : (params.leagueSide == LeagueSide.al ? 'al_top' : 'nl_top');

  final batterList = (batters[key] as List<dynamic>? ?? []);
  final pitcherList = (pitchers[key] as List<dynamic>? ?? []);
  final merged = [...batterList, ...pitcherList];

  final Map<String, Map<String, dynamic>> combinedByName = {};
  for (final item in merged) {
    final m = item as Map<String, dynamic>;
    final name = m['name']?.toString() ?? '';
    final war = (m['war'] as num?)?.toDouble() ?? 0.0;
    if (combinedByName.containsKey(name)) {
      final existing = combinedByName[name]!;
      final existingWar = (existing['war'] as num?)?.toDouble() ?? 0.0;
      combinedByName[name] = {...existing, 'war': existingWar + war};
    } else {
      combinedByName[name] = Map<String, dynamic>.from(m);
    }
  }

  final combinedList = combinedByName.values.toList();
  combinedList.sort((a, b) => (b['war'] as num).compareTo(a['war'] as num));
  final top30 = combinedList.take(30).toList();

  return List.generate(top30.length, (i) {
    final e = top30[i];
    return RankingEntry(
      rank: i + 1,
      name: e['name']?.toString() ?? '-',
      nameJa: e['name_ja']?.toString(),
      team: e['team']?.toString() ?? '-',
      displayValue: (e['war'] as num?)?.toStringAsFixed(1) ?? '-',
      isJapanese: e['name_ja'] != null,
    );
  });
});

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