class JapanesePlayer {
  final int id;
  final String nameJa;
  final String nameEn;
  final String teamName;
  final bool isPitcher;

  const JapanesePlayer({
    required this.id,
    required this.nameJa,
    required this.nameEn,
    required this.teamName,
    required this.isPitcher,
  });
}

// アプリで管理する日本人MLB選手一覧
const List<JapanesePlayer> japanesePlayers = [
  JapanesePlayer(id: 660271, nameJa: '大谷 翔平', nameEn: 'Shohei Ohtani', teamName: 'LAD', isPitcher: true),
  JapanesePlayer(id: 808967, nameJa: '山本 由伸', nameEn: 'Yoshinobu Yamamoto', teamName: 'LAD', isPitcher: true),
  JapanesePlayer(id: 684007, nameJa: '今永 昇太', nameEn: 'Shota Imanaga', teamName: 'CHC', isPitcher: true),
  JapanesePlayer(id: 506433, nameJa: 'ダルビッシュ 有', nameEn: 'Yu Darvish', teamName: 'SD', isPitcher: true),
  JapanesePlayer(id: 673540, nameJa: '千賀 滉大', nameEn: 'Kodai Senga', teamName: 'NYM', isPitcher: true),
  JapanesePlayer(id: 673548, nameJa: '鈴木 誠也', nameEn: 'Seiya Suzuki', teamName: 'CHC', isPitcher: false),
  JapanesePlayer(id: 807799, nameJa: '吉田 正尚', nameEn: 'Masataka Yoshida', teamName: 'BOS', isPitcher: false),
  JapanesePlayer(id: 673513, nameJa: '松井 裕樹', nameEn: 'Yuki Matsui', teamName: 'SD', isPitcher: true),
];