// lib/services/language_provider.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AppLanguage { ja, en }

const String _prefsKey = 'app_language';

/// アプリ全体で共有する表示言語設定（打席結果・球種等の表示に使用）。
/// SharedPreferences で端末に永続化されるため、アプリを再起動しても保持される。
class LanguageNotifier extends Notifier<AppLanguage> {
  @override
  AppLanguage build() {
    _load();
    return AppLanguage.ja;
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_prefsKey);
    if (saved == 'en') {
      state = AppLanguage.en;
    } else if (saved == 'ja') {
      state = AppLanguage.ja;
    }
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, state == AppLanguage.en ? 'en' : 'ja');
  }

  void toggle() {
    state = state == AppLanguage.ja ? AppLanguage.en : AppLanguage.ja;
    _save();
  }
}

final appLanguageProvider = NotifierProvider<LanguageNotifier, AppLanguage>(LanguageNotifier.new);
