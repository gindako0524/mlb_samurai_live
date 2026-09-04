import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'models/player.dart';
import 'models/schedule.dart';
import 'views/schedule_view.dart';
import 'views/live_view.dart';
import 'views/stats_view.dart';
import 'views/ranking_view.dart';
import 'views/standings_view.dart';
import 'views/vs_matchup_view.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('ja');
  runApp(
    const ProviderScope(
      child: MlbSamuraiApp(),
    ),
  );
}

class MlbSamuraiApp extends StatelessWidget {
  const MlbSamuraiApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MLB Samurai Live',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blueAccent,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const MainNavigationScreen(),
    );
  }
}

class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  int _currentIndex = 0;
  GameScheduleItem? _selectedGame;
  JapanesePlayer? _selectedPlayer;

  void _handleSelectGame(GameScheduleItem game, JapanesePlayer player) {
    setState(() {
      _selectedGame = game;
      _selectedPlayer = player;
      _currentIndex = 1; // ライブ観戦画面へ自動遷移
    });
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> screens = [
      ScheduleView(onSelectGame: _handleSelectGame),
      LiveView(
        initialPlayer: _selectedPlayer,
        initialGame: _selectedGame,
      ),
      const StatsView(),
      const RankingView(),
      const StandingsView(),
      const VsMatchupView(),
    ];

    return Scaffold(
      body: screens[_currentIndex],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.calendar_month),
            label: '試合日程',
          ),
          NavigationDestination(
            icon: Icon(Icons.sports_baseball),
            label: 'ライブ観戦',
          ),
          NavigationDestination(
            icon: Icon(Icons.analytics),
            label: '詳細スタッツ',
          ),
          NavigationDestination(
            icon: Icon(Icons.leaderboard),
            label: 'ランキング',
          ),
          NavigationDestination(
            icon: Icon(Icons.scoreboard),
            label: '順位表',
          ),
          NavigationDestination(
            icon: Icon(Icons.compare_arrows),
            label: 'VS',
          ),
        ],
      ),
    );
  }
}