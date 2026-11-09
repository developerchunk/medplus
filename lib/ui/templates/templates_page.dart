import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/format.dart';
import '../../data/repo.dart';
import '../../models/models.dart';
import '../nav.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/suggest_field.dart';

class TemplatesPage extends StatefulWidget {
  const TemplatesPage({super.key});
  @override
  State<TemplatesPage> createState() => _TemplatesPageState();
}

class _TemplatesPageState extends State<TemplatesPage> with DataReload {
  List<BillTemplate> _items = [];
  String _query = '';

  @override
  void reload() async {
    final r = await Repo.templates(_query);
    if (mounted) setState(() => _items = r);
  }

  Future<void> _edit([BillTemplate? t]) async {
    final full = t == null ? null : await Repo.template(id: t.id);
    if (!mounted) return;
    await showDialog(context: context, builder: (_) => _TemplateEditor(template: full));
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      PageHeader(
        title: 'Bill templates',
        subtitle: 'Frequently repeated sets of medicines (e.g. saline kit). Type the template number on the billing screen to load it.',
        actions: [FilledButton.icon(onPressed: _edit, icon: const Icon(Icons.add, size: 18), label: const Text('New template'))],
        bottom: Align(
          alignment: Alignment.centerLeft,
          child: SearchBox(
            hint: 'Template number or name…',
            onChanged: (v) {
              _query = v;
              reload();
            },
          ),
        ),
      ),
      Expanded(
        child: _items.isEmpty
            ? EmptyState(
                icon: Icons.bookmarks_outlined,
                title: 'No templates yet',
                message: 'Create a template once — like the 8 injections most saline patients need — and bill it in seconds with its number. '
                    'Batches are picked from current stock each time and stay editable on the bill.',
                action: FilledButton.icon(onPressed: _edit, icon: const Icon(Icons.add), label: const Text('New template')),
              )
            : GridView.builder(
                padding: const EdgeInsets.fromLTRB(28, 0, 28, 24),
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 380, mainAxisExtent: 170, crossAxisSpacing: 14, mainAxisSpacing: 14),
                itemCount: _items.length,
                itemBuilder: (_, i) {
                  final t = _items[i];
                  return Card(
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: () => _edit(t),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(color: context.cs.primary, borderRadius: BorderRadius.circular(8)),
                              child: Text('#${t.code}', style: TextStyle(color: context.cs.onPrimary, fontWeight: FontWeight.w800)),
                            ),
                            const SizedBox(width: 10),
                            Expanded(child: Text(t.name, style: context.tt.titleMedium, overflow: TextOverflow.ellipsis)),
                          ]),
                          const SizedBox(height: 10),
                          Text(
                            [
                              '${t.itemCount} medicines',
                              if (t.doctorName.isNotEmpty) 'Dr. ${t.doctorName}',
                            ].join(' · '),
                            style: TextStyle(color: context.muted),
                          ),
                          if (t.description.isNotEmpty) Text(t.description, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: context.muted, fontSize: 12)),
                          const Spacer(),
                          Row(children: [
                            TextButton.icon(onPressed: () => _edit(t), icon: const Icon(Icons.edit_outlined, size: 16), label: const Text('Edit')),
                            const Spacer(),
                            FilledButton.tonalIcon(
                              onPressed: () => Nav.billWithTemplate(t.code),
                              icon: const Icon(Icons.point_of_sale, size: 16),
                              label: const Text('Use in bill'),
                            ),
                          ]),
                        ]),
                      ),
                    ),
                  );
                },
              ),
      ),
    ]);
  }
}

class _TemplateEditor extends StatefulWidget {
  const _TemplateEditor({this.template});
  final BillTemplate? template;
  @override
  State<_TemplateEditor> createState() => _TemplateEditorState();
}

class _TemplateEditorState extends State<_TemplateEditor> with EnterFlow {
  late final _code = TextEditingController(text: widget.template?.code ?? '');
  late final _name = TextEditingController(text: widget.template?.name ?? '');
  late final _doctor = TextEditingController(text: widget.template?.doctorName ?? '');
  late final _desc = TextEditingController(text: widget.template?.description ?? '');
  late final List<BillTemplateItem> _items = [...?widget.template?.items];
  final _prodCtrl = TextEditingController();
  final _qtyCtrl = TextEditingController();
  Product? _picked;
  int _qtyMode = 0; // 0 = loose unit (Tab, Vial, Bottle…), 1 = pack (Strip), 2 = box
  String? _error;

