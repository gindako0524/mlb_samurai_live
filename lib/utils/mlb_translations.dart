// lib/utils/mlb_translations.dart
//
// MLB公式APIが返す英語の定型文字列（打席結果種別・球種・投球コール）を、
// 日本語表示モード用に変換するための辞書とヘルパー関数。
// ★ play['result']['description'] のような自由文の完全な文法翻訳は行わない
//   （選手名・守備位置などが不規則に混在し辞書では対応しきれないため）。
//   代わりに、有限個の値しか取らない event / type / call フィールドを
//   辞書で変換し、日本語モードではそちらを短い結果表示として使う。

import '../services/language_provider.dart';

const Map<String, String> _eventJa = {
  'Single': '単打',
  'Double': '二塁打',
  'Triple': '三塁打',
  'Home Run': '本塁打',
  'Walk': '四球',
  'Intent Walk': '敬遠',
  'Strikeout': '三振',
  'Strikeout Double Play': '三振併殺',
  'Groundout': 'ゴロアウト',
  'Grounded Into DP': '併殺打',
  'Flyout': 'フライアウト',
  'Lineout': 'ライナーアウト',
  'Pop Out': 'ポップアウト',
  'Sac Fly': '犠飛',
  'Sac Fly Double Play': '犠飛併殺',
  'Sac Bunt': '犠打',
  'Sac Bunt Double Play': '犠打併殺',
  'Field Error': '失策',
  'Fielders Choice': '野手選択',
  'Fielders Choice Out': '野手選択アウト',
  'Double Play': '併殺打',
  'Triple Play': '三重殺',
  'Hit By Pitch': '死球',
  'Catcher Interference': '捕手妨害',
  'Batter Interference': '打者妨害',
  'Fan interference': '観客妨害',
  'Wild Pitch': '暴投',
  'Passed Ball': '捕逸',
  'Balk': 'ボーク',
  'Stolen Base 2B': '盗塁 (二塁)',
  'Stolen Base 3B': '盗塁 (三塁)',
  'Stolen Base Home': '本盗',
  'Caught Stealing 2B': '盗塁死 (二塁)',
  'Caught Stealing 3B': '盗塁死 (三塁)',
  'Caught Stealing Home': '本盗死',
  'Pickoff 1B': '牽制アウト (一塁)',
  'Pickoff 2B': '牽制アウト (二塁)',
  'Pickoff 3B': '牽制アウト (三塁)',
  'Pickoff Caught Stealing 2B': '牽制盗塁死 (二塁)',
  'Pickoff Caught Stealing 3B': '牽制盗塁死 (三塁)',
  'Runner Out': '走塁死',
  'Forced Balk': 'ボーク',
};

const Map<String, String> _pitchTypeJa = {
  'Four-Seam Fastball': 'フォーシーム',
  'Two-Seam Fastball': 'ツーシーム',
  'Sinker': 'シンカー',
  'Cutter': 'カットボール',
  'Slider': 'スライダー',
  'Sweeper': 'スイーパー',
  'Slurve': 'スラーブ',
  'Curveball': 'カーブ',
  'Knuckle Curve': 'ナックルカーブ',
  'Changeup': 'チェンジアップ',
  'Splitter': 'スプリット',
  'Split-Finger': 'スプリット',
  'Forkball': 'フォークボール',
  'Screwball': 'スクリューボール',
  'Knuckleball': 'ナックルボール',
  'Eephus': 'イーファス',
  'Fastball': '速球',
  'Pitch Out': 'ピッチアウト',
  'Intentional Ball': '意図的ボール',
};

const Map<String, String> _callJa = {
  'Ball': 'ボール',
  'Ball In Dirt': 'ワンバウンド',
  'Called Strike': '見逃し',
  'Swinging Strike': '空振り',
  'Swinging Strike (Blocked)': '空振り (後逸)',
  'Foul': 'ファウル',
  'Foul Tip': 'ファウルチップ',
  'Foul Bunt': 'バントファウル',
  'Missed Bunt': 'バント空振り',
  'Bunt Groundout': 'バントゴロ',
  'Hit By Pitch': '死球',
  'In play, out(s)': 'インプレー (アウト)',
  'In play, no out': 'インプレー',
  'In play, run(s)': 'インプレー (得点)',
  'Pitchout': 'ピッチアウト',
  'Automatic Ball': '自動ボール',
  'Automatic Strike': '自動ストライク',
};

/// 打席結果種別(event)の翻訳。日本語モードで辞書に無い値はそのまま返す。
String translateEvent(String? event, AppLanguage lang) {
  if (event == null || event.isEmpty) {
    return lang == AppLanguage.ja ? '打席完了' : 'Play complete';
  }
  if (lang == AppLanguage.en) return event;
  return _eventJa[event] ?? event;
}

