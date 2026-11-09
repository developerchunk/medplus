import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/settings.dart';
import '../../data/repo.dart';
import '../../models/models.dart';
import '../nav.dart';
import '../theme.dart';
import '../widgets/common.dart';

class ExpiryPage extends StatefulWidget {
  const ExpiryPage({super.key});
  @override
  State<ExpiryPage> createState() => _ExpiryPageState();
}

class _ExpiryPageState extends State<ExpiryPage> with DataReload {
  List<BatchWithProduct> _all = [];
  List<ExpiryAction> _history = [];

  @override
  void reload() async {
    final all = await Repo.expiringBatches(90);
    final h = await Repo.expiryActions();
    if (mounted) {
      setState(() {
        _all = all;
        _history = h;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = Settings.instance;
    final expired = _all.where((b) => b.batch.daysLeft < 0).toList();
    final critical = _all.where((b) => b.batch.daysLeft >= 0 && b.batch.daysLeft <= s.criticalDays).toList();
    final warn = _all.where((b) => b.batch.daysLeft > s.criticalDays && b.batch.daysLeft <= s.warnDays).toList();
    final later = _all.where((b) => b.batch.daysLeft > s.warnDays).toList();
    return DefaultTabController(
      length: 5,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        PageHeader(
          title: 'Expiry',
          subtitle: 'Batches reaching expiry. You get a reminder every day for anything within ${s.warnDays} days.',
          actions: [
            OutlinedButton.icon(
              onPressed: () => showExpiryAlert(context, force: true),
              icon: const Icon(Icons.notifications_active_outlined, size: 18),
              label: const Text('Show today\'s reminder'),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              _tab('Expired', expired.length, AppColors.danger),
              _tab('≤ ${s.criticalDays} days', critical.length, AppColors.warning),
              _tab('${s.criticalDays + 1}–${s.warnDays} days', warn.length, AppColors.caution),
              _tab('${s.warnDays + 1}–90 days', later.length, AppColors.info),
              _tab('Handled', _history.length, AppColors.success),
            ],
          ),
        ),
        const Divider(),
        Expanded(
          child: TabBarView(children: [
            _list(expired, 'No expired stock on the shelf 🎉'),
            _list(critical, 'Nothing expiring in the next ${s.criticalDays} days'),
            _list(warn, 'Nothing in this window'),
            _list(later, 'Nothing in this window'),
            _historyList(),
          ]),
        ),
      ]),
    );
  }

  Tab _tab(String label, int n, Color c) => Tab(
        child: Row(children: [
          Text(label),
          const SizedBox(width: 6),
          if (n > 0) Pill('$n', color: c, small: true),
        ]),
      );

  Widget _list(List<BatchWithProduct> rows, String empty) {
    if (rows.isEmpty) return EmptyState(icon: Icons.event_available_outlined, title: empty);
    final value = rows.fold(0.0, (s, r) => s + r.batch.qty * r.batch.purchaseRate / r.batch.packSize);
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 14, 28, 24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Pill('${rows.length} batches', color: AppColors.info),
          const SizedBox(width: 8),
          Pill('Stock value ${money(value)} at cost', color: context.muted),
        ]),
        const SizedBox(height: 12),
        Expanded(
          child: Card(
            clipBehavior: Clip.antiAlias,
            child: SimpleTable(
              columns: const [
                TableCol('Medicine', flex: 2.4),
                TableCol('Batch', flex: 1),
                TableCol('Expiry', width: 190),
                TableCol('Stock', flex: 1.3),
                TableCol('Value', width: 90, right: true),
                TableCol('Supplier', flex: 1.4),
                TableCol('Action', width: 150),
              ],
              rowCount: rows.length,
              onTap: (i) => Nav.openProduct(rows[i].product.id!),
              cells: (i) {
                final r = rows[i];
                final b = r.batch;
                return [
                  Row(children: [
                    Flexible(child: Text(r.product.name, style: const TextStyle(fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis)),
                    const SizedBox(width: 6),
                    RxBadge(r.product),
                  ]),
                  Text(b.batchNo),
                  ExpiryBadge(b.expiry, showPhrase: true, small: true),
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(r.product.qty(b.qty)),
                    if (r.product.fullBoxes(b.qty) > 0) _FullBoxNote(r.product, b.qty),
                    if (b.discountPct > 0) Text('${trimNum(b.discountPct)}% clearance', style: const TextStyle(fontSize: 11.5, color: AppColors.violet)),
                  ]),
                  Text(amount(b.qty * b.purchaseRate / b.packSize)),
                  Text(r.supplierName.isEmpty ? '—' : r.supplierName, overflow: TextOverflow.ellipsis, style: TextStyle(color: context.muted)),
                  PopupMenuButton<String>(
                    tooltip: 'Handle expiry',
                    onSelected: (a) => handleExpiryAction(context, r, a),
                    itemBuilder: (_) => [
                      const PopupMenuItem(value: 'returned', child: ListTile(dense: true, leading: Icon(Icons.assignment_return_outlined), title: Text('Return to supplier'))),
                      const PopupMenuItem(value: 'disposed', child: ListTile(dense: true, leading: Icon(Icons.delete_sweep_outlined), title: Text('Dispose / destroy'))),
                      if (!b.isExpired)
                        const PopupMenuItem(value: 'discounted', child: ListTile(dense: true, leading: Icon(Icons.local_offer_outlined), title: Text('Clearance discount'))),
                      const PopupMenuItem(value: 'acknowledged', child: ListTile(dense: true, leading: Icon(Icons.visibility_outlined), title: Text('Mark as checked'))),
                    ],
                    child: IgnorePointer(
                      child: OutlinedButton.icon(
                        onPressed: () {},
                        icon: const Icon(Icons.task_alt, size: 16),
                        label: const Text('Handle'),
                        style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10)),
                      ),
                    ),
                  ),
                ];
              },
            ),
          ),
        ),
      ]),
    );
  }

  Widget _historyList() {
    if (_history.isEmpty) return const EmptyState(icon: Icons.history, title: 'No expiries handled yet');
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 14, 28, 24),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: SimpleTable(
          columns: const [
            TableCol('Date', width: 160),
            TableCol('Action', width: 180),
            TableCol('Medicine', flex: 2),
            TableCol('Batch', flex: 1),
            TableCol('Expiry', width: 80),
            TableCol('Qty', flex: 1.2),
            TableCol('Note', flex: 1.6),
          ],
          rowCount: _history.length,
          cells: (i) {
            final h = _history[i];
            return [
              Text(fmtDateTime(h.createdAt), style: TextStyle(color: context.muted, fontSize: 12.5)),
              Pill(ExpiryAction.label(h.action),
                  color: switch (h.action) {
                    'returned' => AppColors.info,
                    'disposed' => AppColors.danger,
                    'discounted' => AppColors.violet,
                    _ => AppColors.success,
                  },
                  small: true),
              Text(h.productName, style: const TextStyle(fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis),
              Text(h.batchNo),
              Text(h.expiry == null ? '—' : fmtExpiry(h.expiry!)),
              Text(h.action == 'discounted' ? '${trimNum(h.value)}% off' : h.qty > 0 ? fmtQty(h.qty, h.packSize, h.unitName, h.packName) : '—'),
              Text(h.note, style: TextStyle(color: context.muted), overflow: TextOverflow.ellipsis),
            ];
          },
        ),
      ),
    );
  }
}

