import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/db.dart';
import '../../core/format.dart';
import '../../data/repo.dart';
import '../../models/models.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// A supplier's (or one-off shop's) account: goods received, paid, still owed,
/// the medicines they supplied, and every stock entry and payment.
/// [onEdit] / [onDelete] are offered for saved suppliers only.
Future<void> showSupplierAccount(BuildContext context, Supplier s, {VoidCallback? onEdit, VoidCallback? onDelete}) =>
    showDialog<void>(context: context, builder: (_) => _SupplierAccount(supplier: s, onEdit: onEdit, onDelete: onDelete));

class _SupplierAccount extends StatefulWidget {
  const _SupplierAccount({required this.supplier, this.onEdit, this.onDelete});
  final Supplier supplier;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  @override
  State<_SupplierAccount> createState() => _SupplierAccountState();
}

class _SupplierAccountState extends State<_SupplierAccount> {
  Supplier get s => widget.supplier;
  List<CreditEntry> _ledger = [];
  List<Map<String, Object?>> _products = [];
  bool _loaded = false;

  double get _goods => round2(_ledger.fold(0.0, (t, e) => t + e.debit));
  double get _paid => round2(_ledger.fold(0.0, (t, e) => t + e.credit));
  double get _remaining => round2(_goods - _paid);

  @override
  void initState() {
    super.initState();
    dataVersion.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    dataVersion.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    final ledger = await Repo.supplierLedger(s);
    final products = await Repo.supplierProducts(s);
    if (!mounted) return;
    setState(() {
      _ledger = ledger;
      _products = products;
      _loaded = true;
    });
  }

  Future<void> _pay() async {
    final paid = await showSupplierPaymentDialog(context, s, owed: _remaining);
    if (paid && mounted) showSnack(context, 'Payment to ${s.name} saved');
  }

  @override
  Widget build(BuildContext context) {
    final saved = s.id != null;
    final remaining = _remaining;
    return FormDialog(
      title: s.name,
      subtitle: saved
          ? [s.contactPerson, s.phone, s.gstin.isEmpty ? '' : 'GSTIN ${s.gstin}', s.drugLicense.isEmpty ? '' : 'DL ${s.drugLicense}'].where((e) => e.isNotEmpty).join(' · ')
          : 'One-off shop — medicines brought from here while billing',
      icon: saved ? Icons.storefront_outlined : Icons.local_shipping_outlined,
      width: 820,
      actions: [
        if (saved && widget.onDelete != null)
          TextButton.icon(
            onPressed: widget.onDelete,
            icon: const Icon(Icons.delete_outline, size: 18),
            label: const Text('Delete'),
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
          ),
        if (saved && widget.onEdit != null)
          OutlinedButton.icon(onPressed: widget.onEdit, icon: const Icon(Icons.edit_outlined, size: 18), label: const Text('Edit')),
        FilledButton.icon(onPressed: _pay, icon: const Icon(Icons.payments_outlined, size: 18), label: const Text('Record payment')),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
      ],
      child: !_loaded
          ? const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()))
          : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (s.address.isNotEmpty) Text(s.address),
              if (s.notes.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text(s.notes, style: TextStyle(color: context.muted))),
              if (s.address.isNotEmpty || s.notes.isNotEmpty) const SizedBox(height: 12),
              Row(children: [
                Expanded(child: _tile('Goods received', money(_goods), Icons.inventory_2_outlined, AppColors.info)),
                const SizedBox(width: 10),
                Expanded(child: _tile('Paid', money(_paid), Icons.check_circle_outline, AppColors.success)),
                const SizedBox(width: 10),
                Expanded(
                  child: _tile(
                    remaining < 0 ? 'Paid in advance' : 'Remaining to pay',
                    money(remaining.abs()),
                    Icons.account_balance_wallet_outlined,
                    remaining > 0.004 ? AppColors.warning : AppColors.success,
                  ),
                ),
              ]),
              const SizedBox(height: 18),
              SectionLabel('Medicines supplied (${_products.length})'),
              if (_products.isEmpty) Text('Nothing received yet.', style: TextStyle(color: context.muted)),
              for (final r in _products) _productRow(r),
              const SizedBox(height: 14),
              SectionLabel('Stock entries & payments (${_ledger.length})'),
              if (_ledger.isEmpty) Text('No stock entries or payments yet.', style: TextStyle(color: context.muted)),
              if (_ledger.isNotEmpty) _ledgerHeader(),
              for (final e in _ledger.reversed) _ledgerRow(e),
            ]),
    );
  }

  Widget _tile(String label, String value, IconData icon, Color color) => Container(
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
              Text(value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: color), maxLines: 1, overflow: TextOverflow.ellipsis),
            ]),
          ),
        ]),
      );

  Widget _productRow(Map<String, Object?> r) {
    final units = (r['units'] as num?)?.toInt() ?? 0;
    final qty = fmtQty(units, (r['pack_size'] as num?)?.toInt() ?? 1, '${r['unit_name']}', '${r['pack_name']}');
    final times = r['times'] as int? ?? 0;
    final last = r['last_date'] == null ? null : DateTime.tryParse(r['last_date'] as String);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(children: [
        const Icon(Icons.medication_outlined, size: 18),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${r['product_name']}', style: const TextStyle(fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis),
            Text('$qty · $times time${times == 1 ? '' : 's'}${last == null ? '' : ' · last ${fmtDate(last)}'}',
                style: TextStyle(fontSize: 12, color: context.muted), overflow: TextOverflow.ellipsis),
          ]),
        ),
        Text(money((r['value'] as num?) ?? 0), style: const TextStyle(fontWeight: FontWeight.w600)),
      ]),
    );
  }

  Widget _ledgerHeader() {
    final st = TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: context.muted, letterSpacing: 0.3);
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(children: [
        SizedBox(width: 92, child: Text('DATE', style: st)),
        Expanded(child: Text('ENTRY', style: st)),
        SizedBox(width: 96, child: Text('GOODS', style: st, textAlign: TextAlign.right)),
        SizedBox(width: 96, child: Text('PAID', style: st, textAlign: TextAlign.right)),
        SizedBox(width: 104, child: Text('OWED', style: st, textAlign: TextAlign.right)),
        const SizedBox(width: 36),
      ]),
    );
  }

  Widget _ledgerRow(CreditEntry e) {
    final isPay = e.kind == 'payment';
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(border: Border(top: BorderSide(color: context.border))),
      child: Row(children: [
        SizedBox(width: 92, child: Text(fmtDateShort(e.date), style: TextStyle(color: context.muted))),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(e.label, style: TextStyle(fontWeight: FontWeight.w600, color: isPay ? AppColors.success : null), overflow: TextOverflow.ellipsis),
            if (e.note.isNotEmpty) Text(e.note, style: TextStyle(fontSize: 12, color: context.muted), overflow: TextOverflow.ellipsis),
          ]),
        ),
        SizedBox(width: 96, child: Text(e.debit > 0 ? amount(e.debit) : '', textAlign: TextAlign.right)),
        SizedBox(
          width: 96,
          child: Text(e.credit > 0 ? amount(e.credit) : '', textAlign: TextAlign.right, style: const TextStyle(color: AppColors.success)),
        ),
        SizedBox(
          width: 104,
          child: Text(amount(e.runningBalance),
              textAlign: TextAlign.right, style: TextStyle(fontWeight: FontWeight.w700, color: e.runningBalance > 0.004 ? AppColors.warning : null)),
        ),
        SizedBox(
          width: 36,
          child: isPay
              ? IconButton(
                  tooltip: 'Delete payment',
                  icon: const Icon(Icons.close, size: 16),
                  color: context.muted,
                  onPressed: () async {
                    if (!await confirm(context,
                        title: 'Delete this payment?', message: '${money(e.credit)} paid on ${fmtDate(e.date)} will be removed.', confirmLabel: 'Delete', destructive: true)) {
                      return;
                    }
                    await Repo.deleteSupplierPayment(e.refId);
                  },
                )
              : null,
        ),
      ]),
    );
  }
}

/// Asks how much was paid to [s] (pre-filled with what is [owed]) and saves it.
Future<bool> showSupplierPaymentDialog(BuildContext context, Supplier s, {double owed = 0}) async {
  final amountCtrl = TextEditingController(text: owed > 0 ? trimNum(owed) : '');
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
          await Repo.paySupplier(s, a, mode: mode, note: noteCtrl.text.trim());
          if (ctx.mounted) Navigator.pop(ctx, true);
        }

        return AlertDialog(
          title: Text('Payment to ${s.name}'),
          content: SizedBox(
            width: 380,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (owed > 0) Padding(padding: const EdgeInsets.only(bottom: 10), child: Text('Remaining to pay: ${money(owed)}')),
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
              TextField(
                controller: noteCtrl,
                decoration: const InputDecoration(labelText: 'Note (cheque no, invoice…)'),
                onSubmitted: (_) => save(),
              ),
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
