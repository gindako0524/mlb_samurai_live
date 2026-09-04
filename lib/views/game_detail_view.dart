// lib/views/game_detail_view.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/player.dart';
import '../services/schedule_provider.dart';
import '../services/pinned_players_provider.dart';
import '../services/language_provider.dart';
import '../services/head_to_head_service.dart';
import '../widgets/language_toggle_button.dart';
import '../utils/mlb_translations.dart';
import '../utils/live_stat_calc.dart';
import '../widgets/mini_strike_zone.dart';
import '../widgets/at_bat_detail_dialog.dart';
import '../utils/base_out_state.dart';

/// 試合のスタメン・全選手の打席結果・投手成績を見るためのボックススコア画面。
/// 日本人選手専用の「ライブ観戦」画面（live_view.dart）とは別の、
/// 両チーム全選手を対象にした画面。試合日程画面のカードから遷移する。
class GameDetailView extends ConsumerStatefulWidget {
  final int gamePk;
  final String awayTeam;
  final String homeTeam;

  const GameDetailView({
    super.key,
    required this.gamePk,
    required this.awayTeam,
    required this.homeTeam,
  });

  @override
  ConsumerState<GameDetailView> createState() => _GameDetailViewState();
}

class _GameDetailViewState extends ConsumerState<GameDetailView> {
  bool _isLoading = true;
  String? _error;
  Map<String, dynamic>? _feed;
  Timer? _pollingTimer;

  @override
  void initState() {
    super.initState();
    _fetch();
    // ★ 進行中の試合の場合、随時ライブフィードを再取得して画面を更新する
    //   （ライブ観戦画面のポーリング間隔15秒に合わせる）
    _pollingTimer = Timer.periodic(const Duration(seconds: 15), (_) => _fetch(isAutoRefresh: true));
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    super.dispose();
  }

