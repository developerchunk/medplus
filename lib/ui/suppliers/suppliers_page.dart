import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../data/repo.dart';
import '../../models/models.dart';
import '../theme.dart';
import '../widgets/common.dart';

Future<Supplier?> showSupplierForm(BuildContext context, {Supplier? supplier}) =>
    showDialog<Supplier>(context: context, builder: (_) => _SupplierForm(supplier: supplier));

class _SupplierForm extends StatefulWidget {
  const _SupplierForm({this.supplier});
  final Supplier? supplier;
  @override
  State<_SupplierForm> createState() => _SupplierFormState();
}

class _SupplierFormState extends State<_SupplierForm> with EnterFlow {
  late final s = widget.supplier ?? Supplier(name: '');
  late final _name = TextEditingController(text: s.name);
  late final _contact = TextEditingController(text: s.contactPerson);
  late final _phone = TextEditingController(text: s.phone);
  late final _email = TextEditingController(text: s.email);
  late final _address = TextEditingController(text: s.address);
  late final _gstin = TextEditingController(text: s.gstin);
  late final _dl = TextEditingController(text: s.drugLicense);
  late final _notes = TextEditingController(text: s.notes);
  String? _err;

  @override
  List<String> get flowOrder => ['name', 'contact', 'phone', 'gstin', 'dl', 'email', 'address', 'notes'];

  @override
  void onFlowDone() => _save();

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      fn('name').requestFocus();
      return setState(() => _err = 'Required');
    }
    s
      ..name = _name.text.trim()
      ..contactPerson = _contact.text.trim()
      ..phone = _phone.text.trim()
      ..email = _email.text.trim()
      ..address = _address.text.trim()
      ..gstin = _gstin.text.trim().toUpperCase()
      ..drugLicense = _dl.text.trim()
      ..notes = _notes.text.trim();
    await Repo.saveSupplier(s);
    if (mounted) Navigator.pop(context, s);
  }

  @override
  Widget build(BuildContext context) {
    return FormDialog(
      title: s.id == null ? 'New supplier' : 'Edit supplier',
      subtitle: 'Wholesaler / distributor details',
      icon: Icons.storefront_outlined,
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: _save, child: const Text('Save supplier')),
      ],
      child: Column(children: [
        FieldRow(children: [
          flowField('name', _name, label: 'Firm name *', error: _err, autofocus: true, caps: TextCapitalization.words),
        ]),
        FieldRow(children: [
          flowField('contact', _contact, label: 'Contact person', caps: TextCapitalization.words),
          flowField('phone', _phone, label: 'Phone'),
        ]),
        FieldRow(children: [
          flowField('gstin', _gstin, label: 'GSTIN', caps: TextCapitalization.characters, formatters: upperInput),
          flowField('dl', _dl, label: 'Drug license no'),
        ]),
        FieldRow(children: [flowField('email', _email, label: 'Email')]),
        FieldRow(children: [flowField('address', _address, label: 'Address', maxLines: 2)]),
        FieldRow(children: [flowField('notes', _notes, label: 'Notes (credit terms, delivery days…)', maxLines: 2, helper: 'Enter saves')]),
      ]),
    );
  }
}

class SuppliersPage extends StatefulWidget {
  const SuppliersPage({super.key});
  @override
  State<SuppliersPage> createState() => _SuppliersPageState();
}

class _SuppliersPageState extends State<SuppliersPage> with DataReload {
  String _query = '';
  List<Map<String, Object?>> _rows = [];
  Timer? _debounce;

