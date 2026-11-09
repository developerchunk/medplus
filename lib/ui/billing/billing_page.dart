import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/bill_file.dart';
import '../../core/format.dart';
import '../../core/print_service.dart';
import '../../core/settings.dart';
import '../../data/repo.dart';
import '../../models/models.dart';
import '../bills/bill_viewer.dart';
import '../credit/credit_page.dart' show CreditBadge;
import '../nav.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/suggest_field.dart';

/// One medicine line on the bill being prepared.
class BillLine {
  BillLine({required this.product, required this.batches, this.batch, required int qty, double disc = 0})
      : qty = qty,
        disc = disc,
        qtyCtrl = TextEditingController(text: '$qty'),
        discCtrl = TextEditingController(text: disc > 0 ? trimNum(disc) : ''),
        batchCtrl = TextEditingController(text: batch?.batchNo ?? '');

  final Product product;
  List<Batch> batches;
  Batch? batch;
  int qty; // in units (tablets, vials, bottles…)
  double disc;
  final TextEditingController qtyCtrl;
  final TextEditingController discCtrl;
  final TextEditingController batchCtrl;
  final batchFocus = FocusNode();
  final qtyFocus = FocusNode();
  final discFocus = FocusNode();

  double get unitRate => batch?.unitRate ?? 0;
  double get gross => round2(qty * unitRate);
  double get amount => round2(qty * unitRate * (1 - disc / 100));
  double get gstRate => batch?.gstRate ?? product.gstRate;

  void dispose() {
    qtyCtrl.dispose();
    discCtrl.dispose();
    batchCtrl.dispose();
    batchFocus.dispose();
    qtyFocus.dispose();
    discFocus.dispose();
  }
}

class BillingPage extends StatefulWidget {
  const BillingPage({super.key});
  @override
  State<BillingPage> createState() => _BillingPageState();
}

class _BillingPageState extends State<BillingPage> {
  // patient & doctor
  final _custName = TextEditingController();
  final _custPhone = TextEditingController();
  final _custAddr = TextEditingController();
  final _docName = TextEditingController();
  final _docReg = TextEditingController();
  final _docClinic = TextEditingController();
  final _rxNotes = TextEditingController();
  final _custFocus = FocusNode();
  final _phoneFocus = FocusNode();
  final _addrFocus = FocusNode();
  final _docFocus = FocusNode();
  final _regFocus = FocusNode();
  final _clinicFocus = FocusNode();
  final _notesFocus = FocusNode();
  final _billDiscFocus = FocusNode();
  final _payFocus = FocusNode(); // cash received / paid now
  final _saveFocus = FocusNode();

  // entry row
  final _prodCtrl = TextEditingController();
  final _batchCtrl = TextEditingController();
  final _qtyCtrl = TextEditingController();
  final _discCtrl = TextEditingController();
  final _prodFocus = FocusNode();
  final _batchFocus = FocusNode();
  final _qtyFocus = FocusNode();
  final _discFocus = FocusNode();
  ProductStock? _selProduct;
  List<Batch> _selBatches = [];
  Batch? _selBatch;
  int _qtyMode = 0; // 0 = loose units, 1 = packs (strips), 2 = outer packs (boxes)
  String? _entryError;

  // template & summary
  final _tplCtrl = TextEditingController();
  final _tplFocus = FocusNode();
  final _billDiscCtrl = TextEditingController();
  final _receivedCtrl = TextEditingController();
  final _paidNowCtrl = TextEditingController();
  String _payment = 'Cash';
  Customer? _customer; // picked from suggestions (credit badge, balance)
  Doctor? _defaultDoctor;
  String _templateCode = '';

  final List<BillLine> _lines = [];
  bool _saving = false;
  Sale? _lastSale;
  Timer? _clock;

  @override
  void initState() {
    super.initState();
    Nav.pendingTemplate.addListener(_onPendingTemplate);
    Nav.pendingCustomer.addListener(_onPendingCustomer);
    Settings.instance.addListener(_onSettings);
    _batchFocus.addListener(_onEntryBatchFocus);
    _clock = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _applyDefaultDoctor();
      _onPendingTemplate();
      _onPendingCustomer();
      _prodFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    Nav.pendingTemplate.removeListener(_onPendingTemplate);
    Nav.pendingCustomer.removeListener(_onPendingCustomer);
    Settings.instance.removeListener(_onSettings);
    _clock?.cancel();
    for (final c in [_custName, _custPhone, _custAddr, _docName, _docReg, _docClinic, _rxNotes, _prodCtrl, _batchCtrl, _qtyCtrl, _discCtrl, _tplCtrl, _billDiscCtrl, _receivedCtrl, _paidNowCtrl]) {
      c.dispose();
    }
    for (final f in [_custFocus, _phoneFocus, _addrFocus, _docFocus, _regFocus, _clinicFocus, _notesFocus, _billDiscFocus, _payFocus, _saveFocus,
      _prodFocus, _batchFocus, _qtyFocus, _discFocus, _tplFocus]) {
      f.dispose();
    }
    for (final l in _lines) {
      l.dispose();
    }
    super.dispose();
  }

  void _onSettings() {
    if (!mounted) return;
    final id = Settings.instance.integer('default_doctor_id');
    if ((_defaultDoctor?.id ?? 0) != id) {
      // Default doctor changed in settings: refresh it on an untouched bill.
      final untouched = _lines.isEmpty && (_docName.text.trim().isEmpty || _docName.text.trim() == _defaultDoctor?.name);
      _applyDefaultDoctor(fill: untouched);
    }
    setState(() {});
  }

  /// Loads the default doctor and, when [fill], pre-fills the doctor fields.
  Future<void> _applyDefaultDoctor({bool fill = true}) async {
    final id = Settings.instance.integer('default_doctor_id');
    final d = id > 0 ? await Repo.doctor(id) : null;
    if (!mounted) return;
    setState(() {
      _defaultDoctor = d;
      if (fill) {
        _docName.text = d?.name ?? '';
        _docReg.text = d?.regNo ?? '';
        _docClinic.text = d?.clinic ?? '';
      }
    });
  }

  bool get _isDefaultDoctor => _defaultDoctor != null && _docName.text.trim().toLowerCase() == _defaultDoctor!.name.toLowerCase();

