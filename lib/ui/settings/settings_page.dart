import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../../core/backup.dart';
import '../../core/bill_file.dart';
import '../../core/db.dart';
import '../../core/format.dart';
import '../../core/print_service.dart';
import '../../core/settings.dart';
import '../../data/repo.dart';
import '../../models/models.dart';
import '../theme.dart';
import '../widgets/common.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> with EnterFlow {
  final s = Settings.instance;
  final _c = <String, TextEditingController>{};
  List<Printer> _printers = [];
  bool _loadingPrinters = true;
  bool _busy = false;

  static const _textKeys = [
    'shop_name', 'shop_tagline', 'address', 'phone', 'email', 'gstin', 'dl_no', 'pharmacist_name', 'pharmacist_reg',
    'bill_prefix', 'next_bill_seq', 'footer_note', 'expiry_warn_days', 'expiry_critical_days',
  ];

  TextEditingController c(String k) => _c.putIfAbsent(k, () => TextEditingController(text: s.get(k)));

  @override
  void initState() {
    super.initState();
    _loadPrinters();
  }

  @override
  void dispose() {
    for (final x in _c.values) {
      x.dispose();
    }
    super.dispose();
  }

  Future<void> _loadPrinters() async {
    final p = await PrintService.printers();
    if (mounted) {
      setState(() {
        _printers = p;
        _loadingPrinters = false;
      });
    }
  }

  Future<void> _save() async {
    final warn = int.tryParse(c('expiry_warn_days').text) ?? 60;
    final crit = int.tryParse(c('expiry_critical_days').text) ?? 30;
    if (crit >= warn) {
      showSnack(context, 'The "urgent" window must be shorter than the reminder window', error: true);
      return;
    }
    await s.setAll({for (final k in _textKeys) k: c(k).text.trim()});
    if (mounted) showSnack(context, 'Settings saved');
  }

  Future<void> _run(Future<String?> Function() job, String Function(String) done) async {
    setState(() => _busy = true);
    try {
      final r = await job();
      if (r != null && mounted) showSnack(context, done(r));
    } catch (e) {
      if (mounted) showSnack(context, '$e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restore() async {
    final f = await FilePicker.pickFile(dialogTitle: 'Choose a MedBillings backup', type: FileType.custom, allowedExtensions: [BackupService.extension]);
    if (f?.path == null || !mounted) return;
    if (!await confirm(context,
        title: 'Restore this backup?',
        message: 'All current data (medicines, stock, bills, settings) will be replaced by the backup. '
            'A safety copy of the current data is saved to the Backups folder first.',
        confirmLabel: 'Restore',
        destructive: true)) {
      return;
    }
    await _run(() => BackupService.restoreBackup(f!.path!), (safety) => 'Backup restored. Previous data saved to $safety');
    for (final k in _textKeys) {
      c(k).text = s.get(k);
    }
    if (mounted) setState(() {});
  }

  void _openFolder(String path) {
    try {
      if (Platform.isMacOS) {
        Process.run('open', [path]);
      } else if (Platform.isWindows) {
        Process.run('explorer', [path]);
      } else {
        Process.run('xdg-open', [path]);
      }
    } catch (_) {}
  }

  Future<void> _testPrint() async {
    final sale = Sale(
      billNo: 'TEST-0001',
      customerName: 'Test Patient',
      doctorName: 'Test Doctor',
      grossTotal: 35,
      grandTotal: 35,
      taxableTotal: 31.25,
      gstTotal: 3.75,
      items: [
        SaleItem(
          productId: 0,
          batchId: 0,
          productName: 'Sample Tablet 500',
          batchNo: 'AB1234',
          expiry: today().add(const Duration(days: 400)),
          packSize: 10,
          unitName: 'Tab',
          packName: 'Strip',
          qtyUnits: 10,
          mrp: 35,
          unitRate: 3.5,
          gstRate: 12,
          amount: 35,
        ),
      ],
    );
    try {
      await PrintService.printBill(BillDocument.fromSale(sale), copyLabel: 'TEST PRINT');
    } catch (e) {
      if (mounted) showSnack(context, 'Print failed: $e', error: true);
    }
  }

  // Enter moves through the settings top to bottom; Enter on the last one saves.
  @override
  List<String> get flowOrder => const [
        'shop_name', 'shop_tagline', 'address', 'phone', 'email', 'gstin', 'dl_no', 'pharmacist_name', 'pharmacist_reg',
        'bill_prefix', 'next_bill_seq', 'footer_note', 'expiry_warn_days', 'expiry_critical_days',
      ];

  @override
  void onFlowDone() => _save();

  Widget _field(String k, String label, {String? hint, int maxLines = 1, TextInputType? type}) => TextField(
        controller: c(k),
        focusNode: fn(k),
        maxLines: maxLines,
        minLines: 1,
        keyboardType: type ?? TextInputType.text,
        decoration: InputDecoration(labelText: label, hintText: hint),
        onChanged: k == 'bill_prefix' || k == 'next_bill_seq' ? (_) => setState(() {}) : null,
        onSubmitted: (_) => advance(k),
      );

  Widget _section(String title, String subtitle, IconData icon, List<Widget> children) => Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(
                width: 240,
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(icon, color: context.cs.primary, size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(title, style: context.tt.titleMedium),
                      const SizedBox(height: 4),
                      Text(subtitle, style: TextStyle(color: context.muted, fontSize: 12.5)),
                    ]),
                  ),
                ]),
              ),
              const SizedBox(width: 24),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children)),
            ]),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final printerUrl = s.get('printer_url');
    return ListenableBuilder(
      listenable: s,
      builder: (context, _) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        PageHeader(
          title: 'Settings',
          subtitle: 'Shop details, bill printing, expiry reminders and your data',
          actions: [FilledButton.icon(onPressed: _save, icon: const Icon(Icons.save_outlined, size: 18), label: const Text('Save changes'))],
        ),
        if (_busy) const LinearProgressIndicator(minHeight: 2),
        Expanded(
          child: ListView(padding: const EdgeInsets.fromLTRB(28, 0, 28, 28), children: [
            _section('Shop details', 'Printed on the top of every bill', Icons.storefront_outlined, [
              FieldRow(flex: const [3, 2], children: [_field('shop_name', 'Shop name'), _field('shop_tagline', 'Tagline', hint: 'Chemist & Druggist')]),
              FieldRow(children: [_field('address', 'Address', maxLines: 2)]),
              FieldRow(children: [_field('phone', 'Phone'), _field('email', 'Email')]),
              FieldRow(children: [_field('gstin', 'GSTIN', hint: '27XXXXX…'), _field('dl_no', 'Drug license no(s)', hint: '20B: MH-…, 21B: MH-…')]),
              FieldRow(children: [_field('pharmacist_name', 'Registered pharmacist'), _field('pharmacist_reg', 'Pharmacist reg. no')]),
            ]),
            _section('Billing', 'Bill numbering and rules at the counter', Icons.receipt_long_outlined, [
              FieldRow(children: [
                _field('bill_prefix', 'Bill number prefix', hint: 'B-'),
                _field('next_bill_seq', 'Next bill number', type: TextInputType.number),
                InputDecorator(
                  decoration: const InputDecoration(labelText: 'Next bill will be'),
                  child: Text(Repo.formatBillNo(c('bill_prefix').text, int.tryParse(c('next_bill_seq').text) ?? 1), style: const TextStyle(fontWeight: FontWeight.w700)),
                ),
              ]),
              FutureBuilder<List<Doctor>>(
                future: Repo.searchDoctors('', limit: 200),
                builder: (context, snap) {
                  final docs = snap.data ?? [];
                  final current = s.get('default_doctor_id');
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: DropdownButtonFormField<String>(
                      key: ValueKey('defdoc-$current-${docs.length}'),
                      initialValue: docs.any((d) => '${d.id}' == current) ? current : '',
                      decoration: const InputDecoration(
                        labelText: 'Default doctor',
                        helperText: 'Pre-filled on every new bill. Visiting doctors can still be typed in. Manage doctors under Doctors & Patients.',
                        prefixIcon: Icon(Icons.star_outline_rounded, size: 20),
                      ),
                      items: [
                        const DropdownMenuItem(value: '', child: Text('No default doctor')),
                        for (final d in docs)
                          DropdownMenuItem(value: '${d.id}', child: Text('Dr. ${d.name}${d.clinic.isEmpty ? '' : '  ·  ${d.clinic}'}')),
                      ],
                      onChanged: (v) => s.set('default_doctor_id', v ?? ''),
                    ),
                  );
                },
              ),
              FieldRow(children: [_field('footer_note', 'Bill footer note', maxLines: 2)]),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: s.gstEnabled,
                onChanged: (v) => s.set('gst_enabled', '$v'),
                title: const Text('GST registered — charge GST on bills'),
                subtitle: Text(s.gstEnabled
                    ? 'Bills are Tax Invoices with taxable amount, CGST/SGST at each rate and your GSTIN. GST fields appear in medicines and stock entry.'
                    : 'Off: bills are simple Cash Memos with just the total — no GST anywhere. Small shops below the GST limit needn\'t register.'),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: s.flag('require_doctor_for_rx'),
                onChanged: (v) => s.set('require_doctor_for_rx', '$v'),
                title: const Text('Require doctor\'s name for prescription medicines'),
                subtitle: const Text('Antibiotics and Schedule H/H1/X items cannot be billed without it'),
              ),
            ]),
            _section('Printer', 'The customer copy prints here. The medical copy is always saved on this computer.', Icons.print_outlined, [
              Row(children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    key: ValueKey('printer-$printerUrl-${_printers.length}'),
                    initialValue: _printers.any((p) => p.url == printerUrl) ? printerUrl : '',
                    decoration: InputDecoration(labelText: 'Bill printer', helperText: _loadingPrinters ? 'Looking for printers…' : '${_printers.length} printer(s) found'),
                    items: [
                      const DropdownMenuItem(value: '', child: Text('Ask every time (system print dialog)')),
                      for (final p in _printers) DropdownMenuItem(value: p.url, child: Text('${p.name}${p.isDefault ? '  (default)' : ''}')),
                    ],
                    onChanged: (v) {
                      final p = _printers.where((x) => x.url == v).firstOrNull;
                      s.setAll({'printer_url': v ?? '', 'printer_name': p?.name ?? ''});
                    },
                  ),
                ),
                const SizedBox(width: 10),
                IconButton(tooltip: 'Refresh printers', onPressed: _loadPrinters, icon: const Icon(Icons.refresh)),
              ]),
              const SizedBox(height: 16),
              Row(children: [
                Text('Paper size', style: TextStyle(color: context.muted)),
                const SizedBox(width: 16),
                SegmentedButton<String>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: 'A4', label: Text('A4')),
                    ButtonSegment(value: 'A5', label: Text('A5 (half page)')),
                    ButtonSegment(value: '80mm', label: Text('80 mm thermal')),
                  ],
                  selected: {s.get('paper')},
                  onSelectionChanged: (v) => s.set('paper', v.first),
                ),
                const Spacer(),
                OutlinedButton.icon(onPressed: _testPrint, icon: const Icon(Icons.print_outlined, size: 18), label: const Text('Test print')),
              ]),
            ]),
            _section('Expiry reminders', 'A pop-up appears once every day while anything is inside the reminder window', Icons.event_busy_outlined, [
              FieldRow(children: [
                _field('expiry_warn_days', 'Remind me this many days before expiry', type: TextInputType.number),
                _field('expiry_critical_days', 'Mark as urgent within (days)', type: TextInputType.number),
              ]),
            ]),
            _section('Appearance', 'Light or dark look', Icons.palette_outlined, [
              Align(
                alignment: Alignment.centerLeft,
                child: SegmentedButton<String>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: 'light', icon: Icon(Icons.light_mode_outlined, size: 16), label: Text('Light')),
                    ButtonSegment(value: 'dark', icon: Icon(Icons.dark_mode_outlined, size: 16), label: Text('Dark')),
                    ButtonSegment(value: 'system', icon: Icon(Icons.computer, size: 16), label: Text('System')),
                  ],
                  selected: {s.get('theme_mode')},
                  onSelectionChanged: (v) => s.set('theme_mode', v.first),
                ),
              ),
            ]),
            _section('Data & backup', 'Everything is stored locally on this computer', Icons.storage_outlined, [
              InputDecorator(
                decoration: const InputDecoration(labelText: 'Data folder'),
                child: Row(children: [
                  Expanded(child: SelectableText(AppPaths.root.path)),
                  TextButton.icon(onPressed: () => _openFolder(AppPaths.root.path), icon: const Icon(Icons.folder_open_outlined, size: 18), label: const Text('Open')),
                ]),
              ),
              const SizedBox(height: 6),
              Text(
                'Bills/ holds one .${BillFile.extension} medical-copy file per bill (compressed, usually under 1 KB). '
                'Backups (.${BackupService.extension}) contain the whole database plus all bill files.',
                style: TextStyle(fontSize: 12, color: context.muted),
              ),
              const SizedBox(height: 14),
              Wrap(spacing: 10, runSpacing: 10, children: [
                FilledButton.icon(
                  onPressed: _busy ? null : () => _run(BackupService.exportBackup, (p) => 'Backup saved to $p'),
                  icon: const Icon(Icons.backup_outlined, size: 18),
                  label: const Text('Export full backup…'),
                ),
                OutlinedButton.icon(
                  onPressed: _busy ? null : () => _run(BackupService.quickBackup, (p) => 'Backup saved to $p'),
                  icon: const Icon(Icons.bolt_outlined, size: 18),
                  label: const Text('Quick backup to Backups folder'),
                ),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _restore,
                  icon: const Icon(Icons.settings_backup_restore, size: 18),
                  label: const Text('Import / restore backup…'),
                ),
              ]),
              const SizedBox(height: 10),
              Wrap(spacing: 10, runSpacing: 10, children: [
                TextButton.icon(
                  onPressed: () => _run(BackupService.exportStockCsv, (p) => 'Exported to $p'),
                  icon: const Icon(Icons.table_view_outlined, size: 18),
                  label: const Text('Stock CSV'),
                ),
                TextButton.icon(
                  onPressed: () => _run(() => BackupService.exportSalesCsv(DateTime(2020), today()), (p) => 'Exported to $p'),
                  icon: const Icon(Icons.receipt_outlined, size: 18),
                  label: const Text('All bills CSV'),
                ),
                TextButton.icon(
                  onPressed: () => _run(BackupService.exportProductsCsv, (p) => 'Exported to $p'),
                  icon: const Icon(Icons.medication_outlined, size: 18),
                  label: const Text('Medicine list CSV'),
                ),
                TextButton.icon(
                  onPressed: () => _run(() async {
                    final r = await BackupService.importProductsCsv();
                    return r.added + r.updated == 0 ? null : '${r.added} added, ${r.updated} updated';
                  }, (m) => 'Medicines imported: $m'),
                  icon: const Icon(Icons.upload_file_outlined, size: 18),
                  label: const Text('Import medicines CSV'),
                ),
              ]),
            ]),
            Center(child: Text('MedBillings · v1.0.0 · ${fmtDate(DateTime.now())}', style: TextStyle(color: context.muted, fontSize: 12))),
          ]),
        ),
      ]),
    );
  }
}
