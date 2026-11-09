import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/format.dart';
import '../../core/settings.dart';
import '../../data/repo.dart';
import '../../models/models.dart';
import '../bills/bills_page.dart' show RangeFilter, RangePreset;
import '../inventory/product_form.dart';
import '../suppliers/suppliers_page.dart' show showSupplierForm;
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/date_input.dart';
import '../widgets/suggest_field.dart';

class PurchasesPage extends StatefulWidget {
  const PurchasesPage({super.key});
  @override
  State<PurchasesPage> createState() => _PurchasesPageState();
}

class _PurchasesPageState extends State<PurchasesPage> with DataReload {
  bool _entry = false;
  String _query = '';
  RangePreset _preset = RangePreset.all;
  DateTime? _from, _to;
  List<Purchase> _items = [];
  Timer? _debounce;

  @override
  void reload() async {
    final r = await Repo.purchases(query: _query, from: _from, to: _to);
    if (mounted) setState(() => _items = r);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_entry) return PurchaseEntry(onClose: () => setState(() => _entry = false));
    final total = _items.fold(0.0, (s, p) => s + p.netTotal);
    final unpaid = _items.where((p) => !p.paid).fold(0.0, (s, p) => s + p.netTotal);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      PageHeader(
        title: 'Stock Entry',
        subtitle: 'Purchases from wholesalers — each entry adds batches to inventory',
        actions: [FilledButton.icon(onPressed: () => setState(() => _entry = true), icon: const Icon(Icons.add, size: 18), label: const Text('New stock entry'))],
        bottom: Row(children: [
          SearchBox(
            hint: 'Invoice no or supplier…',
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
        ]),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(28, 0, 28, 12),
        child: Row(children: [
          Pill('${_items.length} entries', color: AppColors.info, icon: Icons.local_shipping_outlined),
          const SizedBox(width: 8),
          Pill('Purchased ${money(total)}', color: AppColors.brand),
          if (unpaid > 0) ...[const SizedBox(width: 8), Pill('Unpaid ${money(unpaid)}', color: AppColors.warning, icon: Icons.pending_outlined)],
        ]),
      ),
      Expanded(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 0, 28, 24),
          child: Card(
            clipBehavior: Clip.antiAlias,
            child: _items.isEmpty
                ? EmptyState(
                    icon: Icons.local_shipping_outlined,
                    title: 'No stock entries yet',
                    message: 'When medicines arrive from a wholesaler, record the invoice here. Batches, expiry and MRP go straight into inventory.',
                    action: FilledButton.icon(onPressed: () => setState(() => _entry = true), icon: const Icon(Icons.add), label: const Text('New stock entry')),
                  )
                : SimpleTable(
                    columns: [
                      const TableCol('Invoice date', width: 120),
                      const TableCol('Supplier', flex: 2),
                      const TableCol('Invoice no', flex: 1),
                      const TableCol('Items', width: 60, right: true),
                      if (Settings.instance.gstEnabled) const TableCol('GST', width: 100, right: true),
                      const TableCol('Net amount', width: 120, right: true),
                      const TableCol('Payment', width: 100),
                    ],
                    rowCount: _items.length,
                    onTap: (i) => _showPurchase(context, _items[i]),
                    cells: (i) {
                      final p = _items[i];
                      return [
                        Text(fmtDate(p.invoiceDate)),
                        Text(p.supplierName, style: const TextStyle(fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis),
                        Text(p.invoiceNo.isEmpty ? '—' : p.invoiceNo),
                        Text('${p.itemCount}'),
                        if (Settings.instance.gstEnabled) Text(amount(p.gstTotal), style: TextStyle(color: context.muted)),
                        Text(money(p.netTotal), style: const TextStyle(fontWeight: FontWeight.w700)),
                        p.paid ? const Pill('Paid', color: AppColors.success, small: true) : const Pill('Unpaid', color: AppColors.warning, small: true),
                      ];
                    },
                  ),
          ),
        ),
      ),
    ]);
  }
}

