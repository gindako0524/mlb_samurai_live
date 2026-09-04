// lib/widgets/pitch_trajectory_view.dart
//
// 1球の投球について、Statcastの軌道物理データ（リリース位置・初速・加速度）から
// ボールの実際の軌道を再現し、3Dカメラで自由に視点を回転させながら見られる
// ダイアログ。変化球がどれだけ曲がって見えるかを、打者目線に限らず
// 好きな角度から視覚化できる。
//
// 物理モデル: MLB公式のPITCHf/x方式。各軸についてリリース時刻(t=0)からの
// 等加速度運動として位置を近似する。
//   x(t) = x0 + vX0*t + 0.5*aX*t^2   （左右方向、フィート）
//   y(t) = y0 + vY0*t + 0.5*aY*t^2   （投手→捕手方向の奥行き、フィート）
//   z(t) = z0 + vZ0*t + 0.5*aZ*t^2   （高さ、フィート）
// t は 0〜plateTime（本塁到達までの秒数）まで動かして軌道サンプルを作る。
//
// 視点は本塁付近を中心（pivot）に軌道を球面上のカメラで囲む方式で、
// ドラッグ操作でazimuth（水平回転）とelevation（上下回転）を変更できる
// 「360度カメラ」的な操作を実現している。

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';

// ★ ミニストライクゾーン（mini_strike_zone.dart）が使う pX/pZ は、本塁ベース
//   前端（投手からの奥行きy = 1.417フィート）を通過する瞬間の座標として
//   MLB公式が計算した値。実測で確認したところ、pitchDataの plateTime
//   フィールドをそのまま終端時刻として使うと、この基準面とはズレた時刻の
//   座標になってしまい、ミニストライクゾーンの点とわずかに位置がずれる
//   （plateTimeは「本塁到達」の別の基準を指しているらしく、y=1.417での
//   通過時刻とは一致しない）。そのため、plateTimeは使わず、
//   y(t) = y0 + vY0*t + 0.5*aY*t^2 = 1.417 を自前で解いて本塁到達時刻を求める。
const double _homePlateFrontY = 1.417;

/// 1球分のpitchデータ（pitch_log_widget.extractPitchDetailsが返す形式）から、
/// 軌道サンプル点 [x, y, z]（フィート）のリストを計算する。
/// 必要なフィールドが欠けている場合は空リストを返す。
List<List<double>> computePitchTrajectory(Map<String, dynamic> pitch, {int steps = 30}) {
  final x0 = (pitch['x0'] as num?)?.toDouble();
  final y0 = (pitch['y0'] as num?)?.toDouble();
  final z0 = (pitch['z0'] as num?)?.toDouble();
  final vX0 = (pitch['vX0'] as num?)?.toDouble();
  final vY0 = (pitch['vY0'] as num?)?.toDouble();
  final vZ0 = (pitch['vZ0'] as num?)?.toDouble();
  final aX = (pitch['aX'] as num?)?.toDouble();
  final aY = (pitch['aY'] as num?)?.toDouble();
  final aZ = (pitch['aZ'] as num?)?.toDouble();

  if (x0 == null || y0 == null || z0 == null || vX0 == null || vY0 == null || vZ0 == null || aX == null || aY == null || aZ == null) {
    return [];
  }

  // y(t) = y0 + vY0*t + 0.5*aY*t^2 = 1.417 を解き、本塁到達時刻を求める
  double? arrivalTime;
  final a = 0.5 * aY;
  final b = vY0;
  final c = y0 - _homePlateFrontY;
  if (a.abs() < 1e-9) {
    if (b.abs() > 1e-9) arrivalTime = -c / b;
  } else {
    final disc = b * b - 4 * a * c;
    if (disc >= 0) {
      final sqrtDisc = math.sqrt(disc);
      final roots = [(-b + sqrtDisc) / (2 * a), (-b - sqrtDisc) / (2 * a)].where((t) => t > 0).toList();
      if (roots.isNotEmpty) arrivalTime = roots.reduce((x, y) => x < y ? x : y);
    }
  }
  if (arrivalTime == null || arrivalTime <= 0) return [];

  final points = <List<double>>[];
  for (int i = 0; i <= steps; i++) {
    final t = arrivalTime * i / steps;
    final x = x0 + vX0 * t + 0.5 * aX * t * t;
    final y = y0 + vY0 * t + 0.5 * aY * t * t;
    final z = z0 + vZ0 * t + 0.5 * aZ * t * t;
    points.add([x, y, z]);
  }

  // ★ 最終点はミニストライクゾーンと完全に一致させるため、公式発表のpX/pZが
  //   あればそちらで上書きする（自前計算はごくわずかな誤差が出るため）
  final pX = (pitch['pX'] as num?)?.toDouble();
  final pZ = (pitch['pZ'] as num?)?.toDouble();
  if (pX != null && pZ != null && points.isNotEmpty) {
    points[points.length - 1] = [pX, _homePlateFrontY, pZ];
  }

  return points;
}

