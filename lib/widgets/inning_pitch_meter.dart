import 'package:flutter/material.dart';

class InningPitchData {
  final int inning;
  final int pitchCount;
  final bool isCurrent;

  const InningPitchData({
    required this.inning,
    required this.pitchCount,
    this.isCurrent = false,
  });

  // ペース判定 (14球以下: 省エネ緑, 15-19球: 標準黄, 20球以上: 過多赤)
  Color get statusColor {
    if (pitchCount <= 14) return Colors.greenAccent;
    if (pitchCount <= 19) return Colors.amberAccent;
    return Colors.redAccent;
  }
}

class InningPitchMeterWidget extends StatelessWidget {
  final List<InningPitchData> innings;
  final int maxLimitPitches; // 目安球数 (例: 95球)

  const InningPitchMeterWidget({
    super.key,
    required this.innings,
    this.maxLimitPitches = 95,
  });

  @override
  Widget build(BuildContext context) {
    final totalPitches = innings.fold(0, (sum, item) => sum + item.pitchCount);
    final progress = (totalPitches / maxLimitPitches).clamp(0.0, 1.0);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E2C),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('イニング別 球数', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              Text('計 $totalPitches 球 / 目安 $maxLimitPitches 球', style: const TextStyle(fontSize: 12, color: Colors.white70)),
            ],
          ),
          const SizedBox(height: 8),
          // 総球数プログレスバー
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 6,
              backgroundColor: Colors.white12,
              valueColor: AlwaysStoppedAnimation<Color>(
                progress > 0.85 ? Colors.redAccent : Colors.blueAccent,
              ),
            ),
          ),
          const SizedBox(height: 12),
          // 各イニングの縦リスト
          Expanded(
            child: ListView.builder(
              itemCount: innings.length,
              itemBuilder: (context, index) {
                final item = innings[index];
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 42,
                        child: Text('${item.inning}回', style: TextStyle(
                          fontSize: 12,
                          fontWeight: item.isCurrent ? FontWeight.bold : FontWeight.normal,
                          color: item.isCurrent ? Colors.lightBlueAccent : Colors.white,
                        )),
                      ),
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: item.statusColor,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text('${item.pitchCount}球', style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: item.statusColor,
                      )),
                      const SizedBox(width: 8),
                      if (item.isCurrent)
                        const Text('(投球中)', style: TextStyle(fontSize: 10, color: Colors.lightBlueAccent)),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}