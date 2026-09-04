// lib/services/pinned_players_provider.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String _prefsKey = 'pinned_player_ids';

/// ピン止めされた選手ID一覧を管理する Notifier（Riverpod 3.x系のNotifier API）。
/// SharedPreferences で端末に永続化されるため、アプリを再起動しても保持される。
class PinnedPlayersNotifier extends Notifier<Set<int>> {
  @override
  Set<int> build() {
    _load();
    return {};
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_prefsKey) ?? [];
    state = list.map((s) => int.tryParse(s)).whereType<int>().toSet();
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_prefsKey, state.map((id) => id.toString()).toList());
  }

  bool isPinned(int playerId) => state.contains(playerId);

  void toggle(int playerId) {
    final next = Set<int>.from(state);
    if (next.contains(playerId)) {
      next.remove(playerId);
    } else {
      next.add(playerId);
    }
    state = next;
    _save();
  }
}

final pinnedPlayersProvider = NotifierProvider<PinnedPlayersNotifier, Set<int>>(PinnedPlayersNotifier.new);

/// 選手リストを「ピン止めされた選手が先頭」になるよう並び替えるユーティリティ。
/// 元の並び順は、ピン止め同士・非ピン止め同士それぞれの中で維持される（安定ソート）。
List<T> sortWithPinnedFirst<T>(List<T> players, Set<int> pinnedIds, int Function(T) idOf) {
  final pinned = players.where((p) => pinnedIds.contains(idOf(p))).toList();
  final others = players.where((p) => !pinnedIds.contains(idOf(p))).toList();
  return [...pinned, ...others];
}