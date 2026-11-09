import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/db.dart';
import '../../core/format.dart';
import '../../data/repo.dart';
import '../../models/models.dart';
import '../bills/bill_viewer.dart';
import '../nav.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// Credit accounts: who owes what, credit bills and payments received.
class CreditPage extends StatefulWidget {
  const CreditPage({super.key});
  @override
  State<CreditPage> createState() => _CreditPageState();
}

class _CreditPageState extends State<CreditPage> with DataReload {
  String _query = '';
  String _filter = 'due';
  List<Map<String, Object?>> _rows = [];
  Map<String, num> _stats = {};
  Timer? _debounce;

  @override
  void reload() async {
    final rows = await Repo.creditCustomers(_query, onlyDue: _filter == 'due', onlyCredit: _filter != 'all');
    final stats = await Repo.creditStats(DateTime(today().year, today().month, 1));
    if (mounted) {
      setState(() {
        _rows = rows;
        _stats = stats;
      });
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final withDues = _rows.where((r) => (r['balance'] as num) > 0.004).length;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      PageHeader(
        title: 'Credit',
        subtitle: 'Customer accounts — credit bills, dues and payments received',
        actions: [
          FilledButton.icon(
            onPressed: () async {
              final c = await showCustomerForm(context, customer: Customer(name: '', creditAllowed: true));
              if (c != null && context.mounted) showCustomerProfile(context, c.id!);
            },
            icon: const Icon(Icons.person_add_alt, size: 18),
            label: const Text('New credit customer'),
          ),
        ],
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(28, 0, 28, 14),
        child: Row(children: [
          Expanded(
            child: StatCard(
              label: 'Total outstanding',
              value: money0(_stats['outstanding'] ?? 0),
              sub: '$withDues customer${withDues == 1 ? '' : 's'} with dues',
              icon: Icons.account_balance_wallet_outlined,
              color: AppColors.warning,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: StatCard(label: 'Credit given', value: money0(_stats['given'] ?? 0), sub: 'this month, on credit bills', icon: Icons.north_east, color: AppColors.info),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: StatCard(label: 'Collected', value: money0(_stats['collected'] ?? 0), sub: 'this month, payments received', icon: Icons.south_west, color: AppColors.success),
          ),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(28, 0, 28, 12),
        child: Row(children: [
          SearchBox(
            hint: 'Name or mobile…',
            onChanged: (v) {
              _query = v;
              _debounce?.cancel();
              _debounce = Timer(const Duration(milliseconds: 200), reload);
            },
          ),
          const SizedBox(width: 14),
          for (final e in const {'due': 'With dues', 'credit': 'All credit customers', 'all': 'All patients'}.entries) ...[
            ChoiceChip(
              label: Text(e.value),
              selected: _filter == e.key,
              showCheckmark: false,
              onSelected: (_) {
                setState(() => _filter = e.key);
                reload();
              },
            ),
            const SizedBox(width: 6),
          ],
        ]),
      ),
      Expanded(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 0, 28, 24),
          child: Card(
            clipBehavior: Clip.antiAlias,
            child: _rows.isEmpty
                ? EmptyState(
                    icon: Icons.account_balance_wallet_outlined,
                    title: _filter == 'due' ? 'No pending dues' : 'No customers here yet',
                    message: 'Choose "Credit" as the payment mode on a bill, or add a credit customer. Their dues and payments show up here.',
                  )
                : SimpleTable(
                    columns: const [
                      TableCol('Customer', flex: 2),
                      TableCol('Address', flex: 1.6),
                      TableCol('Credit bills', width: 104, right: true),
                      TableCol('Limit', width: 90, right: true),
                      TableCol('Outstanding', width: 120, right: true),
                      TableCol('Last bill', width: 100),
                      TableCol('Last payment', width: 110),
                      TableCol('', width: 120),
                    ],
                    rowCount: _rows.length,
                    onTap: (i) => showCustomerProfile(context, _rows[i]['id'] as int),
                    cells: (i) {
                      final r = _rows[i];
                      final c = Customer.fromMap(r);
                      DateTime? d(String k) => r[k] == null ? null : DateTime.tryParse(r[k] as String);
                      return [
                        Row(children: [
                          _Avatar(c.name),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(c.name, style: const TextStyle(fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis),
                              if (c.phone.isNotEmpty) Text(c.phone, style: TextStyle(fontSize: 12, color: context.muted)),
                            ]),
                          ),
                        ]),
                        Text(c.address.isEmpty ? '—' : c.address, overflow: TextOverflow.ellipsis, style: TextStyle(color: context.muted)),
                        Text('${r['credit_bills']}'),
                        Text(c.creditLimit > 0 ? money0(c.creditLimit) : '—', style: TextStyle(color: context.muted)),
                        Text(c.balance > 0.004 ? money(c.balance) : '—',
                            style: TextStyle(fontWeight: FontWeight.w700, color: c.balance > 0.004 ? AppColors.danger : context.muted)),
                        Text(d('last_bill') == null ? '—' : fmtDateShort(d('last_bill')!), style: TextStyle(color: context.muted)),
                        Text(d('last_payment') == null ? '—' : fmtDateShort(d('last_payment')!), style: TextStyle(color: context.muted)),
                        c.balance > 0.004
                            ? OutlinedButton(
                                onPressed: () => showReceivePayment(context, c),
                                style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10)),
                                child: const Text('Receive'),
                              )
                            : const SizedBox.shrink(),
                      ];
                    },
                  ),
          ),
        ),
      ),
    ]);
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar(this.name, {this.radius = 16});
  final String name;
  final double radius;
  @override
  Widget build(BuildContext context) {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    final initials = parts.isEmpty ? '?' : parts.take(2).map((p) => p[0].toUpperCase()).join();
    return CircleAvatar(
      radius: radius,
      backgroundColor: context.cs.primary.withValues(alpha: 0.12),
      child: Text(initials, style: TextStyle(fontSize: radius * 0.75, fontWeight: FontWeight.w700, color: context.cs.primary)),
    );
  }
}