Future<void> _showPurchase(BuildContext context, Purchase p) async {
  final items = await Repo.purchaseItems(p.id!);
  if (!context.mounted) return;
  await showDialog(
    context: context,
    builder: (ctx) => FormDialog(
      title: 'Invoice ${p.invoiceNo.isEmpty ? '#${p.id}' : p.invoiceNo}',
      subtitle: '${p.supplierName} · ${fmtDate(p.invoiceDate)} · ${money(p.netTotal)}',
      icon: Icons.local_shipping_outlined,
      width: 900,
      actions: [
        TextButton.icon(
          onPressed: () async {
            if (!await confirm(ctx, title: 'Delete this stock entry?', message: 'Its stock will be removed from inventory. Not allowed if any of it was already sold.', confirmLabel: 'Delete', destructive: true)) {
              return;
            }
            try {
              await Repo.deletePurchase(p.id!);
              if (ctx.mounted) Navigator.pop(ctx);
            } on RepoException catch (e) {
              if (ctx.mounted) showSnack(ctx, e.message, error: true);
            }
          },
          icon: const Icon(Icons.delete_outline, size: 18),
          label: const Text('Delete entry'),
          style: TextButton.styleFrom(foregroundColor: AppColors.danger),
        ),
        OutlinedButton(
          onPressed: () async {
            await Repo.setPurchasePaid(p.id!, !p.paid);
            if (ctx.mounted) Navigator.pop(ctx);
          },
          child: Text(p.paid ? 'Mark as unpaid' : 'Mark as paid'),
        ),
        FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
      ],
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (p.notes.isNotEmpty) Padding(padding: const EdgeInsets.only(bottom: 12), child: Text(p.notes)),
        Table(
          columnWidths: const {0: FlexColumnWidth(3), 1: FlexColumnWidth(1.4), 2: FixedColumnWidth(60), 3: FixedColumnWidth(160), 4: FixedColumnWidth(80), 5: FixedColumnWidth(80), 6: FixedColumnWidth(50), 7: FixedColumnWidth(90)},
          defaultVerticalAlignment: TableCellVerticalAlignment.middle,
          children: [
            TableRow(
              decoration: BoxDecoration(border: Border(bottom: BorderSide(color: ctx.border))),
              children: [for (final h in ['Medicine', 'Batch', 'Exp', 'Qty', 'Rate', 'MRP', 'GST', 'Amount']) Padding(padding: const EdgeInsets.all(6), child: Text(h, style: TextStyle(fontWeight: FontWeight.w700, color: ctx.muted, fontSize: 12)))],
            ),
            for (final it in items)
              TableRow(children: [
                Padding(padding: const EdgeInsets.all(6), child: Text(it.productName, style: const TextStyle(fontWeight: FontWeight.w600))),
                Padding(padding: const EdgeInsets.all(6), child: Text(it.batchNo)),
                Padding(padding: const EdgeInsets.all(6), child: Text(fmtExpiry(it.expiry))),
                Padding(padding: const EdgeInsets.all(6), child: Text(it.qtyLabel)),
                Padding(padding: const EdgeInsets.all(6), child: Text(amount(it.purchaseRate))),
                Padding(padding: const EdgeInsets.all(6), child: Text(amount(it.mrp))),
                Padding(padding: const EdgeInsets.all(6), child: Text(it.gstRate > 0 ? '${trimNum(it.gstRate)}%' : '—')),
                Padding(padding: const EdgeInsets.all(6), child: Text(amount(it.total), style: const TextStyle(fontWeight: FontWeight.w600))),
              ]),
          ],
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerRight,
          child: Text(
              [
                if (p.discountTotal > 0 || p.gstTotal > 0) 'Items ${money(p.grossTotal)}',
                if (p.discountTotal > 0) 'Discount ${money(p.discountTotal)}',
                if (p.gstTotal > 0) 'GST ${money(p.gstTotal)}',
                'Total ${money(p.netTotal)}',
              ].join(' · '),
              style: const TextStyle(fontWeight: FontWeight.w600)),
        ),
      ]),
    ),
  );
}