  Future<void> _fetch({bool isAutoRefresh = false}) async {
    if (!isAutoRefresh) {
      setState(() {
        _isLoading = true;
        _error = null;
      });
    }
    try {
      final api = ref.read(apiServiceProvider);
      final feed = await api.getLiveGameFeed(widget.gamePk);
      if (mounted) {
        setState(() {
          _feed = feed;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted && !isAutoRefresh) {
        setState(() {
          _error = 'データ取得エラー: $e';
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            '${widget.awayTeam} vs ${widget.homeTeam}',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
          ),
          actions: [
            const LanguageToggleButton(),
            IconButton(icon: const Icon(Icons.refresh), onPressed: () => _fetch()),
          ],
          bottom: TabBar(
            tabs: [
              const Tab(text: 'リアルタイム結果'),
              Tab(text: widget.awayTeam),
              Tab(text: widget.homeTeam),
            ],
          ),
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(child: Text(_error!, style: const TextStyle(color: Colors.redAccent)))
                : TabBarView(
                    children: [
                      _LiveResultsTab(feed: _feed!, gamePk: widget.gamePk),
                      _TeamBoxScore(feed: _feed!, side: 'away'),
                      _TeamBoxScore(feed: _feed!, side: 'home'),
                    ],
                  ),
      ),
    );
  }
}

// ============================================================
// 「リアルタイム結果」タブ：試合全体の打席結果を、直近のイニングが
// 一番上に来る順（新しい順）で一覧表示する。登板中の投手・打席の打者には
// 「シーズン成績 + この試合のここまでの成績」を合算した最新の防御率・
// 打率・OPSをその場で表示する。
// ============================================================

class _LiveResultsTab extends ConsumerStatefulWidget {
  final Map<String, dynamic> feed;
  final int gamePk;

  const _LiveResultsTab({required this.feed, required this.gamePk});

  @override
  ConsumerState<_LiveResultsTab> createState() => _LiveResultsTabState();
}

class _LiveResultsTabState extends ConsumerState<_LiveResultsTab> {
  bool _isLoadingBaseline = true;
  final Map<int, Map<String, dynamic>> _battingBaseline = {};
  final Map<int, Map<String, dynamic>> _pitchingBaseline = {};

  @override
  void initState() {
    super.initState();
    _fetchBaseline();
  }

  Future<void> _fetchBaseline() async {
    try {
      final api = ref.read(apiServiceProvider);
      final awayTeamId = (widget.feed['gameData']?['teams']?['away']?['id'] as num?)?.toInt();
      final homeTeamId = (widget.feed['gameData']?['teams']?['home']?['id'] as num?)?.toInt();

      final List<int> batterIds = [];
      final List<int> pitcherIds = [];

      Future<void> collectRoster(int? teamId) async {
        if (teamId == null) return;
        final rosterData = await api.getTeamRoster(teamId);
        final rosterRaw = rosterData['roster'] as List<dynamic>? ?? [];
        for (final r in rosterRaw) {
          final personId = (r['person']?['id'] as num?)?.toInt();
          if (personId == null) continue;
          final isPitcher = r['position']?['type']?.toString() == 'Pitcher';
          if (isPitcher) {
            pitcherIds.add(personId);
          } else {
            batterIds.add(personId);
          }
        }
      }

      await Future.wait([collectRoster(awayTeamId), collectRoster(homeTeamId)]);

      final results = await Future.wait([
        api.getBulkPlayerSeasonStats(batterIds, 'hitting'),
        api.getBulkPlayerSeasonStats(pitcherIds, 'pitching'),
      ]);

      // ★ MLB公式APIの「シーズン成績」は、試合が進行中でも取得時点までの
      //   今日の分をすでに含んでいる。boxscoreから「今日ここまでの成績」を
      //   引き算し、真の「試合開始前」の値に補正してから保存する。
      Map<String, dynamic>? gameStatFor(int personId, {required bool pitching}) {
        final teams = widget.feed['liveData']?['boxscore']?['teams'] as Map<String, dynamic>?;
        if (teams == null) return null;
        for (final side in ['away', 'home']) {
          final players = teams[side]?['players'] as Map<String, dynamic>?;
          final p = players?['ID$personId'] as Map<String, dynamic>?;
          if (p == null) continue;
          final stats = p['stats'] as Map<String, dynamic>?;
          final stat = stats?[pitching ? 'pitching' : 'batting'] as Map<String, dynamic>?;
          if (stat != null) return stat;
        }
        return null;
      }

      void applyBaseline(Map<String, dynamic> data, Map<int, Map<String, dynamic>> target, {required bool pitching}) {
        final people = data['people'] as List<dynamic>? ?? [];
        for (final p in people) {
          final personId = (p['id'] as num?)?.toInt();
          if (personId == null) continue;
          final statsList = p['stats'] as List<dynamic>? ?? [];
          if (statsList.isEmpty) continue;
          final splits = statsList[0]['splits'] as List<dynamic>? ?? [];
          if (splits.isEmpty) continue;
          final stat = splits[0]['stat'] as Map<String, dynamic>?;
          if (stat == null) continue;
          final gameStat = gameStatFor(personId, pitching: pitching);
          target[personId] = pitching ? subtractPitchingStat(stat, gameStat) : subtractBattingStat(stat, gameStat);
        }
      }

      applyBaseline(results[0], _battingBaseline, pitching: false);
      applyBaseline(results[1], _pitchingBaseline, pitching: true);

      if (mounted) setState(() => _isLoadingBaseline = false);
    } catch (_) {
      if (mounted) setState(() => _isLoadingBaseline = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final lang = ref.watch(appLanguageProvider);
    final japaneseIds = japanesePlayers.map((p) => p.id).toSet();
    final playsRaw = widget.feed['liveData']?['plays']?['allPlays'] as List<dynamic>? ?? [];
    final chronological = playsRaw.cast<Map<String, dynamic>>().toList();

    if (chronological.isEmpty) {
      return const Center(child: Text('試合開始前です', style: TextStyle(color: Colors.white54)));
    }

    // ★ 「失点する前は変動しない」その時点での防御率・打率を再現するため、
    //   試合開始から時系列順に1プレイずつ走査し、投手・打者ごとに
    //   「その打席が終わった直後」の試合内累積成績を積み上げて記録する。
    //   （boxscoreの現在合計をそのまま使うと、過去の打席にも試合終了時点の
    //   最新の数字が出てしまい、当時の状況と食い違ってしまうため）
    final Map<int, RunningPitcherState> pitcherRunning = {};
    final Map<int, RunningBatterState> batterRunning = {};
    final Map<int, int> pitchCountByPitcher = {};
    int outsInHalfInning = 0;
    int? trackedInning;
    bool? trackedIsTop;
    final baseOutStates = computeBaseOutStates(chronological);

    final List<Map<String, dynamic>> enriched = [];
    for (final play in chronological) {
      final inning = play['about']?['inning'] as int?;
      final isTop = play['about']?['isTopInning'] == true;
      if (inning != trackedInning || isTop != trackedIsTop) {
        outsInHalfInning = 0;
        trackedInning = inning;
        trackedIsTop = isTop;
      }

      final outsAfter = (play['count']?['outs'] as num?)?.toInt() ?? outsInHalfInning;
      final outsGained = (outsAfter - outsInHalfInning).clamp(0, 3);
      outsInHalfInning = outsAfter;

      final pitcherId = (play['matchup']?['pitcher']?['id'] as num?)?.toInt();
      final batterId = (play['matchup']?['batter']?['id'] as num?)?.toInt();
      final earnedRuns = countEarnedRunsInPlay(play);
      final event = play['result']?['event']?.toString();

      Map<String, dynamic>? pitcherStatSoFar;
      int? pitchCountSoFar;
      if (pitcherId != null) {
        final st = pitcherRunning.putIfAbsent(pitcherId, () => RunningPitcherState());
        st.outs += outsGained;
        st.earnedRuns += earnedRuns;
        pitcherStatSoFar = st.toStatMap();

        final pitchesInPlay = (play['playEvents'] as List<dynamic>? ?? []).where((e) => e['isPitch'] == true).length;
        pitchCountByPitcher[pitcherId] = (pitchCountByPitcher[pitcherId] ?? 0) + pitchesInPlay;
        pitchCountSoFar = pitchCountByPitcher[pitcherId];
      }
      Map<String, dynamic>? batterStatSoFar;
      if (batterId != null) {
        final st = batterRunning.putIfAbsent(batterId, () => RunningBatterState());
        st.apply(classifyPlateAppearance(event));
        batterStatSoFar = st.toStatMap();
      }

      final atBatIndex = play['about']?['atBatIndex'] as int?;

      enriched.add({
        'play': play,
        'pitcherStatSoFar': pitcherStatSoFar,
        'batterStatSoFar': batterStatSoFar,
        'baseOutState': atBatIndex != null ? baseOutStates[atBatIndex] : null,
        'pitchCountSoFar': pitchCountSoFar,
        'isScoringPlay': play['about']?['isScoringPlay'] == true,
        'awayScore': (play['result']?['awayScore'] as num?)?.toInt(),
        'homeScore': (play['result']?['homeScore'] as num?)?.toInt(),
      });
    }

    // ★ 直近のイニング・打席が一番上に来るよう、全体を逆順にする
    final ordered = enriched.reversed.toList();

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: ordered.length,
      itemBuilder: (context, index) {
        final play = ordered[index]['play'] as Map<String, dynamic>;
        final inning = play['about']?['inning'] as int? ?? 0;
        final isTop = play['about']?['isTopInning'] == true;
        final half = translateHalf(isTop, lang);

        // ★ 1つ上（＝直近側）の要素とイニングが違う場合にヘッダーを表示する
        final prevPlay = index > 0 ? ordered[index - 1]['play'] as Map<String, dynamic> : null;
        final prevInning = prevPlay?['about']?['inning'] as int?;
        final prevIsTop = prevPlay != null ? (prevPlay['about']?['isTopInning'] == true) : null;
        final showHeader = index == 0 || prevInning != inning || prevIsTop != isTop;

        final batterId = (play['matchup']?['batter']?['id'] as num?)?.toInt();
        final batterName = play['matchup']?['batter']?['fullName']?.toString() ?? '-';
        final pitcherId = (play['matchup']?['pitcher']?['id'] as num?)?.toInt();
        final pitcherName = play['matchup']?['pitcher']?['fullName']?.toString() ?? '-';
        final result = translateAtBatResult(
          play['result']?['description']?.toString(),
          play['result']?['event']?.toString(),
          lang,
        );

        final battingBaseline = batterId != null ? _battingBaseline[batterId] : null;
        final battingSoFar = ordered[index]['batterStatSoFar'] as Map<String, dynamic>?;
        final liveAvg = computeLiveAvg(battingBaseline, battingSoFar);
        final liveOps = computeLiveOps(battingBaseline, battingSoFar);

        final pitchingBaseline = pitcherId != null ? _pitchingBaseline[pitcherId] : null;
        final pitchingSoFar = ordered[index]['pitcherStatSoFar'] as Map<String, dynamic>?;
        final liveEra = computeLiveEra(pitchingBaseline, pitchingSoFar);

        final pitchPoints = extractPitchZonePoints(play['playEvents'] as List<dynamic>? ?? []);
        final baseOutState = ordered[index]['baseOutState'] as String?;
        final pitchCountSoFar = ordered[index]['pitchCountSoFar'] as int?;
        final isScoringPlay = ordered[index]['isScoringPlay'] == true;
        final awayScore = ordered[index]['awayScore'] as int?;
        final homeScore = ordered[index]['homeScore'] as int?;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (showHeader) ...[
              if (index != 0) const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 10),
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: Colors.blueAccent.withAlpha(30),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text('$inning回$half', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.blueAccent)),
              ),
            ],
            Card(
              margin: const EdgeInsets.only(bottom: 8),
              color: isScoringPlay ? const Color(0xFF2C2410) : const Color(0xFF1E1E2C),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
                side: isScoringPlay ? const BorderSide(color: Colors.amberAccent, width: 1.2) : BorderSide.none,
              ),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        if (baseOutState != null)
                          Text(baseOutState, style: const TextStyle(fontSize: 11, color: Colors.white54, fontWeight: FontWeight.bold))
                        else
                          const SizedBox.shrink(),
                        if (isScoringPlay)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(color: Colors.amberAccent, borderRadius: BorderRadius.circular(6)),
                            child: const Text('⚾ 得点', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.black)),
                          ),
                      ],
                    ),
                    if (awayScore != null && homeScore != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        '${widget.feed['gameData']?['teams']?['away']?['abbreviation'] ?? ''} $awayScore - $homeScore ${widget.feed['gameData']?['teams']?['home']?['abbreviation'] ?? ''}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: isScoringPlay ? Colors.amberAccent : Colors.white54,
                        ),
                      ),
                    ],
                    const SizedBox(height: 6),
                    // ★ 打者・投手を見やすく2列に分けて表示し、右側にこの打席の
                    //   投球コースをミニストライクゾーンで表示する
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: _LiveMatchupColumn(
                                  roleLabel: '打者',
                                  name: batterName,
                                  isJapanese: japaneseIds.contains(batterId),
                                  statLines: !_isLoadingBaseline && (liveAvg != null || liveOps != null)
                                      ? [
                                          if (liveAvg != null) '打率 ${formatAvg(liveAvg)}',
                                          if (liveOps != null) 'OPS ${formatOps(liveOps)}',
                                        ]
                                      : const [],
                                  onTap: () => showAtBatDetailDialog(
                                    context,
                                    batterName: batterName,
                                    pitcherName: pitcherName,
                                    batterId: batterId,
                                    pitcherId: pitcherId,
                                    inning: inning,
                                    half: half,
                                    result: result,
                                    playEvents: play['playEvents'] as List<dynamic>? ?? [],
                                    lang: lang,
                                  ),
                                ),
                              ),
                              Container(width: 1, height: 44, color: Colors.white12, margin: const EdgeInsets.symmetric(horizontal: 10)),
                              Expanded(
                                child: _LiveMatchupColumn(
                                  roleLabel: '投手',
                                  name: pitcherName,
                                  isJapanese: japaneseIds.contains(pitcherId),
                                  statLines: [
                                    if (!_isLoadingBaseline && liveEra != null) '防御率 ${formatEra(liveEra)}',
                                    if (pitchCountSoFar != null) '$pitchCountSoFar球',
                                  ],
                                  onTap: () => showAtBatDetailDialog(
                                    context,
                                    batterName: batterName,
                                    pitcherName: pitcherName,
                                    batterId: batterId,
                                    pitcherId: pitcherId,
                                    inning: inning,
                                    half: half,
                                    result: result,
                                    playEvents: play['playEvents'] as List<dynamic>? ?? [],
                                    lang: lang,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (pitchPoints.isNotEmpty) ...[
                          const SizedBox(width: 10),
                          MiniStrikeZone(pitches: pitchPoints, width: 70, height: 84),
                        ],
                      ],
                    ),
                    const Divider(height: 16, color: Colors.white12),
                    Text(result, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white)),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// 「リアルタイム結果」の各プレイカード内で使う、打者側/投手側それぞれの列。