  FocusNode get _prodFocus => fn('medicine');
  FocusNode get _qtyFocus => fn('qty');

  @override
  List<String> get flowOrder => ['code', 'name', 'doctor', 'note', 'medicine'];

  @override
  void onFlowDone() => _prodFocus.requestFocus();

  /// Quantity units this medicine can be counted in: Tab / Strip / Box, or just Vial, Bottle…
  List<(int, String)> _modes(Product p) => [
        (0, p.unitName),
        if (p.packSize > 1 && p.packName != p.unitName) (1, p.packName),
        if (p.hasOuter) (2, p.outerName),
      ];

  String _modeName(Product p) => _modes(p).firstWhere((m) => m.$1 == _qtyMode, orElse: () => _modes(p).first).$2;

  Widget _tf(String key, TextEditingController c, String label, {String? hint, bool autofocus = false, TextCapitalization caps = TextCapitalization.none}) =>
      TextField(
        controller: c,
        focusNode: fn(key),
        autofocus: autofocus,
        textCapitalization: caps,
        decoration: InputDecoration(labelText: label, hintText: hint),
        onSubmitted: (_) => advance(key),
      );

  @override
  void initState() {
    super.initState();
    if (widget.template == null) Repo.suggestTemplateCode().then((c) => _code.text = c);
  }

  void _add() {
    final p = _picked;
    if (p == null) return;
    final q = parseQty(_qtyCtrl.text.isEmpty ? '1' : _qtyCtrl.text, p.packSize, outerSize: p.hasOuter ? p.outerSize : 0, mode: _qtyMode);
    if (q == null) return setState(() => _error = 'Invalid quantity');
    setState(() {
      final existing = _items.where((i) => i.productId == p.id).firstOrNull;
      if (existing != null) {
        existing.qtyUnits += q;
      } else {
        _items.add(BillTemplateItem(productId: p.id!, qtyUnits: q, product: p));
      }
      _picked = null;
      _qtyMode = 0;
      _error = null;
    });
    _prodCtrl.clear();
    _qtyCtrl.clear();
    _prodFocus.requestFocus();
  }

