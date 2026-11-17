import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../data/repo.dart';
import '../../models/models.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../nav.dart';
import 'supplier_account.dart';

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
  Supplier? _open; // dashboard being shown

  @override
  void initState() {
    super.initState();
    Nav.pendingSupplier.addListener(_onPending);
    WidgetsBinding.instance.addPostFrameCallback((_) => _onPending());
  }

  void _onPending() {
    final s = Nav.pendingSupplier.value;
    if (s == null || !mounted) return;
    Nav.pendingSupplier.value = null;
    setState(() => _open = s);
  }

  @override
  void reload() async {
    final r = await Repo.suppliersWithStats(_query);
    if (mounted) setState(() => _rows = r);
  }

  @override
  void dispose() {
    Nav.pendingSupplier.removeListener(_onPending);
    _debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final open = _open;
    if (open != null) {
      // A saved supplier may have been edited: show the latest details.
      final fresh = open.id == null ? open : _rows.where((r) => r['id'] == open.id).map(Supplier.fromMap).firstOrNull ?? open;
      return SupplierDashboard(
        key: ValueKey('${open.id}|${open.name}'),
        supplier: fresh,
        onBack: () => setState(() => _open = null),
        onEdit: () => showSupplierForm(context, supplier: fresh),
        onDelete: () async {
          if (!await confirm(context,
              title: 'Delete ${fresh.name}?',
              message: 'Past stock entries stay, but will no longer show this supplier. Payments recorded to them are removed.',
              confirmLabel: 'Delete',
              destructive: true)) {
            return;
          }
          await Repo.deleteSupplier(fresh.id!);
          if (mounted) setState(() => _open = null);
        },
      );
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      PageHeader(
        title: 'Suppliers',
        subtitle: 'Who you buy from: goods received, paid and remaining',
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
                      TableCol('Phone', flex: 1.1),
                      TableCol('Entries', width: 78, right: true),
                      TableCol('Goods', width: 120, right: true),
                      TableCol('Paid', width: 110, right: true),
                      TableCol('Remaining', width: 110, right: true),
                      TableCol('Last', width: 92),
                    ],
                    rowCount: _rows.length,
                    onTap: (i) => setState(() => _open = Supplier.fromMap(_rows[i])),
                    cells: (i) {
                      final r = _rows[i];
                      final s = Supplier.fromMap(r);
                      final oneOff = r['one_off'] == 1;
                      final remaining = (r['remaining'] as num).toDouble();
                      return [
                        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(children: [
                            Flexible(child: Text(s.name, style: const TextStyle(fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis)),
                            if (oneOff) ...[const SizedBox(width: 6), const Pill('One-off shop', color: AppColors.info, small: true)],
                          ]),
                          if ([s.contactPerson, s.gstin].any((e) => e.isNotEmpty))
                            Text([s.contactPerson, s.gstin].where((e) => e.isNotEmpty).join(' · '),
                                style: TextStyle(fontSize: 12, color: context.muted), overflow: TextOverflow.ellipsis),
                        ]),
                        Text(s.phone.isEmpty ? '—' : s.phone),
                        Text('${r['purchase_count']}'),
                        Text(money((r['purchase_total'] as num).toDouble())),
                        Text(money((r['paid_total'] as num).toDouble()), style: const TextStyle(color: AppColors.success)),
                        Text(remaining > 0.004 ? money(remaining) : (remaining < -0.004 ? '${money(-remaining)} adv.' : '—'),
                            style: TextStyle(color: remaining > 0.004 ? AppColors.warning : context.muted, fontWeight: FontWeight.w700)),
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
