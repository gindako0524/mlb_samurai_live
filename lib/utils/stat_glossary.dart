// lib/utils/stat_glossary.dart
//
// セイバーメトリクス・成績略称の簡潔な解説辞書。MLB公式APIのフィールド名
// （'avg', 'era', 'whip'など）をキーにすることで、詳細スタッツ・通算成績・
// ランキング画面など複数箇所から同じ辞書を再利用できるようにしている。
// 対象は「打率」「本塁打」のような一目でわかる基本項目ではなく、
// 初心者には意味が伝わりにくい計算・略称系の指標に絞っている。

import 'package:flutter/material.dart';

const Map<String, String> statGlossary = {
  'avg': '安打÷打数。打席で安打を打てた割合。',
  'obp': '四球・死球も含め、打者がどれだけ塁に出られたかの割合。',
  'slg': '打数あたりの塁打数。長打力の指標。',
  'ops': '出塁率＋長打率。出塁力と長打力を合わせた総合的な打撃指標。',
  'babip': 'フェアゾーンに飛んだ打球が安打になった割合。',
  'risp': '得点圏（二塁・三塁に走者）での打率。勝負強さの目安。',
  'era': '9イニングあたりの平均自責点。低いほど好成績。',
  'whip': '1イニングあたりに許した走者数（安打＋四球）。低いほど好成績。',
  'strikeoutsPer9Inn': '9イニングあたりの奪三振数。',
  'walksPer9Inn': '9イニングあたりの与四球数。低いほど制球が良い。',
  'strikeoutWalkRatio': '奪三振数を与四球数で割った比率。制球力の指標。',
  'winPercentage': '勝利数÷（勝利数＋敗戦数）。',
  'qs': 'クオリティスタート。先発投手が6回以上を自責点3以下に抑えた登板。',
  'qsRate': '先発試合のうち、QS（クオリティスタート）を記録した割合。',
  'hqs': 'ハイクオリティスタート。QSよりさらに好投で、7回以上を自責点2以下に抑えた登板。',
  'war': '「平均的な控え選手」と比べて、その選手がチームの勝利数をどれだけ増やしたかを1つの数値にまとめた総合指標。数字が大きいほど貢献度が高い。',
};

/// 指標の簡潔な解説を示す小さな (ⓘ) アイコン。統計キーに対応する説明が
/// 辞書に無い場合は何も表示しない。タップすると吹き出しで説明が出る。
class StatInfoIcon extends StatelessWidget {
  final String? statKey;
  final double size;

  const StatInfoIcon(this.statKey, {super.key, this.size = 12});

  @override
  Widget build(BuildContext context) {
    final explanation = statGlossary[statKey];
    if (explanation == null) return const SizedBox.shrink();
    return IconButton(
      visualDensity: VisualDensity.compact,
      icon: Icon(Icons.info_outline, size: size, color: Colors.white38),
      onPressed: () {
        showDialog(
          context: context,
          builder: (dialogContext) => AlertDialog(
            backgroundColor: const Color(0xFF1E1E2C),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            content: Text(explanation, style: const TextStyle(fontSize: 14, color: Colors.white)),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('閉じる'),
              ),
            ],
          ),
        );
      },
    );
  }
}