/// 球種(pitch type)の翻訳。
String translatePitchType(String? type, AppLanguage lang) {
  if (type == null || type.isEmpty) {
    return lang == AppLanguage.ja ? '球種不明' : 'Unknown pitch';
  }
  if (lang == AppLanguage.en) return type;
  return _pitchTypeJa[type] ?? type;
}

/// 投球コール(ボール/ストライク等)の翻訳。
String translateCall(String? call, AppLanguage lang) {
  if (call == null || call.isEmpty) return '';
  if (lang == AppLanguage.en) return call;
  return _callJa[call] ?? call;
}

/// イニング表/裏の翻訳。
String translateHalf(bool isTopInning, AppLanguage lang) {
  if (lang == AppLanguage.en) return isTopInning ? 'Top' : 'Bot';
  return isTopInning ? '表' : '裏';
}

const Map<String, String> _positionJa = {
  'P': '投',
  'C': '捕',
  '1B': '一',
  '2B': '二',
  '3B': '三',
  'SS': '遊',
  'LF': '左',
  'CF': '中',
  'RF': '右',
  'DH': '指',
  'PH': '代打',
  'PR': '代走',
  'IF': '内',
  'OF': '外',
};

/// 守備位置の翻訳（ボックススコア表示用）。
String translatePosition(String? abbr, AppLanguage lang) {
  if (abbr == null || abbr.isEmpty) return '-';
  if (lang == AppLanguage.en) return abbr;
  return _positionJa[abbr] ?? abbr;
}

/// 打者の1試合成績を「◯打数◯安打」形式で組み立てる（アプリ内の他画面と統一した表記）。
/// MLB公式が生成する`summary`文字列は値が0の項目を省略することがあり不安定なため、
/// 生の統計値から毎回組み立て直す。
String formatBattingLine(Map<String, dynamic> stat, AppLanguage lang) {
  final ab = (stat['atBats'] as num?)?.toInt() ?? 0;
  final hits = (stat['hits'] as num?)?.toInt() ?? 0;
  final bb = (stat['baseOnBalls'] as num?)?.toInt() ?? 0;
  final so = (stat['strikeOuts'] as num?)?.toInt() ?? 0;
  final hr = (stat['homeRuns'] as num?)?.toInt() ?? 0;
  final rbi = (stat['rbi'] as num?)?.toInt() ?? 0;

  if (lang == AppLanguage.en) {
    final parts = <String>['$ab AB', '$hits H'];
    if (hr > 0) parts.add('$hr HR');
    if (rbi > 0) parts.add('$rbi RBI');
    if (bb > 0) parts.add('$bb BB');
    if (so > 0) parts.add('$so K');
    return parts.join(', ');
  }
  final parts = <String>['$ab打数$hits安打'];
  if (hr > 0) parts.add('$hr本塁打');
  if (rbi > 0) parts.add('$rbi打点');
  if (bb > 0) parts.add('$bb四球');
  if (so > 0) parts.add('$so三振');
  return parts.join(' ');
}

/// 投手の1試合成績を組み立てる（自責点は0でも必ず表示する）。
/// MLB公式の`summary`文字列は自責点が0の場合に項目自体を省略することがあり、
/// 「ERが表示されない選手がいる」不具合の原因だったため、生の統計値から組み立て直す。
String formatPitchingLine(Map<String, dynamic> stat, AppLanguage lang) {
  final ip = stat['inningsPitched']?.toString() ?? '0.0';
  final h = (stat['hits'] as num?)?.toInt() ?? 0;
  final er = (stat['earnedRuns'] as num?)?.toInt() ?? 0;
  final so = (stat['strikeOuts'] as num?)?.toInt() ?? 0;
  final bb = (stat['baseOnBalls'] as num?)?.toInt() ?? 0;

  if (lang == AppLanguage.en) {
    return '$ip IP, $h H, $er ER, $so K, $bb BB';
  }
  return '$ip回 $h安打 $er自責点 $so奪三振 $bb四球';
}

/// 打席・対戦結果の表示用文字列。
/// 英語モード: MLB公式の詳細な英文description をそのまま表示（情報量最大）。
/// 日本語モード: 自由文の翻訳はせず、有限個の値である event を辞書変換した
///   短い結果表示にする（誰が・どこに、等の詳細は省略されるが正確性を優先）。
String translateAtBatResult(String? description, String? event, AppLanguage lang) {
  if (lang == AppLanguage.en) {
    return description ?? event ?? 'In play';
  }
  return translateEvent(event, lang);
}
