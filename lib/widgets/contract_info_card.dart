// lib/widgets/contract_info_card.dart
//
// 選手個別画面に埋め込む契約情報カード。assets/contracts_data.json に
// データが無い選手は何も表示しない（＝データが無いことをそのまま示す）。

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/contract_provider.dart';

class ContractInfoCard extends ConsumerWidget {
  final int playerId;

  const ContractInfoCard({super.key, required this.playerId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final contractsAsync = ref.watch(contractDataProvider);

    return contractsAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
      data: (map) {
        final c = map[playerId];
        if (c == null) return const SizedBox.shrink();

        return Card(
          color: const Color(0xFF1E2A1E),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: Colors.greenAccent, width: 1)),
          margin: const EdgeInsets.only(bottom: 16),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.request_quote, color: Colors.greenAccent, size: 18),
                    const SizedBox(width: 6),
                    const Text('契約情報', style: TextStyle(fontSize: 12, color: Colors.greenAccent, fontWeight: FontWeight.bold)),
                    const Spacer(),
                    Text(
                      formatUsd(c.totalValueUsd),
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.greenAccent),
                    ),
                  ],
                ),
                const Divider(height: 20, color: Colors.white12),
                Wrap(
                  spacing: 20,
                  runSpacing: 10,
                  children: [
                    _MiniField(label: '契約年数', val: '${c.years}年'),
                    _MiniField(label: '平均年俸(AAV)', val: formatUsd(c.aavUsd)),
                    _MiniField(label: '契約期間', val: '${c.startYear}〜${c.endYear}'),
                  ],
                ),
                if (c.notes != null && c.notes!.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(c.notes!, style: const TextStyle(fontSize: 11, color: Colors.white54)),
                ],
                const SizedBox(height: 6),
                const Text('※公開報道をもとに手動集計した参考値', style: TextStyle(fontSize: 10, color: Colors.white38)),
              ],
            ),
          ),
        );
      },
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