class _LiveMatchupColumn extends StatelessWidget {
  final String roleLabel;
  final String name;
  final bool isJapanese;
  final List<String> statLines;
  final VoidCallback? onTap;

  const _LiveMatchupColumn({
    required this.roleLabel,
    required this.name,
    required this.isJapanese,
    required this.statLines,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final nameText = Text(
      '$name${isJapanese ? " 🇯🇵" : ""}',
      style: TextStyle(
        fontSize: 12,
        color: onTap != null ? Colors.lightBlueAccent : Colors.white,
        fontWeight: FontWeight.bold,
        decoration: onTap != null ? TextDecoration.underline : TextDecoration.none,
        decorationColor: Colors.lightBlueAccent,
      ),
      overflow: TextOverflow.ellipsis,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(roleLabel, style: const TextStyle(fontSize: 10, color: Colors.white38, fontWeight: FontWeight.bold)),
        const SizedBox(height: 2),
        onTap != null ? InkWell(onTap: onTap, child: nameText) : nameText,
        for (final line in statLines) ...[
          const SizedBox(height: 2),
          Text(line, style: const TextStyle(fontSize: 11, color: Colors.amberAccent, fontWeight: FontWeight.bold)),
        ],
      ],
    );
  }
}

class _TeamBoxScore extends ConsumerWidget {
  final Map<String, dynamic> feed;
  final String side; // 'away' | 'home'