  Future<void> _save() async {
    if (_code.text.trim().isEmpty || _name.text.trim().isEmpty) return setState(() => _error = 'Template number and name are required');
    if (_items.isEmpty) return setState(() => _error = 'Add at least one medicine');
    try {
      await Repo.saveTemplate(BillTemplate(
        id: widget.template?.id,
        code: _code.text.trim(),
        name: _name.text.trim(),
        doctorName: _doctor.text.trim(),
        description: _desc.text.trim(),
        items: _items,
      ));
      if (mounted) Navigator.pop(context);
    } on RepoException catch (e) {
      setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FormDialog(
      title: widget.template == null ? 'New template' : 'Edit template #${widget.template!.code}',
      subtitle: 'Changes here update the saved template. Edits made on a bill never change it.',
      icon: Icons.bookmarks_outlined,
      width: 720,
      actions: [
        if (widget.template != null)
          TextButton.icon(
            onPressed: () async {
              if (!await confirm(context, title: 'Delete template?', message: 'Template #${widget.template!.code} will be removed.', confirmLabel: 'Delete', destructive: true)) return;
              await Repo.deleteTemplate(widget.template!.id!);
              if (context.mounted) Navigator.pop(context);
            },
            icon: const Icon(Icons.delete_outline, size: 18),
            label: const Text('Delete'),
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
          ),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: _save, child: const Text('Save template')),
      ],
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (_error != null) ...[Pill(_error!, color: AppColors.danger, icon: Icons.error_outline), const SizedBox(height: 12)],
        FieldRow(flex: const [1, 3], children: [
          _tf('code', _code, 'Template no *'),
          _tf('name', _name, 'Name *', hint: 'e.g. Saline kit – adult', autofocus: widget.template == null, caps: TextCapitalization.sentences),
        ]),
        FieldRow(children: [
          _tf('doctor', _doctor, 'Default doctor (optional)', caps: TextCapitalization.words),
          _tf('note', _desc, 'Note (optional)'),
        ]),
        const SectionLabel('Medicines'),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: SuggestField<ProductStock>(
              controller: _prodCtrl,
              focusNode: _prodFocus,
              label: 'Add medicine',
              prefixIcon: const Icon(Icons.search, size: 18),
              search: (q) => q.trim().isEmpty ? Future.value(<ProductStock>[]) : Repo.searchProducts(q, limit: 20),
              display: (ps) => ps.product.name,
              itemBuilder: (c, ps, hi) => SuggestTile(
                title: ps.product.name,
                badges: [RxBadge(ps.product)],
                subtitle: [ps.product.form, ps.product.manufacturer].where((e) => e.isNotEmpty).join(' · '),
                trailing: Text(ps.stockUnits == 0 ? 'No stock' : ps.product.qty(ps.stockUnits), style: TextStyle(fontSize: 12, color: context.muted)),
              ),
              onSelected: (ps) {
                setState(() {
                  _picked = ps.product;
                  _qtyMode = 0;
                });
                // Qty enables on the next frame.
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) _qtyFocus.requestFocus();
                });
              },
              onChanged: (_) {
                if (_picked != null && _prodCtrl.text != _picked!.name) setState(() => _picked = null);
              },
              // Enter on an empty medicine field (after adding lines) saves the template.
              onSubmitted: (v) {
                if (_picked != null) {
                  _qtyFocus.requestFocus();
                } else if (v.trim().isEmpty && _items.isNotEmpty) {
                  _save();
                }
              },
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 120,
            child: TextField(
              controller: _qtyCtrl,
              focusNode: _qtyFocus,
              enabled: _picked != null,
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.a-zA-Z ]'))],
              decoration: InputDecoration(labelText: 'Qty', hintText: '1', suffixText: _picked == null ? null : _modeName(_picked!)),
              onSubmitted: (_) => _add(),
            ),
          ),
          if (_picked != null && _modes(_picked!).length > 1) ...[
            const SizedBox(width: 8),
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: SegmentedButton<int>(
                showSelectedIcon: false,
                segments: [for (final m in _modes(_picked!)) ButtonSegment(value: m.$1, label: Text(m.$2))],
                selected: {_qtyMode},
                onSelectionChanged: (v) {
                  setState(() => _qtyMode = v.first);
                  _qtyFocus.requestFocus();
                },
              ),
            ),
          ],
          const SizedBox(width: 10),
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: FilledButton(onPressed: _picked == null ? null : _add, child: const Text('Add')),
          ),
        ]),
        if (_picked != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              [_picked!.form, if (_picked!.packingLabel.isNotEmpty) _picked!.packingLabel, 'Enter adds · Enter on an empty medicine saves the template'].join(' · '),
              style: TextStyle(fontSize: 12, color: context.muted),
            ),
          ),
        const SizedBox(height: 12),
        if (_items.isEmpty) Padding(padding: const EdgeInsets.all(20), child: Text('No medicines added', textAlign: TextAlign.center, style: TextStyle(color: context.muted))),
        for (var i = 0; i < _items.length; i++)
          Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(border: Border.all(color: context.border), borderRadius: BorderRadius.circular(10)),
            child: Row(children: [
              Text('${i + 1}.', style: TextStyle(color: context.muted)),
              const SizedBox(width: 10),
              Expanded(
                child: Row(children: [
                  Flexible(child: Text(_items[i].product?.name ?? '#${_items[i].productId}', style: const TextStyle(fontWeight: FontWeight.w600))),
                  const SizedBox(width: 6),
                  if (_items[i].product != null) RxBadge(_items[i].product!),
                ]),
              ),
              IconButton(
                icon: const Icon(Icons.remove_circle_outline, size: 20),
                onPressed: _items[i].qtyUnits <= 1 ? null : () => setState(() => _items[i].qtyUnits--),
              ),
              SizedBox(
                width: 120,
                child: Text(_items[i].product?.qty(_items[i].qtyUnits) ?? '${_items[i].qtyUnits}', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w600)),
              ),
              IconButton(icon: const Icon(Icons.add_circle_outline, size: 20), onPressed: () => setState(() => _items[i].qtyUnits++)),
              IconButton(icon: const Icon(Icons.close, size: 18), onPressed: () => setState(() => _items.removeAt(i))),
            ]),
          ),
      ]),
    );
  }
}
