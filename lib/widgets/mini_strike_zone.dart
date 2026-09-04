// lib/widgets/mini_strike_zone.dart
//
// 投球のストライクゾーン通過位置をミニ表示するための共通ウィジェット。
// live_view.dart（選手個別のライブ観戦画面）と game_detail_view.dart
// （試合全体のリアルタイム結果タブ）の両方から使う。

import 'package:flutter/material.dart';

/// playEvents から、ゾーン表示に必要な最小限の情報（球番号・座標・ストライク判定）を抽出する。
List<Map<String, dynamic>> extractPitchZonePoints(List<dynamic> playEvents) {
  final List<Map<String, dynamic>> pitches = [];
  for (final event in playEvents) {
    if (event['isPitch'] == true) {
      final pX = (event['pitchData']?['coordinates']?['pX'] as num?)?.toDouble();
      final pZ = (event['pitchData']?['coordinates']?['pZ'] as num?)?.toDouble();
      final rawCall = event['details']?['description']?.toString() ?? '';
      final isStrike = rawCall.contains('Strike') || rawCall.contains('Foul') || rawCall.contains('In play');
      pitches.add({
        'pitchNumber': event['pitchNumber'] ?? (pitches.length + 1),
        'pX': pX,
        'pZ': pZ,
        'isStrike': isStrike,
      });
    }
  }
  return pitches;
}

/// ミニストライクゾーン表示ウィジェット（枠＋グリッド＋各投球のプロット）。
class MiniStrikeZone extends StatelessWidget {
  final List<Map<String, dynamic>> pitches;
  final double width;
  final double height;

  const MiniStrikeZone({super.key, required this.pitches, this.width = 120, this.height = 140});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: const Color(0xFF14141E),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white12),
      ),
      child: CustomPaint(painter: MiniStrikeZonePainter(pitches: pitches)),
    );
  }
}

class MiniStrikeZonePainter extends CustomPainter {
  final List<Map<String, dynamic>> pitches;

  MiniStrikeZonePainter({required this.pitches});

  @override
  void paint(Canvas canvas, Size size) {
    final zoneWidth = size.width * 0.6;
    final zoneHeight = size.height * 0.65;
    final zoneLeft = (size.width - zoneWidth) / 2;
    final zoneTop = (size.height - zoneHeight) / 2;
    final zoneRect = Rect.fromLTWH(zoneLeft, zoneTop, zoneWidth, zoneHeight);

    final bgPaint = Paint()..color = const Color(0xFF222232);
    canvas.drawRect(zoneRect, bgPaint);

    final borderPaint = Paint()
      ..color = Colors.white70
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawRect(zoneRect, borderPaint);

    final gridPaint = Paint()
      ..color = Colors.white24
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;

    for (int i = 1; i <= 2; i++) {
      canvas.drawLine(
        Offset(zoneLeft + (zoneWidth / 3) * i, zoneTop),
        Offset(zoneLeft + (zoneWidth / 3) * i, zoneTop + zoneHeight),
        gridPaint,
      );
      canvas.drawLine(
        Offset(zoneLeft, zoneTop + (zoneHeight / 3) * i),
        Offset(zoneLeft + zoneWidth, zoneTop + (zoneHeight / 3) * i),
        gridPaint,
      );
    }

    for (final p in pitches) {
      final double? pX = p['pX'];
      final double? pZ = p['pZ'];
      if (pX == null || pZ == null) continue;

      // MLB座標系 (pX: -2.0 ~ 2.0 ft, pZ: 0.5 ~ 4.5 ft) を Canvas 座標にマッピング
      // Strike Zone: X: -0.83 ~ 0.83 ft, Z: 1.5 ~ 3.5 ft
      final double normalizedX = (pX + 0.83) / (0.83 * 2);
      final double normalizedY = 1.0 - ((pZ - 1.5) / (3.5 - 1.5));

      final double cx = zoneLeft + (normalizedX * zoneWidth);
      final double cy = zoneTop + (normalizedY * zoneHeight);

      final isStrike = p['isStrike'] as bool? ?? false;
      final ballColor = isStrike ? Colors.redAccent : Colors.blueAccent;

      final ballPaint = Paint()..color = ballColor;
      canvas.drawCircle(Offset(cx, cy), 8, ballPaint);

      final strokePaint = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0;
      canvas.drawCircle(Offset(cx, cy), 8, strokePaint);

      final textSpan = TextSpan(
        text: '${p['pitchNumber']}',
        style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
      );
      final textPainter = TextPainter(
        text: textSpan,
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
      )..layout();

      textPainter.paint(
        canvas,
        Offset(cx - (textPainter.width / 2), cy - (textPainter.height / 2)),
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