  const _TeamBoxScore({required this.feed, required this.side});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lang = ref.watch(appLanguageProvider);
    final pinnedIds = ref.watch(pinnedPlayersProvider);
    final japaneseIds = japanesePlayers.map((p) => p.id).toSet();

    final box = feed['liveData']?['boxscore']?['teams']?[side] as Map<String, dynamic>?;
    if (box == null) {
      return const Center(child: Text('ボックススコアデータがありません', style: TextStyle(color: Colors.white54)));
    }

    final players = box['players'] as Map<String, dynamic>? ?? {};
    final pitcherIds = (box['pitchers'] as List<dynamic>? ?? []).map((e) => e as int).toList();

    // ★ battingOrderフィールドを持つ選手＝実際に打席に立った選手（スタメン＋途中出場）
    //   下2桁00=スタメン、01以降=途中出場。数値順に並べればスタメン順＋交代順になる。
    final batterEntries = <MapEntry<int, Map<String, dynamic>>>[];
    players.forEach((key, value) {
      final p = value as Map<String, dynamic>;
      final boStr = p['battingOrder']?.toString();
      if (boStr != null && boStr.isNotEmpty) {
        final boInt = int.tryParse(boStr);
        if (boInt != null) batterEntries.add(MapEntry(boInt, p));
      }
    });
    batterEntries.sort((a, b) => a.key.compareTo(b.key));

