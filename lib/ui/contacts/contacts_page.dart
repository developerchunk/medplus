import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/settings.dart';
import '../../data/repo.dart';
import '../../models/models.dart';
import '../credit/credit_page.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// Doctors and regular patients — the source of billing-screen suggestions.
class ContactsPage extends StatefulWidget {
  const ContactsPage({super.key});
  @override
  State<ContactsPage> createState() => _ContactsPageState();
}

class _ContactsPageState extends State<ContactsPage> with DataReload, SingleTickerProviderStateMixin {
  late final _tabs = TabController(length: 2, vsync: this)..addListener(() => setState(() {}));
  String _query = '';
  List<Map<String, Object?>> _doctors = [];
  List<Map<String, Object?>> _customers = [];

  @override
  void reload() async {
    final d = await Repo.doctorsWithStats(_query);
    final c = await Repo.customersWithStats(_query);
    if (mounted) {
      setState(() {
        _doctors = d;
        _customers = c;
      });
    }
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  int get _defaultDoctorId => Settings.instance.integer('default_doctor_id');

  Future<void> _setDefault(Doctor d) async {
    final isDefault = _defaultDoctorId == d.id;
    await Settings.instance.set('default_doctor_id', isDefault ? '' : '${d.id}');
    if (!mounted) return;
    setState(() {});
    showSnack(context, isDefault ? 'Dr. ${d.name} is no longer the default doctor' : 'Dr. ${d.name} will be pre-filled on every new bill');
  }

  Future<void> _editDoctor([Doctor? d]) async {
    final doc = d ?? Doctor(name: '');
    final name = TextEditingController(text: doc.name);
    final qual = TextEditingController(text: doc.qualification);
    final reg = TextEditingController(text: doc.regNo);
    final clinic = TextEditingController(text: doc.clinic);
    final phone = TextEditingController(text: doc.phone);
    var makeDefault = d != null && _defaultDoctorId == d.id;
    // Enter order: name → qualification → reg no → phone → clinic → save.
    final nodes = List.generate(5, (_) => FocusNode());
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => FormDialog(
        title: d == null ? 'New doctor' : 'Edit doctor',
        icon: Icons.medical_services_outlined,
        actions: [
          if (d != null)
            TextButton(
              onPressed: () async {
                await Repo.deleteDoctor(d.id!);
                if (ctx.mounted) Navigator.pop(ctx, false);
              },
              style: TextButton.styleFrom(foregroundColor: AppColors.danger),
              child: const Text('Delete'),
            ),
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
        ],
        child: Column(children: [
          FieldRow(flex: const [2, 1], children: [
            TextField(
              controller: name,
              focusNode: nodes[0],
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Name *', prefixText: 'Dr. '),
              onSubmitted: (_) => nodes[1].requestFocus(),
            ),
            TextField(
              controller: qual,
              focusNode: nodes[1],
              decoration: const InputDecoration(labelText: 'Qualification', hintText: 'MBBS, MD'),
              onSubmitted: (_) => nodes[2].requestFocus(),
            ),
          ]),
          FieldRow(children: [
            TextField(
              controller: reg,
              focusNode: nodes[2],
              decoration: const InputDecoration(labelText: 'Registration no', hintText: 'MMC reg. no'),
              onSubmitted: (_) => nodes[3].requestFocus(),
            ),
            TextField(
              controller: phone,
              focusNode: nodes[3],
              decoration: const InputDecoration(labelText: 'Phone'),
              onSubmitted: (_) => nodes[4].requestFocus(),
            ),
          ]),
          FieldRow(children: [
            TextField(
              controller: clinic,
              focusNode: nodes[4],
              decoration: const InputDecoration(labelText: 'Clinic / hospital', helperText: 'Enter saves'),
              onSubmitted: (_) => Navigator.pop(ctx, true),
            ),
          ]),
          StatefulBuilder(
            builder: (ctx, set) => Container(
              decoration: BoxDecoration(border: Border.all(color: ctx.border), borderRadius: BorderRadius.circular(10)),
              child: SwitchListTile(
                value: makeDefault,
                onChanged: (v) => set(() => makeDefault = v),
                secondary: const Icon(Icons.star_rounded, color: AppColors.caution),
                title: const Text('Default doctor'),
                subtitle: const Text('Pre-filled on every new bill. You can still type another doctor for visiting doctors.'),
              ),
            ),
          ),
        ]),
      ),
    );
    for (final n in nodes) {
      n.dispose();
    }
    if (ok != true || name.text.trim().isEmpty) return;
    doc
      ..name = name.text.trim()
      ..qualification = qual.text.trim()
      ..regNo = reg.text.trim()
      ..clinic = clinic.text.trim()
      ..phone = phone.text.trim();
    await Repo.saveDoctor(doc);
    final wasDefault = d != null && _defaultDoctorId == d.id;
    if (makeDefault) {
      await Settings.instance.set('default_doctor_id', '${doc.id}');
    } else if (wasDefault) {
      await Settings.instance.set('default_doctor_id', '');
    }
    if (mounted) setState(() {});
  }

