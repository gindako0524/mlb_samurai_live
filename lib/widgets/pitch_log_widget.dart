// lib/widgets/pitch_log_widget.dart
//
// 1打席分の配球ログ（テキスト）＋ミニストライクゾーンを横並びで表示する共通ウィジェット。
// live_view.dart（選手個別のライブ観戦画面）と at_bat_detail_dialog.dart
// （試合全体のリアルタイム結果タブから開く打席詳細ダイアログ）の両方から使う。

import 'package:flutter/material.dart';
import '../services/language_provider.dart';
import '../utils/mlb_translations.dart';
import 'mini_strike_zone.dart';
import 'pitch_trajectory_view.dart';

/// playEvents から一球ずつの詳細（球種・球速・コース座標・コール）を抽出する。
List<Map<String, dynamic>> extractPitchDetails(List<dynamic> playEvents, AppLanguage lang) {
  final List<Map<String, dynamic>> pitches = [];
  for (final event in playEvents) {
    if (event['isPitch'] == true) {
      final speedMph = (event['pitchData']?['startSpeed'] as num?)?.toDouble() ?? 0.0;
      final speedKmh = speedMph * 1.60934;
      final rawCall = event['details']?['description']?.toString() ?? '';
      final type = translatePitchType(event['details']?['type']?['description']?.toString(), lang);
      final call = translateCall(rawCall, lang);
      final count = '${event['count']?['balls'] ?? 0}-${event['count']?['strikes'] ?? 0}';

      final coords = event['pitchData']?['coordinates'] as Map<String, dynamic>?;
      final pX = (coords?['pX'] as num?)?.toDouble();
      final pZ = (coords?['pZ'] as num?)?.toDouble();

      // ★ isStrike判定は翻訳前の原文(英語)で行う（翻訳後の文字列には'Strike'等が含まれないため）
      final isStrike = rawCall.contains('Strike') || rawCall.contains('Foul') || rawCall.contains('In play');

      final breaks = event['pitchData']?['breaks'] as Map<String, dynamic>?;
      final rawTypeCode = event['details']?['type']?['code']?.toString();

      pitches.add({
        'pitchNumber': event['pitchNumber'] ?? (pitches.length + 1),
        'type': type,
        'rawTypeCode': rawTypeCode,
        'speedMph': speedMph,
        'speedKmh': speedKmh,
        'call': call,
        'count': count,
        'pX': pX,
        'pZ': pZ,
        'isStrike': isStrike,
        // ★ 軌道再現（打者目線ビュー）に必要な生の物理データ一式
        'x0': coords?['x0'],
        'y0': coords?['y0'],
        'z0': coords?['z0'],
        'vX0': coords?['vX0'],
        'vY0': coords?['vY0'],
        'vZ0': coords?['vZ0'],
        'aX': coords?['aX'],
        'aY': coords?['aY'],
        'aZ': coords?['aZ'],
        'plateTime': event['pitchData']?['plateTime'],
        'strikeZoneTop': event['pitchData']?['strikeZoneTop'],
        'strikeZoneBottom': event['pitchData']?['strikeZoneBottom'],
        'breakHorizontal': breaks?['breakHorizontal'],
        'breakVerticalInduced': breaks?['breakVerticalInduced'],
        'spinRate': breaks?['spinRate'],
      });
    }
  }
  return pitches;
}

/// 配球ログ（テキスト）＋ ミニストライクゾーン（座標プロット）を横並びで表示する。
class PitchLogWithZone extends StatelessWidget {
  final List<Map<String, dynamic>> pitches;

  const PitchLogWithZone({super.key, required this.pitches});

  @override
  Widget build(BuildContext context) {
    if (pitches.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Text('投球データなし', style: TextStyle(color: Colors.white38, fontSize: 12)),
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 左側：配球推移テキスト
        Expanded(
          flex: 6,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('【配球推移】（タップで軌道表示）', style: TextStyle(fontSize: 11, color: Colors.white54)),
              const SizedBox(height: 6),
              ...pitches.map((p) {
                final isStrike = p['isStrike'] as bool;
                return InkWell(
                  onTap: () => showPitchTrajectoryDialog(context, p),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(
                      children: [
                        Container(
                          width: 18,
                          height: 18,
                          decoration: BoxDecoration(
                            color: isStrike ? Colors.redAccent : Colors.blueAccent,
                            borderRadius: BorderRadius.circular(9),
                          ),
                          alignment: Alignment.center,
                          child: Text('${p['pitchNumber']}', style: const TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.bold)),
                        ),
                        const SizedBox(width: 6),
                        Text('[${p['count']}]', style: const TextStyle(fontSize: 11, color: Colors.amberAccent, fontWeight: FontWeight.bold)),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            '${p['type']}\n${(p['speedMph'] as double).toStringAsFixed(1)} mph (${(p['speedKmh'] as double).toStringAsFixed(0)}km/h)',
                            style: const TextStyle(fontSize: 11, color: Colors.white),
                          ),
                        ),
                        Text(
                          p['call'] as String,
                          style: TextStyle(fontSize: 10, color: isStrike ? Colors.orangeAccent : Colors.lightBlueAccent),
                        ),
                        const SizedBox(width: 4),
                        const Icon(Icons.timeline, size: 14, color: Colors.white24),
                      ],
                    ),
                  ),
                );
              }),
            ],
          ),
        ),
        const SizedBox(width: 12),
        // 右側：ミニストライクゾーン
        Expanded(
          flex: 4,
          child: Column(
            children: [
              const Text('【ゾーン通過位置】', style: TextStyle(fontSize: 11, color: Colors.white54)),
              const SizedBox(height: 6),
              MiniStrikeZone(pitches: pitches, width: 120, height: 140),
            ],
          ),
        ),
      ],
    );
  }
}