class _Vec3 {
  final double x, y, z;
  const _Vec3(this.x, this.y, this.z);
  _Vec3 operator -(_Vec3 o) => _Vec3(x - o.x, y - o.y, z - o.z);
  _Vec3 operator +(_Vec3 o) => _Vec3(x + o.x, y + o.y, z + o.z);
  _Vec3 scale(double s) => _Vec3(x * s, y * s, z * s);
  double dot(_Vec3 o) => x * o.x + y * o.y + z * o.z;
  _Vec3 cross(_Vec3 o) => _Vec3(y * o.z - z * o.y, z * o.x - x * o.z, x * o.y - y * o.x);
  double get length => math.sqrt(x * x + y * y + z * z);
  _Vec3 get normalized {
    final l = length;
    return l == 0 ? this : _Vec3(x / l, y / l, z / l);
  }
}

/// 球面上を自由に動けるカメラ。pivotを中心にtheta（水平角）・phi（仰角）で
/// 位置が決まり、そこから見た3D→2D透視投影を行う。
class _OrbitCamera {
  final double theta;
  final double phi;
  final _Vec3 pivot;
  final double distance;
  final double focal;

  _OrbitCamera({required this.theta, required this.phi, required this.pivot, required this.distance, required this.focal});

  late final _Vec3 viewDir = _Vec3(
    math.sin(theta) * math.cos(phi),
    math.cos(theta) * math.cos(phi),
    math.sin(phi),
  ).normalized;

  late final _Vec3 right = viewDir.cross(const _Vec3(0, 0, 1)).normalized;
  late final _Vec3 up = right.cross(viewDir).normalized;
  late final _Vec3 eye = pivot - viewDir.scale(distance);

  /// カメラの後方にある点はnullを返す。
  Offset? project(_Vec3 p, Size size) {
    final v = p - eye;
    final depth = v.dot(viewDir);
    if (depth <= 0.5) return null;
    final u = v.dot(right);
    final w = v.dot(up);
    return Offset(size.width / 2 + u * focal / depth, size.height / 2 - w * focal / depth);
  }

  double depthOf(_Vec3 p) => (p - eye).dot(viewDir);
}

class PitchTrajectoryPainter extends CustomPainter {
  final List<List<double>> points;
  final double strikeZoneTop;
  final double strikeZoneBottom;
  final bool isStrike;
  final double theta;
  final double phi;
  final double zoom;

  PitchTrajectoryPainter({
    required this.points,
    required this.strikeZoneTop,
    required this.strikeZoneBottom,
    required this.isStrike,
    required this.theta,
    required this.phi,
    this.zoom = 1.0,
  });

  static const double _zoneHalfWidthFt = (17 / 12) / 2;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;

    final zCenter = (strikeZoneTop + strikeZoneBottom) / 2;
    final plateY = points.last[1];
    final pivot = _Vec3(0, plateY, zCenter);

    final worldPoints = points.map((p) => _Vec3(p[0], p[1], p[2])).toList();

    // ★ カメラをどの角度に回転させても軌道全体（特にリリース点付近）が
    //   視界内に収まるよう、軌道の中で最もpivotから遠い点との距離をもとに
    //   カメラ距離・画角を動的に決める（近すぎると回転時に軌道が視界から
    //   切れて見えてしまうため）
    double maxDistFromPivot = 0;
    for (final wp in worldPoints) {
      final d = (wp - pivot).length;
      if (d > maxDistFromPivot) maxDistFromPivot = d;
    }
    final cameraDistance = maxDistFromPivot + 12;
    final focal = cameraDistance * 105.0 * zoom;
    final camera = _OrbitCamera(theta: theta, phi: phi, pivot: pivot, distance: cameraDistance, focal: focal);

    // ストライクゾーン（本塁到達面の実寸の枠）
    final zoneCorners = [
      _Vec3(-_zoneHalfWidthFt, plateY, strikeZoneTop),
      _Vec3(_zoneHalfWidthFt, plateY, strikeZoneTop),
      _Vec3(_zoneHalfWidthFt, plateY, strikeZoneBottom),
      _Vec3(-_zoneHalfWidthFt, plateY, strikeZoneBottom),
    ];

