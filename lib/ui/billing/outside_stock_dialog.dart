import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/format.dart';
import '../../data/repo.dart';
import '../../models/models.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/date_input.dart';
import '../widgets/suggest_field.dart';

/// What the biller entered for a medicine brought from another shop.
class OutsideStockResult {
  OutsideStockResult({required this.product, required this.batch, required this.billUnits});
  final Product product;
  final Batch batch; // the new batch, holding everything brought (minus nothing — the bill takes billUnits from it)
  final int billUnits; // how much of it goes on this bill
}

/// Medicine brought from another medical shop while making a bill — either a
/// medicine that isn't in the list at all ([product] == null, [name] pre-filled)
/// or one that is out of / short on stock. Records the purchase (saved supplier
/// or a one-off source) and returns the new batch to bill from. Whatever isn't
/// put on this bill stays in stock when "Keep the rest in stock" is ticked.
Future<OutsideStockResult?> showOutsideStockDialog(BuildContext context, {Product? product, String name = '', int needUnits = 0, String reason = ''}) =>
    showDialog<OutsideStockResult>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _OutsideStockDialog(product: product, name: name, needUnits: needUnits, reason: reason),
    );

class _OutsideStockDialog extends StatefulWidget {
  const _OutsideStockDialog({this.product, required this.name, required this.needUnits, required this.reason});
  final Product? product;
  final String name;
  final int needUnits;
  final String reason;
  @override
  State<_OutsideStockDialog> createState() => _OutsideStockDialogState();
}

class _OutsideStockDialogState extends State<_OutsideStockDialog> with EnterFlow {
  bool get _isNew => widget.product == null;

  // new medicine
  late final _name = TextEditingController(text: widget.name.trim());
  final _maker = TextEditingController();
  String _form = 'Tablet';
  late final _perPack = TextEditingController(text: '${ProductForm.of(_form).packSize}');
  bool _rx = false;
  bool _saveInList = true;

