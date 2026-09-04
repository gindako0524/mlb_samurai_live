import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart';
import '../utils/jst_time.dart';
import '../models/player.dart';
import '../models/schedule.dart';
import '../services/schedule_provider.dart';
import '../services/pinned_players_provider.dart';
import 'today_summary_view.dart';
import 'settings_view.dart';
import 'game_detail_view.dart';

/// 試合日程の表示範囲：日本人選手所属チームのみ／MLB全体
enum ScheduleScope { japaneseTeams, allMlb }

/// リーグ内訳フィルター（MLB全体表示の時のみ意味を持つ）
enum ScheduleLeagueFilter { all, al, nl }

// MLB全30球団のチームID → リーグ（AL/NL）対応表（ホームチームのリーグで分類する）
const Map<int, String> _teamLeagueMap = {
  108: 'AL', 109: 'NL', 110: 'AL', 111: 'AL', 112: 'NL', 113: 'NL', 114: 'AL', 115: 'NL',
  116: 'AL', 117: 'AL', 118: 'AL', 119: 'NL', 120: 'NL', 121: 'NL', 133: 'AL', 134: 'NL',
  135: 'NL', 136: 'AL', 137: 'NL', 138: 'NL', 139: 'AL', 140: 'AL', 141: 'AL', 142: 'AL',
  143: 'NL', 144: 'NL', 145: 'AL', 146: 'NL', 147: 'AL', 158: 'NL',
};

class ScheduleView extends ConsumerStatefulWidget {
  final Function(GameScheduleItem game, JapanesePlayer player) onSelectGame;

  const ScheduleView({super.key, required this.onSelectGame});

  @override
  ConsumerState<ScheduleView> createState() => _ScheduleViewState();
}

class _ScheduleViewState extends ConsumerState<ScheduleView> {
  Timer? _countdownTimer;
  DateTime _focusedDay = nowJst();
  DateTime _selectedDay = nowJst();
  CalendarFormat _calendarFormat = CalendarFormat.month;
  bool _isCalendarExpanded = false; // ★ カレンダーは初期状態で折りたたんでおく
  ScheduleScope _scope = ScheduleScope.japaneseTeams;
  ScheduleLeagueFilter _leagueFilter = ScheduleLeagueFilter.all;

  void _shiftSelectedDay(int deltaDays) {
    setState(() {
      _selectedDay = _selectedDay.add(Duration(days: deltaDays));
      _focusedDay = _selectedDay;
    });
  }

  @override
  void initState() {
    super.initState();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    super.dispose();
  }

  String _formatPreciseCountdown(DateTime gameTimeJst, String status) {
    final now = nowJst();
    if (status == 'Live') return '試合進行中 (LIVE)';
    if (status == 'Final') return '試合終了';

    final diff = gameTimeJst.difference(now);
    if (diff.isNegative) {
      return status == 'Live' ? '試合中' : '試合中 / 終了間近';
    }

    final hours = diff.inHours;
    final minutes = diff.inMinutes % 60;
    final seconds = diff.inSeconds % 60;

    if (hours > 0) {
      return '開始まで あと $hours時間 $minutes分 $seconds秒';
    } else if (minutes > 0) {
      return '開始まで あと $minutes分 $seconds秒';
    } else {
      return 'まもなく開始! あと $seconds秒';
    }
  }

  DateTime _dateOnly(DateTime dt) => DateTime(dt.year, dt.month, dt.day);

