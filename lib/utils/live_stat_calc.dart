// lib/utils/live_stat_calc.dart
//
// 「今シーズンの成績」に「進行中の試合でのここまでの成績」を合算し、
// 打率・OPS・防御率をその場で再計算するためのヘルパー。
//
// ★ 重要：MLB公式APIの「シーズン成績」(stats=season)は、試合終了後にしか
//   更新されないと思われがちだが、実際には進行中の試合でも取得時点までの
//   今日の分がすでに反映されている（実測で確認済み。例：ある投手の
//   試合前ERAが1.73だったのに対し、試合中に取得した「シーズン成績」は
//   既に今日の分を含んだ1.97になっていた）。
//   そのため、取得した「シーズン成績」をそのまま「試合開始前の基準値」として
//   扱い、そこにライブ試合の成績をさらに加算すると、今日の分が二重に
//   カウントされてしまう。これを防ぐため、baseline取得時に「その時点までの
//   今日の試合の成績」をboxscoreから引き算し、真の「試合開始前」の値に
//   補正してから使う（subtractPitchingStat/subtractBattingStat）。

/// 投球回文字列（"5.2"のような、小数部が2/3表記のMLB独自形式）をアウト数に変換する。
/// 小数部 .0=0アウト .1=1アウト .2=2アウト（3アウトで1イニング）
int inningsPitchedToOuts(dynamic ip) {
  if (ip == null) return 0;
  final s = ip.toString();
  final parts = s.split('.');
  final whole = int.tryParse(parts[0]) ?? 0;
  final frac = parts.length > 1 ? (int.tryParse(parts[1]) ?? 0) : 0;
  return whole * 3 + frac.clamp(0, 2);
}

/// アウト数を投球回文字列（"5.2"形式）に戻す。
String outsToInningsPitched(int outs) {
  final whole = outs ~/ 3;
  final frac = outs % 3;
  return '$whole.$frac';
}

/// 打率・出塁率・長打率・OPSの計算に使う「合算済みの生数値」をまとめて保持する入れ物。
class _CombinedBattingTotals {
  final int atBats;
  final int hits;
  final int baseOnBalls;
  final int hitByPitch;
  final int sacFlies;
  final int totalBases;

  const _CombinedBattingTotals({
    required this.atBats,
    required this.hits,
    required this.baseOnBalls,
    required this.hitByPitch,
    required this.sacFlies,
    required this.totalBases,
  });
}

int _toInt(dynamic v) => (v as num?)?.toInt() ?? int.tryParse(v?.toString() ?? '') ?? 0;

_CombinedBattingTotals _combineBattingTotals(Map<String, dynamic>? season, Map<String, dynamic>? game) {
  int sum(String key) => _toInt(season?[key]) + _toInt(game?[key]);
  return _CombinedBattingTotals(
    atBats: sum('atBats'),
    hits: sum('hits'),
    baseOnBalls: sum('baseOnBalls'),
    hitByPitch: sum('hitByPitch'),
    sacFlies: sum('sacFlies'),
    totalBases: sum('totalBases'),
  );
}

/// シーズン成績(試合開始前) + 進行中の試合のboxscore成績を合算し、
/// 「この試合を含めた最新の打率」を計算する。打数が無ければnull。
double? computeLiveAvg(Map<String, dynamic>? season, Map<String, dynamic>? game) {
  final t = _combineBattingTotals(season, game);
  if (t.atBats <= 0) return null;
  return t.hits / t.atBats;
}

/// シーズン成績 + 進行中の試合を合算した「この試合を含めた最新のOPS（出塁率＋長打率）」。
double? computeLiveOps(Map<String, dynamic>? season, Map<String, dynamic>? game) {
  final t = _combineBattingTotals(season, game);
  final obpDenom = t.atBats + t.baseOnBalls + t.hitByPitch + t.sacFlies;
  if (obpDenom <= 0 || t.atBats <= 0) return null;
  final obp = (t.hits + t.baseOnBalls + t.hitByPitch) / obpDenom;
  final slg = t.totalBases / t.atBats;
  return obp + slg;
}

