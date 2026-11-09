import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/format.dart';
import '../../core/settings.dart';
import '../../data/repo.dart';
import '../../models/models.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/date_input.dart';

/// Add opening stock (new batch without a purchase invoice) or edit batch details.
Future<bool?> showBatchForm(BuildContext context, {required Product product, Batch? batch}) =>
    showDialog<bool>(context: context, builder: (_) => _BatchForm(product: product, batch: batch));

class _BatchForm extends StatefulWidget {
  const _BatchForm({required this.product, this.batch});
  final Product product;
  final Batch? batch;
  @override
  State<_BatchForm> createState() => _BatchFormState();
}

class _BatchFormState extends State<_BatchForm> with EnterFlow {
  late final bool _isNew = widget.batch == null;
  late final Batch? b = widget.batch;
  late final _batchNo = TextEditingController(text: b?.batchNo ?? '');
  late final _mfg = TextEditingController(text: b?.mfgDate == null ? '' : fmtExpiry(b!.mfgDate!));
  late final _exp = TextEditingController(text: b == null ? '' : fmtExpiry(b!.expiry));
  final _outers = TextEditingController();
  final _packs = TextEditingController();
  final _loose = TextEditingController();
  late final _mrp = TextEditingController(text: b == null ? '' : trimNum(b!.mrp));
  late final _sale = TextEditingController(text: b == null ? '' : trimNum(b!.saleRate));
  late final _purchase = TextEditingController(text: b == null ? '' : trimNum(b!.purchaseRate));
  late final _disc = TextEditingController(text: b == null || b!.discountPct == 0 ? '' : trimNum(b!.discountPct));
  late double _gst = b?.gstRate ?? widget.product.gstRate;
  String? _error;
  static final _monthYearDone = RegExp(r'^\d\d/\d\d$');

  bool get _gstOn => Settings.instance.gstEnabled;

  @override
  List<String> get flowOrder => [
        'batch', 'mfg', 'exp',
        if (_isNew && widget.product.hasOuter) 'outers',
        if (_isNew) ...['packs', 'loose'],
        'mrp', 'sale', 'purchase',
        if (_gstOn) 'gst',
        'disc',
      ];

  @override
  void onFlowDone() => _save();

  Widget _tf(String key, TextEditingController c, InputDecoration d,
          {List<TextInputFormatter>? formatters, bool autofocus = false, ValueChanged<String>? onChanged, bool upper = false}) =>
      TextField(
        controller: c,
        focusNode: fn(key),
        autofocus: autofocus,
        inputFormatters: formatters,
        textCapitalization: upper ? TextCapitalization.characters : TextCapitalization.none,
        decoration: d,
        onChanged: onChanged,
        onSubmitted: (_) => advance(key),
      );

