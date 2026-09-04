// lib/widgets/at_bat_detail_dialog.dart
//
// 1打席分の詳細（配球推移＋ミニストライクゾーン＋対戦成績）をダイアログで表示する。
// game_detail_view.dart の「リアルタイム結果」タブで選手名をタップした時に使う。

import 'package:flutter/material.dart';
import '../services/head_to_head_service.dart';
import '../services/language_provider.dart';
import 'pitch_log_widget.dart';

Future<void> showAtBatDetailDialog(
  BuildContext context, {
  required String batterName,
  required String pitcherName,
  required int? batterId,
  required int? pitcherId,
  required int inning,
  required String half,
  required String result,
  required List<dynamic> playEvents,
  required AppLanguage lang,
}) {
  final pitches = extractPitchDetails(playEvents, lang);

  return showDialog(
    context: context,
    builder: (context) {
      return Dialog(
        backgroundColor: const Color(0xFF1E1E2C),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
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
                        '$batterName の打席詳細',
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.amberAccent),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white70),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
                const Divider(color: Colors.white12),
                const SizedBox(height: 4),
                Text(
                  '$inning回$half   vs $pitcherName',
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.blueAccent),
                ),
                const SizedBox(height: 6),
                Text(result, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white)),
                if (batterId != null && pitcherId != null) ...[
                  const SizedBox(height: 8),
                  HeadToHeadBadge(batterId: batterId, pitcherId: pitcherId),
                ],
                const Divider(height: 24, color: Colors.white12),
                PitchLogWithZone(pitches: pitches),
              ],
            ),
          ),
        ),
      );
    },
  );
}
