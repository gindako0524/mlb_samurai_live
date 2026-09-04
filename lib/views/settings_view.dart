// lib/views/settings_view.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/player.dart';
import '../services/language_provider.dart';
import '../services/pinned_players_provider.dart';

/// アプリ全体の設定画面。表示言語の切替と、ピン留め選手の一括管理を行う。
/// ここで変更した内容は全画面で共有される（言語設定・ピン留めともにグローバルな
/// Riverpodプロバイダーで管理されているため）。
class SettingsView extends ConsumerWidget {
  const SettingsView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lang = ref.watch(appLanguageProvider);
    final pinnedIds = ref.watch(pinnedPlayersProvider);
    final sortedPlayers = sortWithPinnedFirst(japanesePlayers, pinnedIds, (p) => p.id);

    return Scaffold(
      appBar: AppBar(
        title: const Text('設定', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('表示言語', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.blueAccent)),
          const SizedBox(height: 4),
          const Text(
            '打席結果・球種などの表示に反映されます（アプリ全体で共通）',
            style: TextStyle(fontSize: 11, color: Colors.white54),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(color: const Color(0xFF1E1E2C), borderRadius: BorderRadius.circular(10)),
            child: Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () {
                      if (lang != AppLanguage.ja) ref.read(appLanguageProvider.notifier).toggle();
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: lang == AppLanguage.ja ? Colors.blueAccent : Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      alignment: Alignment.center,
                      child: const Text('日本語', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    ),
                  ),
                ),
                Expanded(
                  child: GestureDetector(
                    onTap: () {
                      if (lang != AppLanguage.en) ref.read(appLanguageProvider.notifier).toggle();
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: lang == AppLanguage.en ? Colors.blueAccent : Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      alignment: Alignment.center,
                      child: const Text('English', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),
          const Text('ピン留め選手の管理', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.blueAccent)),
          const SizedBox(height: 4),
          const Text(
            'ここでピン留めした選手は、試合日程・ライブ観戦・詳細スタッツ・選手比較・ランキング・本日のまとめ、\nすべての画面で共通して先頭表示されます',
            style: TextStyle(fontSize: 11, color: Colors.white54),
          ),
          const SizedBox(height: 10),
          Material(
            color: const Color(0xFF1E1E2C),
            borderRadius: BorderRadius.circular(10),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: List.generate(sortedPlayers.length, (i) {
                final p = sortedPlayers[i];
                final isPinned = pinnedIds.contains(p.id);
                return Column(
                  children: [
                    ListTile(
                      leading: IconButton(
                        icon: Icon(
                          isPinned ? Icons.push_pin : Icons.push_pin_outlined,
                          color: isPinned ? Colors.amberAccent : Colors.white38,
                        ),
                        onPressed: () => ref.read(pinnedPlayersProvider.notifier).toggle(p.id),
                      ),
                      title: Text('${p.nameJa} (${p.teamName})'),
                      trailing: Text(
                        p.isPitcher ? '投手' : '打者',
                        style: const TextStyle(fontSize: 12, color: Colors.white54),
                      ),
                      onTap: () => ref.read(pinnedPlayersProvider.notifier).toggle(p.id),
                    ),
                    if (i < sortedPlayers.length - 1) const Divider(height: 1, color: Colors.white12),
                  ],
                );
              }),
            ),
          ),
        ],
      ),
    );
  }
}