Future<void> handleExpiryAction(BuildContext context, BatchWithProduct r, String action) async {
  final b = r.batch;
  final p = r.product;
  final note = TextEditingController();
  final packs = TextEditingController(text: '${b.qty ~/ b.packSize}');
  final loose = TextEditingController(text: '${b.qty % b.packSize}');
  final disc = TextEditingController(text: b.discountPct > 0 ? trimNum(b.discountPct) : '10');
  final removes = action == 'returned' || action == 'disposed';
  final fPacks = FocusNode(), fLoose = FocusNode(), fDisc = FocusNode(), fNote = FocusNode();
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(ExpiryAction.label(action)),
      content: SizedBox(
        width: 440,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('${p.name} · batch ${b.batchNo} · exp ${fmtExpiry(b.expiry)}', style: const TextStyle(fontWeight: FontWeight.w600)),
          Text('In stock: ${p.qty(b.qty)}', style: TextStyle(color: ctx.muted)),
          const SizedBox(height: 14),
          if (removes)
            Row(children: [
              if (b.packSize > 1) ...[
                Expanded(
                  child: TextField(
                    controller: packs,
                    focusNode: fPacks,
                    autofocus: true,
                    inputFormatters: intInput,
                    decoration: InputDecoration(labelText: '${p.packName}s'),
                    onSubmitted: (_) => fLoose.requestFocus(),
                  ),
                ),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: TextField(
                  controller: loose,
                  focusNode: fLoose,
                  autofocus: b.packSize <= 1,
                  inputFormatters: intInput,
                  decoration: InputDecoration(labelText: b.packSize > 1 ? '+ ${p.unitName}s' : '${p.unitName}s'),
                  onSubmitted: (_) => fNote.requestFocus(),
                ),
              ),
            ]),
          if (action == 'discounted')
            TextField(
              controller: disc,
              focusNode: fDisc,
              autofocus: true,
              onSubmitted: (_) => fNote.requestFocus(),
              inputFormatters: decimalInput,
              decoration: const InputDecoration(labelText: 'Discount on this batch', suffixText: '%', helperText: 'Auto-applied whenever this batch is billed'),
            ),
          const SizedBox(height: 12),
          TextField(
            controller: note,
            focusNode: fNote,
            autofocus: !removes && action != 'discounted',
            decoration: InputDecoration(labelText: action == 'returned' ? 'Note (credit note no., etc.)' : 'Note', helperText: 'Enter confirms'),
            onSubmitted: (_) => Navigator.pop(ctx, true),
          ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Confirm')),
      ],
    ),
  );
  for (final f in [fPacks, fLoose, fDisc, fNote]) {
    f.dispose();
  }
  if (ok != true) return;
  final qty = (b.packSize > 1 ? (int.tryParse(packs.text) ?? 0) * b.packSize : 0) + (int.tryParse(loose.text) ?? 0);
  await Repo.handleExpiry(b, action, qty: qty, discountPct: parseNum(disc.text).clamp(0, 100).toDouble(), note: note.text.trim());
  if (context.mounted) showSnack(context, '${ExpiryAction.label(action)} recorded for ${p.name} (${b.batchNo})');
}

