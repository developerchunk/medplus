import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../core/backup.dart';
import '../../core/bill_file.dart';
import '../../core/format.dart';
import '../../data/repo.dart';
import '../../models/models.dart';
import '../nav.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'bill_viewer.dart';

/// Date range quick filters shared by list screens.
enum RangePreset { today, week, month, lastMonth, all, custom }

extension RangePresetX on RangePreset {
  String get label => switch (this) {
        RangePreset.today => 'Today',
        RangePreset.week => 'Last 7 days',
        RangePreset.month => 'This month',
        RangePreset.lastMonth => 'Last month',
        RangePreset.all => 'All time',
        RangePreset.custom => 'Custom',
      };

  (DateTime?, DateTime?) get range {
    final t = today();
    return switch (this) {
      RangePreset.today => (t, t),
      RangePreset.week => (t.subtract(const Duration(days: 6)), t),
      RangePreset.month => (DateTime(t.year, t.month, 1), t),
      RangePreset.lastMonth => (DateTime(t.year, t.month - 1, 1), DateTime(t.year, t.month, 0)),
      _ => (null, null),
    };
  }
}

class RangeFilter extends StatelessWidget {
  const RangeFilter({super.key, required this.preset, required this.from, required this.to, required this.onChanged});
  final RangePreset preset;
  final DateTime? from;
  final DateTime? to;
  final void Function(RangePreset preset, DateTime? from, DateTime? to) onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
      for (final p in RangePreset.values.where((p) => p != RangePreset.custom))
        ChoiceChip(
          label: Text(p.label),
          selected: preset == p,
          showCheckmark: false,
          onSelected: (_) {
            final r = p.range;
            onChanged(p, r.$1, r.$2);
          },
        ),
      ChoiceChip(
        avatar: const Icon(Icons.date_range, size: 16),
        label: Text(preset == RangePreset.custom && from != null ? '${fmtDateShort(from!)} – ${fmtDateShort(to!)}' : 'Custom'),
        selected: preset == RangePreset.custom,
        showCheckmark: false,
        onSelected: (_) async {
          final r = await showDateRangePicker(
            context: context,
            firstDate: DateTime(2020),
            lastDate: today().add(const Duration(days: 1)),
            initialDateRange: from != null && to != null ? DateTimeRange(start: from!, end: to!) : null,
          );
          if (r != null) onChanged(RangePreset.custom, r.start, r.end);
        },
      ),
    ]);
  }
}

class BillsPage extends StatefulWidget {
  const BillsPage({super.key});
  @override
  State<BillsPage> createState() => _BillsPageState();
}

class _BillsPageState extends State<BillsPage> with DataReload {
  String _query = '';
  String _status = 'all';
  RangePreset _preset = RangePreset.month;
  DateTime? _from = RangePreset.month.range.$1;
  DateTime? _to = RangePreset.month.range.$2;
  List<Sale> _sales = [];
  bool _loading = true;
  Timer? _debounce;

  @override
  void reload() async {
    final s = await Repo.sales(query: _query, from: _from, to: _to, status: _status);
    if (mounted) {
      setState(() {
        _sales = s;
        _loading = false;
      });
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _openFile() async {
    final f = await FilePicker.pickFile(dialogTitle: 'Open bill file', type: FileType.custom, allowedExtensions: [BillFile.extension]);
    if (f?.path == null || !mounted) return;
    await showBillViewer(context, filePath: f!.path);
  }

  Future<void> _export() async {
    final from = _from ?? DateTime(2020);
    final to = _to ?? today();
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Export sales to CSV'),
        children: [
          SimpleDialogOption(onPressed: () => Navigator.pop(ctx, 'bills'), child: const ListTile(leading: Icon(Icons.receipt_long), title: Text('Bill register (one row per bill)'))),
          SimpleDialogOption(onPressed: () => Navigator.pop(ctx, 'items'), child: const ListTile(leading: Icon(Icons.list_alt), title: Text('Item-wise sales (one row per medicine)'))),
        ],
      ),
    );
    if (choice == null) return;
    final path = choice == 'bills' ? await BackupService.exportSalesCsv(from, to) : await BackupService.exportSaleItemsCsv(from, to);
    if (path != null && mounted) showSnack(context, 'Exported to $path');
  }

