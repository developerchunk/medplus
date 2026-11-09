import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/format.dart';
import '../../core/settings.dart';
import '../../data/repo.dart';
import '../../models/models.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/suggest_field.dart';

/// Create / edit a medicine in the master list. Returns the saved product.
Future<Product?> showProductForm(BuildContext context, {Product? product, String initialName = ''}) =>
    showDialog<Product>(context: context, builder: (_) => _ProductForm(product: product, initialName: initialName));

class _ProductForm extends StatefulWidget {
  const _ProductForm({this.product, this.initialName = ''});
  final Product? product;
  final String initialName;
  @override
  State<_ProductForm> createState() => _ProductFormState();
}

class _ProductFormState extends State<_ProductForm> with EnterFlow {
  late final Product p = widget.product == null
      ? Product(name: widget.initialName)
      : Product.fromMap(widget.product!.toMap());
  late final _name = TextEditingController(text: p.name);
  late final _generic = TextEditingController(text: p.genericName);
  late final _mfr = TextEditingController(text: p.manufacturer);
  late final _unit = TextEditingController(text: p.unitName);
  late final _pack = TextEditingController(text: p.packName);
  late final _packSize = TextEditingController(text: '${p.packSize}');
  late bool _hasOuter = p.hasOuter;
  late final _outer = TextEditingController(text: p.hasOuter ? p.outerName : 'Box');
  late final _outerSize = TextEditingController(text: p.outerSize > 1 ? '${p.outerSize}' : '');
  late final _hsn = TextEditingController(text: p.hsn);
  late final _instructions = TextEditingController(text: p.instructions);
  late final _rack = TextEditingController(text: p.rack);
  late final _reorder = TextEditingController(text: p.reorderLevel > 0 ? packsDecimal(p.reorderLevel, p.packSize) : '');
  String? _nameError;
  bool _saving = false;

