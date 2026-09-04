import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/player.dart';
import '../services/schedule_provider.dart';
import '../utils/jst_time.dart';
import '../services/head_to_head_service.dart';
import '../widgets/player_picker_sheet.dart';
import '../services/pinned_players_provider.dart';
import '../services/language_provider.dart';
import '../widgets/language_toggle_button.dart';
import '../utils/mlb_translations.dart';
import '../widgets/pitch_log_widget.dart';
import '../utils/live_stat_calc.dart';
import '../utils/base_out_state.dart';
import '../utils/would_be_homerun.dart';
import '../utils/ballpark_dimensions.dart';
import 'game_detail_view.dart';

class LiveView extends ConsumerStatefulWidget {
  final dynamic initialGame;
  final JapanesePlayer? initialPlayer;

  const LiveView({super.key, this.initialGame, this.initialPlayer});

  @override
  ConsumerState<LiveView> createState() => _LiveViewState();
}

class _LiveViewState extends ConsumerState<LiveView> {
  late int _selectedPlayerIndex;
  Timer? _pollingTimer;

  Map<String, dynamic>? _liveGameData;
  bool _isLoading = false;
  String? _errorMessage;
  // ★ 投手セクションの「○回: ○球」チップで選んだイニングに絞り込むためのフィルター（nullなら全イニング）
  int? _selectedInning;
  // ★ 投手が現在追跡中の選手の場合の「試合開始前」防御率ベースライン（シーズン成績−今日の分）
  Map<String, dynamic>? _pitcherEraBaseline;
  int? _pitcherEraBaselineForId;

  @override
  void initState() {
    super.initState();
    if (widget.initialPlayer != null) {
      final idx = japanesePlayers.indexWhere((p) => p.id == widget.initialPlayer!.id);
      _selectedPlayerIndex = idx != -1 ? idx : 0;
    } else {
      _selectedPlayerIndex = 0;
    }

    _fetchLiveGame();
    _pollingTimer = Timer.periodic(const Duration(seconds: 15), (_) => _fetchLiveGame(isAutoRefresh: true));
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    super.dispose();
  }

  Future<void> _fetchLiveGame({bool isAutoRefresh = false}) async {
    if (!isAutoRefresh) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }

    final targetPlayer = japanesePlayers[_selectedPlayerIndex];