  Future<void> _save() async {
    final exp = parseMonthYear(_exp.text);
    final mfg = _mfg.text.trim().isEmpty ? null : parseMonthYear(_mfg.text, endOfMonth: false);
    final packSize = b?.packSize ?? widget.product.packSize;
    final mrp = parseNum(_mrp.text);
    if (_batchNo.text.trim().isEmpty) return setState(() => _error = 'Batch number is required');
    if (mfg == null) {
      fn('mfg').requestFocus();
      return setState(() => _error = 'Mfg date is required, like 08/25');
    }
    if (exp == null) {
      fn('exp').requestFocus();
      return setState(() => _error = 'Expiry must be like 08/27');
    }
    if (!exp.isAfter(mfg)) return setState(() => _error = 'Expiry must be after the Mfg date');
    if (mrp <= 0) return setState(() => _error = 'MRP is required');
    final sale = _sale.text.trim().isEmpty ? mrp : parseNum(_sale.text);
    if (sale > mrp) return setState(() => _error = 'Sale rate cannot be more than MRP');
    if (_isNew) {
      final outer = widget.product.hasOuter ? widget.product.outerSize : 0;
      final qty = (parseNum(_outers.text) * outer * packSize + parseNum(_packs.text) * packSize + parseNum(_loose.text)).round();
      if (qty <= 0) return setState(() => _error = 'Enter the quantity in stock');
      await Repo.addOpeningBatch(Batch(
        productId: widget.product.id!,
        batchNo: _batchNo.text.trim().toUpperCase(),
        mfgDate: mfg,
        expiry: exp,
        packSize: packSize,
        mrp: mrp,
        saleRate: sale,
        purchaseRate: parseNum(_purchase.text),
        gstRate: _gst,
        discountPct: parseNum(_disc.text).clamp(0, 100).toDouble(),
        qty: qty,
      ));
    } else {
      b!
        ..batchNo = _batchNo.text.trim().toUpperCase()
        ..mfgDate = mfg
        ..expiry = exp
        ..mrp = mrp
        ..saleRate = sale
        ..purchaseRate = parseNum(_purchase.text)
        ..gstRate = _gst
        ..discountPct = parseNum(_disc.text).clamp(0, 100).toDouble();
      await Repo.updateBatch(b!);
    }
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.product;
    return FormDialog(
      title: _isNew ? 'Add opening stock' : 'Edit batch ${b!.batchNo}',
      subtitle: p.name,
      icon: Icons.inventory_2_outlined,
      width: 600,
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: _save, child: Text(_isNew ? 'Add stock' : 'Save batch')),
      ],
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (_error != null) ...[Pill(_error!, color: AppColors.danger, icon: Icons.error_outline), const SizedBox(height: 12)],
        FieldRow(flex: const [2, 1, 1], children: [
          _tf('batch', _batchNo, const InputDecoration(labelText: 'Batch no *'), formatters: upperInput, autofocus: true, upper: true),
          _tf('mfg', _mfg, const InputDecoration(labelText: 'Mfg *', hintText: 'MM/YY'), formatters: monthYearInput, onChanged: (v) {
            if (_monthYearDone.hasMatch(v)) fn('exp').requestFocus();
          }),
          _tf('exp', _exp, const InputDecoration(labelText: 'Expiry *', hintText: 'MM/YY'), formatters: monthYearInput, onChanged: (v) {
            if (_monthYearDone.hasMatch(v)) advance('exp');
          }),
        ]),
        FieldRow(children: [
          InputDecorator(
            decoration: InputDecoration(
              labelText: '${p.unitName}s in ${p.packName}',
              enabled: false,
              suffixIcon: const Tooltip(message: 'From the medicine\'s packing', child: Icon(Icons.lock_outline, size: 16)),
            ),
            child: Text('${b?.packSize ?? p.packSize}', style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
          if (_isNew && p.hasOuter)
            _tf('outers', _outers, InputDecoration(labelText: '${p.outerName}s', helperText: '${p.outerSize} ${p.packName} each'), formatters: intInput),
          if (_isNew) _tf('packs', _packs, InputDecoration(labelText: p.hasOuter ? '+ ${p.packName}s' : 'Qty (${p.packName}s)'), formatters: decimalInput),
          if (_isNew) _tf('loose', _loose, InputDecoration(labelText: '+ loose ${p.unitName}s'), formatters: intInput),
          if (!_isNew) InputDecorator(decoration: const InputDecoration(labelText: 'In stock'), child: Text(p.qty(b!.qty))),
        ]),
        FieldRow(children: [
          _tf('mrp', _mrp, InputDecoration(labelText: 'MRP per ${p.packName} *', prefixText: '₹ '), formatters: decimalInput),
          _tf('sale', _sale, const InputDecoration(labelText: 'Selling rate (≤ MRP)', prefixText: '₹ ', hintText: 'same as MRP'), formatters: decimalInput),
          _tf('purchase', _purchase, const InputDecoration(labelText: 'Purchase rate', prefixText: '₹ '), formatters: decimalInput),
        ]),
        FieldRow(children: [
          if (_gstOn) GstField(value: _gst, focusNode: fn('gst'), onChanged: (v) => _gst = v, onSubmitted: () => advance('gst')),
          _tf('disc', _disc, const InputDecoration(labelText: 'Default discount', suffixText: '%', helperText: 'Auto-applied on the bill'), formatters: decimalInput),
        ]),
      ]),
    );
  }
}

/// Physical stock count correction for one batch.
Future<void> showAdjustStock(BuildContext context, Product p, Batch b) async {
  final packs = TextEditingController(text: '${b.qty ~/ b.packSize}');
  final loose = TextEditingController(text: '${b.qty % b.packSize}');
  final reason = TextEditingController();
  final fPacks = FocusNode(), fLoose = FocusNode(), fReason = FocusNode();
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('Adjust stock · ${b.batchNo}'),
      content: SizedBox(
        width: 420,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('${p.name} — currently ${p.qty(b.qty)}', style: TextStyle(color: ctx.muted)),
          const SizedBox(height: 14),
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
                onSubmitted: (_) => fReason.requestFocus(),
                inputFormatters: intInput,
                decoration: InputDecoration(labelText: b.packSize > 1 ? '+ loose ${p.unitName}s' : '${p.unitName}s'),
              ),
            ),
          ]),
          const SizedBox(height: 12),
          TextField(
            controller: reason,
            focusNode: fReason,
            decoration: const InputDecoration(labelText: 'Reason', hintText: 'Physical count, damaged, breakage…'),
            onSubmitted: (_) => Navigator.pop(ctx, true),
          ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Update stock')),
      ],
    ),
  );
  for (final f in [fPacks, fLoose, fReason]) {
    f.dispose();
  }
  if (ok != true) return;
  final newQty = (b.packSize > 1 ? (int.tryParse(packs.text) ?? 0) * b.packSize : 0) + (int.tryParse(loose.text) ?? 0);
  await Repo.adjustStock(b, newQty, reason.text.trim().isEmpty ? 'Stock correction' : reason.text.trim());
  if (context.mounted) showSnack(context, 'Stock updated to ${p.qty(newQty)}');
}
