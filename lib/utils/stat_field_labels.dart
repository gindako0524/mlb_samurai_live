// lib/utils/stat_field_labels.dart
//
// MLB公式APIが返す生の成績フィールド名（英語のcamelCase）を、
// 「全成績を項目名付きでそのまま一覧表示する」画面向けに日本語ラベルへ変換する。
// 辞書に無いキーは _humanize() でそれっぽい表記に変換して表示する
// （＝どんなフィールドが来ても必ず何かしらの読める形で表示できるようにする）。

const Map<String, String> statFieldLabels = {
  // 共通
  'gamesPlayed': '出場試合数',
  'plateAppearances': '打席数',
  // 打撃
  'atBats': '打数',
  'hits': '安打',
  'doubles': '二塁打',
  'triples': '三塁打',
  'homeRuns': '本塁打',
  'rbi': '打点',
  'runs': '得点',
  'baseOnBalls': '四球',
  'intentionalWalks': '故意四球',
  'strikeOuts': '三振',
  'stolenBases': '盗塁',
  'stolenBasePercentage': '盗塁成功率',
  'caughtStealing': '盗塁死',
  'caughtStealingPercentage': '盗塁死率',
  'hitByPitch': '死球',
  'sacBunts': '犠打',
  'sacFlies': '犠飛',
  'groundIntoDoublePlay': '併殺打',
  'groundIntoTriplePlay': '併殺（三重）',
  'totalBases': '塁打数',
  'leftOnBase': '残塁数',
  'numberOfPitches': '対戦投球数',
  'avg': '打率',
  'obp': '出塁率',
  'slg': '長打率',
  'ops': 'OPS',
  'babip': 'BABIP',
  'atBatsPerHomeRun': '本塁打あたり打数',
  'groundOutsToAirouts': 'ゴロ/フライ比',
  'groundOuts': 'ゴロアウト',
  'airOuts': 'フライアウト',
  'catchersInterference': '捕手妨害',
  // 投手
  'wins': '勝利',
  'losses': '敗戦',
  'winPercentage': '勝率',
  'era': '防御率',
  'inningsPitched': '投球回',
  'earnedRuns': '自責点',
  'gamesStarted': '先発試合数',
  'gamesFinished': '試合終了',
  'completeGames': '完投',
  'shutouts': '完封',
  'saves': 'セーブ',
  'saveOpportunities': 'セーブ機会',
  'holds': 'ホールド',
  'blownSaves': 'セーブ失敗',
  'battersFaced': '対戦打者数',
  'outs': 'アウト数',
  'hitBatsmen': '与死球',
  'wildPitches': '暴投',
  'balks': 'ボーク',
  'whip': 'WHIP',
  'strikeoutsPer9Inn': '9イニングあたり奪三振',
  'walksPer9Inn': '9イニングあたり与四球',
  'hitsPer9Inn': '9イニングあたり被安打',
  'runsScoredPer9': '9イニングあたり失点',
  'homeRunsPer9': '9イニングあたり被本塁打',
  'strikeoutWalkRatio': '奪三振/与四球比',
  'pitchesPerInning': '1イニングあたり投球数',
  'strikePercentage': 'ストライク率',
  'winPercentageAgainst': '被勝率',
  'stolenBasePercentageAgainst': '被盗塁成功率',
  'runsScoredPer9Inn': '9イニングあたり失点',
  'inheritedRunners': '引き継ぎ走者',
  'inheritedRunnersScored': '引き継ぎ走者の生還数',
  'sacBuntsAgainst': '被犠打',
  'sacFliesAgainst': '被犠飛',
  'passedBall': '捕逸',
};

/// キャメルケースのキーを、辞書に無い場合の簡易的な人間可読表記に変換する
/// （例: "leftOnBase" -> "Left On Base"）。
String _humanize(String key) {
  final withSpaces = key.replaceAllMapped(RegExp(r'([a-z0-9])([A-Z])'), (m) => '${m[1]} ${m[2]}');
  final words = withSpaces.split(' ');
  return words.map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}').join(' ');
}

/// 生の成績フィールド名を表示用ラベルに変換する。辞書に無ければ簡易変換した英語表記を返す。
String formatStatFieldLabel(String key) => statFieldLabels[key] ?? _humanize(key);