/// "2 full Box expiring" — shown only for medicines that come in boxes.
class _FullBoxNote extends StatelessWidget {
  const _FullBoxNote(this.p, this.units);
  final Product p;
  final int units;
  @override
  Widget build(BuildContext context) {
    final n = p.fullBoxes(units);
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Pill('$n full ${p.outerName}${n == 1 ? '' : 'es'} · ${p.qtyWithBoxes(units)}', color: AppColors.danger, icon: Icons.inventory_2_outlined, small: true),
    );
  }
}

// ====================================================================== daily reminder

/// Shows the expiry reminder once per day (or always when [force]).
Future<void> showExpiryAlert(BuildContext context, {bool force = false}) async {
  final s = Settings.instance;
  final todayStr = isoDate(today());
  if (!force && s.get('last_expiry_alert') == todayStr) return;
  final rows = await Repo.expiringBatches(s.warnDays);
  if (!context.mounted) return;
  if (rows.isEmpty) {
    if (force) showSnack(context, 'Nothing is expiring in the next ${s.warnDays} days');
    await s.set('last_expiry_alert', todayStr);
    return;
  }
  await s.set('last_expiry_alert', todayStr);
  if (!context.mounted) return;
  await showDialog(context: context, builder: (_) => _ExpiryAlert(rows: rows));
}

class _ExpiryAlert extends StatelessWidget {
  const _ExpiryAlert({required this.rows});
  final List<BatchWithProduct> rows;

  @override
  Widget build(BuildContext context) {
    final s = Settings.instance;
    final expired = rows.where((r) => r.batch.daysLeft < 0).length;
    final critical = rows.where((r) => r.batch.daysLeft >= 0 && r.batch.daysLeft <= s.criticalDays).length;
    final warn = rows.length - expired - critical;
    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 760, maxHeight: MediaQuery.sizeOf(context).height * 0.85),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(
            padding: const EdgeInsets.fromLTRB(22, 20, 22, 18),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [AppColors.warning.withValues(alpha: 0.16), AppColors.danger.withValues(alpha: 0.10)]),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Row(children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(color: AppColors.warning, borderRadius: BorderRadius.circular(12)),
                child: const Icon(Icons.notification_important_outlined, color: Colors.white),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Medicines are going to expire', style: context.tt.titleLarge),
                  Text('Daily reminder · ${fmtDate(DateTime.now())}', style: TextStyle(color: context.muted)),
                ]),
              ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 14, 22, 8),
            child: Wrap(spacing: 8, runSpacing: 6, children: [
              if (expired > 0) Pill('$expired already expired', color: AppColors.danger, icon: Icons.block),
              if (critical > 0) Pill('$critical within ${s.criticalDays} days', color: AppColors.warning, icon: Icons.schedule),
              if (warn > 0) Pill('$warn within ${s.warnDays} days', color: AppColors.caution, icon: Icons.schedule),
            ]),
          ),
          Flexible(
            child: ListView.separated(
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: rows.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final r = rows[i];
                return ListTile(
                  dense: true,
                  leading: Icon(r.batch.isExpired ? Icons.block : Icons.hourglass_bottom, color: expiryColor(context, r.batch.expiry)),
                  title: Text('${r.product.name}  ·  ${r.batch.batchNo}', style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(
                    '${r.product.qty(r.batch.qty)} in stock'
                    '${r.product.fullBoxes(r.batch.qty) > 0 ? ' — incl. ${r.product.fullBoxes(r.batch.qty)} full ${r.product.outerName}${r.product.fullBoxes(r.batch.qty) == 1 ? '' : 'es'}' : ''}'
                    '${r.supplierName.isEmpty ? '' : ' · from ${r.supplierName}'}',
                  ),
                  trailing: ExpiryBadge(r.batch.expiry, showPhrase: true),
                );
              },
            ),
          ),
          const Divider(),
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 12, 22, 14),
            child: Row(children: [
              Expanded(child: Text('This reminder appears once every day until these batches are handled.', style: TextStyle(fontSize: 12, color: context.muted))),
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Remind me tomorrow')),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  Nav.go(Nav.expiry);
                },
                icon: const Icon(Icons.task_alt, size: 18),
                label: const Text('Handle now'),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}