  // purchase
  Supplier? _supplier;
  final _source = TextEditingController();
  final _batch = TextEditingController();
  final _exp = TextEditingController();
  final _mrp = TextEditingController();
  final _rate = TextEditingController();
  final _brought = TextEditingController();
  final _forBill = TextEditingController();
  int _mode = 0; // 0 = units (tablets…), 1 = packs (strips…)
  bool _keepRest = true;
  bool _paid = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final need = widget.needUnits;
    final pack = _packSize;
    if (need > 0) {
      if (pack > 1 && need % pack == 0) {
        _mode = 1;
        _brought.text = '${need ~/ pack}';
        _forBill.text = '${need ~/ pack}';
      } else {
        _brought.text = '$need';
        _forBill.text = '$need';
      }
    } else if (pack > 1) {
      _mode = 1;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => fn(_isNew ? (_name.text.isEmpty ? 'name' : 'maker') : 'source').requestFocus());
  }

  @override
  void dispose() {
    for (final c in [_name, _maker, _perPack, _source, _batch, _exp, _mrp, _rate, _brought, _forBill]) {
      c.dispose();
    }
    super.dispose();
  }

  // ------------------------------------------------------------ derived

  ProductForm get _pf => ProductForm.of(_form);
  int get _packSize => _isNew ? (int.tryParse(_perPack.text.trim()) ?? 1).clamp(1, 10000) : widget.product!.packSize.clamp(1, 10000);
  String get _unitName => _isNew ? _pf.unit : widget.product!.unitName;
  String get _packName => _isNew ? _pf.pack : widget.product!.packName;
  bool get _hasPacks => _packSize > 1 && _unitName != _packName;

  int? _units(TextEditingController c) => parseQty(c.text, _packSize, mode: _hasPacks ? _mode : 0);
  int get _broughtUnits => _units(_brought) ?? 0;
  int get _billUnits => _forBill.text.trim().isEmpty ? _broughtUnits : (_units(_forBill) ?? 0);
  int get _leftover => _broughtUnits - _billUnits;
  String _qty(int units) => fmtQty(units, _packSize, _unitName, _packName);

  @override
  List<String> get flowOrder => [
        if (_isNew) ...['name', 'maker', 'perpack'],
        'source',
        'batch',
        'exp',
        'mrp',
        'rate',
        'brought',
        'forbill',
      ];

  @override
  void onFlowDone() => _save();

  // ------------------------------------------------------------ save

  Future<void> _save() async {
    if (_saving) return;
    String? err;
    final exp = parseMonthYear(_exp.text);
    final mrp = parseNum(_mrp.text);
    if (_isNew && _name.text.trim().isEmpty) {
      err = 'Enter the medicine name';
    } else if (_source.text.trim().isEmpty) {
      err = 'Where was it brought from? Pick a supplier or type the shop\'s name';
    } else if (exp == null) {
      err = 'Enter the expiry as MM/YY';
    } else if (exp.isBefore(today())) {
      err = 'This batch is already expired';
    } else if (mrp <= 0) {
      err = 'Enter the MRP per $_packName';
    } else if (_units(_brought) == null) {
      err = 'Enter how much was brought';
    } else if (_billUnits <= 0) {
      err = 'Enter how much goes on this bill';
    } else if (_leftover < 0) {
      err = 'More is going on the bill than was brought';
    }
    if (err != null) {
      setState(() => _error = err);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final keepRest = _keepRest || _leftover <= 0;
    final product = widget.product ??
        Product(
          name: _name.text.trim(),
          manufacturer: _maker.text.trim(),
          form: _form,
          unitName: _pf.unit,
          packName: _pf.pack,
          packSize: _packSize,
          rxRequired: _rx,
          gstRate: 5,
          // Kept off the medicine list only when nothing of it is left on the shelf.
          active: _saveInList || (keepRest && _leftover > 0),
        );
    try {
      final batch = await Repo.addOutsideStock(
        product: product,
        supplier: _supplier != null && _supplier!.id != null && _supplier!.name == _source.text.trim() ? _supplier : null,
        sourceName: _source.text.trim(),
        batchNo: _batch.text,
        expiry: exp!,
        mrp: mrp,
        purchaseRate: parseNum(_rate.text),
        units: keepRest ? _broughtUnits : _billUnits,
        paid: _paid,
        note: 'Brought for a bill${keepRest && _leftover > 0 ? ' · ${_qty(_leftover)} kept in stock' : ''}',
      );
      if (mounted) Navigator.pop(context, OutsideStockResult(product: product, batch: batch, billUnits: _billUnits));
    } on RepoException catch (e) {
      setState(() {
        _saving = false;
        _error = e.message;
      });
    } catch (e) {
      setState(() {
        _saving = false;
        _error = 'Could not save: $e';
      });
    }
  }

  // ------------------------------------------------------------ build

  @override
  Widget build(BuildContext context) {
    final p = widget.product;
    final leftover = _leftover;
    return CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.escape): () => Navigator.pop(context)},
      child: FormDialog(
        icon: Icons.local_shipping_outlined,
        title: _isNew ? 'Medicine brought from outside' : 'Add brought stock',
        subtitle: widget.reason.isNotEmpty ? widget.reason : 'Bought from another medical shop for this bill',
        width: 620,
        actions: [
          TextButton(onPressed: _saving ? null : () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.add_shopping_cart, size: 18),
            label: const Text('Add to bill'),
          ),
        ],
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_isNew) ...[
              const SectionLabel('Medicine'),
              FieldRow(
                flex: const [3, 2],
                children: [
                  flowField('name', _name, label: 'Medicine name *', caps: TextCapitalization.words),
                  flowField('maker', _maker, label: 'Company (optional)', caps: TextCapitalization.words),
                ],
              ),
              FieldRow(
                flex: const [3, 2],
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: _form,
                    decoration: const InputDecoration(labelText: 'Form'),
                    items: [for (final f in ProductForm.all) DropdownMenuItem(value: f.name, child: Text(f.name))],
                    onChanged: (v) => setState(() {
                      _form = v ?? 'Tablet';
                      _perPack.text = '${_pf.packSize}';
                      _mode = _pf.packSize > 1 ? _mode : 0;
                    }),
                  ),
                  flowField('perpack', _perPack, label: '${_pf.unit}s per ${_pf.pack}', formatters: intInput, onChanged: (_) => setState(() {})),
                ],
              ),
              Wrap(
                spacing: 18,
                children: [
                  _check('Needs prescription (Rx)', _rx, (v) => setState(() => _rx = v)),
                  _check('Save in the medicine list', _saveInList, (v) => setState(() => _saveInList = v)),
                ],
              ),
              const SizedBox(height: 8),
            ] else ...[
              Container(
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(color: context.cs.surfaceContainerLow, borderRadius: BorderRadius.circular(10)),
                child: Row(
                  children: [
                    const Icon(Icons.medication_outlined, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(p!.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                    ),
                    Text(p.packingLabel, style: TextStyle(color: context.muted, fontSize: 12.5)),
                  ],
                ),
              ),
            ],
            const SectionLabel('Brought from'),
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: SuggestField<Supplier>(
                controller: _source,
                focusNode: fn('source'),
                label: 'Supplier or shop name *',
                helperText: 'Pick a saved supplier, or type any shop name for a one-off purchase',
                textCapitalization: TextCapitalization.words,
                showOnFocus: true,
                prefixIcon: const Icon(Icons.storefront_outlined, size: 18),
                search: Repo.purchaseSources,
                display: (s) => s.name,
                itemBuilder: (c, s, hi) => SuggestTile(
                  leading: CircleAvatar(radius: 14, child: Icon(s.id == null ? Icons.history : Icons.storefront_outlined, size: 15)),
                  title: s.name,
                  subtitle: s.id == null ? 'Used before (one-off)' : [s.phone, s.address].where((e) => e.isNotEmpty).join(' · '),
                ),
                onSelected: (s) {
                  setState(() => _supplier = s);
                  fn('batch').requestFocus();
                },
                onChanged: (_) {
                  if (_supplier != null) setState(() => _supplier = null);
                },
                onSubmitted: (_) => fn('batch').requestFocus(),
              ),
            ),
            FieldRow(
              flex: const [3, 2, 2, 2],
              children: [
                flowField('batch', _batch, label: 'Batch no', hint: 'optional', formatters: upperInput),
                flowField('exp', _exp, label: 'Expiry *', hint: 'MM/YY', formatters: monthYearInput),
                flowField('mrp', _mrp, label: 'MRP / $_packName *', prefix: '₹ ', formatters: decimalInput),
                flowField('rate', _rate, label: 'Paid / $_packName', prefix: '₹ ', formatters: decimalInput),
              ],
            ),
            const SectionLabel('Quantity'),
            if (_hasPacks)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  children: [
                    Text('Count in', style: TextStyle(color: context.muted)),
                    const SizedBox(width: 10),
                    SegmentedButton<int>(
                      showSelectedIcon: false,
                      segments: [
                        ButtonSegment(value: 0, label: Text(_unitName)),
                        ButtonSegment(value: 1, label: Text(_packName)),
                      ],
                      selected: {_mode},
                      onSelectionChanged: (s) => setState(() => _mode = s.first),
                    ),
                  ],
                ),
              ),
            FieldRow(
              children: [
                flowField('brought', _brought, label: 'Brought *', suffix: _hasPacks && _mode == 1 ? _packName : _unitName, onChanged: (_) => setState(() {})),
                flowField(
                  'forbill',
                  _forBill,
                  label: 'For this bill',
                  hint: 'all',
                  suffix: _hasPacks && _mode == 1 ? _packName : _unitName,
                  onChanged: (_) => setState(() {}),
                ),
              ],
            ),
            if (_broughtUnits > 0 && leftover > 0)
              Container(
                padding: const EdgeInsets.fromLTRB(12, 4, 8, 4),
                decoration: BoxDecoration(
                  color: AppColors.info.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.info.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.inventory_2_outlined, size: 18, color: AppColors.info),
                    const SizedBox(width: 10),
                    Expanded(child: Text('${_qty(leftover)} left over after this bill')),
                    _check('Keep the rest in stock', _keepRest, (v) => setState(() => _keepRest = v)),
                  ],
                ),
              ),
            const SizedBox(height: 6),
            _check('Paid to them', _paid, (v) => setState(() => _paid = v)),
            if (_error != null) ...[const SizedBox(height: 8), Pill(_error!, color: AppColors.danger, icon: Icons.error_outline)],
          ],
        ),
      ),
    );
  }

  Widget _check(String label, bool value, ValueChanged<bool> onChanged) => InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => onChanged(!value),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Checkbox(value: value, onChanged: (v) => onChanged(v ?? false)),
            Text(label),
            const SizedBox(width: 6),
          ],
        ),
      );
}
