import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/db.dart';
import '../../core/format.dart';
import '../../data/repo.dart';
import '../../models/models.dart';
import '../inventory/inventory_page.dart' show showProductDetail;
import '../theme.dart';
import '../widgets/common.dart';

/// Full-screen account of one supplier (or one-off shop): money summary, every bill with
/// what's paid / remaining / when it was cleared, every payment and which bills it paid,
/// and every medicine they supplied. Built for long lists: each tab has search and filters.
class SupplierDashboard extends StatefulWidget {
  const SupplierDashboard({super.key, required this.supplier, required this.onBack, this.onEdit, this.onDelete});
  final Supplier supplier;
  final VoidCallback onBack;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  @override
  State<SupplierDashboard> createState() => _SupplierDashboardState();
}

class _SupplierDashboardState extends State<SupplierDashboard> {
  Supplier get s => widget.supplier;
  SupplierAccount? _acc;
  List<Map<String, Object?>> _products = [];
  String _billFilter = 'all'; // all | open | cleared
  String _billQuery = '';
  String _medQuery = '';

  @override
  void initState() {
    super.initState();
    dataVersion.addListener(_load);
    _load();
  }

  @override
  void didUpdateWidget(SupplierDashboard old) {
    super.didUpdateWidget(old);
    if (old.supplier.id != s.id || old.supplier.name != s.name) _load();
  }

  @override
  void dispose() {
    dataVersion.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    final acc = await Repo.supplierAccount(s);
    final products = await Repo.supplierProducts(s);
    if (!mounted) return;
    setState(() {
      _acc = acc;
      _products = products;
    });
  }

  Future<void> _pay({SupplierBill? bill}) async {
    final acc = _acc;
    if (acc == null) return;
    final ok = await showSupplierPaymentDialog(context, s, account: acc, bill: bill);
    if (ok && mounted) showSnack(context, 'Payment to ${s.name} saved');
  }

