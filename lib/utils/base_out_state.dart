// lib/utils/base_out_state.dart
//
// 各打席が「何死・走者どこ」の状況で始まったかを算出するヘルパー。
// MLB公式APIの各play（打席）には、その打席が"終わった後"の走者情報
// （matchup.postOnFirst/postOnSecond/postOnThird）しか含まれていないため、
// 同じ半イニング内の直前のplayの「終了後」の状態を、この打席が
// "始まった時点の状況"として利用する（半イニングが変わったらリセット）。

/// allPlaysを渡すと、atBatIndexをキーに「1死1・2塁」のような
/// 打席開始時点の状況を表す文字列のマップを返す。
Map<int, String> computeBaseOutStates(List<dynamic> allPlays) {
  final Map<int, String> result = {};
  int outsInHalfInning = 0;
  int? trackedInning;
  bool? trackedIsTop;
  bool onFirst = false;
  bool onSecond = false;
  bool onThird = false;

  for (final play in allPlays) {
    final inning = play['about']?['inning'] as int?;
    final isTop = play['about']?['isTopInning'] == true;
    if (inning != trackedInning || isTop != trackedIsTop) {
      outsInHalfInning = 0;
      onFirst = false;
      onSecond = false;
      onThird = false;
      trackedInning = inning;
      trackedIsTop = isTop;
    }

    final atBatIndex = play['about']?['atBatIndex'] as int?;
    if (atBatIndex != null) {
      result[atBatIndex] = _formatBaseOutState(outsInHalfInning, onFirst, onSecond, onThird);
    }

    // このplayの結果を反映し、次のplayの「開始時点」の状態として使う
    final outsAfter = (play['count']?['outs'] as num?)?.toInt() ?? outsInHalfInning;
    outsInHalfInning = outsAfter.clamp(0, 3);

    final matchup = play['matchup'] as Map<String, dynamic>?;
    onFirst = matchup?['postOnFirst'] != null;
    onSecond = matchup?['postOnSecond'] != null;
    onThird = matchup?['postOnThird'] != null;
  }

  return result;
}

String _formatBaseOutState(int outs, bool onFirst, bool onSecond, bool onThird) {
  final outsText = outs <= 0 ? '無死' : '$outs死';
  if (onFirst && onSecond && onThird) return '$outsText満塁';
  final parts = <String>[];
  if (onFirst) parts.add('1');
  if (onSecond) parts.add('2');
  if (onThird) parts.add('3');
  if (parts.isEmpty) return '$outsText走者なし';
  return '$outsText${parts.join('・')}塁';
}