/// Small "Credit" badge used in patient suggestions and lists.
class CreditBadge extends StatelessWidget {
  const CreditBadge(this.customer, {super.key, this.small = true});
  final Customer customer;
  final bool small;
  @override
  Widget build(BuildContext context) {
    if (!customer.isCreditCustomer) return const SizedBox.shrink();
    final due = customer.balance > 0.004;
    return Pill(due ? 'Credit · ${money0(customer.balance)} due' : 'Credit', color: due ? AppColors.warning : AppColors.violet, icon: Icons.account_balance_wallet_outlined, small: small);
  }
}

// ====================================================================== customer form

Future<Customer?> showCustomerForm(BuildContext context, {Customer? customer}) =>
    showDialog<Customer>(context: context, builder: (_) => _CustomerForm(customer: customer));

class _CustomerForm extends StatefulWidget {
  const _CustomerForm({this.customer});
  final Customer? customer;
  @override
  State<_CustomerForm> createState() => _CustomerFormState();
}

class _CustomerFormState extends State<_CustomerForm> with EnterFlow {
  late final c = widget.customer ?? Customer(name: '');
  late final _name = TextEditingController(text: c.name);
  late final _phone = TextEditingController(text: c.phone);
  late final _addr = TextEditingController(text: c.address);
  late final _limit = TextEditingController(text: c.creditLimit > 0 ? trimNum(c.creditLimit) : '');
  late final _notes = TextEditingController(text: c.notes);
  late bool _credit = c.creditAllowed;
  String? _err;

  @override
  List<String> get flowOrder => ['name', 'phone', 'address', if (_credit) 'limit', 'notes'];