  @override
  Widget build(BuildContext context) {
    final acc = _acc;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _header(),
      if (acc == null)
        const Expanded(child: Center(child: CircularProgressIndicator()))
      else ...[
        Padding(padding: const EdgeInsets.fromLTRB(24, 0, 24, 12), child: _kpis(acc)),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
            child: Card(
              clipBehavior: Clip.antiAlias,
              child: DefaultTabController(
                length: 3,
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  TabBar(
                    isScrollable: true,
                    tabAlignment: TabAlignment.start,
                    tabs: [
                      Tab(text: 'Bills (${acc.bills.length})'),
                      Tab(text: 'Payments (${acc.payments.length})'),
                      Tab(text: 'Medicines (${_products.length})'),
                    ],
                  ),
                  const Divider(),
                  Expanded(child: TabBarView(children: [_billsTab(acc), _paymentsTab(acc), _medicinesTab()])),
                ]),
              ),
            ),
          ),
        ),
      ],
    ]);
  }

  // ------------------------------------------------------------ header & summary

  Widget _header() {
    final saved = s.id != null;
    final sub = saved
        ? [s.contactPerson, s.phone, s.gstin.isEmpty ? '' : 'GSTIN ${s.gstin}', s.drugLicense.isEmpty ? '' : 'DL ${s.drugLicense}', s.address]
            .where((e) => e.isNotEmpty)
            .join(' · ')
        : 'One-off shop — medicines brought from here while billing';
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 16, 24, 14),
      child: Row(children: [
        IconButton(tooltip: 'Back to suppliers', onPressed: widget.onBack, icon: const Icon(Icons.arrow_back)),
        const SizedBox(width: 6),
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(color: context.cs.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
          child: Icon(saved ? Icons.storefront_outlined : Icons.local_shipping_outlined, color: context.cs.primary),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Flexible(child: Text(s.name, style: context.tt.headlineSmall, overflow: TextOverflow.ellipsis)),
              if (!saved) ...[const SizedBox(width: 8), const Pill('One-off shop', color: AppColors.info, small: true)],
            ]),
            if (sub.isNotEmpty) Text(sub, style: TextStyle(color: context.muted), maxLines: 1, overflow: TextOverflow.ellipsis),
          ]),
        ),
        if (saved && widget.onDelete != null)
          TextButton.icon(
            onPressed: widget.onDelete,
            icon: const Icon(Icons.delete_outline, size: 18),
            label: const Text('Delete'),
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
          ),
        if (saved && widget.onEdit != null) ...[
          const SizedBox(width: 6),
          OutlinedButton.icon(onPressed: widget.onEdit, icon: const Icon(Icons.edit_outlined, size: 18), label: const Text('Edit')),
        ],
        const SizedBox(width: 8),
        FilledButton.icon(onPressed: () => _pay(), icon: const Icon(Icons.payments_outlined, size: 18), label: const Text('Record payment')),
      ]),
    );
  }

  Widget _kpis(SupplierAccount a) {
    final last = a.lastPayment;
    final tiles = [
      _kpi('Goods received', money(a.goods), '${a.bills.length} bill${a.bills.length == 1 ? '' : 's'}', Icons.inventory_2_outlined, AppColors.info),
      _kpi('Paid', money(a.paid), last == null ? 'No payments yet' : 'Last ${money(last.amount)} on ${fmtDateShort(last.date)}', Icons.check_circle_outline,
          AppColors.success),
      a.advance > 0
          ? _kpi('Paid in advance', money(a.advance), 'More paid than billed', Icons.savings_outlined, AppColors.violet)
          : _kpi('Remaining to pay', money(a.remaining), a.openBills == 0 ? 'All bills cleared' : '${a.openBills} bill${a.openBills == 1 ? '' : 's'} open',
              Icons.account_balance_wallet_outlined, a.remaining > 0.004 ? AppColors.warning : AppColors.success),
      _kpi('Last purchase', a.lastPurchase == null ? '—' : fmtDate(a.lastPurchase!), '${_products.length} medicine${_products.length == 1 ? '' : 's'} supplied',
          Icons.event_outlined, AppColors.brand),
    ];
    return LayoutBuilder(builder: (context, box) {
      if (box.maxWidth < 760) {
        return Wrap(spacing: 10, runSpacing: 10, children: [for (final t in tiles) SizedBox(width: (box.maxWidth - 10) / 2, child: t)]);
      }
      return Row(children: [
        for (var i = 0; i < tiles.length; i++) ...[if (i > 0) const SizedBox(width: 10), Expanded(child: tiles[i])],
      ]);
    });
  }

  Widget _kpi(String label, String value, String sub, IconData icon, Color color) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: context.isDark ? 0.16 : 0.07),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Row(children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: TextStyle(fontSize: 12, color: context.muted), maxLines: 1, overflow: TextOverflow.ellipsis),
              Text(value, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: color), maxLines: 1, overflow: TextOverflow.ellipsis),
              Text(sub, style: TextStyle(fontSize: 11.5, color: context.muted), maxLines: 1, overflow: TextOverflow.ellipsis),
            ]),
          ),
        ]),
      );

  // ------------------------------------------------------------ bills

  Widget _statusPill(SupplierBill b) => switch (b.status) {
        'Cleared' => Pill('Cleared ${b.clearedAt == null ? '' : fmtDateShort(b.clearedAt!)}', color: AppColors.success, small: true),
        'Part paid' => const Pill('Part paid', color: AppColors.warning, small: true),
        _ => const Pill('Unpaid', color: AppColors.danger, small: true),
      };

  Widget _billsTab(SupplierAccount a) {
    final q = _billQuery.trim().toLowerCase();
    final bills = a.bills.where((b) {
      if (_billFilter == 'open' && b.isCleared) return false;
      if (_billFilter == 'cleared' && !b.isCleared) return false;
      return q.isEmpty || b.label.toLowerCase().contains(q) || fmtDateShort(b.purchase.invoiceDate).contains(q);
    }).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        child: Row(children: [
          SizedBox(width: 240, child: SearchBox(hint: 'Invoice no or date…', onChanged: (v) => setState(() => _billQuery = v))),
          const SizedBox(width: 12),
          for (final f in const {'all': 'All', 'open': 'Open', 'cleared': 'Cleared'}.entries) ...[
            ChoiceChip(
              label: Text(f.key == 'open' ? 'Open (${a.openBills})' : f.value),
              selected: _billFilter == f.key,
              showCheckmark: false,
              onSelected: (_) => setState(() => _billFilter = f.key),
            ),
            const SizedBox(width: 6),
          ],
        ]),
      ),
      Expanded(
        child: bills.isEmpty
            ? const EmptyState(icon: Icons.receipt_long_outlined, title: 'No bills here')
            : SimpleTable(
                columns: const [
                  TableCol('Date', width: 92),
                  TableCol('Bill', flex: 1.6),
                  TableCol('Amount', width: 104, right: true),
                  TableCol('Paid', width: 104, right: true),
                  TableCol('Remaining', width: 104, right: true),
                  TableCol('Status', width: 136),
                  TableCol('', width: 76),
                ],
                rowCount: bills.length,
                onTap: (i) => showSupplierBill(context, s, bills[i], onPay: () => _pay(bill: bills[i])),
                cells: (i) {
                  final b = bills[i];
                  return [
                    Text(fmtDateShort(b.purchase.invoiceDate), style: TextStyle(color: context.muted)),
                    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(b.label, style: const TextStyle(fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis),
                      Text(
                          '${b.purchase.itemCount} item${b.purchase.itemCount == 1 ? '' : 's'}'
                          '${b.paidAtEntry ? ' · paid at purchase' : b.payments.isEmpty ? '' : ' · ${b.payments.length} payment${b.payments.length == 1 ? '' : 's'}'}',
                          style: TextStyle(fontSize: 12, color: context.muted),
                          overflow: TextOverflow.ellipsis),
                    ]),
                    Text(amount(b.amount)),
                    Text(b.paid > 0 ? amount(b.paid) : '—', style: const TextStyle(color: AppColors.success)),
                    Text(b.remaining > 0 ? amount(b.remaining) : '—',
                        style: TextStyle(fontWeight: FontWeight.w700, color: b.remaining > 0 ? AppColors.warning : context.muted)),
                    _statusPill(b),
                    b.isCleared ? const SizedBox.shrink() : TextButton(onPressed: () => _pay(bill: b), child: const Text('Pay')),
                  ];
                },
              ),
      ),
    ]);
  }

  // ------------------------------------------------------------ payments

  Widget _paymentsTab(SupplierAccount a) {
    if (a.payments.isEmpty) {
      return EmptyState(
        icon: Icons.payments_outlined,
        title: 'No payments yet',
        message: 'Bills marked paid at stock entry count as paid. Record other payments here.',
        action: FilledButton.icon(onPressed: () => _pay(), icon: const Icon(Icons.payments_outlined), label: const Text('Record payment')),
      );
    }
    return SimpleTable(
      columns: const [
        TableCol('Paid on', width: 150),
        TableCol('Amount', width: 104, right: true),
        TableCol('Mode', width: 84),
        TableCol('Paid for', flex: 2.2),
        TableCol('Note', flex: 1.2),
        TableCol('', width: 44),
      ],
      rowCount: a.payments.length,
      cells: (i) {
        final p = a.payments[i];
        final parts = [
          for (final (b, amt) in p.appliedTo) '${b.label} ${money(amt)}${b.isCleared && b.clearedAt == p.date ? ' (cleared)' : ''}',
          if (p.advance > 0) 'Advance ${money(p.advance)}',
        ];
        return [
          Text(fmtDateTime(p.date), style: TextStyle(color: context.muted, fontSize: 12.5)),
          Text(amount(p.amount), style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.success)),
          Text(p.mode),
          Text(parts.isEmpty ? '—' : parts.join(' · '), maxLines: 2, overflow: TextOverflow.ellipsis),
          Text(p.note.isEmpty ? '—' : p.note, style: TextStyle(color: context.muted), overflow: TextOverflow.ellipsis),
          IconButton(
            tooltip: 'Delete payment',
            icon: const Icon(Icons.delete_outline, size: 18),
            color: context.muted,
            onPressed: () async {
              if (!await confirm(context,
                  title: 'Delete this payment?',
                  message: '${money(p.amount)} paid on ${fmtDateTime(p.date)} will be removed and the bills it paid become open again.',
                  confirmLabel: 'Delete',
                  destructive: true)) {
                return;
              }
              await Repo.deleteSupplierPayment(p.id);
            },
          ),
        ];
      },
    );
  }

  // ------------------------------------------------------------ medicines

  Widget _medicinesTab() {
    final q = _medQuery.trim().toLowerCase();
    final rows = _products.where((r) => q.isEmpty || '${r['product_name']}'.toLowerCase().contains(q)).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        child: Align(alignment: Alignment.centerLeft, child: SizedBox(width: 280, child: SearchBox(hint: 'Search medicine…', onChanged: (v) => setState(() => _medQuery = v)))),
      ),
      Expanded(
        child: rows.isEmpty
            ? const EmptyState(icon: Icons.medication_outlined, title: 'No medicines here')
            : SimpleTable(
                columns: const [
                  TableCol('Medicine', flex: 2.4),
                  TableCol('Received', flex: 1.4),
                  TableCol('Times', width: 64, right: true),
                  TableCol('Last bought', width: 110),
                  TableCol('Value', width: 110, right: true),
                ],
                rowCount: rows.length,
                onTap: (i) => showProductDetail(context, rows[i]['product_id'] as int),
                cells: (i) {
                  final r = rows[i];
                  final units = (r['units'] as num?)?.toInt() ?? 0;
                  final last = r['last_date'] == null ? null : DateTime.tryParse(r['last_date'] as String);
                  return [
                    Text('${r['product_name']}', style: const TextStyle(fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis),
                    Text(fmtQty(units, (r['pack_size'] as num?)?.toInt() ?? 1, '${r['unit_name']}', '${r['pack_name']}')),
                    Text('${r['times']}'),
                    Text(last == null ? '—' : fmtDateShort(last), style: TextStyle(color: context.muted)),
                    Text(money((r['value'] as num?) ?? 0)),
                  ];
                },
              ),
      ),
    ]);
  }
}