    // ストライクゾーン（本塁到達面の実寸の枠）
    final zoneScreen = zoneCorners.map((c) => camera.project(c, size)).toList();
    if (!zoneScreen.contains(null)) {
      final zonePath = Path()..moveTo(zoneScreen[0]!.dx, zoneScreen[0]!.dy);
      for (int i = 1; i < zoneScreen.length; i++) {
        zonePath.lineTo(zoneScreen[i]!.dx, zoneScreen[i]!.dy);
      }
      zonePath.close();
      canvas.drawPath(
        zonePath,
        Paint()
          ..color = Colors.white38
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
      // グリッド線（縦横3分割）
      final gridPaint = Paint()
        ..color = Colors.white24
        ..strokeWidth = 0.8;
      for (int i = 1; i <= 2; i++) {
        final top = Offset.lerp(zoneScreen[0]!, zoneScreen[1]!, i / 3)!;
        final bottom = Offset.lerp(zoneScreen[3]!, zoneScreen[2]!, i / 3)!;
        canvas.drawLine(top, bottom, gridPaint);
        final left = Offset.lerp(zoneScreen[0]!, zoneScreen[3]!, i / 3)!;
        final right = Offset.lerp(zoneScreen[1]!, zoneScreen[2]!, i / 3)!;
        canvas.drawLine(left, right, gridPaint);
      }
    }

    // 軌道パス（カメラの後ろに回った区間は繋げない）
    final path = Path();
    bool started = false;
    for (final wp in worldPoints) {
      final o = camera.project(wp, size);
      if (o == null) {
        started = false;
        continue;
      }
      if (!started) {
        path.moveTo(o.dx, o.dy);
        started = true;
      } else {
        path.lineTo(o.dx, o.dy);
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = (isStrike ? Colors.redAccent : Colors.blueAccent).withAlpha(200)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round,
    );

    // 奥ほど小さいボールの通過点
    for (final wp in worldPoints) {
      final o = camera.project(wp, size);
      if (o == null) continue;
      final depth = camera.depthOf(wp);
      final r = (cameraDistance * 7 / depth).clamp(1.5, 7.0);
      final alpha = (255 * (1 - (depth / 60)).clamp(0.25, 1.0)).toInt();
      canvas.drawCircle(o, r, Paint()..color = Colors.white.withAlpha(alpha));
    }

    // リリースポイント
    final releaseScreen = camera.project(worldPoints.first, size);
    if (releaseScreen != null) {
      canvas.drawCircle(releaseScreen, 5, Paint()..color = Colors.amberAccent);
    }
    // 本塁到達点（実際にボールが通過した位置）
    final plateScreen = camera.project(worldPoints.last, size);
    if (plateScreen != null) {
      canvas.drawCircle(
        plateScreen,
        7,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = Colors.white,
      );
    }
  }

  @override
  bool shouldRepaint(covariant PitchTrajectoryPainter oldDelegate) =>
      oldDelegate.theta != theta || oldDelegate.phi != phi || oldDelegate.zoom != zoom || oldDelegate.points != points;
}

/// ドラッグで視点（azimuth/elevation）を回転できる軌道表示キャンバス。
class RotatableTrajectoryCanvas extends StatefulWidget {
  final List<List<double>> points;
  final double strikeZoneTop;
  final double strikeZoneBottom;
  final bool isStrike;

  const RotatableTrajectoryCanvas({
    super.key,
    required this.points,
    required this.strikeZoneTop,
    required this.strikeZoneBottom,
    required this.isStrike,
  });

  @override
  State<RotatableTrajectoryCanvas> createState() => _RotatableTrajectoryCanvasState();
}

class _RotatableTrajectoryCanvasState extends State<RotatableTrajectoryCanvas> {
  // ★ 初期値(0, 0)が「打者目線（本塁の後ろからマウンド方向を見る視点）」に相当する
  double _theta = 0;
  double _phi = 0;
  double _zoom = 1.0;

  // ★ ピンチ操作(onScaleUpdate)は開始時のズーム値を基準にscale倍率が
  //   累積で来るため、ジェスチャー開始時点の値を覚えておく必要がある
  double _zoomAtGestureStart = 1.0;

  static const double _phiLimit = 1.45; // 真上・真下付近の特異点を避ける
  static const double _minZoom = 0.4;
  static const double _maxZoom = 3.0;

