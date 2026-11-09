import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/backup.dart';
import '../../core/db.dart';
import '../../core/format.dart';
import '../../data/repo.dart';
import '../../models/models.dart';
import '../nav.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'batch_dialogs.dart';
import 'product_form.dart';

class InventoryPage extends StatefulWidget {
  const InventoryPage({super.key});
  @override
  State<InventoryPage> createState() => _InventoryPageState();
}

class _InventoryPageState extends State<InventoryPage> with DataReload {
  String _query = '';
  String _filter = 'all';
  List<ProductStock> _items = [];
  Map<String, num> _stats = {};
  bool _loading = true;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    Nav.pendingProduct.addListener(_onPendingProduct);
    WidgetsBinding.instance.addPostFrameCallback((_) => _onPendingProduct());
  }

  @override
  void dispose() {
    Nav.pendingProduct.removeListener(_onPendingProduct);
    _debounce?.cancel();
    super.dispose();
  }

  void _onPendingProduct() {
    final id = Nav.pendingProduct.value;
    if (id == null || !mounted) return;
    Nav.pendingProduct.value = null;
    showProductDetail(context, id);
  }

  @override
  void reload() async {
    final items = await Repo.searchProducts(_query, limit: 2000, filter: _filter);
    final stats = await Repo.inventoryStats();
    if (mounted) {
      setState(() {
        _items = items;
        _stats = stats;
        _loading = false;
      });
    }
  }

  Future<void> _newProduct() async {
    final p = await showProductForm(context);
    if (p != null && mounted) {
      showSnack(context, '${p.name} added. Add stock via Stock Entry or opening stock.');
      showProductDetail(context, p.id!);
    }
  }

  Future<void> _dataMenu(String v) async {
    try {
      String? msg;
      switch (v) {
        case 'import':
          final r = await BackupService.importProductsCsv();
          if (r.added + r.updated > 0) msg = 'Imported: ${r.added} new, ${r.updated} updated';
        case 'export_stock':
          final p = await BackupService.exportStockCsv();
          if (p != null) msg = 'Stock exported to $p';
        case 'export_products':
          final p = await BackupService.exportProductsCsv();
          if (p != null) msg = 'Medicines exported to $p';
      }
      if (msg != null && mounted) showSnack(context, msg);
    } catch (e) {
      if (mounted) showSnack(context, '$e', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    const filters = {'all': 'All', 'in_stock': 'In stock', 'low': 'Low stock', 'out': 'Out of stock', 'expired': 'Has expired stock', 'rx': 'Prescription (Rx)'};
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      PageHeader(
        title: 'Inventory',
        subtitle: 'Medicines, batches and live stock',
        actions: [
          PopupMenuButton<String>(
            onSelected: _dataMenu,
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'import', child: ListTile(dense: true, leading: Icon(Icons.upload_file), title: Text('Import medicines (CSV)'))),
              PopupMenuItem(value: 'export_products', child: ListTile(dense: true, leading: Icon(Icons.download), title: Text('Export medicine list (CSV)'))),
              PopupMenuItem(value: 'export_stock', child: ListTile(dense: true, leading: Icon(Icons.table_view), title: Text('Export stock with batches (CSV)'))),
            ],
            child: IgnorePointer(child: OutlinedButton.icon(onPressed: () {}, icon: const Icon(Icons.import_export, size: 18), label: const Text('Import / Export'))),
          ),
          OutlinedButton.icon(onPressed: () => Nav.go(Nav.purchases), icon: const Icon(Icons.local_shipping_outlined, size: 18), label: const Text('Stock entry')),
          FilledButton.icon(onPressed: _newProduct, icon: const Icon(Icons.add, size: 18), label: const Text('New medicine')),
        ],
        bottom: Row(children: [
          SearchBox(
            hint: 'Search name, generic or company…',
            onChanged: (v) {
              _query = v;
              _debounce?.cancel();
              _debounce = Timer(const Duration(milliseconds: 200), reload);
            },
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Wrap(spacing: 6, runSpacing: 6, children: [
              for (final e in filters.entries)
                ChoiceChip(
                  label: Text(e.value),
                  selected: _filter == e.key,
                  showCheckmark: false,
                  onSelected: (_) {
                    setState(() => _filter = e.key);
                    reload();
                  },
                ),
            ]),
          ),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(28, 0, 28, 12),
        child: Wrap(spacing: 8, runSpacing: 6, children: [
          Pill('${intFmt(_stats['products'] ?? 0)} medicines', color: AppColors.info, icon: Icons.medication_outlined),
          Pill('Stock value ${money0(_stats['stock_value'] ?? 0)} (cost)', color: AppColors.brand, icon: Icons.account_balance_wallet_outlined),
          Pill('${money0(_stats['stock_mrp'] ?? 0)} at MRP', color: context.muted),
          if ((_stats['low_stock'] ?? 0) > 0) Pill('${_stats['low_stock']} low on stock', color: AppColors.warning, icon: Icons.trending_down),
        ]),
      ),
      Expanded(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 0, 28, 24),
          child: Card(
            clipBehavior: Clip.antiAlias,
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _items.isEmpty
                    ? EmptyState(
                        icon: Icons.medication_outlined,
                        title: _query.isEmpty && _filter == 'all' ? 'Your medicine list is empty' : 'Nothing matches',
                        message: _query.isEmpty && _filter == 'all'
                            ? 'Add medicines one by one, import a CSV, or record your first Stock Entry from a wholesaler.'
                            : null,
                        action: _query.isEmpty && _filter == 'all'
                            ? FilledButton.icon(onPressed: _newProduct, icon: const Icon(Icons.add), label: const Text('New medicine'))
                            : null,
                      )
                    : SimpleTable(
                        columns: const [
                          TableCol('Medicine', flex: 3),
                          TableCol('Form', width: 110),
                          TableCol('Company', flex: 1.4),
                          TableCol('Stock', width: 160),
                          TableCol('Batches', width: 70, right: true),
                          TableCol('Next expiry', width: 130),
                          TableCol('MRP', width: 90, right: true),
                          TableCol('Rack', width: 70),
                        ],
                        rowCount: _items.length,
                        onTap: (i) => showProductDetail(context, _items[i].product.id!),
                        cells: (i) {
                          final ps = _items[i];
                          final p = ps.product;
                          return [
                            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Row(children: [
                                Flexible(child: Text(p.name, style: const TextStyle(fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis)),
                                const SizedBox(width: 6),
                                RxBadge(p),
                              ]),
                              if (p.genericName.isNotEmpty)
                                Text(p.genericName, style: TextStyle(fontSize: 12, color: context.muted), overflow: TextOverflow.ellipsis),
                            ]),
                            Text(p.form, style: TextStyle(color: context.muted)),
                            Text(p.manufacturer, overflow: TextOverflow.ellipsis, style: TextStyle(color: context.muted)),
                            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(ps.stockUnits == 0 ? 'Out of stock' : p.qty(ps.stockUnits),
                                  style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      color: ps.stockUnits == 0 ? AppColors.danger : ps.lowStock ? AppColors.warning : null)),
                              if (ps.expiredUnits > 0) Text('+ ${p.qty(ps.expiredUnits)} expired', style: const TextStyle(fontSize: 11.5, color: AppColors.danger)),
                            ]),
                            Text('${ps.batchCount}'),
                            ps.nearestExpiry == null ? Text('—', style: TextStyle(color: context.muted)) : ExpiryBadge(ps.nearestExpiry!, small: true),
                            Text(ps.mrp == null ? '—' : amount(ps.mrp!)),
                            Text(p.rack.isEmpty ? '—' : p.rack, style: TextStyle(color: context.muted)),
                          ];
                        },
                      ),
          ),
        ),
      ),
    ]);
  }
}

