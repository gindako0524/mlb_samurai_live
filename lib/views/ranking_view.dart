// lib/views/ranking_view.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/ranking_provider.dart';
import '../services/pinned_players_provider.dart';
import '../services/contract_provider.dart';
import '../utils/stat_glossary.dart';
import '../models/player.dart';

String _categoryUniqueKey(StatCategory c) => c.specialType == 'normal' ? c.statKey : '${c.statKey}#${c.specialType}';

class RankingView extends StatelessWidget {
  const RankingView({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Row(
            children: [
              Icon(Icons.leaderboard, color: Colors.blueAccent),
              SizedBox(width: 8),
              Text('個人成績ランキング', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ],
          ),
          bottom: const TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              Tab(text: '成績ランキング'),
              Tab(text: '総合WARランキング'),
              Tab(text: '契約金ランキング'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _StatRankingTab(),
            _TotalWarRankingTab(),
            _ContractRankingTab(),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// タブ1: 成績ランキング
// ============================================================

class _StatRankingTab extends ConsumerStatefulWidget {
  const _StatRankingTab();

  @override
  ConsumerState<_StatRankingTab> createState() => _StatRankingTabState();
}

class _StatRankingTabState extends ConsumerState<_StatRankingTab> {
  RankingScope _scope = RankingScope.japan;
  LeagueSide _leagueSide = LeagueSide.al;
  PlayerType _playerType = PlayerType.batter;
  String _categoryKey = _categoryUniqueKey(batterCategories.first);
  HandFilter _handFilter = HandFilter.all;
  TeamRankMode _teamMode = TeamRankMode.aggregate;
  bool _teamAllTeams = true; // true=全30球団、false=リーグ内(AL/NL)
  bool _isCareer = false; // false=今シーズン、true=通算成績
  bool _activeOnly = false; // isCareer==trueの時のみ意味を持つ。true=現役選手のみ

  List<StatCategory> get _currentCategories {
    var base = _playerType == PlayerType.pitcher ? pitcherCategories : batterCategories;
    if (_isCareer) {
      // ★ 通算版はキャリア全登板ログ等が必要で現実的でないため除外
      base = base.where((c) => !['qs', 'qsRate', 'hqs', 'risp'].contains(c.specialType)).toList();
    }
    if (_scope != RankingScope.team) return base;
    // ★ チームごとランキングでは、通常カテゴリ(hitting/pitching)のみ対象とする
    return base.where((c) => c.specialType == 'normal' && c.group != 'fielding').toList();
  }

  StatCategory get _selectedCategory =>
      _currentCategories.firstWhere((c) => _categoryUniqueKey(c) == _categoryKey, orElse: () => _currentCategories.first);

  void _openCategoryPicker(BuildContext context) {
    showModalBottomSheet(
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
            return Column(
              children: [
                const SizedBox(height: 10),
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
                ),
                const Padding(
                  padding: EdgeInsets.all(14),
                  child: Text('成績カテゴリを選択', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.amberAccent)),
                ),
                const Divider(height: 1, color: Colors.white12),
                Expanded(
                  child: ListView.separated(
                    controller: scrollController,
                    itemCount: _currentCategories.length,
                    separatorBuilder: (_, _) => const Divider(height: 1, color: Colors.white12),
                    itemBuilder: (context, index) {
                      final cat = _currentCategories[index];
                      final key = _categoryUniqueKey(cat);
                      final isSelected = _categoryKey == key;
                      return ListTile(
                        title: Text(
                          cat.label,
                          style: TextStyle(
                            color: isSelected ? Colors.amberAccent : Colors.white,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                        trailing: isSelected ? const Icon(Icons.check, color: Colors.amberAccent) : null,
                        onTap: () {
                          setState(() => _categoryKey = key);
                          Navigator.pop(sheetContext);
                        },
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
  }

  @override
  Widget build(BuildContext context) {
    final params = RankingParams(
      scope: _scope,
      leagueSide: _leagueSide,
      playerType: _playerType,
      categoryKey: _categoryKey,
      teamMode: _teamMode,
      allTeams: _teamAllTeams,
      isCareer: _isCareer,
      activeOnly: _activeOnly,
    );
    final rankingAsync = ref.watch(rankingProvider(params));

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // --- 今シーズン / 通算 切替 ---
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(color: const Color(0xFF1E1E2C), borderRadius: BorderRadius.circular(10)),
                child: Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () => setState(() {
                          _isCareer = false;
                        }),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          decoration: BoxDecoration(
                            color: !_isCareer ? Colors.blueAccent : Colors.transparent,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          alignment: Alignment.center,
                          child: const Text('今シーズン', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                        ),
                      ),
                    ),
                    Expanded(
                      child: GestureDetector(
                        onTap: () => setState(() {
                          _isCareer = true;
                          if (_scope == RankingScope.team) {
                            _scope = RankingScope.japan;
                          }
                          if (['qs', 'qsRate', 'hqs', 'risp'].contains(_selectedCategory.specialType)) {
                            _categoryKey = _categoryUniqueKey(_currentCategories.first);
                          }
                        }),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          decoration: BoxDecoration(
                            color: _isCareer ? Colors.blueAccent : Colors.transparent,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          alignment: Alignment.center,
                          child: const Text('通算成績', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              if (_isCareer) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    ChoiceChip(
                      label: const Text('歴代 (引退選手も含む)'),
                      selected: !_activeOnly,
                      onSelected: (_) => setState(() => _activeOnly = false),
                    ),
                    ChoiceChip(
                      label: const Text('現役選手のみ'),
                      selected: _activeOnly,
                      onSelected: (_) => setState(() => _activeOnly = true),
                    ),
                  ],
                ),
              ],

              const SizedBox(height: 12),

              // --- スコープ選択 ---
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ChoiceChip(
                    label: const Text('日本人選手内'),
                    selected: _scope == RankingScope.japan,
                    onSelected: (_) => setState(() => _scope = RankingScope.japan),
                  ),
                  ChoiceChip(
                    label: const Text('リーグ内'),
                    selected: _scope == RankingScope.league,
                    onSelected: (_) => setState(() => _scope = RankingScope.league),
                  ),
                  ChoiceChip(
                    label: const Text('MLB全体 (上位30)'),
                    selected: _scope == RankingScope.mlb,
                    onSelected: (_) => setState(() => _scope = RankingScope.mlb),
                  ),
                  if (!_isCareer)
                    ChoiceChip(
                      label: const Text('チームごと'),
                      selected: _scope == RankingScope.team,
                      onSelected: (_) {
                        setState(() {
                          _scope = RankingScope.team;
                          _categoryKey = _categoryUniqueKey(_currentCategories.first);
                        });
                      },
                    ),
                ],
              ),

              if (_scope == RankingScope.league) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    ChoiceChip(
                      label: const Text('ア・リーグ (AL)'),
                      selected: _leagueSide == LeagueSide.al,
                      onSelected: (_) => setState(() => _leagueSide = LeagueSide.al),
                    ),
                    ChoiceChip(
                      label: const Text('ナ・リーグ (NL)'),
                      selected: _leagueSide == LeagueSide.nl,
                      onSelected: (_) => setState(() => _leagueSide = LeagueSide.nl),
                    ),
                  ],
                ),
              ],

              if (_scope == RankingScope.team) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    ChoiceChip(
                      label: const Text('全30球団'),
                      selected: _teamAllTeams,
                      onSelected: (_) => setState(() => _teamAllTeams = true),
                    ),
                    ChoiceChip(
                      label: const Text('ア・リーグのみ'),
                      selected: !_teamAllTeams && _leagueSide == LeagueSide.al,
                      onSelected: (_) => setState(() {
                        _teamAllTeams = false;
                        _leagueSide = LeagueSide.al;
                      }),
                    ),
                    ChoiceChip(
                      label: const Text('ナ・リーグのみ'),
                      selected: !_teamAllTeams && _leagueSide == LeagueSide.nl,
                      onSelected: (_) => setState(() {
                        _teamAllTeams = false;
                        _leagueSide = LeagueSide.nl;
                      }),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(color: const Color(0xFF1E1E2C), borderRadius: BorderRadius.circular(10)),
                  child: Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: () => setState(() => _teamMode = TeamRankMode.aggregate),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            decoration: BoxDecoration(
                              color: _teamMode == TeamRankMode.aggregate ? Colors.blueAccent : Colors.transparent,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            alignment: Alignment.center,
                            child: const Text('チーム成績', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                          ),
                        ),
                      ),
                      Expanded(
                        child: GestureDetector(
                          onTap: () => setState(() => _teamMode = TeamRankMode.topPlayer),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            decoration: BoxDecoration(
                              color: _teamMode == TeamRankMode.topPlayer ? Colors.blueAccent : Colors.transparent,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            alignment: Alignment.center,
                            child: const Text('チームTOP成績', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _teamMode == TeamRankMode.aggregate ? 'チーム全体の合計/平均成績でランキングします' : '各チームの最上位選手だけを抜き出して比較します',
                  style: const TextStyle(fontSize: 11, color: Colors.white38),
                ),
                if (_isCareer && _teamMode == TeamRankMode.aggregate) ...[
                  const SizedBox(height: 6),
                  const Text(
                    '※チーム成績の通算は正確な集計が難しいため非対応です（チームTOP成績なら通算も対応）',
                    style: TextStyle(fontSize: 11, color: Colors.orangeAccent),
                  ),
                ],
              ],

              const SizedBox(height: 12),

              // --- 投手 / 打者 切替 ---
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E1E2C),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () {
                          setState(() {
                            _playerType = PlayerType.batter;
                            _categoryKey = _categoryUniqueKey(batterCategories.first);
                            _handFilter = HandFilter.all;
                          });
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          decoration: BoxDecoration(
                            color: _playerType == PlayerType.batter ? Colors.blueAccent : Colors.transparent,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          alignment: Alignment.center,
                          child: const Text('🏏 打者', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                        ),
                      ),
                    ),
                    Expanded(
                      child: GestureDetector(
                        onTap: () {
                          setState(() {
                            _playerType = PlayerType.pitcher;
                            _categoryKey = _categoryUniqueKey(pitcherCategories.first);
                            _handFilter = HandFilter.all;
                          });
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          decoration: BoxDecoration(
                            color: _playerType == PlayerType.pitcher ? Colors.blueAccent : Colors.transparent,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          alignment: Alignment.center,
                          child: const Text('⚾ 投手', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 12),

              // --- 成績カテゴリ選択（タップでボトムシートを開く方式） ---
              InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () => _openCategoryPicker(context),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E1E2C),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.amberAccent.withAlpha(80)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.bar_chart, size: 18, color: Colors.amberAccent),
                          const SizedBox(width: 8),
                          Text(
                            _selectedCategory.label,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.amberAccent),
                          ),
                          StatInfoIcon(_selectedCategory.statKey, size: 14),
                        ],
                      ),
                      const Icon(Icons.unfold_more, size: 20, color: Colors.white54),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 10),

              // --- 左右フィルター（チーム成績モードでは意味を持たないため非表示） ---
              if (!(_scope == RankingScope.team && _teamMode == TeamRankMode.aggregate))
                Wrap(
                  spacing: 8,
                  children: [
                    ChoiceChip(
                      label: const Text('全体'),
                      selected: _handFilter == HandFilter.all,
                      onSelected: (_) => setState(() => _handFilter = HandFilter.all),
                    ),
                    ChoiceChip(
                      label: Text(_playerType == PlayerType.pitcher ? '右投手' : '右打者'),
                      selected: _handFilter == HandFilter.right,
                      onSelected: (_) => setState(() => _handFilter = HandFilter.right),
                    ),
                    ChoiceChip(
                      label: Text(_playerType == PlayerType.pitcher ? '左投手' : '左打者'),
                      selected: _handFilter == HandFilter.left,
                      onSelected: (_) => setState(() => _handFilter = HandFilter.left),
                    ),
                  ],
                ),

              if (_scope == RankingScope.league || _scope == RankingScope.mlb) ...[
                const SizedBox(height: 8),
                const Text(
                  '※リーグ内・MLB全体は規定投球回・規定打席数に達した選手のみ表示しています',
                  style: TextStyle(fontSize: 11, color: Colors.white38),
                ),
              ],

              if (_scope != RankingScope.japan &&
                  ['qs', 'qsRate', 'hqs', 'risp'].contains(_selectedCategory.specialType)) ...[
                const SizedBox(height: 8),
                Text(
                  _selectedCategory.specialType == 'risp'
                      ? '※この項目は規定打席数に達した打者を対象に個別集計するため、上位20人までの表示になります'
                      : '※この項目はMLB全体の投手を対象に個別集計するため、上位20人までの表示になります',
                  style: const TextStyle(fontSize: 11, color: Colors.white38),
                ),
              ],
            ],
          ),
        ),
        const Divider(height: 1, color: Colors.white12),

        Expanded(
          child: rankingAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (err, _) => Center(
              child: Text('ランキング取得エラー\n$err', textAlign: TextAlign.center, style: const TextStyle(color: Colors.redAccent)),
            ),
            data: (entries) {
              final bypassHandFilter = _scope == RankingScope.team && _teamMode == TeamRankMode.aggregate;
              final filteredAll = (bypassHandFilter || _handFilter == HandFilter.all)
                  ? entries
                  : entries.where((e) => e.handCode == (_handFilter == HandFilter.right ? 'R' : 'L')).toList();
              final filtered = filteredAll.take(30).toList();

              if (filtered.isEmpty) {
                return const Center(
                  child: Text('データを取得できませんでした', style: TextStyle(color: Colors.white54)),
                );
              }
              return ListView.separated(
                padding: const EdgeInsets.all(12),
                itemCount: filtered.length,
                separatorBuilder: (_, _) => const Divider(height: 1, color: Colors.white12),
                itemBuilder: (context, index) {
                  return _RankingRow(rank: index + 1, entry: filtered[index]);
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

// ============================================================
// タブ2: 総合WARランキング
// ============================================================

class _TotalWarRankingTab extends ConsumerStatefulWidget {
  const _TotalWarRankingTab();

  @override
  ConsumerState<_TotalWarRankingTab> createState() => _TotalWarRankingTabState();
}

class _TotalWarRankingTabState extends ConsumerState<_TotalWarRankingTab> {
  RankingScope _scope = RankingScope.japan;
  LeagueSide _leagueSide = LeagueSide.al;

  @override
  Widget build(BuildContext context) {
    final params = TotalWarParams(scope: _scope, leagueSide: _leagueSide);
    final rankingAsync = ref.watch(totalWarRankingProvider(params));

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '投打の区別なく、rWAR(Baseball-Reference)の総合値でランキングします。二刀流選手は打撃+投手を合算します。',
                style: TextStyle(fontSize: 11, color: Colors.white54),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ChoiceChip(
                    label: const Text('日本人選手内'),
                    selected: _scope == RankingScope.japan,
                    onSelected: (_) => setState(() => _scope = RankingScope.japan),
                  ),
                  ChoiceChip(
                    label: const Text('リーグ内'),
                    selected: _scope == RankingScope.league,
                    onSelected: (_) => setState(() => _scope = RankingScope.league),
                  ),
                  ChoiceChip(
                    label: const Text('MLB全体 (上位30)'),
                    selected: _scope == RankingScope.mlb,
                    onSelected: (_) => setState(() => _scope = RankingScope.mlb),
                  ),
                ],
              ),
              if (_scope == RankingScope.league) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    ChoiceChip(
                      label: const Text('ア・リーグ (AL)'),
                      selected: _leagueSide == LeagueSide.al,
                      onSelected: (_) => setState(() => _leagueSide = LeagueSide.al),
                    ),
                    ChoiceChip(
                      label: const Text('ナ・リーグ (NL)'),
                      selected: _leagueSide == LeagueSide.nl,
                      onSelected: (_) => setState(() => _leagueSide = LeagueSide.nl),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
        const Divider(height: 1, color: Colors.white12),
        Expanded(
          child: rankingAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (err, _) => Center(
              child: Text('ランキング取得エラー\n$err', textAlign: TextAlign.center, style: const TextStyle(color: Colors.redAccent)),
            ),
            data: (entries) {
              if (entries.isEmpty) {
                return const Center(
                  child: Text('データを取得できませんでした', style: TextStyle(color: Colors.white54)),
                );
              }
              return ListView.separated(
                padding: const EdgeInsets.all(12),
                itemCount: entries.length,
                separatorBuilder: (_, _) => const Divider(height: 1, color: Colors.white12),
                itemBuilder: (context, index) {
                  return _RankingRow(rank: entries[index].rank, entry: entries[index]);
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

// ============================================================
// タブ3: 契約金ランキング
// ============================================================

class _ContractRankingTab extends ConsumerWidget {
  const _ContractRankingTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rankingAsync = ref.watch(contractRankingProvider);
    final japaneseLookup = {for (final p in japanesePlayers) p.id: p.nameJa};

    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          color: Colors.orangeAccent.withAlpha(15),
          child: const Text(
            'MLB公式APIには契約金・契約年数のデータが存在しないため、公開報道をもとに手動でまとめたデータです。'
            '自動更新はされないため一部選手のみの掲載で、金額は目安としてご利用ください。',
            style: TextStyle(fontSize: 11, color: Colors.orangeAccent),
          ),
        ),
        const Divider(height: 1, color: Colors.white12),
        Expanded(
          child: rankingAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (err, _) => Center(
              child: Text('契約金データ取得エラー\n$err', textAlign: TextAlign.center, style: const TextStyle(color: Colors.redAccent)),
            ),
            data: (contracts) {
              if (contracts.isEmpty) {
                return const Center(child: Text('契約金データがありません', style: TextStyle(color: Colors.white54)));
              }
              return ListView.separated(
                padding: const EdgeInsets.all(12),
                itemCount: contracts.length,
                separatorBuilder: (_, _) => const Divider(height: 1, color: Colors.white12),
                itemBuilder: (context, index) {
                  final c = contracts[index];
                  final isJp = isJapanesePlayerId(c.playerId);
                  final entry = RankingEntry(
                    rank: index + 1,
                    name: c.playerName,
                    nameJa: isJp ? japaneseLookup[c.playerId] : null,
                    team: c.team,
                    displayValue: '${formatUsd(c.totalValueUsd)} (${c.years}年)',
                    isJapanese: isJp,
                    personId: c.playerId,
                  );
                  return _RankingRow(rank: index + 1, entry: entry);
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

// ============================================================
// 共通: ランキング1行の表示ウィジェット
// ============================================================

class _RankingRow extends ConsumerWidget {
  final int rank;
  final RankingEntry entry;

  const _RankingRow({required this.rank, required this.entry});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final e = entry;
    final isPinned = e.personId != null && ref.watch(pinnedPlayersProvider).contains(e.personId);
    return Container(
      color: e.isJapanese ? Colors.blueAccent.withAlpha(20) : Colors.transparent,
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      child: Row(
        children: [
          SizedBox(
            width: 36,
            child: Text(
              '$rank',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 15,
                color: rank <= 3 ? Colors.amberAccent : Colors.white70,
              ),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (e.isJapanese) const Text('🇯🇵 ', style: TextStyle(fontSize: 12)),
                    if (isPinned) const Padding(
                      padding: EdgeInsets.only(right: 4),
                      child: Icon(Icons.push_pin, size: 12, color: Colors.amberAccent),
                    ),
                    Flexible(
                      child: Text(
                        e.nameJa ?? e.name,
                        style: TextStyle(
                          fontWeight: e.isJapanese ? FontWeight.bold : FontWeight.normal,
                          fontSize: 14,
                          color: e.isJapanese ? Colors.amberAccent : Colors.white,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                Text(e.team, style: const TextStyle(fontSize: 11, color: Colors.white54)),
              ],
            ),
          ),
          Text(
            e.displayValue,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.white),
          ),
          if (e.isJapanese && e.personId != null)
            IconButton(
              visualDensity: VisualDensity.compact,
              icon: Icon(
                isPinned ? Icons.push_pin : Icons.push_pin_outlined,
                size: 18,
                color: isPinned ? Colors.amberAccent : Colors.white38,
              ),
              onPressed: () => ref.read(pinnedPlayersProvider.notifier).toggle(e.personId!),
            ),
        ],
      ),
    );
  }
}