    return RefreshIndicator(
      onRefresh: () async {},
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          const Text('スタメン・打撃成績', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.blueAccent)),
          const SizedBox(height: 8),
          if (batterEntries.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text('打撃データはまだありません', style: TextStyle(color: Colors.white38, fontSize: 12)),
            )
          else
            ...batterEntries.map((entry) {
              final boInt = entry.key;
              final p = entry.value;
              final personId = (p['person']?['id'] as num?)?.toInt();
              final name = p['person']?['fullName']?.toString() ?? '-';
              final posAbbr = translatePosition(p['position']?['abbreviation']?.toString(), lang);
              final battingStat = p['stats']?['batting'] as Map<String, dynamic>? ?? {};
              final statLine = formatBattingLine(battingStat, lang);
              final slot = boInt ~/ 100;
              final subSeq = boInt % 100;
              final isJp = personId != null && japaneseIds.contains(personId);
              final isPinned = personId != null && pinnedIds.contains(personId);

              return _PlayerRow(
                feed: feed,
                isPitcherRow: false,
                orderLabel: '$slot',
                subLabel: subSeq > 0 ? (lang == AppLanguage.en ? 'sub' : '途中') : null,
                name: name,
                subInfo: posAbbr,
                statLine: statLine,
                isJapanese: isJp,
                isPinned: isPinned,
                personId: personId,
              );
            }),
          const SizedBox(height: 24),
          const Text('投手成績', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.blueAccent)),
          const SizedBox(height: 8),
          if (pitcherIds.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text('投球データはまだありません', style: TextStyle(color: Colors.white38, fontSize: 12)),
            )
          else
            ...pitcherIds.map((id) {
              final p = players['ID$id'] as Map<String, dynamic>?;
              if (p == null) return const SizedBox.shrink();
              final name = p['person']?['fullName']?.toString() ?? '-';
              final pitchingStat = p['stats']?['pitching'] as Map<String, dynamic>? ?? {};
              final statLine = formatPitchingLine(pitchingStat, lang);
              final note = pitchingStat['note']?.toString();
              final isJp = japaneseIds.contains(id);
              final isPinned = pinnedIds.contains(id);

              return _PlayerRow(
                feed: feed,
                isPitcherRow: true,
                orderLabel: null,
                subLabel: null,
                name: name,
                subInfo: note,
                statLine: statLine,
                isJapanese: isJp,
                isPinned: isPinned,
                personId: id,
              );
            }),
        ],
      ),
    );
  }
}

