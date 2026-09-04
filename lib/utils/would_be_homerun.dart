// lib/utils/would_be_homerun.dart
//
// 打球データ(Statcast由来のhitData)から「もし他球場だったらホームランに
// なっていたか」を判定するロジック。
//
// spray角度(打球の左右方向)は、MLB Gameday座標系のhitData.coordinates
// (coordX, coordY)から、コミュニティで広く使われている変換式で算出する
// (MLB公式は変換式を明示していないが、本塁の位置がおよそ(125.42, 198.27)で
// あることは複数のセイバーメトリクス系ツールで再現・共有されている)。
//
// ★ この判定はあくまで「飛距離 vs 球場ごとの単純化したフェンス距離」の比較に
//   よる目安。壁の高さは考慮していないため、フェンウェイのグリーンモンスター
//   のような高い壁は正しく判定できない場合がある(ballpark_dimensions.dartの
//   コメント参照)。

import 'dart:math';
import 'ballpark_dimensions.dart';

const double _homePlateX = 125.42;
const double _homePlateY = 198.27;

/// Gameday座標(coordX, coordY)からspray角度(度)を算出。
/// 0° = 中堅方向、負 = レフト方向、正 = ライト方向。
double sprayAngleFromCoords(double coordX, double coordY) {
  final dx = coordX - _homePlateX;
  final dy = _homePlateY - coordY;
  if (dx == 0 && dy == 0) return 0;
  return atan2(dx, dy) * 180 / pi;
}

/// この打球が「他球場ならホームランだったか」を判定する対象として
/// 妥当かどうか(フライ・ライナー性の打球で、ある程度の飛距離があるもの)。
bool isEligibleForWouldBeHomer({required String? trajectory, required double? launchAngle, required double? totalDistance}) {
  if (totalDistance == null || totalDistance < 250) return false;
  if (trajectory != 'fly_ball' && trajectory != 'line_drive') return false;
  if (launchAngle != null && (launchAngle < 10 || launchAngle > 55)) return false;
  return true;
}

/// 飛距離(フィート)とspray角度(度)から、その打球がホームランになる球場の
/// 一覧を返す(距離ベースの簡易判定)。
List<BallparkProfile> wouldBeHomeRunParks({required double totalDistance, required double angleDeg}) {
  return mlbBallparks.where((p) => totalDistance >= p.fenceDistanceAt(angleDeg)).toList();
}