  void _reset() => setState(() {
        _theta = 0;
        _phi = 0;
        _zoom = 1.0;
      });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Listener(
          // ★ マウスホイールでの拡大縮小（デスクトップ向け）
          onPointerSignal: (event) {
            if (event is PointerScrollEvent) {
              setState(() {
                _zoom = (_zoom - event.scrollDelta.dy * 0.0015).clamp(_minZoom, _maxZoom);
              });
            }
          },
          child: GestureDetector(
            // ★ ScaleGestureRecognizerは1本指ドラッグ（回転）とピンチ（拡大縮小・
            //   スマホ向け）を両方扱えるため、pan単体ではなくscale系に統一している
            onScaleStart: (_) => _zoomAtGestureStart = _zoom,
            onScaleUpdate: (details) {
              setState(() {
                _theta -= details.focalPointDelta.dx * 0.012;
                _phi = (_phi + details.focalPointDelta.dy * 0.012).clamp(-_phiLimit, _phiLimit);
                _zoom = (_zoomAtGestureStart * details.scale).clamp(_minZoom, _maxZoom);
              });
            },
            onDoubleTap: _reset,
            child: Container(
              width: 300,
              height: 340,
              decoration: BoxDecoration(
                color: const Color(0xFF14141E),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white12),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: CustomPaint(
                  size: const Size(300, 340),
                  painter: PitchTrajectoryPainter(
                    points: widget.points,
                    strikeZoneTop: widget.strikeZoneTop,
                    strikeZoneBottom: widget.strikeZoneBottom,
                    isStrike: widget.isStrike,
                    theta: _theta,
                    phi: _phi,
                    zoom: _zoom,
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('ドラッグで回転・スクロールやピンチで拡大縮小（ダブルタップでリセット）', style: TextStyle(fontSize: 10, color: Colors.white38)),
            const SizedBox(width: 8),
            InkWell(
              onTap: _reset,
              child: const Icon(Icons.replay, size: 14, color: Colors.white38),
            ),
          ],
        ),
      ],
    );
  }
}

/// 1球の軌道を、視点回転可能な3D表示で見せるダイアログ。
Future<void> showPitchTrajectoryDialog(BuildContext context, Map<String, dynamic> pitch) {
  final points = computePitchTrajectory(pitch);
  final strikeZoneTop = (pitch['strikeZoneTop'] as num?)?.toDouble() ?? 3.5;
  final strikeZoneBottom = (pitch['strikeZoneBottom'] as num?)?.toDouble() ?? 1.5;
  final isStrike = pitch['isStrike'] as bool? ?? false;
  final breakH = (pitch['breakHorizontal'] as num?)?.toDouble();
  final breakV = (pitch['breakVerticalInduced'] as num?)?.toDouble();
  final spinRate = (pitch['spinRate'] as num?)?.toInt();

  return showDialog(
    context: context,
    builder: (context) {
      return Dialog(
        backgroundColor: const Color(0xFF1E1E2C),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        '${pitch['pitchNumber']}球目 ${pitch['type']} の軌道',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.amberAccent),
                      ),
                    ),
                    IconButton(icon: const Icon(Icons.close, color: Colors.white70), onPressed: () => Navigator.of(context).pop()),
                  ],
                ),
                const Divider(color: Colors.white12),
                Text(
                  '${(pitch['speedMph'] as double).toStringAsFixed(1)} mph (${(pitch['speedKmh'] as double).toStringAsFixed(0)} km/h)   ${pitch['call']}',
                  style: const TextStyle(fontSize: 13, color: Colors.white70),
                ),
                const SizedBox(height: 12),
                if (points.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(child: Text('この球の軌道データはありません', style: TextStyle(color: Colors.white38))),
                  )
                else ...[
                  Center(
                    child: RotatableTrajectoryCanvas(
                      points: points,
                      strikeZoneTop: strikeZoneTop,
                      strikeZoneBottom: strikeZoneBottom,
                      isStrike: isStrike,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text('● 黄=リリース点　○ 白=本塁到達点　奥ほど小さく表示', style: TextStyle(fontSize: 10, color: Colors.white38)),
                  if (breakH != null || breakV != null || spinRate != null) ...[
                    const Divider(height: 20, color: Colors.white12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        if (breakH != null)
                          _TrajectoryStat(label: '横変化', val: '${breakH.abs().toStringAsFixed(1)}in'),
                        if (breakV != null)
                          _TrajectoryStat(label: '縦変化', val: '${breakV.abs().toStringAsFixed(1)}in'),
                        if (spinRate != null)
                          _TrajectoryStat(label: '回転数', val: '$spinRate rpm'),
                      ],
                    ),
                  ],
                ],
              ],
            ),
          ),
        ),
      );
    },
  );
}

class _TrajectoryStat extends StatelessWidget {
  final String label;
  final String val;

  const _TrajectoryStat({required this.label, required this.val});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(label, style: const TextStyle(fontSize: 10, color: Colors.white54)),
        const SizedBox(height: 2),
        Text(val, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white)),
      ],
    );
  }
}