// ====================================================================== entry form

class PurchaseEntry extends StatefulWidget {
  const PurchaseEntry({super.key, required this.onClose});
  final VoidCallback onClose;
  @override
  State<PurchaseEntry> createState() => _PurchaseEntryState();
}

class _PurchaseEntryState extends State<PurchaseEntry> {
  // invoice header
  Supplier? _supplier;
  final _supplierCtrl = TextEditingController();
  final _invoice = TextEditingController();
  late final _dateCtrl = TextEditingController(text: fmtDateInput(today()));
  final _notes = TextEditingController();
  String? _dateError;
  bool _paid = true;

  // item line
  ProductStock? _product;
  final _prodCtrl = TextEditingController();
  final _batch = TextEditingController();
  final _mfg = TextEditingController();
  final _exp = TextEditingController();
  final _qty = TextEditingController();
  final _free = TextEditingController();
  final _rate = TextEditingController();
  final _mrp = TextEditingController();
  final _disc = TextEditingController();
  double _gst = 5;
  String? _rowError;

  // Strip/Box choice per field — only offered when the medicine comes in boxes.
  bool _qtyBox = false, _freeBox = false, _rateBox = false, _mrpBox = false;

  // Enter moves through these in order.
  final _fSupplier = FocusNode(), _fInvoice = FocusNode(), _fDate = FocusNode(), _fNotes = FocusNode();
  final _fProd = FocusNode(), _fBatch = FocusNode(), _fMfg = FocusNode(), _fExp = FocusNode();
  final _fQty = FocusNode(), _fFree = FocusNode(), _fRate = FocusNode(), _fMrp = FocusNode(), _fGst = FocusNode(), _fDisc = FocusNode();

  final List<PurchaseItem> _items = [];
  bool _saving = false;

  static final _monthYearDone = RegExp(r'^\d\d/\d\d$');

  @override
  void dispose() {
    for (final c in [_supplierCtrl, _invoice, _notes, _dateCtrl, _prodCtrl, _batch, _mfg, _exp, _qty, _free, _rate, _mrp, _disc]) {
      c.dispose();
    }
    for (final f in [_fSupplier, _fInvoice, _fDate, _fNotes, _fProd, _fBatch, _fMfg, _fExp, _fQty, _fFree, _fRate, _fMrp, _fGst, _fDisc]) {
      f.dispose();
    }
    super.dispose();
  }

  /// GST fields only when the shop is GST registered; otherwise the rate typed is simply what was paid.
  bool get _gstOn => Settings.instance.gstEnabled;
  double get _gstEff => _gstOn ? _gst : 0;

  Product? get _p => _product?.product;
  bool get _hasBox => _p?.hasOuter ?? false;
  int get _boxSize => _hasBox ? _p!.outerSize : 1;
  String get _packName => _p?.packName ?? 'Strip';

  /// Value per strip for a field that may have been typed per box.
  double _perStrip(TextEditingController c, bool box) => box ? parseNum(c.text) / _boxSize : parseNum(c.text);
  int _strips(TextEditingController c, bool box) => (int.tryParse(c.text) ?? 0) * (box ? _boxSize : 1);