  @override
  void onFlowDone() => _save();

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      fn('name').requestFocus();
      return setState(() => _err = 'Required');
    }
    c
      ..name = _name.text.trim()
      ..phone = _phone.text.trim()
      ..address = _addr.text.trim()
      ..creditAllowed = _credit
      ..creditLimit = parseNum(_limit.text)
      ..notes = _notes.text.trim();
    await Repo.saveCustomer(c);
    if (mounted) Navigator.pop(context, c);
  }

  @override
  Widget build(BuildContext context) {
    return FormDialog(
      title: c.id == null ? 'New patient / customer' : 'Edit ${c.name}',
      icon: Icons.person_outline,
      actions: [
        if (c.id != null)
          TextButton(
            onPressed: () async {
              if (c.balance > 0.004) {
                showSnack(context, 'Settle the outstanding ${money(c.balance)} before deleting', error: true);
                return;
              }
              if (!await confirm(context, title: 'Delete ${c.name}?', message: 'Past bills stay, but this profile is removed.', confirmLabel: 'Delete', destructive: true)) return;
              await Repo.deleteCustomer(c.id!);
              if (context.mounted) Navigator.pop(context);
            },
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            child: const Text('Delete'),
          ),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        FieldRow(children: [
          flowField('name', _name, label: 'Name *', error: _err, autofocus: true, caps: TextCapitalization.words),
          flowField('phone', _phone, label: 'Mobile', formatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9+ ]'))]),
        ]),
        FieldRow(children: [flowField('address', _addr, label: 'Address')]),
        Container(
          decoration: BoxDecoration(border: Border.all(color: context.border), borderRadius: BorderRadius.circular(10)),
          child: SwitchListTile(
            value: _credit,
            onChanged: (v) => setState(() => _credit = v),
            title: const Text('Credit customer'),
            subtitle: const Text('Can take medicines on credit; shown with a Credit badge while billing'),
          ),
        ),
        const SizedBox(height: 14),
        FieldRow(children: [
          flowField(
            'limit',
            _limit,
            enabled: _credit,
            formatters: decimalInput,
            label: 'Credit limit (optional)',
            prefix: '₹ ',
            helper: 'You are warned before billing beyond this',
          ),
        ]),
        FieldRow(children: [flowField('notes', _notes, label: 'Notes (e.g. pays on the 1st of every month)', maxLines: 2, helper: 'Enter saves')]),
      ]),
    );
  }
}

// ====================================================================== receive payment

Future<bool> showReceivePayment(BuildContext context, Customer c) async {
  final amount = TextEditingController(text: c.balance > 0 ? trimNum(round2(c.balance)) : '');
  final note = TextEditingController();
  final noteFocus = FocusNode();
  var mode = 'Cash';
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, set) => AlertDialog(
        title: Text('Receive payment · ${c.name}'),
        content: SizedBox(
          width: 420,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('Outstanding: ${money(c.balance)}', style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 14),
            TextField(
              controller: amount,
              autofocus: true,
              inputFormatters: decimalInput,
              decoration: const InputDecoration(labelText: 'Amount received', prefixText: '₹ '),
              onChanged: (_) => set(() {}),
              onSubmitted: (_) => noteFocus.requestFocus(),
            ),
            const SizedBox(height: 12),
            Wrap(spacing: 6, children: [
              for (final m in ['Cash', 'UPI', 'Card', 'Cheque'])
                ChoiceChip(label: Text(m), selected: mode == m, showCheckmark: false, onSelected: (_) => set(() => mode = m)),
            ]),
            const SizedBox(height: 12),
            TextField(
              controller: note,
              focusNode: noteFocus,
              decoration: const InputDecoration(labelText: 'Note (UPI ref, etc.)', helperText: 'Enter saves the payment'),
              onSubmitted: (_) => Navigator.pop(ctx, true),
            ),
            const SizedBox(height: 10),
            Text('Balance after: ${money(round2(c.balance - parseNum(amount.text)))}', style: TextStyle(color: ctx.muted)),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save payment')),
        ],
      ),
    ),
  );
  noteFocus.dispose();
  if (ok != true) return false;
  try {
    await Repo.receivePayment(c.id!, parseNum(amount.text), mode: mode, note: note.text.trim());
    if (context.mounted) showSnack(context, '${money(parseNum(amount.text))} received from ${c.name}');
    return true;
  } on RepoException catch (e) {
    if (context.mounted) showSnack(context, e.message, error: true);
    return false;
  }
}

