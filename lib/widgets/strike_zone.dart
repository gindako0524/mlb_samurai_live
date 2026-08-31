import 'package:flutter/material.dart';

class PitchData {
  final int pitchNumber;
  final String pitchName; // 例: 4-Seam Fastball, Slider
  final double speedKmh;  // 球速 (km/h)
  final double x;         // MLB座標 x (-2.0 ~ 2.0程度, 0が真ん中)
  final double y;         // MLB座標 y (0.5 ~ 4.5程度, 高低)
  final String callResult;// Strike, Ball, In play 等

  const PitchData({
    required this.pitchNumber,
    required this.pitchName,
    required this.speedKmh,
    required this.x,
    required this.y,
    required this.callResult,
  });
}

class StrikeZoneWidget extends StatelessWidget {
  final List<PitchData> pitches;

  const StrikeZoneWidget({super.key, required this.pitches});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 220,
      height: 260,
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E2C),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white24),
      ),
      child: CustomPaint(
        painter: _StrikeZonePainter(pitches: pitches),
      ),
    );
  }
}

class _StrikeZonePainter extends CustomPainter {
  final List<PitchData> pitches;

  _StrikeZonePainter({required this.pitches});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);

    // 1. ストライクゾーンの枠（ホームベース上の9分割ゾーン）
    final zoneWidth = size.width * 0.55;
    final zoneHeight = size.height * 0.55;
    final zoneRect = Rect.fromCenter(center: center, width: zoneWidth, height: zoneHeight);

    final zonePaint = Paint()
      ..color = Colors.white70
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    // 外枠
    canvas.drawRect(zoneRect, zonePaint);

    // 内側の9分割グリッド線
    final gridPaint = Paint()
      ..color = Colors.white24
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    final cellW = zoneWidth / 3;
    final cellH = zoneHeight / 3;

    // 縦線2本
    canvas.drawLine(Offset(zoneRect.left + cellW, zoneRect.top), Offset(zoneRect.left + cellW, zoneRect.bottom), gridPaint);
    canvas.drawLine(Offset(zoneRect.left + cellW * 2, zoneRect.top), Offset(zoneRect.left + cellW * 2, zoneRect.bottom), gridPaint);

    // 横線2本
    canvas.drawLine(Offset(zoneRect.left, zoneRect.top + cellH), Offset(zoneRect.right, zoneRect.top + cellH), gridPaint);
    canvas.drawLine(Offset(zoneRect.left, zoneRect.top + cellH * 2), Offset(zoneRect.right, zoneRect.top + cellH * 2), gridPaint);

    // 2. ホームプレート（下部の五角形ベース）
    final platePaint = Paint()
      ..color = Colors.white38
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    final plateTop = zoneRect.bottom + 16;
    final platePath = Path()
      ..moveTo(center.dx - 25, plateTop)
      ..lineTo(center.dx + 25, plateTop)
      ..lineTo(center.dx + 25, plateTop + 10)
      ..lineTo(center.dx, plateTop + 20)
      ..lineTo(center.dx - 25, plateTop + 10)
      ..close();
    canvas.drawPath(platePath, platePaint);

    // 3. 投球ポイント（●）の描画
    for (final pitch in pitches) {
      // MLB Statcast座標を画面ピクセルにマッピング
      // X: -0.85 〜 0.85 がゾーン内
      // Y: 1.5 (低め) 〜 3.5 (高め) がゾーン内
      final px = center.dx + (pitch.x / 1.0) * (zoneWidth / 2);
      final py = center.dy - ((pitch.y - 2.5) / 1.1) * (zoneHeight / 2);

      // 球種ごとの色分け
      Color ballColor;
      if (pitch.pitchName.contains('Fastball') || pitch.pitchName.contains('Sinker')) {
        ballColor = Colors.redAccent; // 直球系: 赤
      } else if (pitch.pitchName.contains('Slider') || pitch.pitchName.contains('Cutter') || pitch.pitchName.contains('Sweeper')) {
        ballColor = Colors.orangeAccent; // スライダー・スイーパー系: 橙
      } else if (pitch.pitchName.contains('Splitter') || pitch.pitchName.contains('Changeup')) {
        ballColor = Colors.blueAccent; // スプリット・チェンジアップ系: 青
      } else {
        ballColor = Colors.purpleAccent; // カーブ・その他: 紫
      }

      final ballPaint = Paint()..color = ballColor;
      canvas.drawCircle(Offset(px, py), 10, ballPaint);

      // 白枠
      final borderPaint = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5;
      canvas.drawCircle(Offset(px, py), 10, borderPaint);

      // 球数テキスト (1, 2, 3...)
      final textSpan = TextSpan(
        text: pitch.pitchNumber.toString(),
        style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
      );
      final textPainter = TextPainter(
        text: textSpan,
        textDirection: TextDirection.ltr,
      )..layout();
      textPainter.paint(
        canvas,
        Offset(px - (textPainter.width / 2), py - (textPainter.height / 2)),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _StrikeZonePainter oldDelegate) => true;
}