import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/db.dart';
import '../core/format.dart';
import '../core/settings.dart';
import '../data/repo.dart';
import 'billing/billing_page.dart';
import 'bills/bill_viewer.dart';
import 'bills/bills_page.dart';
import 'contacts/contacts_page.dart';
import 'credit/credit_page.dart';
import 'dashboard/dashboard_page.dart';
import 'expiry/expiry_page.dart';
import 'inventory/inventory_page.dart';
import 'ledger/ledger_page.dart';
import 'nav.dart';
import 'purchases/purchases_page.dart';
import 'settings/settings_page.dart';
import 'suppliers/suppliers_page.dart';
import 'templates/templates_page.dart';
import 'theme.dart';

class _NavItem {
  final String label;
  final IconData icon;
  final IconData activeIcon;
  final String? shortcut;
  const _NavItem(this.label, this.icon, this.activeIcon, [this.shortcut]);
}

const _items = [
  _NavItem('Dashboard', Icons.space_dashboard_outlined, Icons.space_dashboard, 'F1'),
  _NavItem('New Bill', Icons.point_of_sale_outlined, Icons.point_of_sale, 'F2'),
  _NavItem('Bills', Icons.receipt_long_outlined, Icons.receipt_long),
  _NavItem('Credit', Icons.account_balance_wallet_outlined, Icons.account_balance_wallet),
  _NavItem('Inventory', Icons.medication_outlined, Icons.medication),
  _NavItem('Stock Entry', Icons.local_shipping_outlined, Icons.local_shipping),
  _NavItem('Expiry', Icons.event_busy_outlined, Icons.event_busy),
  _NavItem('Templates', Icons.bookmarks_outlined, Icons.bookmarks),
  _NavItem('Suppliers', Icons.storefront_outlined, Icons.storefront),
  _NavItem('Doctors & Patients', Icons.people_alt_outlined, Icons.people_alt),
  _NavItem('Stock Ledger', Icons.swap_vert, Icons.swap_vert),
  _NavItem('Settings', Icons.settings_outlined, Icons.settings),
];

class AppShell extends StatefulWidget {
  const AppShell({super.key, this.openBillFile});
  final String? openBillFile;
  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  late final _built = <int>{Nav.page.value};
  Timer? _dayTimer;
  int _expiryCount = 0;

  @override
  void initState() {
    super.initState();
    Nav.page.addListener(_onPage);
    dataVersion.addListener(_refreshBadge);
    _refreshBadge();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (widget.openBillFile != null) await showBillViewer(context, filePath: widget.openBillFile);
      if (mounted) await showExpiryAlert(context);
    });
    // Left open overnight? Re-check every 20 minutes; the alert itself only fires once a day.
    _dayTimer = Timer.periodic(const Duration(minutes: 20), (_) {
      if (mounted && Settings.instance.get('last_expiry_alert') != isoDate(today())) {
        _refreshBadge();
        showExpiryAlert(context);
      }
    });
  }

  @override
  void dispose() {
    Nav.page.removeListener(_onPage);
    dataVersion.removeListener(_refreshBadge);
    _dayTimer?.cancel();
    super.dispose();
  }

  void _onPage() => setState(() => _built.add(Nav.page.value));

  Future<void> _refreshBadge() async {
    final s = await Repo.expiryStats(today(), today());
    if (mounted) setState(() => _expiryCount = ((s['expired'] ?? 0) + (s['critical'] ?? 0) + (s['warn'] ?? 0)).toInt());
  }

  Widget _page(int i) => switch (i) {
    Nav.dashboard => const DashboardPage(),
    Nav.billing => const BillingPage(),
    Nav.bills => const BillsPage(),
    Nav.credit => const CreditPage(),
    Nav.inventory => const InventoryPage(),
    Nav.purchases => const PurchasesPage(),
    Nav.expiry => const ExpiryPage(),
    Nav.templates => const TemplatesPage(),
    Nav.suppliers => const SuppliersPage(),
    Nav.contacts => const ContactsPage(),
    Nav.ledger => const LedgerPage(),
    _ => const SettingsPage(),
  };

  @override
  Widget build(BuildContext context) {
    final current = Nav.page.value;
    _built.add(current);
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.f1): () => Nav.go(Nav.dashboard),
        const SingleActivator(LogicalKeyboardKey.f2): () => Nav.go(Nav.billing),
      },
      child: Scaffold(
        body: Row(
          children: [
            _sidebar(current),
            VerticalDivider(width: 1, color: context.border),
            Expanded(
              child: IndexedStack(
                index: current,
                children: [
                  for (var i = 0; i < _items.length; i++)
                    _built.contains(i) ? TickerMode(enabled: i == current, child: _page(i)) : const SizedBox.shrink(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  bool get _compact => MediaQuery.sizeOf(context).width < 1320;

  Widget _sidebar(int current) {
    final compact = _compact;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      width: compact ? 72 : 232,
      color: context.cs.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(compact ? 17 : 18, 22, compact ? 17 : 18, 18),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [AppColors.brandLight, AppColors.brand],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: const Icon(Icons.local_pharmacy_outlined, color: Colors.white, size: 22),
                ),
                if (!compact) const SizedBox(width: 11),
                if (!compact)
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('MedBillings', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, letterSpacing: -0.3)),
                        ListenableBuilder(
                          listenable: Settings.instance,
                          builder: (_, _) => Text(
                            Settings.instance.shopName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 11.5, color: context.muted),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              children: [
                for (var i = 0; i < _items.length; i++) ...[
                  if (i == Nav.bills || i == Nav.inventory || i == Nav.templates || i == Nav.settings) const SizedBox(height: 10),
                  _navTile(i, current == i),
                ],
              ],
            ),
          ),
          if (!compact)
            Padding(
              padding: const EdgeInsets.all(14),
              child: Text(
                'F1 Dashboard · F2 New bill',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11, color: context.muted),
              ),
            ),
        ],
      ),
    );
  }

  Widget _navTile(int i, bool active) {
    final it = _items[i];
    final cs = context.cs;
    final badge = i == Nav.expiry && _expiryCount > 0 ? _expiryCount : null;
    final primaryAction = i == Nav.billing;
    final compact = _compact;
    final icon = Icon(active ? it.activeIcon : it.icon, size: 20, color: active || primaryAction ? cs.primary : context.muted);
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Tooltip(
        message: compact ? '${it.label}${it.shortcut == null ? '' : '  (${it.shortcut})'}' : '',
        preferBelow: false,
        child: Material(
          color: active ? cs.primary.withValues(alpha: context.isDark ? 0.2 : 0.1) : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => Nav.go(i),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: compact ? 0 : 12, vertical: 10),
              child: compact
                  ? Center(
                      child: Badge(isLabelVisible: badge != null, label: Text('${badge ?? ''}'), backgroundColor: AppColors.danger, child: icon),
                    )
                  : Row(
                      children: [
                        icon,
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            it.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: active || primaryAction ? FontWeight.w700 : FontWeight.w500,
                              color: active ? cs.primary : null,
                            ),
                          ),
                        ),
                        if (badge != null)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(color: AppColors.danger, borderRadius: BorderRadius.circular(10)),
                            child: Text(
                              '$badge',
                              style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700),
                            ),
                          )
                        else if (it.shortcut != null)
                          Text(it.shortcut!, style: TextStyle(fontSize: 11, color: context.muted)),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
