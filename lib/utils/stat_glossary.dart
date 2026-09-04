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
  'iso': '長打率－打率。単打を除いた「長打力」だけを取り出した指標。.150前後が平均、.250超えでエリート級。',
  'woba': '四球・単打・二塁打・三塁打・本塁打をそれぞれの得点価値で重み付けした出塁指標。.320前後が平均、.400超えでエリート級。',
  'wrc': 'wOBAをもとに算出した「その選手が何点を作り出したか」を表す総量指標。数字は打席数に依存するため、選手間の比較にはwRC+が向く。',
  'wrcPlus': 'wRCをリーグ平均・球場補正した指標。100が平均で、150なら平均の1.5倍の得点創造力があることを示す。',
  'opsPlus': 'OPSをリーグ平均と比較した指標。100が平均で、150なら平均の1.5倍の攻撃力。本アプリでは球場補正なしの簡易版として算出。',
  'xba': '打球の速度・角度から算出した「本来あるべき打率」。実際の打率と比較することで、運や守備の影響を推定できる。',
  'xslg': '打球の速度・角度から算出した「本来あるべき長打率」。',
  'xwoba': '打球の速度・角度から算出した「本来あるべきwOBA」。運や守備を除いた「真の打撃力」の目安。',
  'fip': '被本塁打・与四球・奪三振など、投手が直接コントロールできる要素だけで算出する防御率相当の指標。リーグ平均は4.20前後、3.50未満でエリート級。',
  'xfip': 'FIPの被本塁打部分を、リーグ平均の本塁打割合に補正した指標。被本塁打の「運」を取り除いた、より実力に近い数値。',
  'eraMinus': 'ERA(防御率)をリーグ平均・球場補正した指標。100が平均で、数字が低いほど好成績(ERA+とは逆方向のスケール)。',
  'eraPlus': 'ERA(防御率)をリーグ平均と比較した指標。100が平均で、150なら平均の1.5倍の良さ。数字が大きいほど好成績。',
  'kPercent': '対戦した打者のうち、三振に打ち取った割合。MLB平均は22%前後、30%超えでエリート級。',
  'bbPercent': '対戦した打者のうち、四球を与えた割合。MLB平均は8%前後、5%未満でエリート級。',
  'kMinusBbPercent': '三振率から四球率を引いた差。投手の支配力を表し、20%超えでエリート級。',
  'whiffPercent': 'スイングした投球のうち、空振りした割合。25%超えで優秀とされ、投球の「キレ」を示す。',
  'exitVelocity': '打球がバットを離れた瞬間の速度(mph)。平均は87mph前後、95mph以上は「Hard Hit」とされる。',
  'launchAngle': '打球の打ち出し角度(度)。8〜32度が長打になりやすい「Sweet Spot」とされる。',
  'barrelPercent': '本塁打・長打になりやすい最適な速度と角度の組み合わせ(バレル)に分類された打球の割合。5%前後が平均、10%超えでエリート級。',
  'hardHitPercent': '打球速度95mph以上の「強い打球」の割合。40%前後が平均、50%超えでエリート級。',
  'sprintSpeed': '選手の最大走力(フィート/秒)。27ft/s前後が平均、30ft/s超えでエリート級。',
  'oaa': 'Outs Above Average。打球の位置・速度・角度をもとにStatcastが算出する守備貢献度。0が平均、+10前後でエリート級。',
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