/// シーズン成績 + 進行中の試合を合算した「この試合を含めた最新の防御率」。
/// 投球回が0（未登板）ならnull。
double? computeLiveEra(Map<String, dynamic>? season, Map<String, dynamic>? game) {
  final seasonOuts = inningsPitchedToOuts(season?['inningsPitched']);
  final gameOuts = inningsPitchedToOuts(game?['inningsPitched']);
  final totalOuts = seasonOuts + gameOuts;
  if (totalOuts <= 0) return null;
  final earnedRuns = _toInt(season?['earnedRuns']) + _toInt(game?['earnedRuns']);
  final totalInnings = totalOuts / 3.0;
  return (earnedRuns * 9.0) / totalInnings;
}

String formatAvg(double? v) {
  if (v == null) return '-';
  if (v >= 1.0) return v.toStringAsFixed(3);
  return '.${(v * 1000).round().toString().padLeft(3, '0')}';
}

String formatOps(double? v) {
  if (v == null) return '-';
  return v.toStringAsFixed(3);
}

String formatEra(double? v) {
  if (v == null) return '-';
  return v.toStringAsFixed(2);
}

/// 試合中に取得した「シーズン成績」から、その時点までの「今日の試合」の
/// 分を引き算し、真の「試合開始前」のシーズン成績を復元する（打者用）。
Map<String, dynamic> subtractBattingStat(Map<String, dynamic>? seasonSoFar, Map<String, dynamic>? gameSoFar) {
  int sub(String key) => (_toInt(seasonSoFar?[key]) - _toInt(gameSoFar?[key])).clamp(0, 1 << 30);
  return {
    'atBats': sub('atBats'),
    'hits': sub('hits'),
    'baseOnBalls': sub('baseOnBalls'),
    'hitByPitch': sub('hitByPitch'),
    'sacFlies': sub('sacFlies'),
    'totalBases': sub('totalBases'),
  };
}

/// 試合中に取得した「シーズン成績」から、その時点までの「今日の試合」の
/// 分を引き算し、真の「試合開始前」のシーズン成績を復元する（投手用）。
Map<String, dynamic> subtractPitchingStat(Map<String, dynamic>? seasonSoFar, Map<String, dynamic>? gameSoFar) {
  final seasonOuts = inningsPitchedToOuts(seasonSoFar?['inningsPitched']);
  final gameOuts = inningsPitchedToOuts(gameSoFar?['inningsPitched']);
  final outs = (seasonOuts - gameOuts).clamp(0, 1 << 30);
  final earnedRuns = (_toInt(seasonSoFar?['earnedRuns']) - _toInt(gameSoFar?['earnedRuns'])).clamp(0, 1 << 30);
  return {
    'inningsPitched': outsToInningsPitched(outs),
    'earnedRuns': earnedRuns,
  };
}

// ============================================================
// 「その時点までの」試合内成績を時系列で積み上げるためのヘルパー。
// boxscoreの現在の合計値をそのまま使うと、過去のプレイにも試合終了時点の
// 最新の数字が表示されてしまい「失点する前なのに既に悪化した防御率が
// 出ている」ようなズレが生じる。プレイを時系列順に1つずつ処理しながら、
// 投手・打者ごとに「その打席が終わった直後」の状態を積み上げて記録する。
// ============================================================

/// 1打席の結果を、打率計算に必要な増分（打数・安打・四球・死球・犠飛・塁打）に分類する。
class PlateAppearanceDelta {
  final int atBats;
  final int hits;
  final int baseOnBalls;
  final int hitByPitch;
  final int sacFlies;
  final int totalBases;

  const PlateAppearanceDelta({
    this.atBats = 0,
    this.hits = 0,
    this.baseOnBalls = 0,
    this.hitByPitch = 0,
    this.sacFlies = 0,
    this.totalBases = 0,
  });
}