  Future<void> _editCustomer([Customer? c]) async {
    if (c?.id != null) return showCustomerProfile(context, c!.id!);
    await showCustomerForm(context);
  }

  @override
  Widget build(BuildContext context) {
    final doctors = _tabs.index == 0;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      PageHeader(
        title: 'Doctors & Patients',
        subtitle: 'Saved automatically from bills — used for quick suggestions while billing',
        actions: [
          FilledButton.icon(
            onPressed: doctors ? _editDoctor : _editCustomer,
            icon: const Icon(Icons.add, size: 18),
            label: Text(doctors ? 'New doctor' : 'New patient'),
          ),
        ],
        bottom: Row(children: [
          SearchBox(
            hint: 'Search name, phone, reg no…',
            onChanged: (v) {
              _query = v;
              reload();
            },
          ),
          const SizedBox(width: 20),
          SizedBox(
            width: 360,
            child: TabBar(controller: _tabs, tabs: [Tab(text: 'Doctors (${_doctors.length})'), Tab(text: 'Patients (${_customers.length})')]),
          ),
        ]),
      ),
      Expanded(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 0, 28, 24),
          child: Card(
            clipBehavior: Clip.antiAlias,
            child: TabBarView(controller: _tabs, children: [
              _doctors.isEmpty
                  ? const EmptyState(icon: Icons.medical_services_outlined, title: 'No doctors yet', message: 'Doctors are remembered automatically when you bill a prescription.')
                  : SimpleTable(
                      columns: const [
                        TableCol('Doctor', flex: 2),
                        TableCol('Reg. no', flex: 1),
                        TableCol('Clinic / hospital', flex: 2),
                        TableCol('Phone', flex: 1),
                        TableCol('Bills', width: 60, right: true),
                        TableCol('Sales', width: 110, right: true),
                        TableCol('Last bill', width: 100),
                        TableCol('Default', width: 70),
                      ],
                      rowCount: _doctors.length,
                      onTap: (i) => _editDoctor(Doctor.fromMap(_doctors[i])),
                      cells: (i) {
                        final r = _doctors[i];
                        final d = Doctor.fromMap(r);
                        return [
                          Row(children: [
                            Flexible(
                              child: Text('Dr. ${d.name}${d.qualification.isEmpty ? '' : ', ${d.qualification}'}',
                                  style: const TextStyle(fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis),
                            ),
                            if (_defaultDoctorId == d.id) ...[const SizedBox(width: 6), const Pill('Default', color: AppColors.caution, small: true)],
                          ]),
                          Text(d.regNo.isEmpty ? '—' : d.regNo),
                          Text(d.clinic.isEmpty ? '—' : d.clinic, overflow: TextOverflow.ellipsis, style: TextStyle(color: context.muted)),
                          Text(d.phone.isEmpty ? '—' : d.phone),
                          Text('${r['bills']}'),
                          Text(money((r['total'] as num).toDouble())),
                          Text(r['last_bill'] == null ? '—' : fmtDateShort(DateTime.parse(r['last_bill'] as String)), style: TextStyle(color: context.muted)),
                          IconButton(
                            tooltip: _defaultDoctorId == d.id ? 'Default doctor (click to remove)' : 'Make default doctor',
                            onPressed: () => _setDefault(d),
                            icon: Icon(
                              _defaultDoctorId == d.id ? Icons.star_rounded : Icons.star_outline_rounded,
                              color: _defaultDoctorId == d.id ? AppColors.caution : context.muted,
                            ),
                          ),
                        ];
                      },
                    ),
              _customers.isEmpty
                  ? const EmptyState(icon: Icons.people_outline, title: 'No patients yet', message: 'Patients are remembered automatically from bills.')
                  : SimpleTable(
                      columns: const [
                        TableCol('Patient', flex: 2.6),
                        TableCol('Mobile', flex: 1),
                        TableCol('Address', flex: 2),
                        TableCol('Bills', width: 60, right: true),
                        TableCol('Purchases', width: 110, right: true),
                        TableCol('Last bill', width: 100),
                      ],
                      rowCount: _customers.length,
                      onTap: (i) => _editCustomer(Customer.fromMap(_customers[i])),
                      cells: (i) {
                        final r = _customers[i];
                        final c = Customer.fromMap(r);
                        return [
                          Row(children: [
                            Flexible(child: Text(c.name, style: const TextStyle(fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis)),
                            const SizedBox(width: 6),
                            CreditBadge(c),
                          ]),
                          Text(c.phone.isEmpty ? '—' : c.phone),
                          Text(c.address.isEmpty ? '—' : c.address, overflow: TextOverflow.ellipsis, style: TextStyle(color: context.muted)),
                          Text('${r['bills']}'),
                          Text(money((r['total'] as num).toDouble())),
                          Text(r['last_bill'] == null ? '—' : fmtDateShort(DateTime.parse(r['last_bill'] as String)), style: TextStyle(color: context.muted)),
                        ];
                      },
                    ),
            ]),
          ),
        ),
      ),
    ]);
  }
}
