// lib/widgets/language_toggle_button.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/language_provider.dart';

/// アプリ全体で共有する表示言語（日本語/英語）の切替ボタン。
/// AppBarのactionsに設置して使う想定。打席結果・球種等の表示に反映される。
class LanguageToggleButton extends ConsumerWidget {
  const LanguageToggleButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lang = ref.watch(appLanguageProvider);
    final isJa = lang == AppLanguage.ja;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => ref.read(appLanguageProvider.notifier).toggle(),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.blueAccent.withAlpha(30),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.blueAccent.withAlpha(100)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.translate, size: 14, color: Colors.blueAccent),
              const SizedBox(width: 4),
              Text(
                isJa ? '日本語' : 'EN',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blueAccent),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