// ====================================================================== product detail

Future<void> showProductDetail(BuildContext context, int productId) =>
    showDialog(context: context, builder: (_) => _ProductDetail(productId: productId));

class _ProductDetail extends StatefulWidget {
  const _ProductDetail({required this.productId});
  final int productId;
  @override
  State<_ProductDetail> createState() => _ProductDetailState();
}

class _ProductDetailState extends State<_ProductDetail> {
  ProductStock? _ps;
  List<Batch> _batches = [];
  List<StockMovement> _moves = [];
  bool _showEmpty = false;

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
    final ps = await Repo.productStock(widget.productId);
    final batches = await Repo.batchesForProduct(widget.productId, includeEmpty: true);
    final moves = await Repo.movements(productId: widget.productId, limit: 200);
    if (!mounted) return;
    setState(() {
      _ps = ps;
      _batches = batches;
      _moves = moves;
    });
  }

  Future<void> _delete() async {
    final p = _ps!.product;
    if (!await confirm(context,
        title: 'Remove ${p.name}?',
        message: 'If this medicine has stock history it will be archived (hidden from search) instead of deleted. Past bills are not affected.',
        confirmLabel: 'Remove',
        destructive: true)) {
      return;
    }
    final deleted = await Repo.deleteProduct(p.id!);
    if (!mounted) return;
    Navigator.pop(context);
    showSnack(context, deleted ? '${p.name} deleted' : '${p.name} archived');
  }

  @override
  Widget build(BuildContext context) {
    final ps = _ps;
    final size = MediaQuery.sizeOf(context);
    if (ps == null) return const Dialog(child: SizedBox(width: 300, height: 200, child: Center(child: CircularProgressIndicator())));
    final p = ps.product;
    final batches = _showEmpty ? _batches : _batches.where((b) => b.qty > 0 && b.status == 'active').toList();
    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      child: SizedBox(
        width: (size.width * 0.8).clamp(760, 1100),
        height: size.height * 0.88,
        child: DefaultTabController(
          length: 2,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 18, 12, 6),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Flexible(child: Text(p.name, style: context.tt.headlineSmall)),
                      const SizedBox(width: 10),
                      RxBadge(p, small: false),
                      if (!p.active) ...[const SizedBox(width: 6), const Pill('Archived', color: Colors.grey)],
                    ]),
                    const SizedBox(height: 2),
                    Text(
                      [p.genericName, p.manufacturer, p.form, p.packingLabel, 'GST ${trimNum(p.gstRate)}%', if (p.hsn.isNotEmpty) 'HSN ${p.hsn}', if (p.rack.isNotEmpty) 'Rack ${p.rack}']
                          .where((e) => e.isNotEmpty)
                          .join(' · '),
                      style: TextStyle(color: context.muted),
                    ),
                    if (p.warningText.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Pill(p.warningText, color: AppColors.rx, icon: Icons.warning_amber_rounded),
                    ],
                  ]),
                ),
                TextButton.icon(onPressed: _delete, icon: const Icon(Icons.delete_outline, size: 18), label: const Text('Remove'), style: TextButton.styleFrom(foregroundColor: AppColors.danger)),
                const SizedBox(width: 6),
                OutlinedButton.icon(
                  onPressed: () async {
                    await showProductForm(context, product: p);
                  },
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: const Text('Edit'),
                ),
                const SizedBox(width: 6),
                IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 8, 22, 8),
              child: Row(children: [
                Expanded(
                    child: StatCard(
                  label: 'In stock (sellable)',
                  value: ps.stockUnits == 0 ? '0' : p.qty(ps.stockUnits),
                  sub: p.fullBoxes(ps.stockUnits) > 0 ? '= ${p.qtyWithBoxes(ps.stockUnits)}' : null,
                  icon: Icons.inventory_2_outlined,
                  color: AppColors.brand,
                )),
                const SizedBox(width: 12),
                Expanded(child: StatCard(label: 'Active batches', value: '${ps.batchCount}', icon: Icons.layers_outlined, color: AppColors.info)),
                const SizedBox(width: 12),
                Expanded(
                    child: StatCard(
                        label: 'Next expiry',
                        value: ps.nearestExpiry == null ? '—' : fmtExpiry(ps.nearestExpiry!),
                        sub: ps.nearestExpiry == null ? null : expiryPhrase(ps.nearestExpiry!),
                        icon: Icons.event_outlined,
                        color: ps.nearestExpiry == null ? Colors.grey : expiryColor(context, ps.nearestExpiry!))),
                const SizedBox(width: 12),
                Expanded(
                    child: StatCard(
                        label: 'Expired on shelf',
                        value: ps.expiredUnits == 0 ? 'None' : p.qty(ps.expiredUnits),
                        icon: Icons.event_busy_outlined,
                        color: ps.expiredUnits == 0 ? AppColors.success : AppColors.danger)),
              ]),
            ),
            TabBar(
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              tabs: [Tab(text: 'Batches (${batches.length})'), Tab(text: 'Stock history (${_moves.length})')],
            ),
            const Divider(),
            Expanded(
              child: TabBarView(children: [
                Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(22, 10, 22, 10),
                    child: Row(children: [
                      FilterChip(label: const Text('Show sold-out / returned'), selected: _showEmpty, onSelected: (v) => setState(() => _showEmpty = v)),
                      const Spacer(),
                      OutlinedButton.icon(
                        onPressed: () => showBatchForm(context, product: p),
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text('Add opening stock'),
                      ),
                    ]),
                  ),
                  Expanded(
                    child: batches.isEmpty
                        ? const EmptyState(icon: Icons.layers_clear_outlined, title: 'No batches in stock', message: 'Record a Stock Entry from your wholesaler, or add opening stock.')
                        : SimpleTable(
                            columns: const [
                              TableCol('Batch', flex: 1.2),
                              TableCol('Expiry', width: 150),
                              TableCol('Stock', flex: 1.4),
                              TableCol('MRP', width: 80, right: true),
                              TableCol('Sale rate', width: 80, right: true),
                              TableCol('Cost', width: 80, right: true),
                              TableCol('Disc', width: 60, right: true),
                              TableCol('', width: 100),
                            ],
                            rowCount: batches.length,
                            cells: (i) {
                              final b = batches[i];
                              return [
                                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Text(b.batchNo, style: const TextStyle(fontWeight: FontWeight.w600)),
                                  if (b.status != 'active') Text(b.status, style: TextStyle(fontSize: 11.5, color: context.muted)),
                                ]),
                                ExpiryBadge(b.expiry, showPhrase: true, small: true),
                                Text(b.qty == 0 ? 'Sold out' : p.qty(b.qty), style: TextStyle(color: b.qty == 0 ? context.muted : null)),
                                Text(amount(b.mrp)),
                                Text(amount(b.saleRate)),
                                Text(amount(b.purchaseRate), style: TextStyle(color: context.muted)),
                                Text(b.discountPct > 0 ? '${trimNum(b.discountPct)}%' : '—'),
                                Row(mainAxisSize: MainAxisSize.min, children: [
                                  IconButton(tooltip: 'Edit batch', icon: const Icon(Icons.edit_outlined, size: 18), onPressed: () => showBatchForm(context, product: p, batch: b)),
                                  IconButton(tooltip: 'Adjust stock', icon: const Icon(Icons.tune, size: 18), onPressed: () => showAdjustStock(context, p, b)),
                                ]),
                              ];
                            },
                          ),
                  ),
                ]),
                _moves.isEmpty
                    ? const EmptyState(icon: Icons.swap_vert, title: 'No stock movements yet')
                    : MovementTable(moves: _moves, showProduct: false),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Stock entries (+) and exits (−) — used by the product detail and the ledger page.