class _PlayerRow extends ConsumerWidget {
  final Map<String, dynamic> feed;
  final bool isPitcherRow;
  final String? orderLabel;
  final String? subLabel;
  final String name;
  final String? subInfo;
  final String statLine;
  final bool isJapanese;
  final bool isPinned;
  final int? personId;

  const _PlayerRow({
    required this.feed,
    required this.isPitcherRow,
    required this.orderLabel,
    required this.subLabel,
    required this.name,
    required this.subInfo,
    required this.statLine,
    required this.isJapanese,
    required this.isPinned,
    required this.personId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: isPinned ? const Color(0xFF2C2818) : const Color(0xFF1E1E2C),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: isPinned ? Colors.amberAccent.withAlpha(150) : Colors.transparent, width: 1.2),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: personId == null
            ? null
            : () {
                showModalBottomSheet(
                  context: context,
                  backgroundColor: const Color(0xFF161622),
                  isScrollControlled: true,
                  shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
                  builder: (_) => _PlayerAtBatDetailSheet(
                    feed: feed,
                    personId: personId!,
                    playerName: name,
                    isPitcherRow: isPitcherRow,
                  ),
                );
              },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              if (orderLabel != null)
                SizedBox(
                  width: 26,
                  child: Text(
                    orderLabel!,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white54),
                  ),
                ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            name,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (isJapanese) const Padding(
                          padding: EdgeInsets.only(left: 4),
                          child: Text('🇯🇵', style: TextStyle(fontSize: 11)),
                        ),
                        if (subLabel != null) ...[
                          const SizedBox(width: 4),
                          Text('($subLabel)', style: const TextStyle(fontSize: 10, color: Colors.white38)),
                        ],
                      ],
                    ),
                    if (subInfo != null && subInfo!.isNotEmpty)
                      Text(subInfo!, style: const TextStyle(fontSize: 11, color: Colors.white54)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(statLine, style: const TextStyle(fontSize: 12, color: Colors.white70)),
              if (personId != null && isJapanese)
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: Icon(
                    isPinned ? Icons.push_pin : Icons.push_pin_outlined,
                    size: 18,
                    color: isPinned ? Colors.amberAccent : Colors.white38,
                  ),
                  onPressed: () => ref.read(pinnedPlayersProvider.notifier).toggle(personId!),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================
// 選手個別の打席・対戦詳細（配球ログ＆ミニストライクゾーン）シート。
// 日本人選手専用の live_view.dart と同じ見せ方を、ボックススコア画面から
// 任意の選手（日本人選手に限らない）に対して使えるようにしたもの。
// gamePkの再取得はせず、既に読み込み済みのfeedからその場でフィルターする。
// ============================================================

class _PlayerAtBatDetailSheet extends ConsumerWidget {
  final Map<String, dynamic> feed;
  final int personId;
  final String playerName;
  final bool isPitcherRow;

  const _PlayerAtBatDetailSheet({
    required this.feed,
    required this.personId,
    required this.playerName,
    required this.isPitcherRow,
  });

  List<Map<String, dynamic>> _extractPitches(List<dynamic> playEvents, AppLanguage lang) {
    List<Map<String, dynamic>> pitches = [];
    for (final event in playEvents) {
      if (event['isPitch'] == true) {
        final speedMph = (event['pitchData']?['startSpeed'] as num?)?.toDouble() ?? 0.0;
        final speedKmh = speedMph * 1.60934;
        final rawCall = event['details']?['description']?.toString() ?? '';
        final type = translatePitchType(event['details']?['type']?['description']?.toString(), lang);
        final call = translateCall(rawCall, lang);
        final count = '${event['count']?['balls'] ?? 0}-${event['count']?['strikes'] ?? 0}';
        final pX = (event['pitchData']?['coordinates']?['pX'] as num?)?.toDouble();
        final pZ = (event['pitchData']?['coordinates']?['pZ'] as num?)?.toDouble();
        final isStrike = rawCall.contains('Strike') || rawCall.contains('Foul') || rawCall.contains('In play');

        pitches.add({
          'pitchNumber': event['pitchNumber'] ?? (pitches.length + 1),
          'type': type,
          'speedMph': speedMph,
          'speedKmh': speedKmh,
          'call': call,
          'count': count,
          'pX': pX,
          'pZ': pZ,
          'isStrike': isStrike,
        });
      }
    }
    return pitches;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lang = ref.watch(appLanguageProvider);
    final plays = feed['liveData']?['plays']?['allPlays'] as List<dynamic>? ?? [];

    final matchups = <Map<String, dynamic>>[];
    for (final play in plays) {
      final batterId = (play['matchup']?['batter']?['id'] as num?)?.toInt();
      final pitcherId = (play['matchup']?['pitcher']?['id'] as num?)?.toInt();
      final isMatch = isPitcherRow ? pitcherId == personId : batterId == personId;
      if (!isMatch) continue;

      final inning = play['about']?['inning'] as int? ?? 1;
      final half = translateHalf(play['about']?['isTopInning'] == true, lang);
      final opponentName = isPitcherRow
          ? (play['matchup']?['batter']?['fullName']?.toString() ?? '-')
          : (play['matchup']?['pitcher']?['fullName']?.toString() ?? '-');
      final opponentId = isPitcherRow ? batterId : pitcherId;
      final result = translateAtBatResult(
        play['result']?['description']?.toString(),
        play['result']?['event']?.toString(),
        lang,
      );
      final playEvents = play['playEvents'] as List<dynamic>? ?? [];
      final pitches = _extractPitches(playEvents, lang);

      matchups.add({
        'inning': inning,
        'half': half,
        'opponent': opponentName,
        'opponentId': opponentId,
        'result': result,
        'pitches': pitches,
      });
    }

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      '$playerName の${isPitcherRow ? "投球" : "打席"}詳細',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.amberAccent),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const LanguageToggleButton(),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white54),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const Divider(color: Colors.white12, height: 20),
              Expanded(
                child: matchups.isEmpty
                    ? const Center(child: Text('該当の投球・打席ログがありません', style: TextStyle(color: Colors.white54)))
                    : ListView.separated(
                        controller: scrollController,
                        itemCount: matchups.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 14),
                        itemBuilder: (context, idx) {
                          final m = matchups[idx];
                          final pitches = m['pitches'] as List<Map<String, dynamic>>;
                          return Card(
                            color: const Color(0xFF1E1E2C),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            child: Padding(
                              padding: const EdgeInsets.all(14),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '第${idx + 1}${isPitcherRow ? "打者" : "打席"}（${m['inning']}回${m['half']}） vs ${m['opponent']}',
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.blueAccent),
                                  ),
                                  const SizedBox(height: 4),
                                  Text('${m['result']}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white)),
                                  if (m['opponentId'] != null) ...[
                                    const SizedBox(height: 4),
                                    HeadToHeadBadge(
                                      batterId: isPitcherRow ? m['opponentId'] as int : personId,
                                      pitcherId: isPitcherRow ? personId : m['opponentId'] as int,
                                    ),
                                  ],
                                  const Divider(height: 16, color: Colors.white12),
                                  _buildPitchZoneRow(pitches),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPitchZoneRow(List<Map<String, dynamic>> pitches) {
    if (pitches.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Text('投球データなし', style: TextStyle(color: Colors.white38, fontSize: 12)),
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 6,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('【配球推移】', style: TextStyle(fontSize: 11, color: Colors.white54)),
              const SizedBox(height: 6),
              ...pitches.map((p) {
                final isStrike = p['isStrike'] as bool;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    children: [
                      Container(
                        width: 18,
                        height: 18,
                        decoration: BoxDecoration(
                          color: isStrike ? Colors.redAccent : Colors.blueAccent,
                          borderRadius: BorderRadius.circular(9),
                        ),
                        alignment: Alignment.center,
                        child: Text('${p['pitchNumber']}', style: const TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.bold)),
                      ),
                      const SizedBox(width: 6),
                      Text('[${p['count']}]', style: const TextStyle(fontSize: 11, color: Colors.amberAccent, fontWeight: FontWeight.bold)),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          '${p['type']}\n${(p['speedMph'] as double).toStringAsFixed(1)} mph (${(p['speedKmh'] as double).toStringAsFixed(0)}km/h)',
                          style: const TextStyle(fontSize: 11, color: Colors.white),
                        ),
                      ),
                      Text(
                        p['call'] as String,
                        style: TextStyle(fontSize: 10, color: isStrike ? Colors.orangeAccent : Colors.lightBlueAccent),
                      ),
                    ],
                  ),
                );
              }),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 4,
          child: Column(
            children: [
              const Text('【ゾーン通過位置】', style: TextStyle(fontSize: 11, color: Colors.white54)),
              const SizedBox(height: 6),
              Container(
                height: 140,
                width: 120,
                decoration: BoxDecoration(
                  color: const Color(0xFF14141E),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.white12),
                ),
                child: CustomPaint(
                  painter: _MiniStrikeZonePainter(pitches: pitches),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _MiniStrikeZonePainter extends CustomPainter {
  final List<Map<String, dynamic>> pitches;

  _MiniStrikeZonePainter({required this.pitches});

  @override
  void paint(Canvas canvas, Size size) {
    final zoneWidth = size.width * 0.6;
    final zoneHeight = size.height * 0.65;
    final zoneLeft = (size.width - zoneWidth) / 2;
    final zoneTop = (size.height - zoneHeight) / 2;
    final zoneRect = Rect.fromLTWH(zoneLeft, zoneTop, zoneWidth, zoneHeight);

    final bgPaint = Paint()..color = const Color(0xFF222232);
    canvas.drawRect(zoneRect, bgPaint);

    final borderPaint = Paint()
      ..color = Colors.white70
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawRect(zoneRect, borderPaint);

    final gridPaint = Paint()
      ..color = Colors.white24
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;

    for (int i = 1; i <= 2; i++) {
      canvas.drawLine(
        Offset(zoneLeft + (zoneWidth / 3) * i, zoneTop),
        Offset(zoneLeft + (zoneWidth / 3) * i, zoneTop + zoneHeight),
        gridPaint,
      );
      canvas.drawLine(
        Offset(zoneLeft, zoneTop + (zoneHeight / 3) * i),
        Offset(zoneLeft + zoneWidth, zoneTop + (zoneHeight / 3) * i),
        gridPaint,
      );
    }

    for (final p in pitches) {
      final double? pX = p['pX'];
      final double? pZ = p['pZ'];
      if (pX == null || pZ == null) continue;

      final double normalizedX = (pX + 0.83) / (0.83 * 2);
      final double normalizedY = 1.0 - ((pZ - 1.5) / (3.5 - 1.5));

      final double cx = zoneLeft + (normalizedX * zoneWidth);
      final double cy = zoneTop + (normalizedY * zoneHeight);

      final isStrike = p['isStrike'] as bool;
      final ballColor = isStrike ? Colors.redAccent : Colors.blueAccent;

      final ballPaint = Paint()..color = ballColor;
      canvas.drawCircle(Offset(cx, cy), 8, ballPaint);

      final strokePaint = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0;
      canvas.drawCircle(Offset(cx, cy), 8, strokePaint);

      final textSpan = TextSpan(
        text: '${p['pitchNumber']}',
        style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
      );
      final textPainter = TextPainter(
        text: textSpan,
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
      )..layout();

      textPainter.paint(
        canvas,
        Offset(cx - (textPainter.width / 2), cy - (textPainter.height / 2)),
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