/// One supplier bill: its medicines, the payments that paid it (with dates) and when it was cleared.
Future<void> showSupplierBill(BuildContext context, Supplier s, SupplierBill b, {VoidCallback? onPay}) async {
  final items = await Repo.purchaseItems(b.purchase.id!);
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (ctx) => FormDialog(
      title: b.label,
      subtitle: '${s.name} · ${fmtDate(b.purchase.invoiceDate)} · ${money(b.amount)}',
      icon: Icons.receipt_long_outlined,
      width: 760,
      actions: [
        if (!b.isCleared && onPay != null)
          FilledButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              onPay();
            },
            icon: const Icon(Icons.payments_outlined, size: 18),
            label: Text('Pay ${money(b.remaining)}'),
          ),
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
      ],
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Wrap(spacing: 18, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
          switch (b.status) {
            'Cleared' => Pill('Cleared on ${b.clearedAt == null ? '—' : fmtDateTime(b.clearedAt!)}', color: AppColors.success, icon: Icons.check_circle_outline),
            'Part paid' => const Pill('Part paid', color: AppColors.warning),
            _ => const Pill('Unpaid', color: AppColors.danger),
          },
          Text('Paid ${money(b.paid)}', style: const TextStyle(color: AppColors.success, fontWeight: FontWeight.w600)),
          Text('Remaining ${money(b.remaining)}', style: TextStyle(fontWeight: FontWeight.w700, color: b.remaining > 0 ? AppColors.warning : null)),
        ]),
        if (b.purchase.notes.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Text(b.purchase.notes, style: TextStyle(color: ctx.muted))),
        const SizedBox(height: 16),
        const SectionLabel('Payments for this bill'),
        if (b.paidAtEntry)
          _payLine(ctx, b.purchase.paidAt ?? b.purchase.createdAt, 'Marked paid at stock entry', b.amount)
        else if (b.payments.isEmpty)
          Text('Nothing paid yet.', style: TextStyle(color: ctx.muted))
        else
          for (final (p, amt) in b.payments)
            _payLine(ctx, p.date, '${p.mode}${p.note.isEmpty ? '' : ' · ${p.note}'}${amt < p.amount ? ' (part of ${money(p.amount)})' : ''}', amt),
        const SizedBox(height: 16),
        SectionLabel('Medicines (${items.length})'),
        for (final it in items)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(it.productName, style: const TextStyle(fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis),
                  Text('Batch ${it.batchNo} · Exp ${fmtExpiry(it.expiry)} · ${it.qtyLabel} · ${money(it.purchaseRate)} each',
                      style: TextStyle(fontSize: 12, color: ctx.muted), overflow: TextOverflow.ellipsis),
                ]),
              ),
              Text(money(it.total), style: const TextStyle(fontWeight: FontWeight.w600)),
            ]),
          ),
      ]),
    ),
  );
}