class MovementTable extends StatelessWidget {
  const MovementTable({super.key, required this.moves, this.showProduct = true});
  final List<StockMovement> moves;
  final bool showProduct;

  @override
  Widget build(BuildContext context) {
    return SimpleTable(
      columns: [
        const TableCol('Date', width: 150),
        const TableCol('Type', width: 150),
        if (showProduct) const TableCol('Medicine', flex: 2),
        const TableCol('Batch', flex: 1),
        const TableCol('In', width: 120, right: true),
        const TableCol('Out', width: 120, right: true),
        const TableCol('Reference', flex: 1.4),
      ],
      rowCount: moves.length,
      cells: (i) {
        final m = moves[i];
        final q = fmtQty(m.qty.abs(), m.packSize, m.unitName, m.packName);
        final color = switch (m.type) {
          'SALE' => AppColors.info,
          'PURCHASE' || 'OPENING' => AppColors.success,
          'SALE_CANCEL' => AppColors.violet,
          'EXPIRY_RETURN' || 'EXPIRY_DISPOSE' => AppColors.danger,
          _ => AppColors.warning,
        };
        return [
          Text(fmtDateTime(m.createdAt), style: TextStyle(fontSize: 12.5, color: context.muted)),
          Pill(StockMovement.typeLabel(m.type), color: color, small: true),
          if (showProduct) Text(m.productName, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
          Text(m.batchNo.isEmpty ? '—' : m.batchNo),
          Text(m.qty > 0 ? '+ $q' : '', style: const TextStyle(color: AppColors.success, fontWeight: FontWeight.w600)),
          Text(m.qty < 0 ? '− $q' : '', style: const TextStyle(color: AppColors.danger, fontWeight: FontWeight.w600)),
          Text([m.refLabel, m.note].where((e) => e.isNotEmpty).join(' · '), overflow: TextOverflow.ellipsis, style: TextStyle(color: context.muted)),
        ];
      },
    );
  }
}
