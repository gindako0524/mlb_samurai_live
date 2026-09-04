// lib/services/statcast_provider.dart
//
// Baseball Savant(baseballsavant.mlb.com)のリーダーボードCSVエクスポートから
// Statcast系の詳細指標(Exit Velocity・Launch Angle・Barrel%・Hard Hit%・
// Sprint Speed・Whiff%・OAA)を取得する。
//
// ★ Baseball Savantを選定した理由: robots.txtが全許可(Disallow指定なし)で、
//   かつMLB Advanced Media自身が運営する公式サイトのため。Cot's Contracts
//   (Anubisによるボット対策あり)やMLB Trade Rumors(robots.txtがページング
//   パラメータを禁止)のような、自動アクセスを制限しているサイトは使用しない
//   という方針に基づく。
//
// ★ CSW%(Called Strike + Whiff%)・UZR・DRS・BsR はこのリーダーボードにも
//   項目自体は存在するが、実測した結果すべての行で値が常に空だったため
//   (2026年9月時点)、取得対象から除外している。UZR/DRS/BsRはそもそも
//   FanGraphs・Baseball Info Solutions独自の非公開算出ロジックであり、
//   無料の公式ソースが存在しない。
//
// ★ min=q(規定打席/規定投球回に達した選手のみ)のリーダーボードを使うため、
//   出場機会が少ない選手はここでは値が取得できない(nullのまま非表示になる)。
//
// ★ リーグ全体を1回のCSV取得でまとめて取ってきて選手IDでルックアップする
//   方式。個別選手ごとにAPIを叩く必要がないため、選手個別ページを何回開いても
//   追加のリクエストは発生しない(Riverpodのプロバイダキャッシュにより
//   アプリのセッション中は再利用される)。

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

const String _savantUserAgent = 'Mozilla/5.0 (compatible; MLBSamuraiLive/1.0)';

/// 簡易CSVパーサ(ダブルクォート内のカンマ・エスケープされた""に対応)
List<List<String>> _parseCsv(String data) {
  final rows = <List<String>>[];
  var i = 0;
  final len = data.length;
  var row = <String>[];
  final buf = StringBuffer();
  var inQuotes = false;
  while (i < len) {
    final c = data[i];
    if (inQuotes) {
      if (c == '"') {
        if (i + 1 < len && data[i + 1] == '"') {
          buf.write('"');
          i += 2;
          continue;
        }
        inQuotes = false;
        i++;
        continue;
      }
      buf.write(c);
      i++;
      continue;
    } else {
      if (c == '"') {
        inQuotes = true;
        i++;
        continue;
      }
      if (c == ',') {
        row.add(buf.toString());
        buf.clear();
        i++;
        continue;
      }
      if (c == '\r') {
        i++;
        continue;
      }
      if (c == '\n') {
        row.add(buf.toString());
        buf.clear();
        rows.add(row);
        row = [];
        i++;
        continue;
      }
      buf.write(c);
      i++;
      continue;
    }
  }
  if (buf.isNotEmpty || row.isNotEmpty) {
    row.add(buf.toString());
    rows.add(row);
  }
  return rows;
}

Future<List<Map<String, String>>> _fetchSavantCsv(String url) async {
  final res = await http.get(Uri.parse(url), headers: {'User-Agent': _savantUserAgent});
  if (res.statusCode != 200) return [];
  var body = res.body;
  if (body.isNotEmpty && body.codeUnitAt(0) == 0xFEFF) {
    body = body.substring(1);
  }
  final rows = _parseCsv(body);
  if (rows.isEmpty) return [];
  final header = rows.first;
  final out = <Map<String, String>>[];
  for (final r in rows.skip(1)) {
    if (r.length < header.length) continue;
    final map = <String, String>{};
    for (var i = 0; i < header.length; i++) {
      map[header[i]] = r[i];
    }
    out.add(map);
  }
  return out;
}

class BatterStatcastRow {
  final double? exitVelocityAvg;
  final double? launchAngleAvg;
  final double? barrelRate;
  final double? hardHitPercent;
  final double? sprintSpeed;

  const BatterStatcastRow({this.exitVelocityAvg, this.launchAngleAvg, this.barrelRate, this.hardHitPercent, this.sprintSpeed});
}

double? _d(String? s) {
  if (s == null || s.isEmpty) return null;
  return double.tryParse(s);
}

/// 打者Statcastリーダーボード(規定打席到達者のみ)。player_id(MLBAM ID)でルックアップ。
final statcastBatterLeaderboardProvider = FutureProvider<Map<int, BatterStatcastRow>>((ref) async {
  const url =
      'https://baseballsavant.mlb.com/leaderboard/custom?year=2026&type=batter&filter=&min=q'
      '&selections=exit_velocity_avg,launch_angle_avg,barrel_batted_rate,hard_hit_percent,sprint_speed'
      '&chart=false&x=xba&y=xba&r=no&chartType=beeswarm&csv=true';
  try {
    final rows = await _fetchSavantCsv(url);
    final map = <int, BatterStatcastRow>{};
    for (final r in rows) {
      final id = int.tryParse(r['player_id'] ?? '');
      if (id == null) continue;
      map[id] = BatterStatcastRow(
        exitVelocityAvg: _d(r['exit_velocity_avg']),
        launchAngleAvg: _d(r['launch_angle_avg']),
        barrelRate: _d(r['barrel_batted_rate']),
        hardHitPercent: _d(r['hard_hit_percent']),
        sprintSpeed: _d(r['sprint_speed']),
      );
    }
    return map;
  } catch (_) {
    return {};
  }
});

/// 投手Whiff%リーダーボード(規定投球回到達者のみ)。player_idでルックアップ。
final statcastPitcherWhiffProvider = FutureProvider<Map<int, double>>((ref) async {
  const url =
      'https://baseballsavant.mlb.com/leaderboard/custom?year=2026&type=pitcher&filter=&min=q'
      '&selections=whiff_percent&chart=false&x=xba&y=xba&r=no&chartType=beeswarm&csv=true';
  try {
    final rows = await _fetchSavantCsv(url);
    final map = <int, double>{};
    for (final r in rows) {
      final id = int.tryParse(r['player_id'] ?? '');
      final v = _d(r['whiff_percent']);
      if (id == null || v == null) continue;
      map[id] = v;
    }
    return map;
  } catch (_) {
    return {};
  }
});

/// 守備OAA(Outs Above Average)リーダーボード(全ポジション対象、規定守備イニング不問)。
final oaaLeaderboardProvider = FutureProvider<Map<int, double>>((ref) async {
  const url =
      'https://baseballsavant.mlb.com/leaderboard/outs_above_average?type=Fielder&startYear=2026&endYear=2026'
      '&split=no&team=&range=year&min=1&pos=&roles=&viz=hide&csv=true';
  try {
    final rows = await _fetchSavantCsv(url);
    final map = <int, double>{};
    for (final r in rows) {
      final id = int.tryParse(r['player_id'] ?? '');
      final v = _d(r['outs_above_average']);
      if (id == null || v == null) continue;
      map[id] = v;
    }
    return map;
  } catch (_) {
    return {};
  }
});