  @override
  Widget build(BuildContext context) {
    final completed = _sales.where((s) => !s.isCancelled).toList();
    final total = completed.fold(0.0, (a, s) => a + s.grandTotal);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      PageHeader(
        title: 'Bills',
        subtitle: 'Every bill is saved as a medical copy (.${BillFile.extension}) on this computer',
        actions: [
          OutlinedButton.icon(onPressed: _openFile, icon: const Icon(Icons.folder_open_outlined, size: 18), label: const Text('Open bill file')),
          OutlinedButton.icon(onPressed: _export, icon: const Icon(Icons.file_download_outlined, size: 18), label: const Text('Export CSV')),
          FilledButton.icon(onPressed: () => Nav.go(Nav.billing), icon: const Icon(Icons.add, size: 18), label: const Text('New bill')),
        ],
        bottom: Row(children: [
          SearchBox(
            hint: 'Bill no, patient, mobile, doctor, medicine…',
            width: 340,
            onChanged: (v) {
              _query = v;
              _debounce?.cancel();
              _debounce = Timer(const Duration(milliseconds: 250), reload);
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
          DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _status,
              borderRadius: BorderRadius.circular(10),
              items: const [
                DropdownMenuItem(value: 'all', child: Text('All bills')),
                DropdownMenuItem(value: 'completed', child: Text('Completed')),
                DropdownMenuItem(value: 'cancelled', child: Text('Cancelled')),
              ],
              onChanged: (v) {
                setState(() => _status = v!);
                reload();
              },
            ),
          ),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(28, 0, 28, 12),
        child: Row(children: [
          Pill('${completed.length} bills', color: AppColors.info, icon: Icons.receipt_long_outlined),
          const SizedBox(width: 8),
          Pill('Total ${money(total)}', color: AppColors.success, icon: Icons.currency_rupee),
          if (completed.isNotEmpty) ...[
            const SizedBox(width: 8),
            Pill('Avg ${money(total / completed.length)}', color: context.muted),
          ],
        ]),
      ),
      Expanded(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 0, 28, 24),
          child: Card(
            clipBehavior: Clip.antiAlias,
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _sales.isEmpty
                    ? const EmptyState(icon: Icons.receipt_long_outlined, title: 'No bills found', message: 'Try a different date range or search.')
                    : SimpleTable(
                        columns: const [
                          TableCol('Bill no', width: 110),
                          TableCol('Date', width: 150),
                          TableCol('Patient', flex: 2),
                          TableCol('Doctor', flex: 2),
                          TableCol('Items', width: 60, right: true),
                          TableCol('Payment', width: 80),
                          TableCol('Amount', width: 110, right: true),
                          TableCol('Status', width: 100),
                          TableCol('', width: 36),
                        ],
                        rowCount: _sales.length,
                        onTap: (i) => showBillViewer(context, saleId: _sales[i].id),
                        cells: (i) {
                          final s = _sales[i];
                          final muted = s.isCancelled ? TextStyle(color: context.muted, decoration: TextDecoration.lineThrough) : null;
                          return [
                            Text(s.billNo, style: const TextStyle(fontWeight: FontWeight.w600)),
                            Text(fmtDateTime(s.createdAt), style: TextStyle(color: context.muted, fontSize: 12.5)),
                            Text(s.customerName.isEmpty ? 'Walk-in' : '${s.customerName}${s.customerPhone.isEmpty ? '' : ' · ${s.customerPhone}'}',
                                overflow: TextOverflow.ellipsis),
                            Text(s.doctorName.isEmpty ? '—' : 'Dr. ${s.doctorName}', overflow: TextOverflow.ellipsis, style: TextStyle(color: context.muted)),
                            Text('${s.itemCount}'),
                            Text(s.paymentMode, style: TextStyle(color: context.muted)),
                            Text(money(s.grandTotal), style: (muted ?? const TextStyle()).copyWith(fontWeight: FontWeight.w700)),
                            s.isCancelled
                                ? const Pill('Cancelled', color: AppColors.danger, small: true)
                                : s.dueAmount > 0
                                    ? Pill('Credit ${money0(s.dueAmount)}', color: AppColors.warning, small: true)
                                    : const Pill('Paid', color: AppColors.success, small: true),
                            Icon(Icons.chevron_right, color: context.muted, size: 18),
                          ];
                        },
                      ),
          ),
        ),
      ),
    ]);
  }
}
