// lib/models/player.dart

class JapanesePlayer {
  final int id;
  final String nameJa;
  final String nameEn;
  final String teamName;
  final int teamId;
  final bool isPitcher;

  const JapanesePlayer({
    required this.id,
    required this.nameJa,
    required this.nameEn,
    required this.teamName,
    required this.teamId,
    required this.isPitcher,
  });
}

// ★ 2026年シーズン MLB在籍 日本人選手 全16名（MLB公式ID完全対応）
const List<JapanesePlayer> japanesePlayers = [
  // --- 打者・二刀流 ---
  JapanesePlayer(id: 660271, nameJa: '大谷 翔平', nameEn: 'Shohei Ohtani', teamName: 'LAD', teamId: 119, isPitcher: false),
  JapanesePlayer(id: 673548, nameJa: '鈴木 誠也', nameEn: 'Seiya Suzuki', teamName: 'CHC', teamId: 112, isPitcher: false),
  JapanesePlayer(id: 807799, nameJa: '吉田 正尚', nameEn: 'Masataka Yoshida', teamName: 'BOS', teamId: 111, isPitcher: false),
  JapanesePlayer(id: 808959, nameJa: '村上 宗隆', nameEn: 'Munetaka Murakami', teamName: 'CWS', teamId: 145, isPitcher: false),
  JapanesePlayer(id: 672960, nameJa: '岡本 和真', nameEn: 'Kazuma Okamoto', teamName: 'TOR', teamId: 141, isPitcher: false),
  JapanesePlayer(id: 663457, nameJa: 'ヌートバー', nameEn: 'Lars Nootbaar', teamName: 'ARI', teamId: 109, isPitcher: false),
  // 2026年5月25日メジャー初昇格（2023年ドラフト11巡目、オレゴン大出身）
  JapanesePlayer(id: 807747, nameJa: '西田 陸浮', nameEn: 'Rikuu Nishida', teamName: 'CWS', teamId: 145, isPitcher: false),

  // --- 投手 ---
  JapanesePlayer(id: 808967, nameJa: '山本 由伸', nameEn: 'Yoshinobu Yamamoto', teamName: 'LAD', teamId: 119, isPitcher: true),
  JapanesePlayer(id: 808963, nameJa: '佐々木 朗希', nameEn: 'Roki Sasaki', teamName: 'LAD', teamId: 119, isPitcher: true),
  JapanesePlayer(id: 684007, nameJa: '今永 昇太', nameEn: 'Shota Imanaga', teamName: 'CHC', teamId: 112, isPitcher: true),
  JapanesePlayer(id: 506433, nameJa: 'ダルビッシュ 有', nameEn: 'Yu Darvish', teamName: 'SD', teamId: 135, isPitcher: true),
  JapanesePlayer(id: 673513, nameJa: '松井 裕樹', nameEn: 'Yuki Matsui', teamName: 'SD', teamId: 135, isPitcher: true),
  JapanesePlayer(id: 579328, nameJa: '菊池 雄星', nameEn: 'Yusei Kikuchi', teamName: 'LAA', teamId: 108, isPitcher: true),
  JapanesePlayer(id: 673540, nameJa: '千賀 滉大', nameEn: 'Kodai Senga', teamName: 'NYM', teamId: 121, isPitcher: true),
  JapanesePlayer(id: 608372, nameJa: '菅野 智之', nameEn: 'Tomoyuki Sugano', teamName: 'COL', teamId: 115, isPitcher: true),
  JapanesePlayer(id: 837227, nameJa: '今井 達也', nameEn: 'Tatsuya Imai', teamName: 'HOU', teamId: 117, isPitcher: true),
];