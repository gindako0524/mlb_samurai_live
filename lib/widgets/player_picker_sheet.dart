// lib/views/widgets/player_picker_sheet.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/player.dart';
import '../services/pinned_players_provider.dart';

/// ピン留めアイコン付きの選手選択ボトムシート。
/// ピン留めされた選手が常にリストの先頭に表示される。
/// 全画面（詳細スタッツ・ライブ観戦・選手比較）で共通利用する。
Future<JapanesePlayer?> showPlayerPickerSheet(
  BuildContext context, {
  required List<JapanesePlayer> candidates,
  int? currentPlayerId,
  String title = '選手を選択',
}) {
  return showModalBottomSheet<JapanesePlayer>(
    context: context,
    backgroundColor: const Color(0xFF161622),
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
    builder: (sheetContext) {
      return DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.3,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) {
          return Consumer(
            builder: (context, ref, _) {
              final pinnedIds = ref.watch(pinnedPlayersProvider);
              final sorted = sortWithPinnedFirst(candidates, pinnedIds, (p) => p.id);

              return Column(
                children: [
                  const SizedBox(height: 10),
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.blueAccent)),
                      ],
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.only(bottom: 8),
                    child: Text('📌 でピン留め（先頭に固定表示）', style: TextStyle(fontSize: 11, color: Colors.white38)),
                  ),
                  const Divider(height: 1, color: Colors.white12),
                  Expanded(
                    child: ListView.separated(
                      controller: scrollController,
                      itemCount: sorted.length,
                      separatorBuilder: (_, _) => const Divider(height: 1, color: Colors.white12),
                      itemBuilder: (context, index) {
                        final p = sorted[index];
                        final isSelected = p.id == currentPlayerId;
                        final isPinned = pinnedIds.contains(p.id);
                        return ListTile(
                          leading: IconButton(
                            icon: Icon(
                              isPinned ? Icons.push_pin : Icons.push_pin_outlined,
                              color: isPinned ? Colors.amberAccent : Colors.white38,
                              size: 20,
                            ),
                            onPressed: () => ref.read(pinnedPlayersProvider.notifier).toggle(p.id),
                          ),
                          title: Text(
                            '${p.nameJa} (${p.teamName})',
                            style: TextStyle(
                              color: isSelected ? Colors.blueAccent : Colors.white,
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                            ),
                          ),
                          trailing: isSelected ? const Icon(Icons.check, color: Colors.blueAccent) : null,
                          onTap: () => Navigator.pop(sheetContext, p),
                        );
                      },
                    ),
                  ),
                ],
              );
            },
          );
        },
      );
    },
  );
}