  void _applyForm(String form) {
    final f = ProductForm.of(form);
    setState(() {
      p.form = f.name;
      _unit.text = f.unit;
      _pack.text = f.pack;
      _packSize.text = '${f.packSize}';
    });
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      setState(() => _nameError = 'Required');
      return;
    }
    setState(() => _saving = true);
    p
      ..name = _name.text.trim()
      ..genericName = _generic.text.trim()
      ..manufacturer = _mfr.text.trim()
      ..unitName = _unit.text.trim().isEmpty ? 'Unit' : _unit.text.trim()
      ..packName = _pack.text.trim().isEmpty ? _unit.text.trim() : _pack.text.trim()
      ..packSize = (int.tryParse(_packSize.text) ?? 1).clamp(1, 10000)
      ..outerSize = _hasOuter ? (int.tryParse(_outerSize.text) ?? 0).clamp(0, 10000) : 0
      ..outerName = _hasOuter ? _outer.text.trim() : ''
      ..hsn = _hsn.text.trim()
      ..instructions = _instructions.text.trim()
      ..rack = _rack.text.trim();
    if (p.outerSize <= 1 || p.outerName.isEmpty) {
      p
        ..outerSize = 0
        ..outerName = '';
    }
    p.reorderLevel = (parseNum(_reorder.text) * p.packSize).round();
    await Repo.saveProduct(p);
    if (mounted) Navigator.pop(context, p);
  }

  String get _unitLabel => _unit.text.trim().isEmpty ? 'Unit' : _unit.text.trim();
  String get _packLabel => _pack.text.trim().isEmpty ? 'Pack' : _pack.text.trim();

  /// e.g. "1 Box = 10 Strip = 100 Tab"
  String get _packingSummary {
    final ps = int.tryParse(_packSize.text) ?? 1;
    final os = _hasOuter ? int.tryParse(_outerSize.text) ?? 0 : 0;
    final outer = _outer.text.trim();
    final parts = <String>[
      if (outer.isNotEmpty && os > 1) '1 $outer = $os $_packLabel',
      if (!(outer.isNotEmpty && os > 1)) '1 $_packLabel',
      if (ps > 1) '${outer.isNotEmpty && os > 1 ? os * ps : ps} $_unitLabel',
    ];
    return parts.join(' = ');
  }

  bool get _gstOn => Settings.instance.gstEnabled;

  @override
  List<String> get flowOrder => [
        'name', 'generic', 'mfr', 'unit', 'pack', 'packSize',
        if (_hasOuter) ...['outer', 'outerSize'],
        if (_gstOn) ...['hsn', 'gst'],
        'instructions', 'rack', 'reorder',
      ];

  @override
  void onFlowDone() => _save();

  /// Plain text field that takes part in the Enter flow.
  Widget _tf(String key, TextEditingController c, InputDecoration d,
          {List<TextInputFormatter>? formatters, bool autofocus = false, TextCapitalization caps = TextCapitalization.none, bool rebuild = false}) =>
      TextField(
        controller: c,
        focusNode: fn(key),
        autofocus: autofocus,
        textCapitalization: caps,
        inputFormatters: formatters,
        decoration: d,
        onChanged: rebuild ? (_) => setState(() {}) : null,
        onSubmitted: (_) => advance(key),
      );

  Widget _distinct(String key, String column, TextEditingController c, String label) => SuggestField<String>(
        controller: c,
        focusNode: fn(key),
        onSubmitted: (_) => advance(key),
        label: label,
        textCapitalization: TextCapitalization.words,
        search: (q) => q.trim().isEmpty ? Future.value(<String>[]) : Repo.distinctValues(column, q),
        display: (s) => s,
        itemBuilder: (ctx, s, hi) => Padding(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9), child: Text(s)),
      );

  @override
  Widget build(BuildContext context) {
    final rxAuto = DrugSchedule.rxByDefault(p.schedule);
    return FormDialog(
      title: widget.product == null ? 'New medicine' : 'Edit medicine',
      subtitle: 'Master details. Batches, MRP and expiry are added through Stock Entry.',
      icon: Icons.medication_outlined,
      width: 680,
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: _saving ? null : _save, child: const Text('Save medicine')),
      ],
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        FieldRow(flex: const [3, 2], children: [
          _tf('name', _name, InputDecoration(labelText: 'Medicine name *', hintText: 'e.g. Azithral 500', errorText: _nameError),
              autofocus: true, caps: TextCapitalization.words),
          DropdownButtonFormField<String>(
            initialValue: ProductForm.all.any((f) => f.name == p.form) ? p.form : 'Other',
            decoration: const InputDecoration(labelText: 'Form'),
            items: [for (final f in ProductForm.all) DropdownMenuItem(value: f.name, child: Text(f.name))],
            onChanged: (v) => _applyForm(v!),
          ),
        ]),
        FieldRow(children: [
          _distinct('generic', 'generic_name', _generic, 'Generic / composition'),
          _distinct('mfr', 'manufacturer', _mfr, 'Manufacturer / company'),
        ]),
        const SectionLabel('Packing'),
        FieldRow(children: [
          _tf('unit', _unit, const InputDecoration(labelText: 'Loose unit', hintText: 'Tab, Cap, Vial…'), rebuild: true),
          _tf('pack', _pack, const InputDecoration(labelText: 'Pack', hintText: 'Strip, Bottle…'), rebuild: true),
          _tf('packSize', _packSize, InputDecoration(labelText: '${_unitLabel}s per $_packLabel', hintText: '10'), formatters: intInput, rebuild: true),
        ]),
        Container(
          margin: const EdgeInsets.only(bottom: 14),
          decoration: BoxDecoration(border: Border.all(color: context.border), borderRadius: BorderRadius.circular(10)),
          child: SwitchListTile(
            value: _hasOuter,
            onChanged: (v) => setState(() => _hasOuter = v),
            title: const Text('Also comes in boxes (optional)'),
            subtitle: Text(_hasOuter
                ? _packingSummary
                : 'Only for the few medicines you buy or sell by the box. Stock is always counted in ${_packLabel}s and ${_unitLabel}s.'),
          ),
        ),
        if (_hasOuter) FieldRow(children: [
          _tf('outer', _outer, const InputDecoration(labelText: 'Outer pack name', hintText: 'Box, Carton…'), rebuild: true),
          _tf(
            'outerSize',
            _outerSize,
            InputDecoration(labelText: '${_packLabel}s per ${_outer.text.trim().isEmpty ? 'outer pack' : _outer.text.trim()}', hintText: 'e.g. 10'),
            formatters: intInput,
            rebuild: true,
          ),
        ]),
        SectionLabel(_gstOn ? 'Tax & regulation' : 'Regulation'),
        FieldRow(children: [
          if (_gstOn) ...[
            _tf('hsn', _hsn, const InputDecoration(labelText: 'HSN code')),
            GstField(label: 'GST rate', value: p.gstRate, focusNode: fn('gst'), onChanged: (v) => p.gstRate = v, onSubmitted: () => advance('gst')),
          ],
          DropdownButtonFormField<String>(
            initialValue: DrugSchedule.values.contains(p.schedule) ? p.schedule : '',
            decoration: const InputDecoration(labelText: 'Drug schedule'),
            items: [for (final s in DrugSchedule.values) DropdownMenuItem(value: s, child: Text(DrugSchedule.label(s)))],
            onChanged: (v) => setState(() => p.schedule = v!),
          ),
        ]),
        Container(
          decoration: BoxDecoration(border: Border.all(color: context.border), borderRadius: BorderRadius.circular(10)),
          child: Column(children: [
            SwitchListTile(
              value: p.isAntibiotic,
              onChanged: (v) => setState(() => p.isAntibiotic = v),
              title: const Text('Antibiotic'),
              subtitle: const Text('Shows "This is an antibiotic. A doctor\'s prescription is required." while billing'),
            ),
            const Divider(),
            SwitchListTile(
              value: p.rxRequired || rxAuto,
              onChanged: rxAuto ? null : (v) => setState(() => p.rxRequired = v),
              title: const Text('Prescription required'),
              subtitle: Text(rxAuto ? 'Always on for Schedule ${p.schedule}' : 'Doctor\'s name will be required on the bill'),
            ),
          ]),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _instructions,
          focusNode: fn('instructions'),
          maxLines: 2,
          minLines: 1,
          keyboardType: TextInputType.text,
          onSubmitted: (_) => advance('instructions'),
          decoration: InputDecoration(
            labelText: 'Instructions / warning shown at billing',
            hintText: p.needsPrescription ? p.warningText : 'e.g. Store below 25°C. Take after food.',
          ),
        ),
        const SizedBox(height: 14),
        FieldRow(children: [
          _distinct('rack', 'rack', _rack, 'Rack / shelf'),
          _tf('reorder', _reorder, InputDecoration(labelText: 'Reorder when stock falls to', suffixText: _pack.text.isEmpty ? 'packs' : _pack.text),
              formatters: decimalInput),
        ]),
      ]),
    );
  }
}