  /// Focus a field that may only become enabled on the next frame.
  void _focusNextFrame(FocusNode f) => WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) f.requestFocus();
      });

  /// Enter from the (empty) medicine field moves to checkout: extra discount → payment → Save & Print.
  void _toCheckout() => (_lines.isEmpty ? _prodFocus : _billDiscFocus).requestFocus();

  void _afterBillDiscount() {
    if (_payment == 'Cash' || _payment == 'Credit') {
      _payFocus.requestFocus();
    } else {
      _saveFocus.requestFocus();
    }
  }

  void _pickCustomer(Customer c) {
    setState(() {
      _customer = c;
      _custName.text = c.name;
      _custPhone.text = c.phone;
      if (c.address.isNotEmpty) _custAddr.text = c.address;
    });
  }

  Future<void> _onPendingCustomer() async {
    final id = Nav.pendingCustomer.value;
    if (id == null) return;
    Nav.pendingCustomer.value = null;
    final c = await Repo.customer(id);
    if (c == null || !mounted) return;
    _pickCustomer(c);
    if (c.creditAllowed) setState(() => _payment = 'Credit');
    _prodFocus.requestFocus();
  }

  void _onPendingTemplate() {
    final code = Nav.pendingTemplate.value;
    if (code == null) return;
    Nav.pendingTemplate.value = null;
    _loadTemplateCode(code);
  }

  // ---------------------------------------------------------------- totals

  double get _billDiscPct => parseNum(_billDiscCtrl.text).clamp(0, 100).toDouble();
  double get _gross => round2(_lines.fold(0.0, (s, l) => s + l.gross));
  double get _net1 => round2(_lines.fold(0.0, (s, l) => s + l.amount));
  double get _itemDisc => round2(_gross - _net1);
  double get _billDisc => round2(_net1 * _billDiscPct / 100);
  double get _net2 => round2(_net1 - _billDisc);
  double get _grand => _net2.roundToDouble();
  double get _roundOff => round2(_grand - _net2);
  /// GST applies only when the shop has turned it on in Settings (most small shops don't charge GST).
  bool get _gstOn => Settings.instance.gstEnabled;
  double _lineGst(BillLine l) => _gstOn ? l.gstRate : 0;
  double get _taxable => round2(_lines.fold(0.0, (s, l) => s + l.amount * (1 - _billDiscPct / 100) / (1 + _lineGst(l) / 100)));
  double get _gst => round2(_net2 - _taxable);
  double get _paidNow => _payment == 'Credit' ? parseNum(_paidNowCtrl.text).clamp(0, _grand).toDouble() : _grand;
  double get _creditDue => round2(_grand - _paidNow);

  int _usedInLines(int batchId, {BillLine? except}) =>
      _lines.where((l) => l != except && l.batch?.id == batchId).fold(0, (s, l) => s + l.qty);

  String? _lineError(BillLine l) {
    final typed = l.batchCtrl.text.trim();
    if (typed.isNotEmpty && typed.toLowerCase() != l.batch?.batchNo.toLowerCase()) {
      return 'Batch "$typed" is not in stock for this medicine — pick one from the list';
    }
    if (l.batch == null) return l.batches.isEmpty ? 'Out of stock' : 'Choose a batch';
    if (l.qty <= 0) return 'Enter quantity';
    final used = _usedInLines(l.batch!.id!);
    if (used > l.batch!.qty) return 'Only ${l.product.qty(l.batch!.qty)} in batch';
    return null;
  }

  List<BillLine> get _rxLines => _lines.where((l) => l.product.needsPrescription).toList();

  // ---------------------------------------------------------------- entry row

  Future<List<ProductStock>> _searchProducts(String q) => q.trim().isEmpty ? Future.value([]) : Repo.searchProducts(q, limit: 25);

  Future<void> _onProductSelected(ProductStock ps) async {
    final batches = await Repo.batchesForProduct(ps.product.id!, sellableOnly: true);
    if (!mounted) return;
    setState(() {
      _selProduct = ps;
      _selBatches = batches;
      _qtyMode = 0;
      _entryError = null;
    });
    if (batches.isEmpty) {
      setState(() {
        _selBatch = null;
        _entryError = ps.expiredUnits > 0 ? 'Only expired stock left for ${ps.product.name}.' : '${ps.product.name} is out of stock.';
      });
      _prodCtrl.selection = TextSelection(baseOffset: 0, extentOffset: _prodCtrl.text.length);
      return;
    }
    // First-expiry-first-out: preselect the earliest-expiring batch that still has free stock.
    final fefo = batches.firstWhere((b) => b.qty - _usedInLines(b.id!) > 0, orElse: () => batches.first);
    _setEntryBatch(fefo);
    // The batch field enables on the next frame; focus it once it can take focus.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _batchFocus.requestFocus();
    });
  }

  void _setEntryBatch(Batch b) {
    setState(() {
      _selBatch = b;
      _batchCtrl.text = b.batchNo;
      _discCtrl.text = b.discountPct > 0 ? trimNum(b.discountPct) : '';
      _entryError = b.qty - _usedInLines(b.id!) <= 0 ? 'Batch ${b.batchNo} is fully used in this bill already.' : null;
    });
  }

  /// Explains why a typed batch number can't be billed for [p].
  Future<String> _batchProblem(Product p, String typed, List<Batch> sellable) async {
    final t = typed.trim();
    final all = await Repo.batchesForProduct(p.id!, includeEmpty: true);
    final hit = all.where((b) => b.batchNo.toLowerCase() == t.toLowerCase()).firstOrNull;
    final options = sellable.map((b) => b.batchNo).take(4).join(', ');
    final hint = sellable.isEmpty ? '' : ' In stock: $options.';
    if (hit == null) return 'Batch "$t" does not exist for ${p.name}.$hint';
    if (hit.isExpired) return 'Batch ${hit.batchNo} of ${p.name} expired (${fmtExpiry(hit.expiry)}) and cannot be sold.$hint';
    if (hit.status != 'active') return 'Batch ${hit.batchNo} of ${p.name} was ${hit.status}.$hint';
    if (hit.qty <= 0) return 'Batch ${hit.batchNo} of ${p.name} is sold out.$hint';
    return 'Batch ${hit.batchNo} is fully used on this bill already.$hint';
  }

  Batch? _matchBatch(List<Batch> list, String typed) =>
      list.where((b) => b.batchNo.toLowerCase() == typed.trim().toLowerCase()).firstOrNull;

  void _onEntryBatchFocus() {
    if (_batchFocus.hasFocus || _selProduct == null) return;
    final typed = _batchCtrl.text.trim();
    if (typed.isEmpty) return;
    final m = _matchBatch(_selBatches, typed);
    if (m != null) {
      if (_selBatch?.id != m.id) _setEntryBatch(m);
      return;
    }
    _batchProblem(_selProduct!.product, typed, _selBatches).then((msg) {
      if (mounted) setState(() => _entryError = msg);
    });
  }

  Future<List<Batch>> _searchEntryBatches(String q) async {
    final t = q.trim().toLowerCase();
    return _selBatches.where((b) => t.isEmpty || b.batchNo.toLowerCase().contains(t)).toList();
  }

  void _resetEntry() {
    setState(() {
      _selProduct = null;
      _selBatches = [];
      _selBatch = null;
      _entryError = null;
      _qtyMode = 0;
    });
    _prodCtrl.clear();
    _batchCtrl.clear();
    _qtyCtrl.clear();
    _discCtrl.clear();
    _prodFocus.requestFocus();
  }

  void _addEntry() {
    final ps = _selProduct;
    final b = _selBatch;
    if (ps == null) {
      setState(() => _entryError = 'Pick a medicine from the suggestions.');
      _prodFocus.requestFocus();
      return;
    }
    final typed = _batchCtrl.text.trim();
    if (b == null || typed.toLowerCase() != b.batchNo.toLowerCase()) {
      if (typed.isEmpty) {
        setState(() => _entryError = 'Pick a batch.');
      } else {
        _batchProblem(ps.product, typed, _selBatches).then((msg) {
          if (mounted) setState(() => _entryError = msg);
        });
      }
      _batchFocus.requestFocus();
      return;
    }
    final qty = parseQty(_qtyCtrl.text.isEmpty ? '1' : _qtyCtrl.text, b.packSize, outerSize: ps.product.hasOuter ? ps.product.outerSize : 0, mode: _qtyMode);
    if (qty == null) {
      setState(() => _entryError = 'Quantity must be a whole number of ${ps.product.unitName}s (e.g. 5, 2s for 2 ${ps.product.packName}s'
          '${ps.product.hasOuter ? ', 1b for 1 ${ps.product.outerName}' : ''}).');
      _qtyFocus.requestFocus();
      return;
    }
    final free = b.qty - _usedInLines(b.id!);
    if (qty > free) {
      setState(() => _entryError = 'Only ${ps.product.qty(free)} available in batch ${b.batchNo}.');
      _qtyFocus.requestFocus();
      return;
    }
    final disc = parseNum(_discCtrl.text).clamp(0, 100).toDouble();
    // Same batch already on the bill → just increase its quantity.
    final existing = _lines.where((l) => l.batch?.id == b.id && l.disc == disc).firstOrNull;
    setState(() {
      if (existing != null) {
        existing.qty += qty;
        existing.qtyCtrl.text = '${existing.qty}';
      } else {
        _lines.add(BillLine(product: ps.product, batches: _selBatches, batch: b, qty: qty, disc: disc));
      }
    });
    _resetEntry();
  }

  // ---------------------------------------------------------------- templates

  Future<List<BillTemplate>> _searchTemplates(String q) => Repo.templates(q);

  Future<void> _loadTemplateCode(String code) async {
    if (code.trim().isEmpty) return;
    final t = await Repo.template(code: code.trim());
    if (!mounted) return;
    if (t == null) {
      showSnack(context, 'No template with number "$code"', error: true);
      return;
    }
    await _applyTemplate(t);
  }

  Future<void> _applyTemplate(BillTemplate tpl) async {
    final t = tpl.items.isEmpty ? await Repo.template(id: tpl.id) : tpl;
    if (t == null || !mounted) return;
    var short = <String>[];
    for (final item in t.items) {
      final p = item.product ?? await Repo.product(item.productId);
      if (p == null) continue;
      final batches = await Repo.batchesForProduct(p.id!, sellableOnly: true);
      var need = item.qtyUnits;
      for (final b in batches) {
        if (need <= 0) break;
        final avail = b.qty - _usedInLines(b.id!);
        if (avail <= 0) continue;
        final take = math.min(need, avail);
        _lines.add(BillLine(product: p, batches: batches, batch: b, qty: take, disc: b.discountPct));
        need -= take;
      }
      if (need > 0) {
        short.add('${p.name} (short ${p.qty(need)})');
        // Keep the line so the biller sees it; it blocks saving until fixed or removed.
        if (batches.isEmpty || need == item.qtyUnits) {
          _lines.add(BillLine(product: p, batches: batches, qty: need));
        }
      }
    }
    if (t.doctorName.isNotEmpty && (_docName.text.trim().isEmpty || _isDefaultDoctor)) {
      _docName.text = t.doctorName;
      final match = (await Repo.searchDoctors(t.doctorName, limit: 1)).where((d) => d.name.toLowerCase() == t.doctorName.toLowerCase()).firstOrNull;
      _docReg.text = match?.regNo ?? '';
      _docClinic.text = match?.clinic ?? '';
    }
    _templateCode = t.code;
    _tplCtrl.clear();
    setState(() {});
    if (!mounted) return;
    if (short.isNotEmpty) {
      showSnack(context, 'Template ${t.code} loaded. Not enough stock: ${short.join(', ')}', error: true);
    } else {
      showSnack(context, 'Template ${t.code} · ${t.name} loaded (${t.items.length} items). Edit anything before saving.');
    }
    _prodFocus.requestFocus();
  }

  Future<void> _saveAsTemplate() async {
    if (_lines.isEmpty) return;
    final code = await Repo.suggestTemplateCode();
    if (!mounted) return;
    final codeCtrl = TextEditingController(text: code);
    final nameCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Save as template'),
        content: SizedBox(
          width: 380,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: codeCtrl, decoration: const InputDecoration(labelText: 'Template number'), onSubmitted: (_) => FocusScope.of(ctx).nextFocus()),
            const SizedBox(height: 12),
            TextField(
              controller: nameCtrl,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Name (e.g. Saline kit)', helperText: 'Enter saves'),
              onSubmitted: (_) => Navigator.pop(ctx, true),
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save template')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final merged = <int, int>{};
    for (final l in _lines) {
      merged[l.product.id!] = (merged[l.product.id!] ?? 0) + l.qty;
    }
    try {
      await Repo.saveTemplate(BillTemplate(
        code: codeCtrl.text.trim().isEmpty ? code : codeCtrl.text.trim(),
        name: nameCtrl.text.trim().isEmpty ? 'Template ${codeCtrl.text.trim()}' : nameCtrl.text.trim(),
        doctorName: _docName.text.trim(),
        items: merged.entries.map((e) => BillTemplateItem(productId: e.key, qtyUnits: e.value)).toList(),
      ));
      if (mounted) showSnack(context, 'Template saved');
    } on RepoException catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    }
  }

  // ---------------------------------------------------------------- save

  Future<void> _save({required bool print}) async {
    if (_saving) return;
    if (_lines.isEmpty) {
      showSnack(context, 'Add at least one medicine', error: true);
      _prodFocus.requestFocus();
      return;
    }
    for (final l in _lines) {
      final err = _lineError(l);
      if (err != null) {
        showSnack(context, '${l.product.name}: $err', error: true);
        return;
      }
    }
    if (_rxLines.isNotEmpty && Settings.instance.flag('require_doctor_for_rx') && _docName.text.trim().isEmpty) {
      showSnack(context, 'Prescription medicines on this bill — enter the doctor\'s name.', error: true);
      _docFocus.requestFocus();
      return;
    }
    if (_payment == 'Credit') {
      if (_custName.text.trim().isEmpty) {
        showSnack(context, 'A credit bill needs the patient\'s name — pick a credit customer.', error: true);
        _custFocus.requestFocus();
        return;
      }
      final c = _customer;
      if (c != null && c.creditLimit > 0 && c.balance + _creditDue > c.creditLimit + 0.004) {
        final go = await confirm(context,
            title: 'Credit limit exceeded',
            message: '${c.name} already owes ${money(c.balance)}. With this bill the dues become ${money(c.balance + _creditDue)}, '
                'above the limit of ${money(c.creditLimit)}. Continue anyway?',
            confirmLabel: 'Continue');
        if (!go || !mounted) return;
      }
    }
    setState(() => _saving = true);
    final pct = _billDiscPct;
    final sale = Sale(
      customerName: _custName.text.trim(),
      customerPhone: _custPhone.text.trim(),
      customerAddress: _custAddr.text.trim(),
      doctorName: _docName.text.trim(),
      doctorRegNo: _docReg.text.trim(),
      doctorClinic: _docClinic.text.trim(),
      rxNotes: _rxNotes.text.trim(),
      paymentMode: _payment,
      grossTotal: _gross,
      itemDiscount: _itemDisc,
      billDiscountPct: pct,
      billDiscount: _billDisc,
      taxableTotal: _taxable,
      gstTotal: _gst,
      roundOff: _roundOff,
      grandTotal: _grand,
      paidAmount: _paidNow,
      templateCode: _templateCode,
      items: [
        for (final l in _lines)
          SaleItem(
            productId: l.product.id!,
            batchId: l.batch!.id!,
            productName: l.product.name,
            form: l.product.form,
            batchNo: l.batch!.batchNo,
            expiry: l.batch!.expiry,
            packSize: l.batch!.packSize,
            unitName: l.product.unitName,
            packName: l.product.packName,
            qtyUnits: l.qty,
            mrp: l.batch!.mrp,
            unitRate: round2(l.unitRate * 10000) / 10000,
            discountPct: l.disc,
            gstRate: _lineGst(l),
            amount: l.amount,
            hsn: l.product.hsn,
            rx: l.product.needsPrescription,
          ),
      ],
    );
    try {
      final saved = await Repo.createSale(sale);
      var message = 'Bill ${saved.billNo} saved · ${money(saved.grandTotal)}';
      if (saved.isCredit && saved.customerId != null) {
        final c = await Repo.customer(saved.customerId!);
        if (c != null) message = 'Bill ${saved.billNo} saved on credit · ${c.name} now owes ${money(c.balance)}';
      }
      final doc = BillDocument.fromSale(saved);
      final path = await BillFile.save(doc);
      await Repo.setSaleFile(saved.id!, path);
      saved.filePath = path;
      _lastSale = saved;
      _clearBill(focus: true);
      if (!mounted) return;
      showSnack(context, message,
          action: SnackBarAction(label: 'VIEW', textColor: AppColors.brandLight, onPressed: () => showBillViewer(context, saleId: saved.id)));
      if (print) {
        try {
          await PrintService.printBill(doc);
        } catch (e) {
          if (mounted) showSnack(context, 'Bill saved, but printing failed: $e', error: true);
        }
      }
    } on RepoException catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    } catch (e) {
      if (mounted) showSnack(context, 'Could not save bill: $e', error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _clearBill({bool focus = true}) {
    for (final l in _lines) {
      l.dispose();
    }
    _lines.clear();
    for (final c in [_custName, _custPhone, _custAddr, _docName, _docReg, _docClinic, _rxNotes, _billDiscCtrl, _receivedCtrl, _paidNowCtrl, _tplCtrl]) {
      c.clear();
    }
    _payment = 'Cash';
    _customer = null;
    _applyDefaultDoctor();
    _templateCode = '';
    _resetEntry();
    if (focus) _prodFocus.requestFocus();
  }

  Future<void> _newBill() async {
    if (_lines.isNotEmpty && !await confirm(context, title: 'Discard this bill?', message: 'The items on the current bill will be cleared.', confirmLabel: 'Discard', destructive: true)) {
      return;
    }
    _clearBill();
  }

  // ---------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.f9): () => _save(print: true),
        const SingleActivator(LogicalKeyboardKey.keyS, control: true): () => _save(print: false),
        const SingleActivator(LogicalKeyboardKey.keyS, meta: true): () => _save(print: false),
        const SingleActivator(LogicalKeyboardKey.keyP, control: true): () => _save(print: true),
        const SingleActivator(LogicalKeyboardKey.keyP, meta: true): () => _save(print: true),
        const SingleActivator(LogicalKeyboardKey.f3): () => _prodFocus.requestFocus(),
        const SingleActivator(LogicalKeyboardKey.f4): () => _tplFocus.requestFocus(),
        const SingleActivator(LogicalKeyboardKey.f6): () => _custFocus.requestFocus(),
        const SingleActivator(LogicalKeyboardKey.f7): () => _docFocus.requestFocus(),
        const SingleActivator(LogicalKeyboardKey.keyN, control: true): _newBill,
        const SingleActivator(LogicalKeyboardKey.keyN, meta: true): _newBill,
      },
      child: FocusTraversalGroup(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                _partiesCard(),
                const SizedBox(height: 12),
                Expanded(child: _itemsCard()),
              ]),
            ),
            const SizedBox(width: 16),
            SizedBox(width: MediaQuery.sizeOf(context).width < 1360 ? 290 : 320, child: _summaryPanel()),
          ]),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------- patient & doctor

  Widget _partiesCard() {
    Widget customerTile(BuildContext c, Customer x, bool hi) => SuggestTile(
          leading: CircleAvatar(
            radius: 14,
            backgroundColor: x.isCreditCustomer ? AppColors.warning.withValues(alpha: 0.15) : null,
            child: Icon(x.isCreditCustomer ? Icons.account_balance_wallet_outlined : Icons.person, size: 15, color: x.isCreditCustomer ? AppColors.warning : null),
          ),
          title: x.name,
          badges: [CreditBadge(x)],
          subtitle: [x.phone, x.address].where((e) => e.isNotEmpty).join(' · '),
        );
    void pickCustomer(Customer c) => _pickCustomer(c);
    void unpickIfEdited(String _) {
      if (_customer != null && _custName.text.trim() != _customer!.name) setState(() => _customer = null);
    }
    final cust = _customer;

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(children: [
          Row(children: [
            Icon(Icons.person_outline, size: 18, color: context.muted),
            const SizedBox(width: 6),
            Text('Patient & prescription', style: context.tt.titleSmall),
            const Spacer(),
            Text('F6 patient · F7 doctor', style: TextStyle(fontSize: 11.5, color: context.muted)),
          ]),
          const SizedBox(height: 12),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              flex: 3,
              child: SuggestField<Customer>(
                controller: _custName,
                focusNode: _custFocus,
                label: 'Patient name',
                textCapitalization: TextCapitalization.words,
                showOnFocus: true,
                overlayWidth: 460,
                search: (q) => Repo.searchCustomers(q),
                headerBuilder: (c, n) => _custName.text.trim().isEmpty
                    ? Padding(
                        padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
                        child: Text('Credit customers — or type any name', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: context.muted)),
                      )
                    : const SizedBox.shrink(),
                display: (c) => c.name,
                itemBuilder: customerTile,
                onSelected: (c) {
                  pickCustomer(c);
                  _docFocus.requestFocus();
                },
                onChanged: unpickIfEdited,
                onSubmitted: (_) => _phoneFocus.requestFocus(),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 2,
              child: SuggestField<Customer>(
                controller: _custPhone,
                focusNode: _phoneFocus,
                label: 'Mobile',
                keyboardType: TextInputType.phone,
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9+ ]'))],
                search: (q) => q.trim().length < 2 ? Future.value(<Customer>[]) : Repo.searchCustomers(q),
                display: (c) => c.phone,
                itemBuilder: customerTile,
                onSelected: (c) {
                  pickCustomer(c);
                  _docFocus.requestFocus();
                },
                onSubmitted: (_) => _addrFocus.requestFocus(),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 3,
              child: TextField(
                controller: _custAddr,
                focusNode: _addrFocus,
                decoration: const InputDecoration(labelText: 'Address (optional)'),
                onSubmitted: (_) => _docFocus.requestFocus(),
              ),
            ),
          ]),
          if (cust != null && cust.isCreditCustomer) ...[
            const SizedBox(height: 8),
            Row(children: [
              CreditBadge(cust, small: false),
              const SizedBox(width: 8),
              if (cust.creditLimit > 0) Pill('Limit ${money0(cust.creditLimit)}', color: context.muted),
              const Spacer(),
              if (_payment != 'Credit')
                TextButton.icon(
                  onPressed: () => setState(() => _payment = 'Credit'),
                  icon: const Icon(Icons.account_balance_wallet_outlined, size: 16),
                  label: const Text('Bill on credit'),
                ),
            ]),
          ],
          const SizedBox(height: 10),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              flex: 3,
              child: SuggestField<Doctor>(
                controller: _docName,
                focusNode: _docFocus,
                label: _rxLines.isNotEmpty ? 'Doctor name *' : 'Doctor name',
                textCapitalization: TextCapitalization.words,
                prefixIcon: const Icon(Icons.medical_services_outlined, size: 18),
                suffix: _isDefaultDoctor
                    ? const Tooltip(message: 'Default doctor — type to use a visiting doctor', child: Icon(Icons.star_rounded, color: AppColors.caution, size: 20))
                    : null,
                onChanged: (_) => setState(() {}),
                search: (q) => Repo.searchDoctors(q),
                showOnFocus: true,
                display: (d) => d.name,
                itemBuilder: (c, d, hi) => SuggestTile(
                  leading: const CircleAvatar(radius: 14, child: Icon(Icons.medical_services_outlined, size: 15)),
                  title: 'Dr. ${d.name}',
                  badges: [if (d.id == _defaultDoctor?.id) const Pill('Default', color: AppColors.caution, small: true)],
                  subtitle: [d.qualification, d.regNo.isEmpty ? '' : 'Reg ${d.regNo}', d.clinic].where((e) => e.isNotEmpty).join(' · '),
                ),
                onSelected: (d) {
                  _docReg.text = d.regNo;
                  _docClinic.text = d.clinic;
                  setState(() {});
                  _notesFocus.requestFocus();
                },
                onSubmitted: (_) => _regFocus.requestFocus(),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 2,
              child: TextField(
                controller: _docReg,
                focusNode: _regFocus,
                decoration: const InputDecoration(labelText: 'Reg. no'),
                onSubmitted: (_) => _clinicFocus.requestFocus(),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 3,
              child: TextField(
                controller: _docClinic,
                focusNode: _clinicFocus,
                decoration: const InputDecoration(labelText: 'Clinic / hospital'),
                onSubmitted: (_) => _notesFocus.requestFocus(),
              ),
            ),
          ]),
          const SizedBox(height: 10),
          TextField(
            controller: _rxNotes,
            focusNode: _notesFocus,
            decoration: const InputDecoration(labelText: 'Medical details (diagnosis, Rx ref, ward/IPD no…)', prefixIcon: Icon(Icons.notes, size: 18)),
            onSubmitted: (_) => _prodFocus.requestFocus(),
          ),
        ]),
      ),
    );
  }

  // ---------------------------------------------------------------- items

  Widget _itemsCard() {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          color: context.cs.surfaceContainerLow,
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
          child: _entryRow(),
        ),
        const Divider(),
        _linesHeader(),
        const Divider(),
        Expanded(
          child: _lines.isEmpty
              ? EmptyState(
                  icon: Icons.medication_outlined,
                  title: 'No medicines yet',
                  message: 'Type a medicine name above (F3) — pick it, confirm the batch, enter quantity and press Enter. '
                      'Or load a template (F4).',
                )
              : ListView.separated(
                  itemCount: _lines.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (_, i) => _lineRow(i),
                ),
        ),
      ]),
    );
  }

  Widget _entryRow() {
    final p = _selProduct?.product;
    final b = _selBatch;
    final packSize = b?.packSize ?? p?.packSize ?? 1;
    final showToggle = p != null && (packSize > 1 || p.hasOuter);
    final modeNames = p == null ? const <String>[] : [p.unitName, if (packSize > 1) p.packName, if (p.hasOuter) p.outerName];
    final modeValues = p == null ? const <int>[] : [0, if (packSize > 1) 1, if (p.hasOuter) 2];
    final warn = p?.warningText ?? '';
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          flex: 5,
          child: SuggestField<ProductStock>(
            controller: _prodCtrl,
            focusNode: _prodFocus,
            label: 'Medicine (F3)',
            hint: 'Type name, generic or company…',
            prefixIcon: const Icon(Icons.search, size: 20),
            overlayWidth: 620,
            overlayMaxHeight: 380,
            search: _searchProducts,
            display: (ps) => ps.product.name,
            onSelected: _onProductSelected,
            onSubmitted: (v) {
              if (_selProduct != null && _selBatches.isNotEmpty) {
                _batchFocus.requestFocus();
              } else if (v.trim().isEmpty) {
                _toCheckout();
              }
            },
            onChanged: (_) {
              if (_selProduct != null) {
                setState(() {
                  _selProduct = null;
                  _selBatch = null;
                  _selBatches = [];
                  _batchCtrl.clear();
                });
              }
            },
            emptyBuilder: (c) => Padding(
              padding: const EdgeInsets.all(14),
              child: Row(children: [
                Icon(Icons.search_off, color: context.muted),
                const SizedBox(width: 10),
                const Expanded(child: Text('No medicine found. Add it in Inventory → New medicine, or via Stock Entry.')),
              ]),
            ),
            itemBuilder: (c, ps, hi) => _productTile(ps),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          flex: 2,
          child: SuggestField<Batch>(
            controller: _batchCtrl,
            focusNode: _batchFocus,
            label: 'Batch',
            inputFormatters: upperInput,
            enabled: _selBatches.isNotEmpty,
            showOnFocus: true,
            selectAllOnFocus: true,
            overlayWidth: 420,
            search: _searchEntryBatches,
            display: (b) => b.batchNo,
            headerBuilder: (c, n) => _batchHeader(n),
            itemBuilder: (c, b, hi) => _batchTile(b, _selProduct!.product, isFirst: b == _selBatches.firstOrNull),
            onSelected: (b) {
              _setEntryBatch(b);
              _focusNextFrame(_qtyFocus);
            },
            onChanged: (v) {
              // Typing a different batch un-selects the old one until it matches stock again.
              final m = _matchBatch(_selBatches, v);
              if (m?.id != _selBatch?.id || _entryError != null) {
                setState(() {
                  _selBatch = m;
                  _entryError = null;
                });
              }
            },
            onSubmitted: (v) async {
              final m = _matchBatch(_selBatches, v);
              if (m != null) {
                _setEntryBatch(m);
                _focusNextFrame(_qtyFocus);
              } else if (_selProduct != null) {
                final msg = await _batchProblem(_selProduct!.product, v, _selBatches);
                if (mounted) setState(() => _entryError = msg);
              }
            },
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 118,
          child: TextField(
            controller: _qtyCtrl,
            focusNode: _qtyFocus,
            enabled: _selBatch != null,
            decoration: InputDecoration(
              labelText: 'Qty',
              hintText: '1',
              suffixText: p == null ? null : switch (_qtyMode) { 2 => p.outerName, 1 => p.packName, _ => p.unitName },
            ),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.a-zA-Z ]'))],
            onSubmitted: (_) => _discFocus.requestFocus(),
          ),
        ),
        if (showToggle) ...[
          const SizedBox(width: 6),
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: SegmentedButton<int>(
              showSelectedIcon: false,
              segments: [for (var i = 0; i < modeValues.length; i++) ButtonSegment(value: modeValues[i], label: Text(modeNames[i]))],
              selected: {modeValues.contains(_qtyMode) ? _qtyMode : 0},
              onSelectionChanged: (s) {
                setState(() => _qtyMode = s.first);
                _focusNextFrame(_qtyFocus);
              },
            ),
          ),
        ],
        const SizedBox(width: 10),
        SizedBox(
          width: 78,
          child: TextField(
            controller: _discCtrl,
            focusNode: _discFocus,
            enabled: _selBatch != null,
            decoration: const InputDecoration(labelText: 'Disc', suffixText: '%'),
            inputFormatters: decimalInput,
            onSubmitted: (_) => _addEntry(),
          ),
        ),
        const SizedBox(width: 10),
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: FilledButton.icon(
            onPressed: _selBatch == null ? null : _addEntry,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Add'),
          ),
        ),
      ]),
      if (p != null || _entryError != null) ...[
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
          if (_entryError != null) Pill(_entryError!, color: AppColors.danger, icon: Icons.error_outline),
          if (p != null && b != null) ...[
            Pill('Stock ${p.qty(b.qty - _usedInLines(b.id!))} in ${b.batchNo}', color: AppColors.info, icon: Icons.inventory_2_outlined),
            Pill('MRP ${money(b.mrp)} / ${p.packName}${b.packSize > 1 ? '  ·  ${money(b.unitRate)} / ${p.unitName}' : ''}', color: context.muted),
            if (expiryLevel(b.expiry) != ExpiryLevel.ok) ExpiryBadge(b.expiry, showPhrase: true),
            if (showToggle)
              Text(
                'Tip: ${[if (packSize > 1) '"2s" = 2 ${p.packName}s', if (p.hasOuter) '"1b" = 1 ${p.outerName} (${p.outerSize} ${p.packName})'].join(' · ')}',
                style: TextStyle(fontSize: 11.5, color: context.muted),
              ),
          ],
          if (warn.isNotEmpty) Pill(warn, color: AppColors.rx, icon: Icons.warning_amber_rounded),
        ]),
      ],
    ]);
  }

  Widget _productTile(ProductStock ps) {
    final p = ps.product;
    final out = ps.stockUnits <= 0;
    return SuggestTile(
      leading: CircleAvatar(
        radius: 16,
        backgroundColor: (out ? AppColors.danger : AppColors.brand).withValues(alpha: 0.1),
        child: Icon(_formIcon(p.form), size: 16, color: out ? AppColors.danger : AppColors.brand),
      ),
      title: p.name,
      badges: [RxBadge(p)],
      subtitle: [p.genericName, p.manufacturer, p.form, if (p.rack.isNotEmpty) 'Rack ${p.rack}'].where((e) => e.isNotEmpty).join(' · '),
      trailing: Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: [
        Text(out ? 'Out of stock' : p.qty(ps.stockUnits),
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5, color: out ? AppColors.danger : (ps.lowStock ? AppColors.warning : null))),
        if (ps.mrp != null) Text('MRP ${money(ps.mrp!)}', style: TextStyle(fontSize: 11.5, color: context.muted)),
      ]),
    );
  }

  Widget _batchHeader(int n) => Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
        child: Text('$n batch${n == 1 ? '' : 'es'} in stock · earliest expiry first',
            style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: context.muted)),
      );

  Widget _batchTile(Batch b, Product p, {bool isFirst = false}) {
    final free = b.qty - _usedInLines(b.id!);
    return SuggestTile(
      title: b.batchNo,
      badges: [
        ExpiryBadge(b.expiry, small: true),
        if (isFirst) Pill('FEFO', color: AppColors.success, small: true),
        if (b.discountPct > 0) Pill('${trimNum(b.discountPct)}% off', color: AppColors.violet, small: true),
      ],
      subtitle: 'MRP ${money(b.mrp)} · ${p.qty(free)} free',
    );
  }

  static IconData _formIcon(String form) {
    final f = form.toLowerCase();
    if (f.contains('inject') || f.contains('iv')) return Icons.vaccines_outlined;
    if (f.contains('syrup') || f.contains('suspension') || f.contains('drops') || f.contains('spray')) return Icons.local_drink_outlined;
    if (f.contains('cream') || f.contains('ointment') || f.contains('gel') || f.contains('lotion')) return Icons.soap_outlined;
    if (f.contains('device') || f.contains('surgical')) return Icons.healing_outlined;
    return Icons.medication_outlined;
  }

  static const _cols = <(String, double?, int, bool)>[
    // label, fixed width, flex, right-aligned
    ('#', 28, 0, false),
    ('Medicine', null, 5, false),
    ('Batch', 132, 0, false),
    ('Exp', 66, 0, false),
    ('Qty', 128, 0, false),
    ('MRP / Rate', 84, 0, true),
    ('Disc %', 64, 0, true),
    ('Amount', 84, 0, true),
    ('', 36, 0, false),
  ];

  Widget _cell(int i, Widget child) {
    final c = _cols[i];
    final w = Align(alignment: c.$4 ? Alignment.centerRight : Alignment.centerLeft, child: child);
    final padded = Padding(padding: const EdgeInsets.symmetric(horizontal: 5), child: w);
    return c.$2 != null ? SizedBox(width: c.$2, child: padded) : Expanded(flex: c.$3, child: padded);
  }

  Widget _linesHeader() {
    final style = TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: context.muted, letterSpacing: 0.4);
    return Container(
      color: context.cs.surfaceContainer,
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
      child: Row(children: [for (var i = 0; i < _cols.length; i++) _cell(i, Text(_cols[i].$1.toUpperCase(), style: style))]),
    );
  }

  Widget _lineRow(int i) {
    final l = _lines[i];
    final err = _lineError(l);
    final p = l.product;
    return Container(
      color: err != null ? AppColors.danger.withValues(alpha: 0.05) : null,
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      child: Row(children: [
        _cell(0, Text('${i + 1}', style: TextStyle(color: context.muted))),
        _cell(
          1,
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Tooltip(
              message: p.name,
              waitDuration: const Duration(milliseconds: 700),
              child: Text(p.name, style: const TextStyle(fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
            Row(children: [
              if (err == null && p.needsPrescription) ...[RxBadge(p), const SizedBox(width: 6)],
              Flexible(
                child: Text(err ?? [p.form, if (l.batch != null && l.batch!.packSize > 1) '${l.batch!.packSize} ${p.unitName}/${p.packName}'].join(' · '),
                    style: TextStyle(fontSize: 11.5, color: err != null ? AppColors.danger : context.muted), maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
            ]),
          ]),
        ),
        _cell(
          2,
          SuggestField<Batch>(
            key: ObjectKey(l),
            controller: l.batchCtrl,
            focusNode: l.batchFocus,
            dense: true,
            inputFormatters: upperInput,
            showOnFocus: true,
            selectAllOnFocus: true,
            overlayWidth: 400,
            search: (q) async {
              final t = q.trim().toLowerCase();
              return l.batches.where((b) => t.isEmpty || b.batchNo.toLowerCase().contains(t)).toList();
            },
            display: (b) => b.batchNo,
            headerBuilder: (c, n) => _batchHeader(n),
            itemBuilder: (c, b, hi) => _batchTile(b, p, isFirst: b == l.batches.firstOrNull),
            onSelected: (b) {
              setState(() {
                l.batch = b;
                if (b.discountPct > 0) {
                  l.disc = b.discountPct;
                  l.discCtrl.text = trimNum(b.discountPct);
                }
              });
              l.qtyFocus.requestFocus();
            },
            onChanged: (v) => setState(() {
              final m = _matchBatch(l.batches, v);
              if (m != null) l.batch = m;
            }),
            onSubmitted: (v) async {
              final m = _matchBatch(l.batches, v);
              if (m != null) {
                setState(() => l.batch = m);
                l.qtyFocus.requestFocus();
                return;
              }
              final msg = await _batchProblem(p, v, l.batches);
              if (mounted) showSnack(context, msg, error: true);
            },
          ),
        ),
        _cell(3, l.batch == null ? Text('—', style: TextStyle(color: context.muted)) : ExpiryBadge(l.batch!.expiry, small: true)),
        _cell(
          4,
          Row(children: [
            SizedBox(
              width: 54,
              child: TextField(
                controller: l.qtyCtrl,
                focusNode: l.qtyFocus,
                textAlign: TextAlign.right,
                decoration: const InputDecoration(contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 9)),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.a-zA-Z ]'))],
                onChanged: (v) {
                  final q = parseQty(v, l.batch?.packSize ?? p.packSize, outerSize: p.hasOuter ? p.outerSize : 0);
                  setState(() => l.qty = q ?? 0);
                },
                onSubmitted: (v) {
                  final q = parseQty(v, l.batch?.packSize ?? p.packSize, outerSize: p.hasOuter ? p.outerSize : 0);
                  if (q != null) l.qtyCtrl.text = '$q';
                  l.discFocus.requestFocus();
                },
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                (l.batch?.packSize ?? p.packSize) > 1 && l.qty >= (l.batch?.packSize ?? p.packSize) ? p.qty(l.qty) : p.unitName,
                style: TextStyle(fontSize: 11.5, color: context.muted),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ]),
        ),
        _cell(
          5,
          l.batch == null
              ? Text('—', style: TextStyle(color: context.muted))
              : Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text(amount(l.batch!.mrp)),
                  if (l.batch!.packSize > 1) Text('${amount(l.unitRate)}/${p.unitName}', style: TextStyle(fontSize: 11, color: context.muted)),
                ]),
        ),
        _cell(
          6,
          SizedBox(
            width: 56,
            child: TextField(
              controller: l.discCtrl,
              focusNode: l.discFocus,
              textAlign: TextAlign.right,
              onSubmitted: (_) => _prodFocus.requestFocus(),
              decoration: const InputDecoration(contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 9), hintText: '0'),
              inputFormatters: decimalInput,
              onChanged: (v) => setState(() => l.disc = parseNum(v).clamp(0, 100).toDouble()),
            ),
          ),
        ),
        _cell(7, Text(amount(l.amount), style: const TextStyle(fontWeight: FontWeight.w700))),
        _cell(
          8,
          IconButton(
            tooltip: 'Remove',
            icon: const Icon(Icons.close, size: 18),
            color: context.muted,
            onPressed: () {
              setState(() => _lines.removeAt(i));
              WidgetsBinding.instance.addPostFrameCallback((_) => l.dispose());
            },
          ),
        ),
      ]),
    );
  }

  // ---------------------------------------------------------------- summary

  Widget _summaryPanel() {
    final now = DateTime.now();
    final received = parseNum(_receivedCtrl.text);
    final change = received - _grand;
    final rx = _rxLines;
    Widget row(String k, String v, {Color? color, bool strong = false}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(children: [
            Text(k, style: TextStyle(color: strong ? null : context.muted, fontWeight: strong ? FontWeight.w700 : null)),
            const Spacer(),
            Text(v, style: TextStyle(fontWeight: strong ? FontWeight.w800 : FontWeight.w600, color: color, fontSize: strong ? 15 : null)),
          ]),
        );

    return ListView(children: [
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('BILL NO', style: TextStyle(fontSize: 11, color: context.muted, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
                Text(Repo.peekNextBillNo(), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              ]),
              const Spacer(),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text(fmtDate(now), style: const TextStyle(fontWeight: FontWeight.w600)),
                Text(fmtTime(now), style: TextStyle(color: context.muted, fontSize: 12)),
              ]),
            ]),
            const SizedBox(height: 14),
            Row(children: [
              Expanded(
                child: SuggestField<BillTemplate>(
                  controller: _tplCtrl,
                  focusNode: _tplFocus,
                  label: 'Template no. (F4)',
                  prefixIcon: const Icon(Icons.bookmarks_outlined, size: 18),
                  showOnFocus: true,
                  overlayWidth: 320,
                  search: _searchTemplates,
                  display: (t) => t.code,
                  itemBuilder: (c, t, hi) => SuggestTile(
                    leading: CircleAvatar(radius: 14, child: Text(t.code, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700))),
                    title: t.name,
                    subtitle: '${t.itemCount} items${t.doctorName.isEmpty ? '' : ' · Dr. ${t.doctorName}'}',
                  ),
                  onSelected: _applyTemplate,
                  onSubmitted: _loadTemplateCode,
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                tooltip: 'Load template',
                onPressed: () => _loadTemplateCode(_tplCtrl.text),
                icon: const Icon(Icons.download_outlined, size: 20),
              ),
            ]),
            if (_templateCode.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text('From template #$_templateCode — edits apply to this bill only', style: TextStyle(fontSize: 11.5, color: context.muted)),
            ],
          ]),
        ),
      ),
      if (rx.isNotEmpty) ...[
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.rx.withValues(alpha: context.isDark ? 0.15 : 0.06),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.rx.withValues(alpha: 0.35)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Icon(Icons.warning_amber_rounded, color: AppColors.rx, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text('Prescription required', style: context.tt.titleSmall?.copyWith(color: AppColors.rx)),
              ),
              if (_docName.text.trim().isNotEmpty) const Pill('Doctor ✓', color: AppColors.success, small: true),
            ]),
            const SizedBox(height: 4),
            Text(
              _docName.text.trim().isEmpty ? 'Enter the doctor\'s name before saving.' : 'Dispense only against the doctor\'s prescription.',
              style: const TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 8),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final l in rx.take(8))
                Tooltip(
                  message: l.product.warningText,
                  child: Pill(
                    '${l.product.name}${l.product.isAntibiotic ? ' · antibiotic' : l.product.schedule.isNotEmpty ? ' · Sch ${l.product.schedule}' : ''}',
                    color: AppColors.rx,
                    small: true,
                  ),
                ),
            ]),
            for (final l in rx.where((l) => l.product.instructions.trim().isNotEmpty).take(3))
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('${l.product.name}: ${l.product.instructions}', style: const TextStyle(fontSize: 12)),
              ),
            if (rx.length > 8) Padding(padding: const EdgeInsets.only(top: 4), child: Text('+ ${rx.length - 8} more', style: const TextStyle(fontSize: 12))),
          ]),
        ),
      ],
      const SizedBox(height: 12),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            row('Items', '${_lines.length}'),
            if (_itemDisc > 0) ...[
              row('MRP value', money(_gross)),
              row('Item discount', '- ${money(_itemDisc)}', color: AppColors.success),
            ],
            const SizedBox(height: 6),
            Row(children: [
              Text('Extra discount', style: TextStyle(color: context.muted)),
              const Spacer(),
              SizedBox(
                width: 84,
                child: TextField(
                  controller: _billDiscCtrl,
                  focusNode: _billDiscFocus,
                  textAlign: TextAlign.right,
                  onSubmitted: (_) => _afterBillDiscount(),
                  inputFormatters: decimalInput,
                  decoration: const InputDecoration(suffixText: '%', hintText: '0', contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 9)),
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ]),
            if (_billDisc > 0) row('', '- ${money(_billDisc)}', color: AppColors.success),
            if (_gstOn) ...[
              row('Taxable amount', money(_taxable)),
              row('GST (included)', money(_gst)),
            ],
            if (_roundOff != 0) row('Round off', '${_roundOff > 0 ? '+' : '−'} ${amount(_roundOff.abs())}'),
            const Padding(padding: EdgeInsets.symmetric(vertical: 10), child: Divider()),
            Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(_gstOn ? 'Net payable' : 'Total amount', style: context.tt.titleMedium),
              const Spacer(),
              Text(money(_grand), style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: context.cs.primary, letterSpacing: -0.5)),
            ]),
            const SizedBox(height: 14),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final m in ['Cash', 'UPI', 'Card', 'Credit'])
                ChoiceChip(
                  label: Text(m),
                  selected: _payment == m,
                  showCheckmark: false,
                  onSelected: (_) => setState(() => _payment = m),
                ),
            ]),
            if (_payment == 'Credit') ...[
              const SizedBox(height: 10),
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: _paidNowCtrl,
                    focusNode: _payFocus,
                    onSubmitted: (_) => _save(print: true),
                    inputFormatters: decimalInput,
                    decoration: const InputDecoration(labelText: 'Paid now (optional)', prefixText: '₹ ', hintText: '0'),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 110,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Text('On credit', style: TextStyle(fontSize: 11.5, color: context.muted)),
                    Text(money(_creditDue), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: AppColors.warning)),
                  ]),
                ),
              ]),
              const SizedBox(height: 6),
              Text(
                _customer == null
                    ? (_custName.text.trim().isEmpty ? 'Pick the patient — credit bills need a name.' : '${_custName.text.trim()} will be saved as a credit customer.')
                    : 'Dues after this bill: ${money(_customer!.balance + _creditDue)}',
                style: TextStyle(fontSize: 12, color: context.muted),
              ),
            ],
            if (_payment == 'Cash') ...[
              const SizedBox(height: 10),
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: _receivedCtrl,
                    focusNode: _payFocus,
                    inputFormatters: decimalInput,
                    decoration: const InputDecoration(labelText: 'Cash received', prefixText: '₹ '),
                    onChanged: (_) => setState(() {}),
                    onSubmitted: (_) => _save(print: true),
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 110,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Text('Return', style: TextStyle(fontSize: 11.5, color: context.muted)),
                    Text(received > 0 ? money(change) : '—',
                        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: change < 0 ? AppColors.danger : AppColors.success)),
                  ]),
                ),
              ]),
            ],
            const SizedBox(height: 16),
            FilledButton.icon(
              focusNode: _saveFocus,
              onPressed: _saving ? null : () => _save(print: true),
              icon: _saving
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.print_outlined),
              label: const Text('Save & Print  (F9)'),
              style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 18)),
            ),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _saving ? null : () => _save(print: false),
                  icon: const Icon(Icons.save_outlined, size: 18),
                  label: const Text('Save only'),
                ),
              ),
              const SizedBox(width: 8),
              PopupMenuButton<String>(
                tooltip: 'More',
                onSelected: (v) {
                  if (v == 'new') _newBill();
                  if (v == 'tpl') _saveAsTemplate();
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'new', child: ListTile(dense: true, leading: Icon(Icons.restart_alt), title: Text('New bill  (Ctrl+N)'))),
                  PopupMenuItem(
                      value: 'tpl',
                      enabled: _lines.isNotEmpty,
                      child: const ListTile(dense: true, leading: Icon(Icons.bookmark_add_outlined), title: Text('Save items as template'))),
                ],
                child: Container(
                  height: 50,
                  width: 50,
                  decoration: BoxDecoration(border: Border.all(color: context.border), borderRadius: BorderRadius.circular(10)),
                  child: const Icon(Icons.more_horiz),
                ),
              ),
            ]),
            const SizedBox(height: 10),
            Text('Ctrl+S save · Ctrl+P / F9 save & print · Ctrl+N new', textAlign: TextAlign.center, style: TextStyle(fontSize: 11, color: context.muted)),
          ]),
        ),
      ),
      if (_lastSale != null) ...[
        const SizedBox(height: 12),
        Card(
          child: ListTile(
            leading: const CircleAvatar(child: Icon(Icons.receipt_long_outlined, size: 20)),
            title: Text('Last bill ${_lastSale!.billNo}', style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text('${money(_lastSale!.grandTotal)} · ${_lastSale!.customerName.isEmpty ? 'Walk-in' : _lastSale!.customerName}'),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              IconButton(
                tooltip: 'Reprint',
                icon: const Icon(Icons.print_outlined, size: 20),
                onPressed: () async {
                  final path = _lastSale!.filePath;
                  final doc = path.isNotEmpty ? await BillFile.read(path) : BillDocument.fromSale(_lastSale!);
                  await PrintService.printBill(doc);
                },
              ),
              IconButton(
                tooltip: 'View',
                icon: const Icon(Icons.open_in_new, size: 20),
                onPressed: () => showBillViewer(context, saleId: _lastSale!.id),
              ),
            ]),
          ),
        ),
      ],
    ]);
  }
}
