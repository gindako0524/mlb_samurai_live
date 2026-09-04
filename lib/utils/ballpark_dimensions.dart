// lib/utils/ballpark_dimensions.dart
//
// 「もし他球場だったらホームランになっていたか」判定のための、MLB全30球場の
// 外野フェンスまでの距離(簡易版)。
//
// ★ MLB公式APIには球場の詳細な形状データ(壁の高さ・角度ごとの正確な距離)は
//   存在しないため、公開されている一般的な球場データ(両翼・中堅の3点)を
//   もとに手動でまとめたもの。左中間・右中間のような詳細な多角形データは
//   自由に使えるソースが無いため、両翼(-45°/+45°)と中堅(0°)の3点を
//   直線的に補間する簡易モデルで距離を推定している。
//
// ★ このモデルの既知の限界:
//   1) 壁の「高さ」は考慮していない(距離だけで判定)。そのためフェンウェイの
//      グリーンモンスター(高さ約11m)のように、距離的には届いていても実際は
//      高い壁に阻まれるケースを区別できない。
//   2) 左中間・右中間は3点の直線補間のため、実際の(曲線的な)フェンス形状より
//      やや短めに出る可能性がある。
//   あくまで「目安」であることをUI上で明示すること。

class BallparkProfile {
  final String teamAbbr;
  final String teamName;
  final String parkName;
  final double lfLine; // -45°
  final double centerField; // 0°
  final double rfLine; // +45°

  const BallparkProfile({
    required this.teamAbbr,
    required this.teamName,
    required this.parkName,
    required this.lfLine,
    required this.centerField,
    required this.rfLine,
  });

  /// spray角度(度、0=中堅、負=レフト側、正=ライト側、範囲は概ね-45〜+45)における
  /// フェンスまでの推定距離(フィート)。3点の直線補間。
  double fenceDistanceAt(double angleDeg) {
    final a = angleDeg.clamp(-45.0, 45.0);
    if (a <= 0) {
      final t = (a + 45.0) / 45.0; // 0 at LF line, 1 at CF
      return lfLine + (centerField - lfLine) * t;
    } else {
      final t = a / 45.0; // 0 at CF, 1 at RF line
      return centerField + (rfLine - centerField) * t;
    }
  }
}

const List<BallparkProfile> mlbBallparks = [
  BallparkProfile(teamAbbr: 'MIL', teamName: 'Brewers', parkName: 'American Family Field', lfLine: 342, centerField: 400, rfLine: 337),
  BallparkProfile(teamAbbr: 'LAA', teamName: 'Angels', parkName: 'Angel Stadium', lfLine: 347, centerField: 396, rfLine: 350),
  BallparkProfile(teamAbbr: 'STL', teamName: 'Cardinals', parkName: 'Busch Stadium', lfLine: 336, centerField: 400, rfLine: 335),
  BallparkProfile(teamAbbr: 'BAL', teamName: 'Orioles', parkName: 'Camden Yards', lfLine: 333, centerField: 400, rfLine: 318),
  BallparkProfile(teamAbbr: 'ARI', teamName: 'Diamondbacks', parkName: 'Chase Field', lfLine: 330, centerField: 407, rfLine: 334),
  BallparkProfile(teamAbbr: 'NYM', teamName: 'Mets', parkName: 'Citi Field', lfLine: 335, centerField: 408, rfLine: 330),
  BallparkProfile(teamAbbr: 'PHI', teamName: 'Phillies', parkName: 'Citizens Bank Park', lfLine: 329, centerField: 401, rfLine: 330),
  BallparkProfile(teamAbbr: 'DET', teamName: 'Tigers', parkName: 'Comerica Park', lfLine: 342, centerField: 412, rfLine: 330),
  BallparkProfile(teamAbbr: 'COL', teamName: 'Rockies', parkName: 'Coors Field', lfLine: 347, centerField: 415, rfLine: 350),
  BallparkProfile(teamAbbr: 'LAD', teamName: 'Dodgers', parkName: 'Dodger Stadium', lfLine: 330, centerField: 395, rfLine: 330),
  BallparkProfile(teamAbbr: 'BOS', teamName: 'Red Sox', parkName: 'Fenway Park', lfLine: 310, centerField: 389, rfLine: 302),
  BallparkProfile(teamAbbr: 'TEX', teamName: 'Rangers', parkName: 'Globe Life Field', lfLine: 329, centerField: 407, rfLine: 326),
  BallparkProfile(teamAbbr: 'CIN', teamName: 'Reds', parkName: 'Great American Ball Park', lfLine: 328, centerField: 404, rfLine: 325),
  BallparkProfile(teamAbbr: 'CWS', teamName: 'White Sox', parkName: 'Guaranteed Rate Field', lfLine: 330, centerField: 400, rfLine: 335),
  BallparkProfile(teamAbbr: 'KC', teamName: 'Royals', parkName: 'Kauffman Stadium', lfLine: 330, centerField: 410, rfLine: 330),
  BallparkProfile(teamAbbr: 'MIA', teamName: 'Marlins', parkName: 'loanDepot Park', lfLine: 344, centerField: 400, rfLine: 335),
  BallparkProfile(teamAbbr: 'HOU', teamName: 'Astros', parkName: 'Daikin Park', lfLine: 315, centerField: 409, rfLine: 326),
  BallparkProfile(teamAbbr: 'WSH', teamName: 'Nationals', parkName: 'Nationals Park', lfLine: 337, centerField: 402, rfLine: 335),
  BallparkProfile(teamAbbr: 'SF', teamName: 'Giants', parkName: 'Oracle Park', lfLine: 339, centerField: 399, rfLine: 309),
  BallparkProfile(teamAbbr: 'SD', teamName: 'Padres', parkName: 'Petco Park', lfLine: 336, centerField: 396, rfLine: 322),
  BallparkProfile(teamAbbr: 'PIT', teamName: 'Pirates', parkName: 'PNC Park', lfLine: 325, centerField: 399, rfLine: 320),
  BallparkProfile(teamAbbr: 'CLE', teamName: 'Guardians', parkName: 'Progressive Field', lfLine: 325, centerField: 400, rfLine: 325),
  BallparkProfile(teamAbbr: 'ATH', teamName: 'Athletics', parkName: 'Sutter Health Park', lfLine: 330, centerField: 403, rfLine: 325),
  BallparkProfile(teamAbbr: 'TOR', teamName: 'Blue Jays', parkName: 'Rogers Centre', lfLine: 328, centerField: 400, rfLine: 328),
  BallparkProfile(teamAbbr: 'SEA', teamName: 'Mariners', parkName: 'T-Mobile Park', lfLine: 331, centerField: 401, rfLine: 326),
  BallparkProfile(teamAbbr: 'MIN', teamName: 'Twins', parkName: 'Target Field', lfLine: 339, centerField: 404, rfLine: 328),
  BallparkProfile(teamAbbr: 'TB', teamName: 'Rays', parkName: 'Tropicana Field', lfLine: 315, centerField: 404, rfLine: 322),
  BallparkProfile(teamAbbr: 'ATL', teamName: 'Braves', parkName: 'Truist Park', lfLine: 335, centerField: 400, rfLine: 325),
  BallparkProfile(teamAbbr: 'CHC', teamName: 'Cubs', parkName: 'Wrigley Field', lfLine: 335, centerField: 400, rfLine: 353),
  BallparkProfile(teamAbbr: 'NYY', teamName: 'Yankees', parkName: 'Yankee Stadium', lfLine: 318, centerField: 408, rfLine: 314),
];