  Future<void> _pickProduct(ProductStock ps) async {
    final known = await Repo.knownBatches(ps.product.id!, '');
    setState(() {
      _product = ps;
      _qtyBox = _freeBox = _rateBox = _mrpBox = false;
      _gst = ps.product.gstRate;
      _rowError = null;
      // Last purchase of this medicine pre-fills its rates (per strip).
      if (known.isNotEmpty) {
        _mrp.text = trimNum(known.first.mrp);
        _rate.text = trimNum(known.first.purchaseRate);
      }
    });
    // The batch field enables on the next frame; focus it once it can take focus.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _fBatch.requestFocus();
    });
  }

  Future<void> _createProduct(String name) async {
    final p = await showProductForm(context, initialName: name.trim());
    if (p == null) return;
    final ps = await Repo.productStock(p.id!);
    if (ps == null) return;
    _prodCtrl.text = p.name;
    await _pickProduct(ps);
  }

  void _addItem() {
    final ps = _product;
    final exp = parseMonthYear(_exp.text);
    final mfg = parseMonthYear(_mfg.text, endOfMonth: false);
    final qty = _strips(_qty, _qtyBox);
    final free = _strips(_free, _freeBox);
    final rate = _perStrip(_rate, _rateBox);
    final mrp = _perStrip(_mrp, _mrpBox);
    String? err;
    FocusNode? focus;
    if (ps == null) {
      (err, focus) = ('Pick a medicine from the list', _fProd);
    } else if (_batch.text.trim().isEmpty) {
      (err, focus) = ('Batch number is required', _fBatch);
    } else if (_mfg.text.trim().isEmpty || mfg == null) {
      (err, focus) = ('Enter the Mfg date like 07/25', _fMfg);
    } else if (mfg.isAfter(today())) {
      (err, focus) = ('Mfg date cannot be in the future', _fMfg);
    } else if (exp == null) {
      (err, focus) = ('Enter the expiry like 07/28', _fExp);
    } else if (!exp.isAfter(mfg)) {
      (err, focus) = ('Expiry must be after the Mfg date', _fExp);
    } else if (exp.isBefore(today())) {
      (err, focus) = ('This batch is already expired', _fExp);
    } else if (qty <= 0 && free <= 0) {
      (err, focus) = ('Enter the quantity', _fQty);
    } else if (mrp <= 0) {
      (err, focus) = ('MRP is required', _fMrp);
    } else if (rate > mrp) {
      (err, focus) = ('Purchase rate is higher than MRP — check the Strip/Box choice', _fRate);
    }
    if (err != null) {
      setState(() => _rowError = err);
      focus?.requestFocus();
      return;
    }
    final p = ps!.product;
    setState(() {
      _items.add(PurchaseItem(
        productId: p.id!,
        productName: p.name,
        batchNo: _batch.text.trim().toUpperCase(),
        mfgDate: mfg,
        expiry: exp!,
        packSize: p.packSize,
        qtyPacks: qty,
        freePacks: free,
        purchaseRate: round2(rate * 10000) / 10000,
        mrp: round2(mrp * 10000) / 10000,
        gstRate: _gstEff,
        discountPct: parseNum(_disc.text).clamp(0, 100).toDouble(),
        boxQty: _qtyBox ? int.tryParse(_qty.text) ?? 0 : 0,
        boxSize: _hasBox ? _boxSize : 0,
        freeBoxes: _freeBox ? int.tryParse(_free.text) ?? 0 : 0,
        packName: p.packName,
      ));
      _product = null;
      _rowError = null;
      _qtyBox = _freeBox = _rateBox = _mrpBox = false;
    });
    for (final c in [_prodCtrl, _batch, _mfg, _exp, _qty, _free, _rate, _mrp, _disc]) {
      c.clear();
    }
    _fProd.requestFocus();
  }

  Future<void> _save() async {
    if (_items.isEmpty) {
      setState(() => _rowError = 'Add at least one item');
      return;
    }
    final date = parseMonthYear(_dateCtrl.text);
    if (date == null || _dateCtrl.text.replaceAll(RegExp(r'\D'), '').length < 6 || date.isAfter(today())) {
      setState(() => _dateError = 'Type the invoice date like 24/09/2026');
      _fDate.requestFocus();
      return;
    }
    setState(() {
      _saving = true;
      _dateError = null;
    });
    try {
      await Repo.createPurchase(
        Purchase(supplierId: _supplier?.id, invoiceNo: _invoice.text.trim(), invoiceDate: date, paid: _paid, notes: _notes.text.trim()),
        _items,
      );
      if (!mounted) return;
      showSnack(context, 'Stock entry saved · ${_items.length} item${_items.length == 1 ? '' : 's'} added to inventory');
      widget.onClose();
    } catch (e) {
      if (mounted) showSnack(context, '$e', error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ---------------------------------------------------------------- building blocks

  /// A "Strip ⇄ Box" switch shown inside a field when the medicine comes in boxes.
  Widget? _unitSuffix(bool box, ValueChanged<bool> onChanged) {
    if (!_hasBox) return null;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: Material(
        color: box ? context.cs.primary.withValues(alpha: 0.14) : context.cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(7),
        child: InkWell(
          canRequestFocus: false,
          borderRadius: BorderRadius.circular(7),
          onTap: () => setState(() => onChanged(!box)),
          child: Tooltip(
            message: 'Switch between ${_p!.packName} and ${_p!.outerName}',
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Text(box ? _p!.outerName : _p!.packName,
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: box ? context.cs.primary : context.muted)),
                const SizedBox(width: 3),
                Icon(Icons.swap_horiz, size: 14, color: box ? context.cs.primary : context.muted),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  Widget _field(
    TextEditingController c,
    FocusNode f,
    String label, {
    FocusNode? next,
    VoidCallback? onEnter,
    List<TextInputFormatter>? formatters,
    String? prefix,
    String? helper,
    String? hint,
    Widget? suffix,
    String? suffixText,
    ValueChanged<String>? onChanged,
  }) =>
      TextField(
        controller: c,
        focusNode: f,
        inputFormatters: formatters,
        onChanged: (v) {
          onChanged?.call(v);
          setState(() {});
        },
        onSubmitted: (_) => onEnter != null ? onEnter() : next?.requestFocus(),
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          prefixText: prefix,
          helperText: helper,
          suffixIcon: suffix,
          suffixText: suffix == null ? suffixText : null,
        ),
      );

  String? _perStripHelper(TextEditingController c, bool box) =>
      box && parseNum(c.text) > 0 ? '= ₹${amount(parseNum(c.text) / _boxSize)} / $_packName' : null;

  String? _stripsHelper(TextEditingController c, bool box) =>
      box && (int.tryParse(c.text) ?? 0) > 0 ? '= ${_strips(c, box)} $_packName' : null;

  Widget _itemForm() {
    final p = _p;
    final qty = _strips(_qty, _qtyBox);
    final free = _strips(_free, _freeBox);
    final rate = _perStrip(_rate, _rateBox);
    final disc = parseNum(_disc.text).clamp(0, 100);
    final lineTotal = qty * rate * (1 - disc / 100) * (1 + _gstEff / 100);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          flex: 4,
          child: SuggestField<ProductStock>(
            controller: _prodCtrl,
            focusNode: _fProd,
            label: 'Medicine',
            prefixIcon: const Icon(Icons.search, size: 18),
            overlayWidth: 520,
            search: (q) => q.trim().isEmpty ? Future.value(<ProductStock>[]) : Repo.searchProducts(q, limit: 20),
            display: (ps) => ps.product.name,
            itemBuilder: (c, ps, hi) => SuggestTile(
              title: ps.product.name,
              badges: [RxBadge(ps.product), if (ps.product.hasOuter) Pill('Box of ${ps.product.outerSize}', color: AppColors.info, small: true)],
              subtitle: [ps.product.manufacturer, ps.product.form, ps.product.packingLabel].where((e) => e.isNotEmpty).join(' · '),
              trailing: Text(ps.stockUnits == 0 ? 'No stock' : ps.product.qty(ps.stockUnits), style: TextStyle(fontSize: 12, color: context.muted)),
            ),
            onSelected: _pickProduct,
            onChanged: (_) {
              if (_product != null && _prodCtrl.text != _product!.product.name) setState(() => _product = null);
            },
            onSubmitted: (v) {
              if (_product != null) {
                _fBatch.requestFocus();
              } else if (v.trim().isNotEmpty) {
                _createProduct(v);
              }
            },
            emptyBuilder: (c) => ListTile(
              leading: const Icon(Icons.add_circle_outline),
              title: Text('Create new medicine "${_prodCtrl.text}"'),
              subtitle: const Text('Press Enter'),
              onTap: () => _createProduct(_prodCtrl.text),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          flex: 2,
          child: SuggestField<Batch>(
            controller: _batch,
            focusNode: _fBatch,
            label: 'Batch no *',
            enabled: p != null,
            textCapitalization: TextCapitalization.characters,
            inputFormatters: upperInput,
            search: (q) => p == null || q.trim().isEmpty ? Future.value(<Batch>[]) : Repo.knownBatches(p.id!, q),
            display: (b) => b.batchNo,
            itemBuilder: (c, b, hi) => SuggestTile(title: b.batchNo, subtitle: 'Mfg ${b.mfgDate == null ? '—' : fmtExpiry(b.mfgDate!)} · Exp ${fmtExpiry(b.expiry)} · MRP ${money(b.mrp)} · seen before'),
            onSelected: (b) {
              setState(() {
                _exp.text = fmtExpiry(b.expiry);
                if (b.mfgDate != null) _mfg.text = fmtExpiry(b.mfgDate!);
                _mrp.text = trimNum(b.mrp);
                _rate.text = trimNum(b.purchaseRate);
                _mrpBox = _rateBox = false;
              });
              (b.mfgDate == null ? _fMfg : _fQty).requestFocus();
            },
            onSubmitted: (_) => _fMfg.requestFocus(),
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 104,
          child: _field(_mfg, _fMfg, 'Mfg *', hint: 'MM/YY', formatters: monthYearInput, next: _fExp, onChanged: (v) {
            if (_monthYearDone.hasMatch(v)) _fExp.requestFocus();
          }),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 104,
          child: _field(_exp, _fExp, 'Expiry *', hint: 'MM/YY', formatters: monthYearInput, next: _fQty, onChanged: (v) {
            if (_monthYearDone.hasMatch(v)) _fQty.requestFocus();
          }),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 120,
          child: InputDecorator(
            decoration: InputDecoration(
              labelText: p == null ? 'Tabs in Strip' : '${p.unitName}s in ${p.packName}',
              enabled: false,
              suffixIcon: const Tooltip(message: 'From the medicine\'s packing (edit it in Inventory)', child: Icon(Icons.lock_outline, size: 16)),
            ),
            child: Text(p == null ? '—' : '${p.packSize}', style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
        ),
      ]),
      const SizedBox(height: 12),
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
          width: 150,
          child: _field(_qty, _fQty, 'Qty *', formatters: intInput, next: _fFree,
              suffix: _unitSuffix(_qtyBox, (v) => _qtyBox = v), suffixText: _packName, helper: _stripsHelper(_qty, _qtyBox)),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 150,
          child: _field(_free, _fFree, 'Free', formatters: intInput, next: _fRate,
              suffix: _unitSuffix(_freeBox, (v) => _freeBox = v), suffixText: _packName, helper: _stripsHelper(_free, _freeBox)),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 170,
          child: _field(_rate, _fRate, 'Purchase rate', prefix: '₹ ', formatters: decimalInput, next: _fMrp,
              suffix: _unitSuffix(_rateBox, (v) => _rateBox = v), suffixText: '/ $_packName', helper: _perStripHelper(_rate, _rateBox)),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 170,
          child: _field(_mrp, _fMrp, 'MRP *', prefix: '₹ ', formatters: decimalInput, next: _gstOn ? _fGst : _fDisc,
              suffix: _unitSuffix(_mrpBox, (v) => _mrpBox = v), suffixText: '/ $_packName', helper: _perStripHelper(_mrp, _mrpBox)),
        ),
        if (_gstOn) ...[
          const SizedBox(width: 10),
          SizedBox(
            width: 124,
            child: GstField(key: ValueKey('gst-${p?.id}'), value: _gst, focusNode: _fGst, onChanged: (v) => setState(() => _gst = v), onSubmitted: () => _fDisc.requestFocus()),
          ),
        ],
        const SizedBox(width: 10),
        SizedBox(width: 90, child: _field(_disc, _fDisc, 'Disc', formatters: decimalInput, suffixText: '%', onEnter: _addItem)),
        const SizedBox(width: 12),
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: FilledButton.icon(onPressed: _addItem, icon: const Icon(Icons.add, size: 18), label: const Text('Add item')),
        ),
      ]),
      const SizedBox(height: 10),
      Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
        if (_rowError != null) Pill(_rowError!, color: AppColors.danger, icon: Icons.error_outline),
        if (p != null) ...[
          Pill(p.packingLabel.isEmpty ? '1 ${p.packName}' : p.packingLabel, color: AppColors.info, icon: Icons.inventory_2_outlined),
          if (qty + free > 0)
            Pill('Receiving ${p.qty((qty + free) * p.packSize)}${free > 0 ? ' (incl. $free $_packName free)' : ''}', color: AppColors.success, icon: Icons.south_west),
          if (lineTotal > 0) Pill('Line total ${money(lineTotal)}', color: context.muted),
        ] else if (_rowError == null)
          Text('Enter moves to the next field · Mfg → Expiry jump automatically · Enter on Disc adds the item',
              style: TextStyle(fontSize: 12, color: context.muted)),
      ]),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final gross = _items.fold(0.0, (s, i) => s + i.gross);
    final disc = _items.fold(0.0, (s, i) => s + i.discount);
    final gst = _items.fold(0.0, (s, i) => s + i.gst);
    final net = _items.fold(0.0, (s, i) => s + i.total);
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyS, control: true): _save,
        const SingleActivator(LogicalKeyboardKey.keyS, meta: true): _save,
      },
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        PageHeader(
          title: 'New stock entry',
          subtitle: 'Enter the wholesaler\'s invoice line by line. Press Enter to move to the next field.',
          actions: [
            TextButton(onPressed: widget.onClose, child: const Text('Cancel')),
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: const Icon(Icons.save_outlined, size: 18),
              label: Text('Save entry · ${money(net)}'),
            ),
          ],
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(28, 0, 28, 24),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(
                      flex: 3,
                      child: SuggestField<Supplier>(
                        controller: _supplierCtrl,
                        focusNode: _fSupplier,
                        autofocus: true,
                        label: 'Supplier / wholesaler',
                        prefixIcon: const Icon(Icons.storefront_outlined, size: 18),
                        showOnFocus: true,
                        search: (q) => Repo.searchSuppliers(q),
                        display: (s) => s.name,
                        itemBuilder: (c, s, hi) => SuggestTile(title: s.name, subtitle: [s.phone, s.gstin].where((e) => e.isNotEmpty).join(' · ')),
                        onSelected: (s) {
                          setState(() => _supplier = s);
                          _fInvoice.requestFocus();
                        },
                        onSubmitted: (_) => _fInvoice.requestFocus(),
                        emptyBuilder: (c) => ListTile(
                          leading: const Icon(Icons.add_business_outlined),
                          title: Text('Add "${_supplierCtrl.text}" as a new supplier'),
                          onTap: () async {
                            final s = await showSupplierForm(context, supplier: Supplier(name: _supplierCtrl.text.trim()));
                            if (s != null) {
                              setState(() => _supplier = s);
                              _supplierCtrl.text = s.name;
                              _fInvoice.requestFocus();
                            }
                          },
                        ),
                        onChanged: (_) {
                          if (_supplier != null && _supplier!.name != _supplierCtrl.text) setState(() => _supplier = null);
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(flex: 2, child: _field(_invoice, _fInvoice, 'Invoice no', next: _fDate)),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: TextField(
                        controller: _dateCtrl,
                        focusNode: _fDate,
                        inputFormatters: dateInput,
                        onSubmitted: (_) => _fNotes.requestFocus(),
                        decoration: InputDecoration(
                          labelText: 'Invoice date',
                          hintText: 'DD/MM/YYYY',
                          errorText: _dateError,
                          suffixIcon: IconButton(
                            tooltip: 'Pick from calendar',
                            icon: const Icon(Icons.calendar_today_outlined, size: 18),
                            onPressed: () async {
                              final d = await showDatePicker(
                                context: context,
                                initialDate: parseMonthYear(_dateCtrl.text) ?? today(),
                                firstDate: DateTime(2020),
                                lastDate: today(),
                              );
                              if (d != null) setState(() => _dateCtrl.text = fmtDateInput(d));
                            },
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(flex: 3, child: _field(_notes, _fNotes, 'Notes', next: _fProd)),
                    const SizedBox(width: 12),
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: SegmentedButton<bool>(
                        showSelectedIcon: false,
                        segments: const [ButtonSegment(value: true, label: Text('Paid')), ButtonSegment(value: false, label: Text('Unpaid'))],
                        selected: {_paid},
                        onSelectionChanged: (v) => setState(() => _paid = v.first),
                      ),
                    ),
                  ]),
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: Card(
                  clipBehavior: Clip.antiAlias,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Container(
                      color: context.cs.surfaceContainerLow,
                      padding: const EdgeInsets.all(14),
                      child: FocusTraversalGroup(child: _itemForm()),
                    ),
                    const Divider(),
                    Expanded(
                      child: _items.isEmpty
                          ? const EmptyState(icon: Icons.playlist_add, title: 'No items yet', message: 'Add each medicine line from the invoice above.')
                          : SimpleTable(
                              columns: [
                                TableCol('Medicine', flex: 3),
                                TableCol('Batch', flex: 1.2),
                                TableCol('Mfg / Exp', width: 110),
                                TableCol('Qty', width: 190),
                                TableCol('Rate', width: 80, right: true),
                                TableCol('MRP', width: 80, right: true),
                                TableCol('Disc', width: 60, right: true),
                                if (_gstOn) const TableCol('GST', width: 60, right: true),
                                TableCol('Amount', width: 100, right: true),
                                TableCol('', width: 44),
                              ],
                              rowCount: _items.length,
                              cells: (i) {
                                final it = _items[i];
                                return [
                                  Text(it.productName, style: const TextStyle(fontWeight: FontWeight.w600)),
                                  Text(it.batchNo),
                                  Text('${it.mfgDate == null ? '—' : fmtExpiry(it.mfgDate!)} → ${fmtExpiry(it.expiry)}', style: TextStyle(fontSize: 12.5, color: context.muted)),
                                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                    Text(it.qtyLabel),
                                    if (it.boughtInBoxes || it.freeBoxes > 0)
                                      Text('= ${it.qtyPacks + it.freePacks} ${it.packName}', style: TextStyle(fontSize: 11.5, color: context.muted)),
                                  ]),
                                  Text(amount(it.purchaseRate)),
                                  Text(amount(it.mrp)),
                                  Text(it.discountPct > 0 ? '${trimNum(it.discountPct)}%' : '—'),
                                  if (_gstOn) Text('${trimNum(it.gstRate)}%'),
                                  Text(amount(it.total), style: const TextStyle(fontWeight: FontWeight.w700)),
                                  IconButton(icon: const Icon(Icons.close, size: 18), onPressed: () => setState(() => _items.removeAt(i))),
                                ];
                              },
                            ),
                    ),
                    const Divider(),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                      child: Row(children: [
                        Text('${_items.length} item${_items.length == 1 ? '' : 's'} · rates shown per strip', style: TextStyle(color: context.muted)),
                        const Spacer(),
                        _total('Gross', gross),
                        _total('Discount', disc),
                        if (_gstOn) _total('GST', gst),
                        _total('Net payable', net, strong: true),
                      ]),
                    ),
                  ]),
                ),
              ),
            ]),
          ),
        ),
      ]),
    );
  }

  Widget _total(String k, double v, {bool strong = false}) => Padding(
        padding: const EdgeInsets.only(left: 28),
        child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(k, style: TextStyle(fontSize: 12, color: context.muted)),
          Text(money(v), style: TextStyle(fontWeight: FontWeight.w700, fontSize: strong ? 18 : 14, color: strong ? context.cs.primary : null)),
        ]),
      );
}
