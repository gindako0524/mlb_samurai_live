// lib/views/compare_view.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/player.dart';
import '../services/schedule_provider.dart';
import '../services/ranking_provider.dart'
    show PlayerType, StatCategory, batterCategories, pitcherCategories, countHqs, countQs;
import '../widgets/player_picker_sheet.dart';
import '../services/pinned_players_provider.dart';
import '../utils/stat_glossary.dart';

class CompareView extends ConsumerStatefulWidget {
  const CompareView({super.key});

  @override
  ConsumerState<CompareView> createState() => _CompareViewState();
}

class _CompareViewState extends ConsumerState<CompareView> {
  PlayerType _playerType = PlayerType.batter;
  JapanesePlayer? _player1;
  JapanesePlayer? _player2;

  Map<String, dynamic>? _stat1;
  Map<String, dynamic>? _stat2;
  int? _hqs1;
  int? _hqs2;
  int? _qs1;
  int? _qs2;
  bool _isLoading = false;
  String? _error;

  List<JapanesePlayer> get _candidates => japanesePlayers
      .where((p) => p.isPitcher == (_playerType == PlayerType.pitcher) || (_playerType == PlayerType.pitcher && p.id == 660271))
      .toList();

  List<StatCategory> get _categories {
    final list = _playerType == PlayerType.pitcher ? pitcherCategories : batterCategories;
    // 比較表は "season" 成績（hitting/pitching）で完結する項目を使用。
    // QS数(qs)・QS率(qsRate)・HQS数(hqs)は既に取得済みのgameLogデータから計算できるため含める。
    // RISP・失策(fielding)は別APIが必要なため対象外。
    return list
        .where((c) =>
            (c.specialType == 'normal' || c.specialType == 'qs' || c.specialType == 'qsRate' || c.specialType == 'hqs') &&
            c.group == (_playerType == PlayerType.pitcher ? 'pitching' : 'hitting'))
        .toList();
  }

  void _resetSelection() {
    setState(() {
      _player1 = null;
      _player2 = null;
      _stat1 = null;
      _stat2 = null;
      _hqs1 = null;
      _hqs2 = null;
      _qs1 = null;
      _qs2 = null;
      _error = null;
    });
  }

  Map<String, dynamic> _extractSeasonStat(Map<String, dynamic> data) {
    final statsList = data['stats'] as List<dynamic>? ?? [];
    for (final s in statsList) {
      final typeName = s['type']?['displayName']?.toString().toLowerCase() ?? '';
      if (typeName == 'season') {
        final splits = s['splits'] as List<dynamic>? ?? [];
        if (splits.isNotEmpty) return splits.first['stat'] as Map<String, dynamic>? ?? {};
      }
    }
    return {};
  }

  // ★ HQS集計用に、当該選手の「全登板」のstatマップ一覧を抽出（既に取得済みのgameLogデータを再利用）
  List<Map<String, dynamic>> _extractGameLog(Map<String, dynamic> data) {
    final statsList = data['stats'] as List<dynamic>? ?? [];
    for (final s in statsList) {
      final typeName = s['type']?['displayName']?.toString().toLowerCase() ?? '';
      if (typeName == 'gamelog') {
        final splits = s['splits'] as List<dynamic>? ?? [];
        return splits.map((g) => (g['stat'] as Map<String, dynamic>?) ?? {}).toList();
      }
    }
    return [];
  }

