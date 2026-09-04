// lib/services/contract_provider.dart
//
// 選手の契約金・契約年数データ。MLB公式APIには契約情報が一切存在しないため
// （Sportradar等の有料APIも年俸のみで契約年数・オプションは非公開、
// Cot's Contractsはボット対策で自動取得不可、MLB Trade Rumorsの契約データベースも
// robots.txtでページング用パラメータが禁止されており全件の自動取得はできない）、
// assets/contracts_data.json に手動でまとめたデータを読み込んで使う。
// 自動更新はされないため、選手が増減した場合はこのJSONを直接編集する。

import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/player.dart';

class PlayerContract {
  final int playerId;
  final String playerName;
  final String team;
  final int years;
  final int totalValueUsd;
  final int aavUsd;
  final int startYear;
  final int endYear;
  final String? notes;

  const PlayerContract({
    required this.playerId,
    required this.playerName,
    required this.team,
    required this.years,
    required this.totalValueUsd,
    required this.aavUsd,
    required this.startYear,
    required this.endYear,
    this.notes,
  });
}

/// 金額をざっくりした「$700.0M」形式の表記に整形する。
String formatUsd(int amount) {
  if (amount >= 1000000000) return '\$${(amount / 1000000000).toStringAsFixed(2)}B';
  if (amount >= 1000000) return '\$${(amount / 1000000).toStringAsFixed(1)}M';
  if (amount >= 1000) return '\$${(amount / 1000).toStringAsFixed(0)}K';
  return '\$$amount';
}

/// assets/contracts_data.json を読み込み、選手ID -> 契約情報のマップを返す。
final contractDataProvider = FutureProvider<Map<int, PlayerContract>>((ref) async {
  final raw = await rootBundle.loadString('assets/contracts_data.json');
  final data = json.decode(raw) as Map<String, dynamic>;
  final contracts = data['contracts'] as Map<String, dynamic>? ?? {};

  final result = <int, PlayerContract>{};
  for (final entry in contracts.entries) {
    final id = int.tryParse(entry.key);
    final c = entry.value as Map<String, dynamic>?;
    if (id == null || c == null) continue;
    result[id] = PlayerContract(
      playerId: id,
      playerName: c['playerName']?.toString() ?? '',
      team: c['team']?.toString() ?? '-',
      years: (c['years'] as num?)?.toInt() ?? 0,
      totalValueUsd: (c['totalValueUsd'] as num?)?.toInt() ?? 0,
      aavUsd: (c['aavUsd'] as num?)?.toInt() ?? 0,
      startYear: (c['startYear'] as num?)?.toInt() ?? 0,
      endYear: (c['endYear'] as num?)?.toInt() ?? 0,
      notes: c['notes']?.toString(),
    );
  }
  return result;
});

/// 契約総額の上位ランキング（$100M以上の契約のみ）。
/// ★ assets/contracts_data.json には日本人選手を例外的に全員(金額を問わず)
///   収録しているため、ランキング側では$100M未満を除外して「大型契約のみ」の
///   一覧を維持する。個人成績ページのContractInfoCardは金額を問わず全件表示。
const int _rankingMinValueUsd = 100000000;

final contractRankingProvider = FutureProvider<List<PlayerContract>>((ref) async {
  final map = await ref.watch(contractDataProvider.future);
  final list = map.values.where((c) => c.totalValueUsd >= _rankingMinValueUsd).toList();
  list.sort((a, b) => b.totalValueUsd.compareTo(a.totalValueUsd));
  return list;
});

bool isJapanesePlayerId(int id) => japanesePlayers.any((p) => p.id == id);