const Map<String, PlateAppearanceDelta> _plateAppearanceByEvent = {
  'Single': PlateAppearanceDelta(atBats: 1, hits: 1, totalBases: 1),
  'Double': PlateAppearanceDelta(atBats: 1, hits: 1, totalBases: 2),
  'Triple': PlateAppearanceDelta(atBats: 1, hits: 1, totalBases: 3),
  'Home Run': PlateAppearanceDelta(atBats: 1, hits: 1, totalBases: 4),
  'Walk': PlateAppearanceDelta(baseOnBalls: 1),
  'Intent Walk': PlateAppearanceDelta(baseOnBalls: 1),
  'Hit By Pitch': PlateAppearanceDelta(hitByPitch: 1),
  'Sac Fly': PlateAppearanceDelta(sacFlies: 1),
  'Sac Fly Double Play': PlateAppearanceDelta(sacFlies: 1),
  'Sac Bunt': PlateAppearanceDelta(),
  'Sac Bunt Double Play': PlateAppearanceDelta(),
  'Catcher Interference': PlateAppearanceDelta(),
  'Batter Interference': PlateAppearanceDelta(),
};

/// event（打席結果種別）を打数などの増分に変換する。
/// 上記の辞書に無いイベント（三振・ゴロアウト・フライアウト・併殺打など、
/// 出塁しない一般的なアウト）は「打数1・安打0」として扱う。
PlateAppearanceDelta classifyPlateAppearance(String? event) {
  if (event == null || event.isEmpty) return const PlateAppearanceDelta();
  return _plateAppearanceByEvent[event] ?? const PlateAppearanceDelta(atBats: 1);
}

/// 打者1人分の「試合内でのここまでの累積成績」を保持するミュータブルな入れ物。
class RunningBatterState {
  int atBats = 0;
  int hits = 0;
  int baseOnBalls = 0;
  int hitByPitch = 0;
  int sacFlies = 0;
  int totalBases = 0;

  void apply(PlateAppearanceDelta d) {
    atBats += d.atBats;
    hits += d.hits;
    baseOnBalls += d.baseOnBalls;
    hitByPitch += d.hitByPitch;
    sacFlies += d.sacFlies;
    totalBases += d.totalBases;
  }

  Map<String, dynamic> toStatMap() => {
        'atBats': atBats,
        'hits': hits,
        'baseOnBalls': baseOnBalls,
        'hitByPitch': hitByPitch,
        'sacFlies': sacFlies,
        'totalBases': totalBases,
      };
}

/// 投手1人分の「試合内でのここまでの累積成績」を保持するミュータブルな入れ物。
class RunningPitcherState {
  int outs = 0;
  int earnedRuns = 0;

  Map<String, dynamic> toStatMap() => {
        'inningsPitched': outsToInningsPitched(outs),
        'earnedRuns': earnedRuns,
      };
}

/// 1プレイ（1打席）の中で記録された自責点の数を数える。
/// runners[].details.isScoringEvent（得点したか）と .earned（自責点か）を見る。
int countEarnedRunsInPlay(Map<String, dynamic> play) {
  final runners = play['runners'] as List<dynamic>? ?? [];
  int count = 0;
  for (final r in runners) {
    final details = (r as Map<String, dynamic>?)?['details'] as Map<String, dynamic>?;
    if (details == null) continue;
    if (details['isScoringEvent'] == true && details['earned'] == true) count++;
  }
  return count;
}

/// 1プレイ（1打席）の中で記録された「自責点かどうかを問わない」総失点数を数える。
/// エラーが絡んだ非自責点も含めた「失点」を把握するために使う。
int countRunsInPlay(Map<String, dynamic> play) {
  final runners = play['runners'] as List<dynamic>? ?? [];
  int count = 0;
  for (final r in runners) {
    final details = (r as Map<String, dynamic>?)?['details'] as Map<String, dynamic>?;
    if (details == null) continue;
    if (details['isScoringEvent'] == true) count++;
  }
  return count;
}