    try {
      final api = ref.read(apiServiceProvider);
      final schedule = await api.getTodaySchedule();
      final dates = schedule['dates'] as List<dynamic>? ?? [];

      // ★ 対象チームが関わる試合を「全部」集める（前後3日=7日間の範囲全て）
      final List<Map<String, dynamic>> matchedGames = [];
      for (final d in dates) {
        final games = d['games'] as List<dynamic>? ?? [];
        for (final g in games) {
          final awayId = g['teams']?['away']?['team']?['id'];
          final homeId = g['teams']?['home']?['team']?['id'];
          if (awayId == targetPlayer.teamId || homeId == targetPlayer.teamId) {
            matchedGames.add(g as Map<String, dynamic>);
          }
        }
      }

      int? gamePk;
      if (matchedGames.isNotEmpty) {
        final now = nowJst();

        // ★ Live状態の試合を最優先。それが無ければ「現在時刻に一番近い試合」を選ぶ
        matchedGames.sort((a, b) {
          final aState = a['status']?['abstractGameState']?.toString();
          final bState = b['status']?['abstractGameState']?.toString();
          if (aState == 'Live' && bState != 'Live') return -1;
          if (bState == 'Live' && aState != 'Live') return 1;

          final aDate = parseToJst(a['gameDate'].toString());
          final bDate = parseToJst(b['gameDate'].toString());
          final aDiff = aDate.difference(now).abs();
          final bDiff = bDate.difference(now).abs();
          return aDiff.compareTo(bDiff);
        });

        gamePk = matchedGames.first['gamePk'] as int?;
      }

      if (gamePk != null) {
        final feed = await api.getLiveGameFeed(gamePk);
        if (mounted) {
          setState(() {
            _liveGameData = feed;
            _isLoading = false;
          });
        }
        if (targetPlayer.isPitcher) {
          _fetchPitcherEraBaseline(targetPlayer, feed);
        }
      } else {
        if (mounted) {
          setState(() {
            _liveGameData = null;
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      if (mounted && !isAutoRefresh) {
        setState(() {
          _errorMessage = 'データ取得エラー: $e';
          _isLoading = false;
        });
      }
    }
  }

  // ★ 追跡中の投手について、防御率のリアルタイム計算に使う「試合開始前」の
  //   ベースラインを取得する（シーズン成績は取得時点で今日の分を含んでいるため、
  //   boxscoreの今日ここまでの成績を差し引いて真の試合開始前の値に補正する）
  Future<void> _fetchPitcherEraBaseline(JapanesePlayer player, Map<String, dynamic> feed) async {
    try {
      final api = ref.read(apiServiceProvider);
      final seasonData = await api.getBulkPlayerSeasonStats([player.id], 'pitching');
      final people = seasonData['people'] as List<dynamic>? ?? [];
      if (people.isEmpty) return;
      final statsList = people[0]['stats'] as List<dynamic>? ?? [];
      if (statsList.isEmpty) return;
      final splits = statsList[0]['splits'] as List<dynamic>? ?? [];
      if (splits.isEmpty) return;
      final seasonStat = splits[0]['stat'] as Map<String, dynamic>?;
      if (seasonStat == null) return;

      Map<String, dynamic>? gameStat;
      final teams = feed['liveData']?['boxscore']?['teams'] as Map<String, dynamic>?;
      if (teams != null) {
        for (final side in ['away', 'home']) {
          final p = teams[side]?['players']?['ID${player.id}'] as Map<String, dynamic>?;
          final stat = p?['stats']?['pitching'] as Map<String, dynamic>?;
          if (stat != null) {
            gameStat = stat;
            break;
          }
        }
      }

      final baseline = subtractPitchingStat(seasonStat, gameStat);
      if (mounted) {
        setState(() {
          _pitcherEraBaseline = baseline;
          _pitcherEraBaselineForId = player.id;
        });
      }
    } catch (_) {
      // 取得に失敗しても致命的ではない（防御率表示を省略するだけ）
    }
  }

  // ★ 選手選択をボトムシートで開く（スマホでの操作性向上のため横スクロールチップから変更）
  Future<void> _openPlayerPicker() async {
    final currentId = japanesePlayers[_selectedPlayerIndex].id;
    final selected = await showPlayerPickerSheet(
      context,
      candidates: japanesePlayers,
      currentPlayerId: currentId,
    );

    if (selected != null && selected.id != currentId) {
      setState(() {
        _selectedPlayerIndex = japanesePlayers.indexWhere((p) => p.id == selected.id);
        _liveGameData = null;
        _selectedInning = null;
      });
      _fetchLiveGame();
    }
  }

  @override
  Widget build(BuildContext context) {
    final player = japanesePlayers[_selectedPlayerIndex];

    return Scaffold(
      appBar: AppBar(
        title: const Text('リアルタイム速報 & Statcast', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          const LanguageToggleButton(),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => _fetchLiveGame(),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: _openPlayerPicker,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E1E2C),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.blueAccent.withAlpha(80)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.person, size: 18, color: Colors.blueAccent),
                        const SizedBox(width: 8),
                        Text(
                          '${japanesePlayers[_selectedPlayerIndex].nameJa} (${japanesePlayers[_selectedPlayerIndex].teamName})',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.blueAccent),
                        ),
                        if (ref.watch(pinnedPlayersProvider).contains(japanesePlayers[_selectedPlayerIndex].id)) ...[
                          const SizedBox(width: 6),
                          const Icon(Icons.push_pin, size: 14, color: Colors.amberAccent),
                        ],
                      ],
                    ),
                    const Icon(Icons.unfold_more, size: 20, color: Colors.white54),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _errorMessage != null
                    ? Center(child: Text(_errorMessage!, style: const TextStyle(color: Colors.redAccent)))
                    : _liveGameData == null
                        ? _buildNoGameView(player)
                        : _buildLiveContent(player, ref.watch(appLanguageProvider)),
          ),
        ],
      ),
    );
  }

  Widget _buildNoGameView(JapanesePlayer player) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(player.isPitcher ? Icons.sports_baseball : Icons.sports_cricket, size: 64, color: Colors.white24),
          const SizedBox(height: 16),
          Text('${player.nameJa} の本日開催試合はありません', style: const TextStyle(fontSize: 16, color: Colors.white70)),
          const SizedBox(height: 8),
          const Text('試合日程タブで次回登板・出場予定をご確認ください', style: TextStyle(fontSize: 12, color: Colors.white38)),
        ],
      ),
    );
  }

  Widget _buildLiveContent(JapanesePlayer player, AppLanguage lang) {
    final gameData = _liveGameData?['gameData'];
    final liveData = _liveGameData?['liveData'];

    final status = gameData?['status']?['detailedState'] ?? '不明';
    final linescore = liveData?['linescore'] as Map<String, dynamic>? ?? {};

    // ★ イニング情報が実際に存在する場合のみ「currentInning + 表/裏」を組み立てる
    final rawInning = linescore['currentInningOrdinal'];
    final String inningStatusText;
    if (rawInning != null) {
      final inningHalf = translateHalf(linescore['isTopInning'] == true, lang);
      inningStatusText = '$rawInning $inningHalf - $status';
    } else {
      inningStatusText = status; // 試合前・試合終了直後などはステータスのみ表示
    }

    final plays = liveData?['plays']?['allPlays'] as List<dynamic>? ?? [];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Card(
            color: const Color(0xFF1E1E2C),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(inningStatusText, style: const TextStyle(color: Colors.amberAccent, fontWeight: FontWeight.bold, fontSize: 13)),
                      const SizedBox(height: 4),
                      Text(
                        '${gameData?['teams']?['away']?['name']} vs ${gameData?['teams']?['home']?['name']}',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                    ],
                  ),
                  if (status == 'In Progress' || status == 'Manager challenge' || status == 'Warmup')
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(color: Colors.redAccent.withAlpha(50), borderRadius: BorderRadius.circular(8)),
                      child: Row(
                        children: const [
                          Icon(Icons.fiber_manual_record, color: Colors.redAccent, size: 12),
                          SizedBox(width: 4),
                          Text('LIVE', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 11)),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (_liveGameData?['gamePk'] != null) ...[
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => GameDetailView(
                        gamePk: _liveGameData!['gamePk'] as int,
                        awayTeam: gameData?['teams']?['away']?['name']?.toString() ?? '',
                        homeTeam: gameData?['teams']?['home']?['name']?.toString() ?? '',
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.list_alt, size: 18),
                label: const Text('試合全体のリアルタイム結果・スタメンを見る'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.blueAccent,
                  side: const BorderSide(color: Colors.blueAccent),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                ),
              ),
            ),
          ],
          const SizedBox(height: 16),
          if (player.isPitcher) ...[
            _buildPitcherLiveSection(player, plays, lang),
          ] else ...[
            _buildBatterLiveSection(player, plays, lang),
          ],
        ],
      ),
    );
  }

  // 投手向けセクション
  Widget _buildPitcherLiveSection(JapanesePlayer player, List<dynamic> plays, AppLanguage lang) {
    int pitchCount = 0;
    Map<int, int> inningPitches = {};
    List<Map<String, dynamic>> matchups = [];

    // ★ この打者との対戦が終わった直後の防御率をその場で再現するため、
    //   時系列順に投球回・自責点を積み上げる（試合開始前ベースラインと合算）
    final pitcherState = RunningPitcherState();
    int outsInHalfInning = 0;
    int? trackedInning;
    bool? trackedIsTop;
    final hasEraBaseline = _pitcherEraBaseline != null && _pitcherEraBaselineForId == player.id;
    final baseOutStates = computeBaseOutStates(plays);
    int hitsAllowed = 0;
    int strikeoutsRecorded = 0;
    int runsAllowed = 0;

    for (final play in plays) {
      final pitcherId = play['matchup']?['pitcher']?['id'];
      if (pitcherId == player.id) {
        final inning = play['about']?['inning'] as int? ?? 1;
        final isTop = play['about']?['isTopInning'] == true;
        if (inning != trackedInning || isTop != trackedIsTop) {
          outsInHalfInning = 0;
          trackedInning = inning;
          trackedIsTop = isTop;
        }
        final outsAfter = (play['count']?['outs'] as num?)?.toInt() ?? outsInHalfInning;
        final outsGained = (outsAfter - outsInHalfInning).clamp(0, 3);
        outsInHalfInning = outsAfter;
        pitcherState.outs += outsGained;
        pitcherState.earnedRuns += countEarnedRunsInPlay(play);
        runsAllowed += countRunsInPlay(play);

        final rawEvent = play['result']?['event']?.toString() ?? '';
        if (rawEvent == 'Single' || rawEvent == 'Double' || rawEvent == 'Triple' || rawEvent == 'Home Run') {
          hitsAllowed++;
        }
        if (rawEvent.startsWith('Strikeout')) {
          strikeoutsRecorded++;
        }

        final half = translateHalf(isTop, lang);
        final opponentName = play['matchup']?['batter']?['fullName']?.toString() ?? '相手打者';
        final opponentId = play['matchup']?['batter']?['id'] as int?;
        final resultDesc = translateAtBatResult(
          play['result']?['description']?.toString(),
          play['result']?['event']?.toString(),
          lang,
        );
        final playEvents = play['playEvents'] as List<dynamic>? ?? [];
        final pitches = extractPitchDetails(playEvents, lang);
        final liveEra = hasEraBaseline ? computeLiveEra(_pitcherEraBaseline, pitcherState.toStatMap()) : null;
        final atBatIndex = play['about']?['atBatIndex'] as int?;

        for (final _ in pitches) {
          pitchCount++;
          inningPitches[inning] = (inningPitches[inning] ?? 0) + 1;
        }

        matchups.add({
          'seq': matchups.length + 1,
          'inning': inning,
          'half': half,
          'opponent': opponentName,
          'opponentId': opponentId,
          'result': resultDesc,
          'pitches': pitches,
          'liveEra': liveEra,
          'baseOutState': atBatIndex != null ? baseOutStates[atBatIndex] : null,
        });
      }
    }

    // ★ 最新の打者との対戦が一番上に来るよう表示用に逆順にする（絞り込み中はそのイニングのみ）
    final filteredMatchups = _selectedInning != null ? matchups.where((m) => m['inning'] == _selectedInning).toList() : matchups;
    final orderedMatchups = filteredMatchups.reversed.toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('イニング別 球数・疲労度メーター', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.blueAccent)),
        const SizedBox(height: 8),
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
                    const Text('総投球数', style: TextStyle(color: Colors.white70)),
                    Text('$pitchCount 球', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.amberAccent)),
                  ],
                ),
                if (matchups.isNotEmpty) ...[
                  const Divider(height: 20, color: Colors.white12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _StatcastMiniCell(label: '対戦打者数', val: '${matchups.length}'),
                      _StatcastMiniCell(label: '被安打数', val: '$hitsAllowed'),
                      _StatcastMiniCell(label: '奪三振数', val: '$strikeoutsRecorded'),
                      _StatcastMiniCell(
                        label: '失点数',
                        val: '$runsAllowed',
                        sub: runsAllowed != pitcherState.earnedRuns ? '(自責 ${pitcherState.earnedRuns})' : null,
                        highlight: runsAllowed > 0,
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 8),
                if (inningPitches.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text('タップしてそのイニングだけ絞り込み表示', style: TextStyle(fontSize: 10, color: Colors.white38)),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      ChoiceChip(
                        label: const Text('全イニング', style: TextStyle(fontSize: 12)),
                        selected: _selectedInning == null,
                        onSelected: (_) => setState(() => _selectedInning = null),
                        backgroundColor: const Color(0xFF2A2A3A),
                        selectedColor: Colors.blueAccent,
                        labelStyle: TextStyle(color: _selectedInning == null ? Colors.white : Colors.white70),
                      ),
                      ...inningPitches.entries.map((e) {
                        final isHigh = e.value >= 20;
                        final selected = _selectedInning == e.key;
                        return ChoiceChip(
                          label: Text(
                            '${e.key}回: ${e.value}球',
                            style: TextStyle(fontSize: 12, color: selected ? Colors.white : (isHigh ? Colors.redAccent : Colors.white70)),
                          ),
                          selected: selected,
                          onSelected: (_) => setState(() => _selectedInning = selected ? null : e.key),
                          backgroundColor: isHigh ? Colors.redAccent.withAlpha(50) : Colors.blueAccent.withAlpha(40),
                          selectedColor: Colors.blueAccent,
                        );
                      }),
                    ],
                  ),
                ] else
                  const Text('投球データなし', style: TextStyle(color: Colors.white38, fontSize: 12)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),

        if (matchups.isEmpty)
          const Card(
            color: Color(0xFF1E1E2C),
            child: Padding(padding: EdgeInsets.all(24), child: Center(child: Text('本日の対戦データはまだありません'))),
          )
        else ...[
          Text(
            _selectedInning != null ? '打者ごとの配球・ゾーン詳細 ($_selectedInning回のみ・新しい順)' : '打者ごとの配球・ゾーン詳細 (新しい順)',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.blueAccent),
          ),
          const SizedBox(height: 10),
          if (orderedMatchups.isEmpty)
            const Card(
              color: Color(0xFF1E1E2C),
              child: Padding(padding: EdgeInsets.all(24), child: Center(child: Text('このイニングの対戦データはありません'))),
            )
          else
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: orderedMatchups.length,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (context, idx) {
              // ★ 最新の打者との対戦が一番上に来る順（seqは元の対戦順の通し番号）
              final m = orderedMatchups[idx];
              return Card(
                color: const Color(0xFF1E1E2C),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              '第${m['seq']}打者（${m['inning']}回${m['half']}） vs ${m['opponent']}',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.blueAccent),
                            ),
                          ),
                          if (m['liveEra'] != null)
                            Text(
                              '防御率 ${formatEra(m['liveEra'] as double)}',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.amberAccent),
                            ),
                        ],
                      ),
                      if (m['baseOutState'] != null) ...[
                        const SizedBox(height: 2),
                        Text(m['baseOutState'] as String, style: const TextStyle(fontSize: 11, color: Colors.white54, fontWeight: FontWeight.bold)),
                      ],
                      const SizedBox(height: 4),
                      Text('${m['result']}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white)),
                      const SizedBox(height: 4),
                      if (m['opponentId'] != null)
                        HeadToHeadBadge(batterId: m['opponentId'] as int, pitcherId: player.id),
                      const Divider(height: 16, color: Colors.white12),
                      PitchLogWithZone(pitches: m['pitches'] as List<Map<String, dynamic>>),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ],
    );
  }

  // 打者向けセクション
  Widget _buildBatterLiveSection(JapanesePlayer player, List<dynamic> plays, AppLanguage lang) {
    List<Map<String, dynamic>> atBats = [];
    final baseOutStates = computeBaseOutStates(plays);
    final currentParkAbbr = _liveGameData?['gameData']?['teams']?['home']?['abbreviation']?.toString();

    for (final play in plays) {
      final batterId = play['matchup']?['batter']?['id'];
      if (batterId == player.id) {
        final rawEvent = play['result']?['event']?.toString();
        final result = translateAtBatResult(
          play['result']?['description']?.toString(),
          rawEvent,
          lang,
        );
        final opponentPitcherId = play['matchup']?['pitcher']?['id'] as int?;
        final opponentPitcherName = play['matchup']?['pitcher']?['fullName']?.toString() ?? '相手投手';
        final playEvents = play['playEvents'] as List<dynamic>? ?? [];
        final pitches = extractPitchDetails(playEvents, lang);

        Map<String, dynamic>? hitData;
        for (final event in playEvents) {
          if (event['hitData'] != null) {
            hitData = event['hitData'] as Map<String, dynamic>;
            break;
          }
        }

        final atBatIndex = play['about']?['atBatIndex'] as int?;

        atBats.add({
          'seq': atBats.length + 1,
          'inning': play['about']?['inning'] ?? 0,
          'half': translateHalf(play['about']?['isTopInning'] == true, lang),
          'result': result,
          'rawEvent': rawEvent,
          'opponentPitcherId': opponentPitcherId,
          'opponentPitcherName': opponentPitcherName,
          'hitData': hitData,
          'pitches': pitches,
          'baseOutState': atBatIndex != null ? baseOutStates[atBatIndex] : null,
        });
      }
    }

    if (atBats.isEmpty) {
      return const Card(
        color: Color(0xFF1E1E2C),
        child: Padding(padding: EdgeInsets.all(24), child: Center(child: Text('本日の打席データはまだありません'))),
      );
    }

    // ★ 最新の打席が一番上に来るよう表示用に逆順にする（第○打席の番号は元の時系列順のまま）
    final orderedAtBats = atBats.reversed.toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('本日の全打席 & Statcast 打球解析 (新しい順)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.blueAccent)),
        const SizedBox(height: 10),
        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: orderedAtBats.length,
          separatorBuilder: (_, _) => const SizedBox(height: 10),
          itemBuilder: (context, index) {
            final ab = orderedAtBats[index];
            final hit = ab['hitData'] as Map<String, dynamic>?;
            final pitches = ab['pitches'] as List<Map<String, dynamic>>;

            final double? launchSpeed = (hit?['launchSpeed'] as num?)?.toDouble();
            final double? launchAngle = (hit?['launchAngle'] as num?)?.toDouble();
            final double? totalDistance = (hit?['totalDistance'] as num?)?.toDouble();

            final bool isBarrel = launchSpeed != null &&
                launchAngle != null &&
                launchSpeed >= 98.0 &&
                launchAngle >= 24.0 &&
                launchAngle <= 34.0;

            final double? speedKmh = launchSpeed != null ? launchSpeed * 1.60934 : null;
            final double? distMeters = totalDistance != null ? totalDistance * 0.3048 : null;

            // ★ 他球場だったらホームランになっていたか(実際にHRだった打球は対象外)
            List<BallparkProfile> wouldBeParks = [];
            final rawEvent = ab['rawEvent'] as String?;
            final trajectory = hit?['trajectory']?.toString();
            if (rawEvent != 'Home Run' &&
                isEligibleForWouldBeHomer(trajectory: trajectory, launchAngle: launchAngle, totalDistance: totalDistance)) {
              final coords = hit?['coordinates'] as Map<String, dynamic>?;
              final coordX = (coords?['coordX'] as num?)?.toDouble();
              final coordY = (coords?['coordY'] as num?)?.toDouble();
              if (coordX != null && coordY != null && totalDistance != null) {
                final angle = sprayAngleFromCoords(coordX, coordY);
                wouldBeParks = wouldBeHomeRunParks(totalDistance: totalDistance, angleDeg: angle)
                    .where((p) => p.teamAbbr != currentParkAbbr)
                    .toList();
              }
            }

            return Card(
              color: isBarrel ? const Color(0xFF2C1E26) : const Color(0xFF1E1E2C),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: isBarrel ? Colors.redAccent : Colors.transparent, width: 1.5),
              ),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            '第${ab['seq']}打席（${ab['inning']}回${ab['half']}） vs ${ab['opponentPitcherName']}',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.blueAccent),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (isBarrel)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(color: Colors.redAccent, borderRadius: BorderRadius.circular(6)),
                            child: const Text('🔥 BARREL', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.white)),
                          ),
                      ],
                    ),
                    if (ab['baseOutState'] != null) ...[
                      const SizedBox(height: 4),
                      Text(ab['baseOutState'] as String, style: const TextStyle(fontSize: 11, color: Colors.white54, fontWeight: FontWeight.bold)),
                    ],
                    const SizedBox(height: 6),
                    Text(ab['result'] as String, style: const TextStyle(fontSize: 13, color: Colors.white)),
                    if (ab['opponentPitcherId'] != null) ...[
                      const SizedBox(height: 6),
                      HeadToHeadBadge(batterId: player.id, pitcherId: ab['opponentPitcherId'] as int),
                    ],

                    if (hit != null) ...[
                      const Divider(height: 16, color: Colors.white12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _StatcastMiniCell(
                            label: '打球初速',
                            val: launchSpeed != null ? '${launchSpeed.toStringAsFixed(1)} mph' : '-',
                            sub: speedKmh != null ? '(${speedKmh.toStringAsFixed(1)} km/h)' : null,
                            highlight: (launchSpeed ?? 0) >= 100,
                          ),
                          _StatcastMiniCell(
                            label: '打球角度',
                            val: launchAngle != null ? '${launchAngle.toStringAsFixed(0)}°' : '-',
                            sub: null,
                          ),
                          _StatcastMiniCell(
                            label: '推定飛距離',
                            val: totalDistance != null ? '${totalDistance.toStringAsFixed(0)} ft' : '-',
                            sub: distMeters != null ? '(${distMeters.toStringAsFixed(1)} m)' : null,
                            highlight: (totalDistance ?? 0) >= 400,
                          ),
                        ],
                      ),
                      if (wouldBeParks.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        _WouldBeHomerBadge(parks: wouldBeParks),
                      ],
                    ],

                    // ★ 配球ログ + ミニストライクゾーン
                    const Divider(height: 16, color: Colors.white12),
                    PitchLogWithZone(pitches: pitches),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

