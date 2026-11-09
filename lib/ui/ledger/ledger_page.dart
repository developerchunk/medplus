import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../data/repo.dart';
import '../../models/models.dart';
import '../bills/bills_page.dart' show RangeFilter, RangePreset, RangePresetX;
import '../inventory/inventory_page.dart' show MovementTable;
import '../theme.dart';
import '../widgets/common.dart';

/// Every stock entry (+) and exit (−) across all medicines.
class LedgerPage extends StatefulWidget {
  const LedgerPage({super.key});
  @override
  State<LedgerPage> createState() => _LedgerPageState();
}

class _LedgerPageState extends State<LedgerPage> with DataReload {
  String _query = '';
  String _type = 'all';
  RangePreset _preset = RangePreset.week;
  DateTime? _from = RangePreset.week.range.$1;
  DateTime? _to = RangePreset.week.range.$2;
  List<StockMovement> _moves = [];
  Timer? _debounce;

  @override
  void reload() async {
    final m = await Repo.movements(query: _query, type: _type, from: _from, to: _to);
    if (mounted) setState(() => _moves = m);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final entries = _moves.where((m) => m.qty > 0).length;
    final exits = _moves.length - entries;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      PageHeader(
        title: 'Stock ledger',
        subtitle: 'Entries and exits — purchases, sales, returns, adjustments and expiry',
        bottom: Row(children: [
          SearchBox(
            hint: 'Medicine, batch or bill/invoice no…',
            onChanged: (v) {
              _query = v;
              _debounce?.cancel();
              _debounce = Timer(const Duration(milliseconds: 250), reload);
            },
          ),
          const SizedBox(width: 12),
          SegmentedButton<String>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: 'all', label: Text('All')),
              ButtonSegment(value: 'in', label: Text('Entries')),
              ButtonSegment(value: 'out', label: Text('Exits')),
            ],
            selected: {_type},
            onSelectionChanged: (v) {
              setState(() => _type = v.first);
              reload();
            },
          ),
          const SizedBox(width: 14),
          Expanded(
            child: RangeFilter(
              preset: _preset,
              from: _from,
              to: _to,
              onChanged: (p, f, t) {
                setState(() {
                  _preset = p;
                  _from = f;
                  _to = t;
                });
                reload();
              },
            ),
          ),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(28, 0, 28, 12),
        child: Row(children: [
          Pill('$entries entries', color: AppColors.success, icon: Icons.south_west),
          const SizedBox(width: 8),
          Pill('$exits exits', color: AppColors.danger, icon: Icons.north_east),
          if (_moves.length >= 1000) ...[const SizedBox(width: 8), Pill('Showing latest 1000 — narrow the dates', color: context.muted)],
        ]),
      ),
      Expanded(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 0, 28, 24),
          child: Card(
            clipBehavior: Clip.antiAlias,
            child: _moves.isEmpty
                ? EmptyState(icon: Icons.swap_vert, title: 'No stock movements', message: _from == null ? null : 'Between ${fmtDate(_from!)} and ${fmtDate(_to!)}')
                : MovementTable(moves: _moves),
          ),
        ),
      ),
    ]);
  }
}