  @override
  Widget build(BuildContext context) {
    // ★ 表示スコープに応じて取得元を切り替える。「MLB全体」を選んだ時のみ
    //   全球団版のプロバイダーを参照する（Riverpodは遅延評価のため、選ばない限り
    //   重いフェッチは発生しない）。
    final scheduleAsync = _scope == ScheduleScope.allMlb
        ? ref.watch(allMlbSeasonScheduleProvider)
        : ref.watch(seasonScheduleProvider);
    final pinnedIds = ref.watch(pinnedPlayersProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.sports_baseball, color: Colors.blueAccent),
            SizedBox(width: 8),
            Text('試合日程 & 予告先発', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ],
        ),
        actions: [
          IconButton(
            tooltip: '本日の日本人選手成績まとめ',
            icon: const Icon(Icons.today),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const TodaySummaryView()),
              );
            },
          ),
          IconButton(
            tooltip: '日程を最新に更新',
            icon: const Icon(Icons.refresh),
            onPressed: () => _scope == ScheduleScope.allMlb
                ? ref.refresh(allMlbSeasonScheduleProvider)
                : ref.refresh(seasonScheduleProvider),
          ),
          IconButton(
            tooltip: '設定（表示言語・ピン留め選手の管理）',
            icon: const Icon(Icons.settings),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SettingsView()),
              );
            },
          ),
        ],
      ),
      body: scheduleAsync.when(
        loading: () => const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 12),
              Text('シーズン全体の日程を取得中...', style: TextStyle(color: Colors.white70)),
            ],
          ),
        ),
        error: (err, stack) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, color: Colors.redAccent, size: 40),
                const SizedBox(height: 12),
                Text('日程データの取得エラー\n$err', textAlign: TextAlign.center, style: const TextStyle(color: Colors.redAccent)),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  icon: const Icon(Icons.refresh),
                  label: const Text('再試行'),
                  onPressed: () => _scope == ScheduleScope.allMlb
                      ? ref.refresh(allMlbSeasonScheduleProvider)
                      : ref.refresh(seasonScheduleProvider),
                ),
              ],
            ),
          ),
        ),
        data: (rawGames) {
          // ★ 「MLB全体」表示時のみ、リーグ内訳フィルター(AL/NL)をホームチームのリーグで適用する
          final games = (_scope == ScheduleScope.allMlb && _leagueFilter != ScheduleLeagueFilter.all)
              ? rawGames.where((g) {
                  final league = _teamLeagueMap[g.homeTeamId];
                  return league == (_leagueFilter == ScheduleLeagueFilter.al ? 'AL' : 'NL');
                }).toList()
              : rawGames;

          if (games.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.event_busy, size: 48, color: Colors.white38),
                  const SizedBox(height: 12),
                  Text(
                    _scope == ScheduleScope.allMlb ? '該当する試合予定が見つかりませんでした' : '日本人選手の試合予定が見つかりませんでした',
                    style: const TextStyle(color: Colors.white70, fontSize: 14),
                  ),
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.refresh),
                    label: const Text('再読み込み'),
                    onPressed: () => _scope == ScheduleScope.allMlb
                        ? ref.refresh(allMlbSeasonScheduleProvider)
                        : ref.refresh(seasonScheduleProvider),
                  ),
                ],
              ),
            );
          }

          // ★ 日付ごとに試合をグルーピング（カレンダーのマーカー表示・当日リスト抽出に使用）
          final Map<DateTime, List<GameScheduleItem>> gamesByDay = {};
          for (final g in games) {
            final key = _dateOnly(g.gameTimeJst);
            gamesByDay.putIfAbsent(key, () => []).add(g);
          }

          final selectedGames = List<GameScheduleItem>.from(gamesByDay[_dateOnly(_selectedDay)] ?? []);
          // ★ 日本人対決（参加する日本人選手のチームが2種類以上）を最優先、
          //   次にピン留め選手が出場する試合を優先して上位に表示する
          selectedGames.sort((a, b) {
            final aIsMatchup = a.participatingJapanesePlayers.map((p) => p.teamId).toSet().length >= 2;
            final bIsMatchup = b.participatingJapanesePlayers.map((p) => p.teamId).toSet().length >= 2;
            if (aIsMatchup != bIsMatchup) return aIsMatchup ? -1 : 1;

            final aHasPinned = a.participatingJapanesePlayers.any((p) => pinnedIds.contains(p.id));
            final bHasPinned = b.participatingJapanesePlayers.any((p) => pinnedIds.contains(p.id));
            if (aHasPinned != bHasPinned) return aHasPinned ? -1 : 1;

            return a.gameTimeJst.compareTo(b.gameTimeJst);
          });

          return Column(
            children: [
              // --- 表示スコープ切替（日本人選手所属チーム／MLB全体）＋ リーグ内訳 ---
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(color: const Color(0xFF1E1E2C), borderRadius: BorderRadius.circular(10)),
                      child: Row(
                        children: [
                          Expanded(
                            child: GestureDetector(
                              onTap: () => setState(() => _scope = ScheduleScope.japaneseTeams),
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 8),
                                decoration: BoxDecoration(
                                  color: _scope == ScheduleScope.japaneseTeams ? Colors.blueAccent : Colors.transparent,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                alignment: Alignment.center,
                                child: const Text('日本人選手所属チーム', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                              ),
                            ),
                          ),
                          Expanded(
                            child: GestureDetector(
                              onTap: () => setState(() => _scope = ScheduleScope.allMlb),
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 8),
                                decoration: BoxDecoration(
                                  color: _scope == ScheduleScope.allMlb ? Colors.blueAccent : Colors.transparent,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                alignment: Alignment.center,
                                child: const Text('MLB全体', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (_scope == ScheduleScope.allMlb) ...[
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Wrap(
                          spacing: 8,
                          children: [
                            ChoiceChip(
                              label: const Text('全体'),
                              selected: _leagueFilter == ScheduleLeagueFilter.all,
                              onSelected: (_) => setState(() => _leagueFilter = ScheduleLeagueFilter.all),
                            ),
                            ChoiceChip(
                              label: const Text('ア・リーグ (AL)'),
                              selected: _leagueFilter == ScheduleLeagueFilter.al,
                              onSelected: (_) => setState(() => _leagueFilter = ScheduleLeagueFilter.al),
                            ),
                            ChoiceChip(
                              label: const Text('ナ・リーグ (NL)'),
                              selected: _leagueFilter == ScheduleLeagueFilter.nl,
                              onSelected: (_) => setState(() => _leagueFilter = ScheduleLeagueFilter.nl),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              // --- コンパクトな日付ナビゲーションバー（常時表示） ---
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.chevron_left, color: Colors.white70),
                      onPressed: () => _shiftSelectedDay(-1),
                    ),
                    Expanded(
                      child: InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: () => setState(() => _isCalendarExpanded = !_isCalendarExpanded),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.calendar_month, size: 18, color: Colors.blueAccent),
                              const SizedBox(width: 8),
                              Text(
                                DateFormat('yyyy年M月d日 (E)', 'ja').format(_selectedDay),
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.blueAccent),
                              ),
                              const SizedBox(width: 6),
                              Icon(
                                _isCalendarExpanded ? Icons.expand_less : Icons.expand_more,
                                size: 20,
                                color: Colors.white54,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.chevron_right, color: Colors.white70),
                      onPressed: () => _shiftSelectedDay(1),
                    ),
                  ],
                ),
              ),

              // --- 展開式カレンダー（タップ時のみ表示） ---
              AnimatedSize(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeInOut,
                child: _isCalendarExpanded
                    ? TableCalendar<GameScheduleItem>(
                        firstDay: DateTime.utc(2026, 3, 1),
                        lastDay: DateTime.utc(2026, 11, 30),
                        focusedDay: _focusedDay,
                        currentDay: nowJst(),
                        selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
                        calendarFormat: _calendarFormat,
                        availableCalendarFormats: const {
                          CalendarFormat.month: '月',
                          CalendarFormat.twoWeeks: '2週間',
                          CalendarFormat.week: '週',
                        },
                        eventLoader: (day) => gamesByDay[_dateOnly(day)] ?? [],
                        onFormatChanged: (format) => setState(() => _calendarFormat = format),
                        onDaySelected: (selectedDay, focusedDay) {
                          setState(() {
                            _selectedDay = selectedDay;
                            _focusedDay = focusedDay;
                            _isCalendarExpanded = false; // 日付を選んだら自動で閉じる
                          });
                        },
                        onPageChanged: (focusedDay) {
                          _focusedDay = focusedDay;
                        },
                        locale: 'ja',
                        daysOfWeekHeight: 24,
                        calendarStyle: CalendarStyle(
                          outsideDaysVisible: false,
                          todayDecoration: BoxDecoration(
                            color: Colors.blueAccent.withAlpha(90),
                            shape: BoxShape.circle,
                          ),
                          selectedDecoration: const BoxDecoration(
                            color: Colors.amberAccent,
                            shape: BoxShape.circle,
                          ),
                          selectedTextStyle: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
                          markerDecoration: const BoxDecoration(
                            color: Colors.greenAccent,
                            shape: BoxShape.circle,
                          ),
                          markersMaxCount: 1,
                          weekendTextStyle: const TextStyle(color: Colors.white70),
                          defaultTextStyle: const TextStyle(color: Colors.white),
                          outsideTextStyle: const TextStyle(color: Colors.white24),
                        ),
                        headerStyle: const HeaderStyle(
                          formatButtonShowsNext: false,
                          titleTextStyle: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                          formatButtonTextStyle: TextStyle(color: Colors.blueAccent),
                          leftChevronIcon: Icon(Icons.chevron_left, color: Colors.white70),
                          rightChevronIcon: Icon(Icons.chevron_right, color: Colors.white70),
                        ),
                        daysOfWeekStyle: const DaysOfWeekStyle(
                          weekdayStyle: TextStyle(color: Colors.white54, fontSize: 12),
                          weekendStyle: TextStyle(color: Colors.white38, fontSize: 12),
                        ),
                      )
                    : const SizedBox(width: double.infinity),
              ),

              const Divider(height: 1, color: Colors.white12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Row(
                  children: [
                    const Icon(Icons.event, size: 16, color: Colors.amberAccent),
                    const SizedBox(width: 6),
                    Text(
                      DateFormat('M月d日 (E)', 'ja').format(_selectedDay),
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.amberAccent),
                    ),
                    const SizedBox(width: 8),
                    Text('${selectedGames.length}試合', style: const TextStyle(fontSize: 12, color: Colors.white54)),
                  ],
                ),
              ),
              Expanded(
                child: selectedGames.isEmpty
                    ? const Center(
                        child: Text('この日は日本人選手の試合予定がありません', style: TextStyle(color: Colors.white54)),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                        itemCount: selectedGames.length,
                        itemBuilder: (context, index) {
                          final game = selectedGames[index];
                          final isLive = game.status == 'Live';
                          final isFinal = game.status == 'Final';
                          final timeStr = DateFormat('HH:mm', 'ja').format(game.gameTimeJst);
                          final countdown = _formatPreciseCountdown(game.gameTimeJst, game.status);

                          // ★ 参加する日本人選手のチームIDが2種類以上あれば「日本人対決」
                          final isJapaneseMatchup =
                              game.participatingJapanesePlayers.map((p) => p.teamId).toSet().length >= 2;
                          // ★ ピン留めした選手が出場する試合かどうか
                          final hasPinnedPlayer =
                              game.participatingJapanesePlayers.any((p) => pinnedIds.contains(p.id));

                          return Card(
                            margin: const EdgeInsets.only(bottom: 14),
                            elevation: isJapaneseMatchup ? 8 : (hasPinnedPlayer ? 6 : 4),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                              side: BorderSide(
                                color: (isJapaneseMatchup || hasPinnedPlayer)
                                    ? Colors.amberAccent
                                    : (isLive ? Colors.redAccent : (isFinal ? Colors.white10 : Colors.blueAccent.withAlpha(80))),
                                width: isJapaneseMatchup ? 2.5 : (hasPinnedPlayer ? 2.0 : (isLive ? 2 : 1)),
                              ),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (isJapaneseMatchup) ...[
                                    Container(
                                      width: double.infinity,
                                      padding: const EdgeInsets.symmetric(vertical: 6),
                                      decoration: BoxDecoration(
                                        color: Colors.amberAccent.withAlpha(30),
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(color: Colors.amberAccent.withAlpha(120)),
                                      ),
                                      child: const Center(
                                        child: Text(
                                          '🇯🇵 日本人対決 🇯🇵',
                                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.amberAccent),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 10),
                                  ] else if (hasPinnedPlayer) ...[
                                    Container(
                                      width: double.infinity,
                                      padding: const EdgeInsets.symmetric(vertical: 6),
                                      decoration: BoxDecoration(
                                        color: Colors.amberAccent.withAlpha(30),
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(color: Colors.amberAccent.withAlpha(120)),
                                      ),
                                      child: const Center(
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(Icons.push_pin, size: 13, color: Colors.amberAccent),
                                            SizedBox(width: 6),
                                            Text(
                                              'ピン留め選手の出場試合',
                                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.amberAccent),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 10),
                                  ],
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Row(
                                        children: [
                                          Icon(Icons.schedule, size: 16, color: Colors.blueAccent[100]),
                                          const SizedBox(width: 6),
                                          Text(timeStr, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                                        ],
                                      ),
                                      if (isLive)
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: Colors.redAccent,
                                            borderRadius: BorderRadius.circular(12),
                                          ),
                                          child: const Row(
                                            children: [
                                              CircleAvatar(radius: 3, backgroundColor: Colors.white),
                                              SizedBox(width: 5),
                                              Text('LIVE', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                                            ],
                                          ),
                                        )
                                      else
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                          decoration: BoxDecoration(
                                            color: isFinal ? Colors.white10 : Colors.blue.withAlpha(40),
                                            borderRadius: BorderRadius.circular(6),
                                          ),
                                          child: Text(
                                            countdown,
                                            style: TextStyle(
                                              color: isFinal ? Colors.white54 : Colors.lightBlueAccent,
                                              fontSize: 11,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                  const Divider(height: 20, color: Colors.white12),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(game.awayTeam, style: const TextStyle(fontSize: 15)),
                                            const SizedBox(height: 4),
                                            Text(game.homeTeam, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                                          ],
                                        ),
                                      ),
                                      if (isLive || isFinal) ...[
                                        Column(
                                          crossAxisAlignment: CrossAxisAlignment.end,
                                          children: [
                                            Text(
                                              '${game.awayScore} - ${game.homeScore}',
                                              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white),
                                            ),
                                            Text(
                                              game.currentInning,
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: isLive ? Colors.amberAccent : Colors.white54,
                                                fontWeight: isLive ? FontWeight.bold : FontWeight.normal,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ],
                                  ),
                                  if (game.probablePitcherJa != null) ...[
                                    const SizedBox(height: 10),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: Colors.amber.withAlpha(30),
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(color: Colors.amberAccent.withAlpha(80)),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(Icons.sports, size: 14, color: Colors.amberAccent),
                                          const SizedBox(width: 6),
                                          Text(game.probablePitcherJa!, style: const TextStyle(fontSize: 11, color: Colors.amberAccent, fontWeight: FontWeight.bold)),
                                        ],
                                      ),
                                    ),
                                  ],
                                  const SizedBox(height: 12),
                                  Wrap(
                                    spacing: 4,
                                    runSpacing: 6,
                                    crossAxisAlignment: WrapCrossAlignment.center,
                                    children: game.participatingJapanesePlayers.expand((player) {
                                      final isPinned = pinnedIds.contains(player.id);
                                      return [
                                        ActionChip(
                                          avatar: CircleAvatar(
                                            backgroundColor: player.isPitcher ? Colors.greenAccent : Colors.orangeAccent,
                                            child: Text(
                                              player.isPitcher ? '投' : '打',
                                              style: const TextStyle(fontSize: 10, color: Colors.black, fontWeight: FontWeight.bold),
                                            ),
                                          ),
                                          label: Text('${player.nameJa} の観戦へ'),
                                          labelStyle: const TextStyle(fontSize: 12),
                                          onPressed: () => widget.onSelectGame(game, player),
                                        ),
                                        InkWell(
                                          borderRadius: BorderRadius.circular(14),
                                          onTap: () => ref.read(pinnedPlayersProvider.notifier).toggle(player.id),
                                          child: Padding(
                                            padding: const EdgeInsets.symmetric(horizontal: 2),
                                            child: Icon(
                                              isPinned ? Icons.push_pin : Icons.push_pin_outlined,
                                              size: 18,
                                              color: isPinned ? Colors.amberAccent : Colors.white38,
                                            ),
                                          ),
                                        ),
                                      ];
                                    }).toList(),
                                  ),
                                  const SizedBox(height: 10),
                                  Align(
                                    alignment: Alignment.centerRight,
                                    child: OutlinedButton.icon(
                                      icon: const Icon(Icons.list_alt, size: 16),
                                      label: const Text('スタメン・ボックススコア', style: TextStyle(fontSize: 12)),
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: Colors.white70,
                                        side: const BorderSide(color: Colors.white24),
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                      ),
                                      onPressed: () {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) => GameDetailView(
                                              gamePk: game.gamePk,
                                              awayTeam: game.awayTeam,
                                              homeTeam: game.homeTeam,
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}