class _StatcastMiniCell extends StatelessWidget {
  final String label;
  final String val;
  final String? sub;
  final bool highlight;

  const _StatcastMiniCell({required this.label, required this.val, this.sub, this.highlight = false});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(label, style: const TextStyle(fontSize: 10, color: Colors.white54)),
        const SizedBox(height: 2),
        Text(
          val,
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: highlight ? Colors.orangeAccent : Colors.white),
        ),
        if (sub != null)
          Text(sub!, style: const TextStyle(fontSize: 9, color: Colors.white38)),
      ],
    );
  }
}

// ★ 「他球場ならホームランだった」打球の球場数バッジ。タップすると球場名の一覧を表示。
class _WouldBeHomerBadge extends StatelessWidget {
  final List<BallparkProfile> parks;

  const _WouldBeHomerBadge({required this.parks});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: () {
        showDialog(
          context: context,
          builder: (dialogContext) => AlertDialog(
            backgroundColor: const Color(0xFF1E1E2C),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            title: const Text('この打球がホームランになる球場', style: TextStyle(fontSize: 15, color: Colors.white)),
            content: SizedBox(
              width: double.maxFinite,
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final p in parks)
                    ListTile(
                      dense: true,
                      leading: const Icon(Icons.stadium, color: Colors.orangeAccent, size: 18),
                      title: Text('${p.teamName}(${p.parkName})', style: const TextStyle(fontSize: 13, color: Colors.white)),
                    ),
                  const SizedBox(height: 8),
                  const Text(
                    '飛距離とspray角度から算出した簡易的な目安です(壁の高さは考慮していません)。',
                    style: TextStyle(fontSize: 10, color: Colors.white38),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('閉じる')),
            ],
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.orangeAccent.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Colors.orangeAccent, width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.stadium, color: Colors.orangeAccent, size: 14),
            const SizedBox(width: 4),
            Text('🏟️ ${parks.length}球場でHRの当たり', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.orangeAccent)),
            const SizedBox(width: 2),
            const Icon(Icons.chevron_right, color: Colors.orangeAccent, size: 14),
          ],
        ),
      ),
    );
  }
}