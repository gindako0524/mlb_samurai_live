// lib/services/head_to_head_service.dart

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

/// 打者 vs 投手 の通算対戦成績
class HeadToHeadStats {
  final int atBats;
  final int hits;
  final int homeRuns;
  final int strikeOuts;
  final int baseOnBalls;
  final String avg;
  final String? ops;

  const HeadToHeadStats({
    required this.atBats,
    required this.hits,
    required this.homeRuns,
    required this.strikeOuts,
    required this.baseOnBalls,
    required this.avg,
    this.ops,
  });
}

String _formatRate(dynamic val) {
  if (val == null) return '-';
  final d = double.tryParse(val.toString());
  if (d == null) return val.toString();
  if (d < 1.0 && d > -1.0) {
    return '.${(d.abs() * 1000).round().toString().padLeft(3, '0')}';
  }
  return d.toStringAsFixed(3);
}

/// 打者(batterId)と投手(pitcherId)の通算対戦成績を取得する。
/// vsPlayerTotal（通算）→ vsPlayer（取得できない場合のフォールバック）の順で試す。
/// ★ MLB公式APIはデフォルトではレギュラーシーズンの対戦成績しか返さないため、
///   gameType=R（レギュラーシーズン）とgameType=P（ポストシーズン全体：
///   ワイルドカード〜リーグ優勝シリーズ〜ワールドシリーズを1つの値として
///   まとめて返す、実測で確認済み）の2回に分けて取得し、合算する。
/// 対戦経験が無い場合は null を返す。
Future<HeadToHeadStats?> fetchHeadToHead({required int batterId, required int pitcherId}) async {
  Future<Map<String, dynamic>?> tryFetch(String statsType, String gameType) async {
    final url = Uri.parse(
      'https://statsapi.mlb.com/api/v1/people/$batterId/stats?stats=$statsType&group=hitting&opposingPlayerId=$pitcherId&sportId=1&gameType=$gameType',
    );
    try {
      final res = await http.get(url);
      if (res.statusCode != 200) return null;
      final data = json.decode(utf8.decode(res.bodyBytes));
      final statsList = data['stats'] as List<dynamic>? ?? [];
      for (final s in statsList) {
        final splits = s['splits'] as List<dynamic>? ?? [];
        if (splits.isNotEmpty) return splits.first['stat'] as Map<String, dynamic>?;
      }
    } catch (_) {}
    return null;
  }

  final regular = await tryFetch('vsPlayerTotal', 'R') ?? await tryFetch('vsPlayer', 'R');
  final postseason = await tryFetch('vsPlayerTotal', 'P') ?? await tryFetch('vsPlayer', 'P');
  if (regular == null && postseason == null) return null;

  int sumField(String key) {
    return ((regular?[key] as num?)?.toInt() ?? 0) + ((postseason?[key] as num?)?.toInt() ?? 0);
  }

  final ab = sumField('atBats');
  if (ab == 0) return null; // 対戦経験なし

  final hits = sumField('hits');

  return HeadToHeadStats(
    atBats: ab,
    hits: hits,
    homeRuns: sumField('homeRuns'),
    strikeOuts: sumField('strikeOuts'),
    baseOnBalls: sumField('baseOnBalls'),
    avg: _formatRate(hits / ab),
    ops: null,
  );
}

/// 「通算 ○-○ (.○○○) ○本 ○四球 ○三振」の形で表示する小さなバッジウィジェット。
/// batterId / pitcherId を渡すだけで内部で取得〜表示まで行う。
class HeadToHeadBadge extends StatefulWidget {
  final int batterId;
  final int pitcherId;
  final String batterLabel;
  final String pitcherLabel;

  const HeadToHeadBadge({
    super.key,
    required this.batterId,
    required this.pitcherId,
    this.batterLabel = '打者',
    this.pitcherLabel = '投手',
  });

  @override
  State<HeadToHeadBadge> createState() => _HeadToHeadBadgeState();
}

class _HeadToHeadBadgeState extends State<HeadToHeadBadge> {
  late Future<HeadToHeadStats?> _future;

  @override
  void initState() {
    super.initState();
    _future = fetchHeadToHead(batterId: widget.batterId, pitcherId: widget.pitcherId);
  }

  @override
  void didUpdateWidget(covariant HeadToHeadBadge oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.batterId != widget.batterId || oldWidget.pitcherId != widget.pitcherId) {
      _future = fetchHeadToHead(batterId: widget.batterId, pitcherId: widget.pitcherId);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<HeadToHeadStats?>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const SizedBox(
            height: 20,
            width: 20,
            child: Padding(
              padding: EdgeInsets.all(2),
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white24),
            ),
          );
        }

        final stat = snapshot.data;
        if (stat == null) {
          return const Text(
            '通算対戦: データなし',
            style: TextStyle(fontSize: 11, color: Colors.white38),
          );
        }

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.purpleAccent.withAlpha(25),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: Colors.purpleAccent.withAlpha(80)),
          ),
          child: Text(
            '通算 ${stat.atBats}-${stat.hits} (${stat.avg})'
            '${stat.homeRuns > 0 ? ' ${stat.homeRuns}本' : ''}'
            '${stat.baseOnBalls > 0 ? ' ${stat.baseOnBalls}四球' : ''}'
            '${stat.strikeOuts > 0 ? ' ${stat.strikeOuts}三振' : ''}',
            style: const TextStyle(fontSize: 11, color: Colors.purpleAccent, fontWeight: FontWeight.bold),
          ),
        );
      },
    );
  }
}