// ====================================================================== profile

Future<void> showCustomerProfile(BuildContext context, int customerId) =>
    showDialog(context: context, builder: (_) => _CustomerProfile(customerId: customerId));

class _CustomerProfile extends StatefulWidget {
  const _CustomerProfile({required this.customerId});
  final int customerId;
  @override
  State<_CustomerProfile> createState() => _CustomerProfileState();
}

class _CustomerProfileState extends State<_CustomerProfile> {
  Customer? _c;
  List<CreditEntry> _ledger = [];
  List<Sale> _bills = [];

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
    final c = await Repo.customer(widget.customerId);
    if (c == null) {
      if (mounted) Navigator.pop(context);
      return;
    }
    final ledger = await Repo.creditLedger(widget.customerId);
    final bills = await Repo.sales(customerId: widget.customerId, limit: 300);
    if (mounted) {
      setState(() {
        _c = c;
        _ledger = ledger.reversed.toList();
        _bills = bills;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = _c;
    final size = MediaQuery.sizeOf(context);
    if (c == null) return const Dialog(child: SizedBox(width: 300, height: 200, child: Center(child: CircularProgressIndicator())));
    final due = c.balance > 0.004;
    final total = _bills.where((b) => !b.isCancelled).fold(0.0, (s, b) => s + b.grandTotal);
    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      child: SizedBox(
        width: (size.width * 0.75).clamp(720, 1000),
        height: size.height * 0.88,
        child: DefaultTabController(
          length: 2,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 18, 12, 10),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _Avatar(c.name, radius: 26),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Flexible(child: Text(c.name, style: context.tt.headlineSmall)),
                      const SizedBox(width: 10),
                      if (c.creditAllowed) const Pill('Credit customer', color: AppColors.violet, icon: Icons.account_balance_wallet_outlined),
                    ]),
                    Text([c.phone, c.address].where((e) => e.isNotEmpty).join(' · '), style: TextStyle(color: context.muted)),
                    if (c.notes.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text(c.notes, style: const TextStyle(fontSize: 12.5))),
                  ]),
                ),
                OutlinedButton.icon(
                  onPressed: () => showCustomerForm(context, customer: c),
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: const Text('Edit'),
                ),
                const SizedBox(width: 6),
                IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 4, 22, 12),
              child: Row(children: [
                Expanded(
                  child: StatCard(
                    label: 'Outstanding',
                    value: money(c.balance),
                    sub: c.creditLimit > 0 ? 'Limit ${money0(c.creditLimit)}' : null,
                    icon: Icons.account_balance_wallet_outlined,
                    color: due ? AppColors.danger : AppColors.success,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(child: StatCard(label: 'Total purchases', value: money0(total), sub: '${_bills.where((b) => !b.isCancelled).length} bills', icon: Icons.receipt_long_outlined, color: AppColors.info)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    FilledButton.icon(
                      onPressed: due ? () => showReceivePayment(context, c) : null,
                      icon: const Icon(Icons.payments_outlined, size: 18),
                      label: const Text('Receive payment'),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        Nav.billForCustomer(c.id!);
                      },
                      icon: const Icon(Icons.point_of_sale, size: 18),
                      label: const Text('New bill for this customer'),
                    ),
                  ]),
                ),
              ]),
            ),
            TabBar(
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              tabs: [Tab(text: 'Credit account (${_ledger.length})'), Tab(text: 'All bills (${_bills.length})')],
            ),
            const Divider(),
            Expanded(
              child: TabBarView(children: [
                _ledger.isEmpty
                    ? const EmptyState(icon: Icons.account_balance_wallet_outlined, title: 'No credit activity', message: 'Credit bills and payments received will be listed here.')
                    : SimpleTable(
                        columns: const [
                          TableCol('Date', width: 150),
                          TableCol('Entry', flex: 2),
                          TableCol('Credit given', width: 120, right: true),
                          TableCol('Received', width: 120, right: true),
                          TableCol('Balance', width: 120, right: true),
                          TableCol('', width: 44),
                        ],
                        rowCount: _ledger.length,
                        onTap: (i) {
                          final e = _ledger[i];
                          if (e.kind == 'bill') showBillViewer(context, saleId: e.refId);
                        },
                        cells: (i) {
                          final e = _ledger[i];
                          return [
                            Text(fmtDateTime(e.date), style: TextStyle(fontSize: 12.5, color: context.muted)),
                            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(e.label, style: const TextStyle(fontWeight: FontWeight.w600)),
                              if (e.note.isNotEmpty) Text(e.note, style: TextStyle(fontSize: 12, color: context.muted), overflow: TextOverflow.ellipsis),
                            ]),
                            Text(e.debit > 0 ? money(e.debit) : '', style: const TextStyle(color: AppColors.danger, fontWeight: FontWeight.w600)),
                            Text(e.credit > 0 ? money(e.credit) : '', style: const TextStyle(color: AppColors.success, fontWeight: FontWeight.w600)),
                            Text(money(e.runningBalance), style: const TextStyle(fontWeight: FontWeight.w700)),
                            e.kind == 'payment'
                                ? IconButton(
                                    tooltip: 'Delete payment entry',
                                    icon: const Icon(Icons.delete_outline, size: 18),
                                    onPressed: () async {
                                      if (await confirm(context, title: 'Delete this payment?', message: '${money(e.credit)} will be added back to the outstanding balance.', confirmLabel: 'Delete', destructive: true)) {
                                        await Repo.deletePayment(e.refId);
                                      }
                                    },
                                  )
                                : Icon(Icons.chevron_right, size: 18, color: context.muted),
                          ];
                        },
                      ),
                _bills.isEmpty
                    ? const EmptyState(icon: Icons.receipt_long_outlined, title: 'No bills yet')
                    : SimpleTable(
                        columns: const [
                          TableCol('Bill no', width: 110),
                          TableCol('Date', width: 150),
                          TableCol('Doctor', flex: 2),
                          TableCol('Items', width: 60, right: true),
                          TableCol('Payment', width: 120),
                          TableCol('Amount', width: 110, right: true),
                        ],
                        rowCount: _bills.length,
                        onTap: (i) => showBillViewer(context, saleId: _bills[i].id),
                        cells: (i) {
                          final s = _bills[i];
                          return [
                            Text(s.billNo, style: const TextStyle(fontWeight: FontWeight.w600)),
                            Text(fmtDateTime(s.createdAt), style: TextStyle(fontSize: 12.5, color: context.muted)),
                            Text(s.doctorName.isEmpty ? '—' : 'Dr. ${s.doctorName}', overflow: TextOverflow.ellipsis),
                            Text('${s.itemCount}'),
                            s.isCancelled
                                ? const Pill('Cancelled', color: AppColors.danger, small: true)
                                : s.isCredit
                                    ? Pill(s.dueAmount > 0 ? 'Credit ${money0(s.dueAmount)}' : 'Credit', color: AppColors.warning, small: true)
                                    : Text(s.paymentMode, style: TextStyle(color: context.muted)),
                            Text(money(s.grandTotal), style: const TextStyle(fontWeight: FontWeight.w700)),
                          ];
                        },
                      ),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}
