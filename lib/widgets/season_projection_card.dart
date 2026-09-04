// lib/widgets/season_projection_card.dart
//
// シーズン終了時点の予想成績カード（日本人選手向け）。
//
// FanGraphs(ZiPS/Steamer)・Baseball Prospectus(PECOTA)・THE BAT X などの
// 本格的な投影システムは、無料の公開APIを提供していない（有料 or
// スクレイピング前提のサイトのみ）ため利用できない。そのため、ここでは
// 「現在のペースがシーズン終了まで続いたら」という単純なペース換算を
// 自前で計算して表示する。ZiPS/PECOTA等のような加齢・回帰・対戦相手調整は
// 一切行っていない、あくまで簡易な目安であることをUI上で明示する。
//
// ★ ペース換算の分母には「選手個人の出場試合数」ではなく「所属チームの
//   消化試合数」を使う。理由は2つ：
//   1) シーズン途中出場・故障離脱などで出場試合数が少ない選手を、
//      個人の出場試合数だけで162試合分に単純外挿すると過大な数字になる
//      （例: 30試合で10本塁打の選手を162/30倍すると54本塁打という
//      非現実的な数字になってしまう）。
//   2) 投手は「登板試合数」がそもそも162試合と比較する数字ではない
//      （先発投手は年間25〜32登板程度）。個人の登板数を分母に162試合へ
//      外挿すると、勝利数・奪三振数が実際にはあり得ない数値まで
//      膨れ上がってしまう（実測で確認したバグ：25登板・12勝の投手が
//      78勝という表示になっていた）。
//   「チームの消化試合数」を分母にすることで、上記どちらの問題も解消される
//   （＝残りのチーム試合数に対して、選手が今のペースを維持した場合の
//   加算分を見積もる「残り試合(ROS)」方式と数学的に同じ結果になる）。

import 'package:flutter/material.dart';

const int _fullSeasonGames = 162;

class SeasonProjectionCard extends StatelessWidget {
  final Map<String, dynamic> seasonStats;
  final bool isPitcher;
  final int? teamGamesPlayed;

  const SeasonProjectionCard({
    super.key,
    required this.seasonStats,
    required this.isPitcher,
    required this.teamGamesPlayed,
  });

  double? _num(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString());
  }

  @override
  Widget build(BuildContext context) {
    final teamGames = teamGamesPlayed;
    if (teamGames == null || teamGames <= 0) return const SizedBox.shrink();

    final paceFactor = _fullSeasonGames / teamGames;
    // ★ 既にチームが162試合を消化・超過している場合はこれ以上の伸びしろが無いため非表示
    if (paceFactor <= 1.0) return const SizedBox.shrink();

    int? projCount(String key) {
      final v = _num(seasonStats[key]);
      if (v == null) return null;
      return (v * paceFactor).round();
    }

    final List<MapEntry<String, String>> projected = [];
    if (isPitcher) {
      // ★ 投手は残り試合すべてに登板するわけではない(先発なら5〜6試合に1回程度)。
      //   「これまでの登板数 ÷ チームの消化試合数」を登板頻度とみなし、
      //   残りのチーム試合数に掛けることで、ローテーションを踏まえた
      //   残り登板数の見積もりを算出して表示する。
      //   ※下記の勝敗・奪三振等の予想値自体は、この登板頻度を反映した
      //   「チーム消化試合数を分母にしたペース換算」と数学的に同じ計算式のため、
      //   もともと「残り試合すべてに登板する」前提にはなっていない。
      final gamesStarted = _num(seasonStats['gamesStarted']);
      final gamesPitched = _num(seasonStats['gamesPitched']) ?? _num(seasonStats['gamesPlayed']);
      final playerAppearances = (gamesStarted != null && gamesStarted > 0) ? gamesStarted : gamesPitched;
      if (playerAppearances != null && playerAppearances > 0) {
        final remainingTeamGames = _fullSeasonGames - teamGames;
        final estRemainingAppearances = remainingTeamGames * playerAppearances / teamGames;
        projected.add(MapEntry('予想残り登板数', '${estRemainingAppearances.round()}試合'));
      }
      final wins = projCount('wins');
      final losses = projCount('losses');
      if (wins != null && losses != null) projected.add(MapEntry('勝敗', '$wins勝$losses敗'));
      final so = projCount('strikeOuts');
      if (so != null) projected.add(MapEntry('奪三振', '$so'));
      final bb = projCount('baseOnBalls');
      if (bb != null) projected.add(MapEntry('与四球', '$bb'));
      final sv = projCount('saves');
      if (sv != null && sv > 0) projected.add(MapEntry('セーブ', '$sv'));
      final ip = _num(seasonStats['inningsPitched']);
      if (ip != null) projected.add(MapEntry('投球回目安', (ip * paceFactor).toStringAsFixed(0)));
    } else {
      final hr = projCount('homeRuns');
      if (hr != null) projected.add(MapEntry('本塁打', '$hr'));
      final rbi = projCount('rbi');
      if (rbi != null) projected.add(MapEntry('打点', '$rbi'));
      final hits = projCount('hits');
      if (hits != null) projected.add(MapEntry('安打', '$hits'));
      final runs = projCount('runs');
      if (runs != null) projected.add(MapEntry('得点', '$runs'));
      final sb = projCount('stolenBases');
      if (sb != null) projected.add(MapEntry('盗塁', '$sb'));
    }

    if (projected.isEmpty) return const SizedBox.shrink();

    final rateLabel = isPitcher ? '防御率' : '打率';
    final rateVal = (seasonStats[isPitcher ? 'era' : 'avg'])?.toString() ?? '-';
    final playerGames = _num(seasonStats['gamesPlayed']);

    return Card(
      color: const Color(0xFF241E2C),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: Colors.purpleAccent, width: 1)),
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: const [
                Icon(Icons.query_stats, color: Colors.purpleAccent, size: 18),
                SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'シーズン終了予想成績（残り試合ペース換算）',
                    style: TextStyle(fontSize: 12, color: Colors.purpleAccent, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const Divider(height: 20, color: Colors.white12),
            Wrap(
              spacing: 20,
              runSpacing: 10,
              children: [
                _MiniField(label: rateLabel, val: rateVal),
                for (final p in projected) _MiniField(label: p.key, val: p.value),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              isPitcher
                  ? 'チームの消化試合数（$teamGames試合${playerGames != null ? '中、本人登板${playerGames.round()}試合' : ''}）を基準に、'
                      '残り${_fullSeasonGames - teamGames}試合における「これまでの登板頻度」から残り登板数を見積もり、'
                      'その分を今のペースで加算した単純な目安です（残り全試合に登板する前提ではありません）。'
                      'ZiPS・PECOTA・THE BAT Xのような加齢・回帰・残り対戦相手を考慮した本格的な投影ではありません。'
                  : 'チームの消化試合数（$teamGames試合${playerGames != null ? '中、本人出場${playerGames.round()}試合' : ''}）を基準に、'
                      '残り${_fullSeasonGames - teamGames}試合も今のペースが続いた場合の単純な目安です。'
                      'ZiPS・PECOTA・THE BAT Xのような加齢・回帰・残り対戦相手を考慮した本格的な投影ではありません。',
              style: const TextStyle(fontSize: 10, color: Colors.white38),
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniField extends StatelessWidget {
  final String label;
  final String val;

  const _MiniField({required this.label, required this.val});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 10, color: Colors.white54)),
        const SizedBox(height: 2),
        Text(val, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white)),
      ],
    );
  }
}