  @override
  void reload() async {
    final r = await Repo.suppliersWithStats(_query);
    if (mounted) setState(() => _rows = r);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _open(Supplier s) async {
    final purchases = await Repo.purchases(supplierId: s.id);
    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (ctx) => FormDialog(
        title: s.name,
        subtitle: [s.contactPerson, s.phone, s.gstin.isEmpty ? '' : 'GSTIN ${s.gstin}', s.drugLicense.isEmpty ? '' : 'DL ${s.drugLicense}'].where((e) => e.isNotEmpty).join(' · '),
        icon: Icons.storefront_outlined,
        width: 760,
        actions: [
          TextButton.icon(
            onPressed: () async {
              if (!await confirm(ctx, title: 'Delete ${s.name}?', message: 'Past stock entries stay, but will no longer show this supplier.', confirmLabel: 'Delete', destructive: true)) return;
              await Repo.deleteSupplier(s.id!);
              if (ctx.mounted) Navigator.pop(ctx);
            },
            icon: const Icon(Icons.delete_outline, size: 18),
            label: const Text('Delete'),
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
          ),
          OutlinedButton.icon(
            onPressed: () async {
              Navigator.pop(ctx);
              await showSupplierForm(context, supplier: s);
            },
            icon: const Icon(Icons.edit_outlined, size: 18),
            label: const Text('Edit'),
          ),
          FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
        ],
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (s.address.isNotEmpty) Text(s.address),
          if (s.notes.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Text(s.notes, style: TextStyle(color: ctx.muted))),
          const SizedBox(height: 12),
          SectionLabel('Purchase history (${purchases.length})'),
          if (purchases.isEmpty) Text('No stock entries from this supplier yet.', style: TextStyle(color: ctx.muted)),
          for (final p in purchases.take(50))
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.receipt_outlined),
              title: Text('${p.invoiceNo.isEmpty ? 'Entry #${p.id}' : 'Invoice ${p.invoiceNo}'} · ${fmtDate(p.invoiceDate)}'),
              subtitle: Text('${p.itemCount} items'),
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                if (!p.paid) const Padding(padding: EdgeInsets.only(right: 8), child: Pill('Unpaid', color: AppColors.warning, small: true)),
                Text(money(p.netTotal), style: const TextStyle(fontWeight: FontWeight.w700)),
              ]),
            ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      PageHeader(
        title: 'Suppliers',
        subtitle: 'Wholesalers and distributors you buy from',
        actions: [FilledButton.icon(onPressed: () => showSupplierForm(context), icon: const Icon(Icons.add, size: 18), label: const Text('New supplier'))],
        bottom: Align(
          alignment: Alignment.centerLeft,
          child: SearchBox(
            hint: 'Name, phone or GSTIN…',
            onChanged: (v) {
              _query = v;
              _debounce?.cancel();
              _debounce = Timer(const Duration(milliseconds: 200), reload);
            },
          ),
        ),
      ),
      Expanded(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 0, 28, 24),
          child: Card(
            clipBehavior: Clip.antiAlias,
            child: _rows.isEmpty
                ? EmptyState(
                    icon: Icons.storefront_outlined,
                    title: 'No suppliers yet',
                    message: 'Add the wholesalers you purchase from. They also appear as suggestions during stock entry.',
                    action: FilledButton.icon(onPressed: () => showSupplierForm(context), icon: const Icon(Icons.add), label: const Text('New supplier')),
                  )
                : SimpleTable(
                    columns: const [
                      TableCol('Supplier', flex: 2.4),
                      TableCol('Phone', flex: 1.2),
                      TableCol('GSTIN / DL', flex: 1.6),
                      TableCol('Entries', width: 70, right: true),
                      TableCol('Purchased', width: 120, right: true),
                      TableCol('Unpaid', width: 110, right: true),
                      TableCol('Last', width: 110),
                    ],
                    rowCount: _rows.length,
                    onTap: (i) => _open(Supplier.fromMap(_rows[i])),
                    cells: (i) {
                      final r = _rows[i];
                      final s = Supplier.fromMap(r);
                      final unpaid = (r['unpaid_total'] as num).toDouble();
                      return [
                        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(s.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                          if (s.contactPerson.isNotEmpty) Text(s.contactPerson, style: TextStyle(fontSize: 12, color: context.muted)),
                        ]),
                        Text(s.phone.isEmpty ? '—' : s.phone),
                        Text([s.gstin, s.drugLicense].where((e) => e.isNotEmpty).join(' · '), style: TextStyle(color: context.muted), overflow: TextOverflow.ellipsis),
                        Text('${r['purchase_count']}'),
                        Text(money((r['purchase_total'] as num).toDouble())),
                        Text(unpaid > 0 ? money(unpaid) : '—', style: TextStyle(color: unpaid > 0 ? AppColors.warning : context.muted, fontWeight: FontWeight.w600)),
                        Text(r['last_purchase'] == null ? '—' : fmtDateShort(DateTime.parse(r['last_purchase'] as String)), style: TextStyle(color: context.muted)),
                      ];
                    },
                  ),
          ),
        ),
      ),
    ]);
  }
}