  Future<void> _fetchBoth() async {
    if (_player1 == null || _player2 == null) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final api = ref.read(apiServiceProvider);
      final isPitcher = _playerType == PlayerType.pitcher;
      final results = await Future.wait([
        api.getPlayerGameLog(_player1!.id, isPitcher: isPitcher),
        api.getPlayerGameLog(_player2!.id, isPitcher: isPitcher),
      ]);
      if (!mounted) return;
      setState(() {
        _stat1 = _extractSeasonStat(results[0]);
        _stat2 = _extractSeasonStat(results[1]);
        if (isPitcher) {
          final log1 = _extractGameLog(results[0]);
          final log2 = _extractGameLog(results[1]);
          _hqs1 = countHqs(log1);
          _hqs2 = countHqs(log2);
          _qs1 = countQs(log1);
          _qs2 = countQs(log2);
        } else {
          _hqs1 = null;
          _hqs2 = null;
          _qs1 = null;
          _qs2 = null;
        }
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '成績取得エラー: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _pickPlayer({required bool isFirst}) async {
    final excludeId = isFirst ? _player2?.id : _player1?.id;
    final options = _candidates.where((p) => p.id != excludeId).toList();

    final selected = await showPlayerPickerSheet(
      context,
      candidates: options,
      currentPlayerId: isFirst ? _player1?.id : _player2?.id,
      title: isFirst ? '選手1を選択' : '選手2を選択',
    );

    if (selected != null) {
      setState(() {
        if (isFirst) {
          _player1 = selected;
        } else {
          _player2 = selected;
        }
        _stat1 = null;
        _stat2 = null;
      });
      if (_player1 != null && _player2 != null) {
        _fetchBoth();
      }
    }
  }

  /// カテゴリに応じた「表示用の値(raw)」を取得する。
  /// QS数・QS率は season 成績に存在しないため、全登板ログから集計した qsCount を使う。
  dynamic _rawFor(StatCategory cat, Map<String, dynamic>? stat, int? qsCount) {
    if (cat.specialType == 'qsRate') {
      if (stat == null || qsCount == null) return null;
      final gs = double.tryParse(stat['gamesStarted']?.toString() ?? '') ?? 0.0;
      if (gs <= 0) return null;
      return qsCount / gs * 100;
    }
    if (cat.specialType == 'qs') {
      return qsCount;
    }
    if (stat == null) return null;
    return stat[cat.statKey];
  }

  String _formatValue(StatCategory cat, dynamic raw) {
    if (raw == null) return '-';
    if (cat.specialType == 'qsRate') {
      final d = double.tryParse(raw.toString());
      return d != null ? '${d.toStringAsFixed(1)}%' : '-';
    }
    if (cat.isRate) {
      final d = double.tryParse(raw.toString());
      if (d == null) return raw.toString();
      if (d < 1.0 && d > -1.0) {
        return '.${(d.abs() * 1000).round().toString().padLeft(3, '0')}';
      }
      return d.toStringAsFixed(3);
    }
    final d = double.tryParse(raw.toString());
    if (d == null) return raw.toString();
    return d.toStringAsFixed(cat.decimals);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('選手比較', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // --- Step1: 投手 / 打者 ---
            const Text('① 比較する種別を選択', style: TextStyle(fontSize: 13, color: Colors.white54)),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(color: const Color(0xFF1E1E2C), borderRadius: BorderRadius.circular(10)),
              child: Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () {
                        if (_playerType != PlayerType.batter) {
                          setState(() => _playerType = PlayerType.batter);
                          _resetSelection();
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: _playerType == PlayerType.batter ? Colors.blueAccent : Colors.transparent,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        alignment: Alignment.center,
                        child: const Text('🏏 打者', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ),
                  Expanded(
                    child: GestureDetector(
                      onTap: () {
                        if (_playerType != PlayerType.pitcher) {
                          setState(() => _playerType = PlayerType.pitcher);
                          _resetSelection();
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: _playerType == PlayerType.pitcher ? Colors.blueAccent : Colors.transparent,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        alignment: Alignment.center,
                        child: const Text('⚾ 投手', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // --- Step2: 選手1 / 選手2 ---
            const Text('② 比較する2人を選択', style: TextStyle(fontSize: 13, color: Colors.white54)),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(child: _PlayerPickButton(player: _player1, hint: '選手1', onTap: () => _pickPlayer(isFirst: true))),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Text('VS', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.amberAccent)),
                ),
                Expanded(child: _PlayerPickButton(player: _player2, hint: '選手2', onTap: () => _pickPlayer(isFirst: false))),
              ],
            ),

            const SizedBox(height: 24),

            // --- Step3: 成績比較 ---
            if (_isLoading)
              const Center(child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator()))
            else if (_error != null)
              Center(child: Text(_error!, style: const TextStyle(color: Colors.redAccent)))
            else if (_stat1 != null && _stat2 != null) ...[
              const Text('③ 成績比較 (2026年シーズン)', style: TextStyle(fontSize: 13, color: Colors.white54)),
              const SizedBox(height: 10),
              Card(
                color: const Color(0xFF1E1E2C),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              _player1!.nameJa,
                              textAlign: TextAlign.center,
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.blueAccent),
                            ),
                          ),
                          const SizedBox(width: 80),
                          Expanded(
                            child: Text(
                              _player2!.nameJa,
                              textAlign: TextAlign.center,
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.orangeAccent),
                            ),
                          ),
                        ],
                      ),
                      const Divider(height: 20, color: Colors.white12),
                      ..._categories.map((cat) {
                        final dynamic raw1 = cat.specialType == 'hqs'
                            ? _hqs1
                            : (cat.specialType == 'qs' ? _qs1 : _rawFor(cat, _stat1, _qs1));
                        final dynamic raw2 = cat.specialType == 'hqs'
                            ? _hqs2
                            : (cat.specialType == 'qs' ? _qs2 : _rawFor(cat, _stat2, _qs2));
                        final v1 = double.tryParse(raw1?.toString() ?? '');
                        final v2 = double.tryParse(raw2?.toString() ?? '');

                        bool p1Better = false;
                        bool p2Better = false;
                        if (v1 != null && v2 != null && v1 != v2) {
                          if (cat.ascending) {
                            p1Better = v1 < v2;
                            p2Better = v2 < v1;
                          } else {
                            p1Better = v1 > v2;
                            p2Better = v2 > v1;
                          }
                        }

                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  _formatValue(cat, raw1),
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontWeight: p1Better ? FontWeight.bold : FontWeight.normal,
                                    fontSize: 14,
                                    color: p1Better ? Colors.amberAccent : Colors.white,
                                  ),
                                ),
                              ),
                              SizedBox(
                                width: 80,
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Flexible(
                                      child: Text(
                                        cat.label,
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(fontSize: 11, color: Colors.white54),
                                      ),
                                    ),
                                    StatInfoIcon(cat.statKey, size: 11),
                                  ],
                                ),
                              ),
                              Expanded(
                                child: Text(
                                  _formatValue(cat, raw2),
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontWeight: p2Better ? FontWeight.bold : FontWeight.normal,
                                    fontSize: 14,
                                    color: p2Better ? Colors.amberAccent : Colors.white,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      }),
                    ],
                  ),
                ),
              ),
            ] else
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: Text('2人選択すると自動で成績比較が表示されます', style: TextStyle(color: Colors.white38, fontSize: 12)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _PlayerPickButton extends ConsumerWidget {
  final JapanesePlayer? player;
  final String hint;
  final VoidCallback onTap;

  const _PlayerPickButton({required this.player, required this.hint, required this.onTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isPinned = player != null && ref.watch(pinnedPlayersProvider).contains(player!.id);
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
        decoration: BoxDecoration(
          color: const Color(0xFF1E1E2C),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: player != null ? Colors.blueAccent.withAlpha(150) : Colors.white24),
        ),
        child: Column(
          children: [
            Icon(Icons.person, color: player != null ? Colors.blueAccent : Colors.white38, size: 22),
            const SizedBox(height: 6),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    player != null ? player!.nameJa : '$hintを選択',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: player != null ? Colors.white : Colors.white38,
                    ),
                  ),
                ),
                if (isPinned) ...[
                  const SizedBox(width: 4),
                  const Icon(Icons.push_pin, size: 12, color: Colors.amberAccent),
                ],
              ],
            ),
            if (player != null)
              Text(player!.teamName, style: const TextStyle(fontSize: 11, color: Colors.white54)),
          ],
        ),
      ),
    );
  }
}