Widget _payLine(BuildContext context, DateTime when, String what, double amt) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        const Icon(Icons.check_circle_outline, size: 18, color: AppColors.success),
        const SizedBox(width: 10),
        SizedBox(width: 160, child: Text(fmtDateTime(when), style: TextStyle(color: context.muted, fontSize: 12.5))),
        Expanded(child: Text(what, overflow: TextOverflow.ellipsis)),
        Text(money(amt), style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.success)),
      ]),
    );

/// Records a payment to [s]: for one bill ([bill], pre-selected) or the oldest unpaid bills.
Future<bool> showSupplierPaymentDialog(BuildContext context, Supplier s, {required SupplierAccount account, SupplierBill? bill}) async {
  final open = account.bills.where((b) => !b.isCleared).toList().reversed.toList(); // oldest first
  SupplierBill? target = bill;
  double owedFor(SupplierBill? t) => t?.remaining ?? (account.remaining > 0 ? account.remaining : 0);
  final amountCtrl = TextEditingController(text: owedFor(target) > 0 ? trimNum(owedFor(target)) : '');
  final noteCtrl = TextEditingController();
  var mode = 'Cash';
  String? error;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setD) {
        Future<void> save() async {
          final a = parseNum(amountCtrl.text);
          if (a <= 0) return setD(() => error = 'Enter the amount paid');
          await Repo.paySupplier(s, a, mode: mode, note: noteCtrl.text.trim(), purchaseId: target?.purchase.id);
          if (ctx.mounted) Navigator.pop(ctx, true);
        }

        return AlertDialog(
          title: Text('Payment to ${s.name}'),
          content: SizedBox(
            width: 420,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              DropdownButtonFormField<int>(
                initialValue: target?.purchase.id ?? 0,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Paying for'),
                items: [
                  DropdownMenuItem(value: 0, child: Text('Oldest unpaid bills first (${money(account.remaining > 0 ? account.remaining : 0)} owed)')),
                  for (final b in open)
                    DropdownMenuItem(value: b.purchase.id!, child: Text('${b.label} · ${fmtDateShort(b.purchase.invoiceDate)} · ${money(b.remaining)} left')),
                ],
                onChanged: (v) => setD(() {
                  target = open.where((b) => b.purchase.id == v).firstOrNull;
                  final owed = owedFor(target);
                  amountCtrl.text = owed > 0 ? trimNum(owed) : '';
                }),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: amountCtrl,
                autofocus: true,
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                decoration: InputDecoration(labelText: 'Amount paid', prefixText: '₹ ', errorText: error),
                onSubmitted: (_) => save(),
              ),
              const SizedBox(height: 12),
              Wrap(spacing: 6, children: [
                for (final m in ['Cash', 'UPI', 'Cheque', 'Bank'])
                  ChoiceChip(label: Text(m), selected: mode == m, showCheckmark: false, onSelected: (_) => setD(() => mode = m)),
              ]),
              const SizedBox(height: 12),
              TextField(controller: noteCtrl, decoration: const InputDecoration(labelText: 'Note (cheque no, UPI ref…)'), onSubmitted: (_) => save()),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: save, child: const Text('Save payment')),
          ],
        );
      },
    ),
  );
  return ok == true;
}
