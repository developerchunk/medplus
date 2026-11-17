import 'package:sqflite_common_ffi/sqflite_ffi.dart' hide Batch;

import '../core/db.dart';
import '../core/format.dart';
import '../core/settings.dart';
import '../models/models.dart';

class RepoException implements Exception {
  final String message;
  RepoException(this.message);
  @override
  String toString() => message;
}

/// All database access. Screens call these and listen to [dataVersion].
int? _firstInt(List<Map<String, Object?>> rows) =>
    rows.isEmpty || rows.first.isEmpty ? null : (rows.first.values.first as num?)?.toInt();

class Repo {
  Repo._();
  static Database get _db => AppDb.db;
  static String get _now => isoDateTime(DateTime.now());
  static String get _today => isoDate(today());

  // ============================================================ products

  static const _productStockSelect = '''
    SELECT p.*,
      COALESCE(SUM(CASE WHEN b.status = 'active' AND b.expiry >= ?1 THEN b.qty END), 0) AS stock,
      COALESCE(SUM(CASE WHEN b.status = 'active' AND b.expiry < ?1 THEN b.qty END), 0) AS expired_stock,
      COUNT(CASE WHEN b.status = 'active' AND b.qty > 0 THEN 1 END) AS batch_count,
      MIN(CASE WHEN b.status = 'active' AND b.qty > 0 AND b.expiry >= ?1 THEN b.expiry END) AS nearest_expiry,
      (SELECT b2.mrp FROM batches b2 WHERE b2.product_id = p.id AND b2.status = 'active'
         AND b2.qty > 0 AND b2.expiry >= ?1 ORDER BY b2.expiry LIMIT 1) AS near_mrp
    FROM products p LEFT JOIN batches b ON b.product_id = p.id
  ''';

  static ProductStock _productStock(Map<String, Object?> r) => ProductStock(
        Product.fromMap(r),
        (r['stock'] as num).toInt(),
        (r['batch_count'] as num).toInt(),
        r['nearest_expiry'] == null ? null : DateTime.parse(r['nearest_expiry'] as String),
        (r['near_mrp'] as num?)?.toDouble(),
        (r['expired_stock'] as num).toInt(),
      );

  /// Token search across name, generic name and manufacturer.
  static Future<List<ProductStock>> searchProducts(String query, {int limit = 30, bool includeInactive = false, String filter = 'all'}) async {
    final tokens = query.trim().split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
    final where = <String>[if (!includeInactive) 'p.active = 1'];
    final args = <Object?>[_today];
    for (final t in tokens) {
      final i = args.length + 1;
      where.add("(p.name LIKE ?$i OR p.generic_name LIKE ?$i OR p.manufacturer LIKE ?$i)");
      args.add('%$t%');
    }
    final having = switch (filter) {
      'in_stock' => 'HAVING stock > 0',
      'out' => 'HAVING stock = 0',
      'low' => 'HAVING p.reorder_level > 0 AND stock <= p.reorder_level',
      'expired' => 'HAVING expired_stock > 0',
      'rx' => '',
      _ => '',
    };
    if (filter == 'rx') where.add("(p.rx_required = 1 OR p.is_antibiotic = 1 OR p.schedule IN ('H','H1','X','NDPS'))");
    final first = tokens.isEmpty ? '' : '${tokens.first}%';
    args.add(first);
    final orderIdx = args.length;
    final rows = await _db.rawQuery('''
      $_productStockSelect
      ${where.isEmpty ? '' : 'WHERE ${where.join(' AND ')}'}
      GROUP BY p.id $having
      ORDER BY (p.name LIKE ?$orderIdx) DESC, (stock > 0) DESC, p.name COLLATE NOCASE
      LIMIT $limit
    ''', args);
    return rows.map(_productStock).toList();
  }

  static Future<ProductStock?> productStock(int productId) async {
    final rows = await _db.rawQuery('$_productStockSelect WHERE p.id = ?2 GROUP BY p.id', [_today, productId]);
    return rows.isEmpty ? null : _productStock(rows.first);
  }

  static Future<Product?> product(int id) async {
    final rows = await _db.query('products', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : Product.fromMap(rows.first);
  }

  static Future<int> saveProduct(Product p) async {
    final map = p.toMap()..remove('id');
    if (p.id == null) {
      map['created_at'] = _now;
      p.id = await _db.insert('products', map);
    } else {
      await _db.update('products', map, where: 'id = ?', whereArgs: [p.id]);
    }
    notifyDataChanged();
    return p.id!;
  }

  /// Deletes a product that was never stocked or sold, otherwise archives it.
  static Future<bool> deleteProduct(int id) async {
    final used = _firstInt(await _db.rawQuery(
          'SELECT (SELECT COUNT(*) FROM batches WHERE product_id = ?1) + (SELECT COUNT(*) FROM sale_items WHERE product_id = ?1)',
          [id],
        )) ??
        0;
    if (used == 0) {
      await _db.delete('products', where: 'id = ?', whereArgs: [id]);
    } else {
      await _db.update('products', {'active': 0}, where: 'id = ?', whereArgs: [id]);
    }
    notifyDataChanged();
    return used == 0;
  }

  static Future<List<String>> distinctValues(String column, String query) async {
    const allowed = {'manufacturer', 'generic_name', 'rack', 'hsn'};
    if (!allowed.contains(column)) return [];
    final rows = await _db.rawQuery(
      "SELECT DISTINCT $column AS v FROM products WHERE $column != '' AND $column LIKE ? ORDER BY $column COLLATE NOCASE LIMIT 12",
      ['%${query.trim()}%'],
    );
    return rows.map((r) => r['v'] as String).toList();
  }

  // ============================================================ batches

  static Future<List<Batch>> batchesForProduct(int productId, {bool sellableOnly = false, bool includeEmpty = false}) async {
    final where = ['product_id = ?'];
    final args = <Object?>[productId];
    if (sellableOnly) {
      where.addAll(["status = 'active'", 'qty > 0', 'expiry >= ?']);
      args.add(_today);
    } else if (!includeEmpty) {
      where.add("(qty > 0 AND status = 'active')");
    }
    final rows = await _db.query('batches', where: where.join(' AND '), whereArgs: args, orderBy: 'expiry, id');
    return rows.map(Batch.fromMap).toList();
  }

  static Future<Batch?> batch(int id) async {
    final rows = await _db.query('batches', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : Batch.fromMap(rows.first);
  }

  /// Batch numbers seen before for a product (for purchase-entry suggestions).
  static Future<List<Batch>> knownBatches(int productId, String query) async {
    final rows = await _db.query('batches',
        where: 'product_id = ? AND batch_no LIKE ?', whereArgs: [productId, '%${query.trim()}%'], orderBy: 'id DESC', limit: 10);
    return rows.map(Batch.fromMap).toList();
  }

  static Future<void> updateBatch(Batch b) async {
    await _db.update(
      'batches',
      {
        'batch_no': b.batchNo,
        'mfg_date': b.mfgDate == null ? null : isoDate(b.mfgDate!),
        'expiry': isoDate(b.expiry),
        'mrp': b.mrp,
        'sale_rate': b.saleRate,
        'purchase_rate': b.purchaseRate,
        'gst_rate': b.gstRate,
        'discount_pct': b.discountPct,
      },
      where: 'id = ?',
      whereArgs: [b.id],
    );
    notifyDataChanged();
  }

  /// Adds stock without a purchase invoice (opening stock / found stock).
  static Future<void> addOpeningBatch(Batch b) async {
    await _db.transaction((txn) async {
      final map = b.toMap()..remove('id');
      map['initial_qty'] = b.qty;
      final id = await txn.insert('batches', map);
      await _move(txn, productId: b.productId, batchId: id, type: 'OPENING', qty: b.qty, note: 'Opening stock');
    });
    notifyDataChanged();
  }

  static Future<void> adjustStock(Batch b, int newQty, String note) async {
    final delta = newQty - b.qty;
    if (delta == 0) return;
    await _db.transaction((txn) async {
      await txn.update('batches', {'qty': newQty}, where: 'id = ?', whereArgs: [b.id]);
      await _move(txn, productId: b.productId, batchId: b.id, type: 'ADJUST', qty: delta, note: note);
    });
    notifyDataChanged();
  }

  static Future<void> _move(
    DatabaseExecutor txn, {
    required int productId,
    required int? batchId,
    required String type,
    required int qty,
    String refType = '',
    int? refId,
    String refLabel = '',
    String note = '',
  }) =>
      txn.insert('stock_movements', {
        'created_at': _now,
        'product_id': productId,
        'batch_id': batchId,
        'type': type,
        'qty': qty,
        'ref_type': refType,
        'ref_id': refId,
        'ref_label': refLabel,
        'note': note,
      });

  // ============================================================ expiry

  /// Active batches with stock expiring within [days] (includes already expired).
  static Future<List<BatchWithProduct>> expiringBatches(int days, {bool includeExpired = true}) async {
    final limit = isoDate(today().add(Duration(days: days)));
    final rows = await _db.rawQuery('''
      SELECT b.*, p.id AS p_id, p.name AS p_name, p.generic_name AS p_generic, p.manufacturer AS p_mfr,
             p.form AS p_form, p.unit_name AS p_unit, p.pack_name AS p_pack, p.pack_size AS p_pack_size,
             p.outer_name AS p_outer, p.outer_size AS p_outer_size,
             p.schedule AS p_schedule, p.rx_required AS p_rx, p.is_antibiotic AS p_ab,
             COALESCE(s.name, '') AS supplier_name
      FROM batches b JOIN products p ON p.id = b.product_id
      LEFT JOIN suppliers s ON s.id = b.supplier_id
      WHERE b.status = 'active' AND b.qty > 0 AND b.expiry <= ? ${includeExpired ? '' : 'AND b.expiry >= ?'}
      ORDER BY b.expiry, p.name COLLATE NOCASE
    ''', [limit, if (!includeExpired) _today]);
    return rows.map((r) {
      final product = Product(
        id: r['p_id'] as int,
        name: r['p_name'] as String,
        genericName: (r['p_generic'] as String?) ?? '',
        manufacturer: (r['p_mfr'] as String?) ?? '',
        form: (r['p_form'] as String?) ?? '',
        unitName: (r['p_unit'] as String?) ?? '',
        packName: (r['p_pack'] as String?) ?? '',
        packSize: (r['p_pack_size'] as int?) ?? 1,
        outerName: (r['p_outer'] as String?) ?? '',
        outerSize: (r['p_outer_size'] as int?) ?? 0,
        schedule: (r['p_schedule'] as String?) ?? '',
        rxRequired: r['p_rx'] == 1,
        isAntibiotic: r['p_ab'] == 1,
      );
      return BatchWithProduct(Batch.fromMap(r), product, r['supplier_name'] as String);
    }).toList();
  }

  /// action: returned | disposed | discounted | acknowledged
  static Future<void> handleExpiry(Batch b, String action, {int qty = 0, double discountPct = 0, String note = ''}) async {
    await _db.transaction((txn) async {
      double value = 0;
      if (action == 'returned' || action == 'disposed') {
        final take = qty.clamp(0, b.qty);
        final left = b.qty - take;
        value = round2(take * b.purchaseRate / b.packSize);
        await txn.update('batches', {'qty': left, if (left == 0) 'status': action}, where: 'id = ?', whereArgs: [b.id]);
        await _move(txn,
            productId: b.productId,
            batchId: b.id,
            type: action == 'returned' ? 'EXPIRY_RETURN' : 'EXPIRY_DISPOSE',
            qty: -take,
            refType: 'expiry',
            note: note);
        qty = take;
      } else if (action == 'discounted') {
        await txn.update('batches', {'discount_pct': discountPct}, where: 'id = ?', whereArgs: [b.id]);
        value = discountPct;
      }
      await txn.insert('expiry_actions', {
        'created_at': _now,
        'batch_id': b.id,
        'product_id': b.productId,
        'action': action,
        'qty': qty,
        'value': value,
        'note': note,
      });
    });
    notifyDataChanged();
  }

  static Future<List<ExpiryAction>> expiryActions({int limit = 200}) async {
    final rows = await _db.rawQuery('''
      SELECT e.*, p.name AS product_name, p.unit_name, p.pack_name, COALESCE(b.pack_size, p.pack_size) AS pack_size,
             b.batch_no, b.expiry
      FROM expiry_actions e
      LEFT JOIN batches b ON b.id = e.batch_id
      LEFT JOIN products p ON p.id = e.product_id
      ORDER BY e.created_at DESC LIMIT $limit
    ''');
    return rows.map(ExpiryAction.fromMap).toList();
  }

  // ============================================================ suppliers

  /// Saved suppliers plus one-off shops (from medicines brought for bills), each with
  /// goods received, paid and remaining. One-off rows have a null id and `one_off` = 1.
  static Future<List<Map<String, Object?>>> suppliersWithStats(String query) async {
    final q = '%${query.trim()}%';
    final saved = await _db.rawQuery('''
      SELECT s.*,
        (SELECT COUNT(*) FROM purchases pu WHERE pu.supplier_id = s.id) AS purchase_count,
        (SELECT COALESCE(SUM(net_total), 0) FROM purchases pu WHERE pu.supplier_id = s.id) AS purchase_total,
        (SELECT COALESCE(SUM(net_total), 0) FROM purchases pu WHERE pu.supplier_id = s.id AND pu.paid = 1)
          + (SELECT COALESCE(SUM(amount), 0) FROM supplier_payments sp WHERE sp.supplier_id = s.id) AS paid_total,
        (SELECT MAX(invoice_date) FROM purchases pu WHERE pu.supplier_id = s.id) AS last_purchase,
        0 AS one_off
      FROM suppliers s
      WHERE s.name LIKE ?1 OR s.phone LIKE ?1 OR s.gstin LIKE ?1 OR s.contact_person LIKE ?1
      ORDER BY s.name COLLATE NOCASE
    ''', [q]);
    final oneOff = await _db.rawQuery('''
      SELECT NULL AS id, MIN(pu.source_name) AS name,
        COUNT(*) AS purchase_count,
        COALESCE(SUM(pu.net_total), 0) AS purchase_total,
        COALESCE(SUM(CASE WHEN pu.paid = 1 THEN pu.net_total ELSE 0 END), 0)
          + (SELECT COALESCE(SUM(amount), 0) FROM supplier_payments sp WHERE sp.supplier_id IS NULL AND sp.source_name = MIN(pu.source_name) COLLATE NOCASE) AS paid_total,
        MAX(pu.invoice_date) AS last_purchase,
        1 AS one_off
      FROM purchases pu
      WHERE pu.supplier_id IS NULL AND pu.source_name != '' AND pu.source_name LIKE ?1
      GROUP BY pu.source_name COLLATE NOCASE
      ORDER BY name COLLATE NOCASE
    ''', [q]);
    return [
      for (final r in [...saved, ...oneOff])
        {...r, 'remaining': round2(((r['purchase_total'] as num?) ?? 0) - ((r['paid_total'] as num?) ?? 0))},
    ];
  }

  /// SQL filter on `purchases pu` for a saved supplier, or a one-off shop by name.
  static (String, List<Object?>) _sourceWhere(Supplier s) =>
      s.id != null ? ('pu.supplier_id = ?', [s.id]) : ("pu.supplier_id IS NULL AND pu.source_name = ? COLLATE NOCASE", [s.name]);

  /// Medicines received from [s]: total quantity, how often, last time and value.
  static Future<List<Map<String, Object?>>> supplierProducts(Supplier s) {
    final (where, args) = _sourceWhere(s);
    return _db.rawQuery('''
      SELECT pi.product_id, MIN(pi.product_name) AS product_name,
        COALESCE(p.unit_name, 'Unit') AS unit_name, COALESCE(p.pack_name, 'Pack') AS pack_name, COALESCE(p.pack_size, 1) AS pack_size,
        SUM((pi.qty_packs + pi.free_packs) * pi.pack_size + COALESCE(pi.loose_units, 0)) AS units,
        COUNT(DISTINCT pi.purchase_id) AS times,
        MAX(pu.invoice_date) AS last_date,
        COALESCE(SUM(pi.amount), 0) AS value
      FROM purchase_items pi
      JOIN purchases pu ON pu.id = pi.purchase_id
      LEFT JOIN products p ON p.id = pi.product_id
      WHERE $where
      GROUP BY pi.product_id
      ORDER BY last_date DESC, product_name COLLATE NOCASE
    ''', args);
  }

  /// Goods received (stock entries) and money paid to [s], oldest first, with the running
  /// amount still owed. Entries marked paid at stock entry show as paid straight away.
  static Future<List<CreditEntry>> supplierLedger(Supplier s) async {
    final (where, args) = _sourceWhere(s);
    final purchases = await _db.rawQuery('''
      SELECT pu.*, (SELECT COUNT(*) FROM purchase_items pi WHERE pi.purchase_id = pu.id) AS item_count
      FROM purchases pu WHERE $where ORDER BY pu.invoice_date, pu.id
    ''', args);
    final pays = s.id != null
        ? await _db.query('supplier_payments', where: 'supplier_id = ?', whereArgs: [s.id], orderBy: 'created_at')
        : await _db.query('supplier_payments', where: 'supplier_id IS NULL AND source_name = ? COLLATE NOCASE', whereArgs: [s.name], orderBy: 'created_at');
    final entries = <CreditEntry>[
      for (final pu in purchases)
        CreditEntry(
          date: DateTime.parse(pu['invoice_date'] as String),
          kind: 'purchase',
          refId: pu['id'] as int,
          label: (pu['invoice_no'] as String? ?? '').isEmpty ? 'Stock entry #${pu['id']}' : 'Invoice ${pu['invoice_no']}',
          debit: (pu['net_total'] as num).toDouble(),
          credit: pu['paid'] == 1 ? (pu['net_total'] as num).toDouble() : 0,
          note: '${pu['item_count']} item${pu['item_count'] == 1 ? '' : 's'}${pu['paid'] == 1 ? ' · paid at purchase' : ''}',
        ),
      for (final p in pays)
        CreditEntry(
          date: DateTime.parse(p['created_at'] as String),
          kind: 'payment',
          refId: p['id'] as int,
          label: 'Payment · ${p['mode']}',
          credit: (p['amount'] as num).toDouble(),
          note: p['note'] as String? ?? '',
        ),
    ]..sort((a, b) => a.date.compareTo(b.date));
    var bal = 0.0;
    for (final e in entries) {
      bal = round2(bal + e.debit - e.credit);
      e.runningBalance = bal;
    }
    return entries;
  }

  /// Money paid to a supplier or one-off shop.
  static Future<void> paySupplier(Supplier s, double amount, {String mode = 'Cash', String note = ''}) async {
    if (amount <= 0) throw RepoException('Enter the amount paid');
    await _db.insert('supplier_payments', {
      'supplier_id': s.id,
      'source_name': s.id == null ? s.name : '',
      'created_at': _now,
      'amount': round2(amount),
      'mode': mode,
      'note': note,
    });
    notifyDataChanged();
  }

  static Future<void> deleteSupplierPayment(int id) async {
    await _db.delete('supplier_payments', where: 'id = ?', whereArgs: [id]);
    notifyDataChanged();
  }

  /// Where each batch of a medicine came from: every stock entry that brought it in, newest first.
  static Future<List<BatchOrigin>> batchOrigins(int productId) async {
    final rows = await _db.rawQuery('''
      SELECT pi.batch_id, pi.batch_no, pu.id AS purchase_id, pu.supplier_id, pu.invoice_no, pu.invoice_date, pu.paid, pi.purchase_rate,
        COALESCE(s.name, NULLIF(pu.source_name, ''), '') AS source,
        (pi.qty_packs + pi.free_packs) * pi.pack_size + COALESCE(pi.loose_units, 0) AS units
      FROM purchase_items pi
      JOIN purchases pu ON pu.id = pi.purchase_id
      LEFT JOIN suppliers s ON s.id = pu.supplier_id
      WHERE pi.product_id = ?
      ORDER BY pu.invoice_date DESC, pu.id DESC
    ''', [productId]);
    return [
      for (final r in rows)
        BatchOrigin(
          batchId: r['batch_id'] as int?,
          batchNo: r['batch_no'] as String? ?? '',
          purchaseId: r['purchase_id'] as int,
          source: Supplier(id: r['supplier_id'] as int?, name: r['source'] as String),
          invoiceNo: r['invoice_no'] as String? ?? '',
          date: DateTime.parse(r['invoice_date'] as String),
          units: (r['units'] as num?)?.toInt() ?? 0,
          ratePerPack: (r['purchase_rate'] as num?)?.toDouble() ?? 0,
          paid: r['paid'] == 1,
        ),
    ];
  }

  static Future<List<Supplier>> searchSuppliers(String query, {int limit = 12}) async {
    final rows = await _db.query('suppliers',
        where: 'name LIKE ? OR phone LIKE ?', whereArgs: ['%${query.trim()}%', '%${query.trim()}%'], orderBy: 'name COLLATE NOCASE', limit: limit);
    return rows.map(Supplier.fromMap).toList();
  }

  static Future<int> saveSupplier(Supplier s) async {
    final map = s.toMap()..remove('id');
    if (s.id == null) {
      map['created_at'] = _now;
      s.id = await _db.insert('suppliers', map);
    } else {
      await _db.update('suppliers', map, where: 'id = ?', whereArgs: [s.id]);
    }
    notifyDataChanged();
    return s.id!;
  }

  static Future<void> deleteSupplier(int id) async {
    await _db.delete('suppliers', where: 'id = ?', whereArgs: [id]);
    notifyDataChanged();
  }

  // ============================================================ purchases

  static Future<int> createPurchase(Purchase pu, List<PurchaseItem> items) async {
    if (items.isEmpty) throw RepoException('Add at least one item');
    pu.grossTotal = round2(items.fold(0.0, (s, i) => s + i.gross));
    pu.discountTotal = round2(items.fold(0.0, (s, i) => s + i.discount));
    pu.gstTotal = round2(items.fold(0.0, (s, i) => s + i.gst));
    pu.netTotal = round2(items.fold(0.0, (s, i) => s + i.total));
    final id = await _db.transaction((txn) => _insertPurchase(txn, pu, items));
    notifyDataChanged();
    return id;
  }

  /// Writes a purchase, its items and their batches/stock movements inside [txn].
  static Future<int> _insertPurchase(Transaction txn, Purchase pu, List<PurchaseItem> items) async {
      final purchaseId = await txn.insert('purchases', pu.toMap()..remove('id'));
      final label = pu.invoiceNo.isEmpty ? 'Purchase #$purchaseId' : 'Inv ${pu.invoiceNo}';
      for (final it in items) {
        final units = it.totalUnits;
        // Same batch arriving again (same product, batch no & expiry) tops up the existing batch.
        final existing = await txn.query('batches',
            where: "product_id = ? AND batch_no = ? COLLATE NOCASE AND expiry = ? AND pack_size = ? AND status = 'active'",
            whereArgs: [it.productId, it.batchNo, isoDate(it.expiry), it.packSize],
            limit: 1);
        int batchId;
        if (existing.isNotEmpty) {
          batchId = existing.first['id'] as int;
          await txn.rawUpdate(
            'UPDATE batches SET qty = qty + ?, initial_qty = initial_qty + ?, mrp = ?, sale_rate = ?, purchase_rate = ?, gst_rate = ?, supplier_id = ? WHERE id = ?',
            [units, units, it.mrp, it.saleRate, it.purchaseRate, it.gstRate, pu.supplierId, batchId],
          );
        } else {
          batchId = await txn.insert('batches', {
            'product_id': it.productId,
            'batch_no': it.batchNo,
            'mfg_date': it.mfgDate == null ? null : isoDate(it.mfgDate!),
            'expiry': isoDate(it.expiry),
            'pack_size': it.packSize,
            'mrp': it.mrp,
            'purchase_rate': it.purchaseRate,
            'sale_rate': it.saleRate,
            'gst_rate': it.gstRate,
            'discount_pct': 0,
            'qty': units,
            'initial_qty': units,
            'supplier_id': pu.supplierId,
            'purchase_id': purchaseId,
            'status': 'active',
            'created_at': _now,
          });
        }
        it.batchId = batchId;
        it.purchaseId = purchaseId;
        // Bought by the box: remember the box size on medicines that don't have one yet.
        if (it.boughtInBoxes) {
          await txn.rawUpdate(
            "UPDATE products SET outer_name = 'Box', outer_size = ? WHERE id = ? AND (outer_size IS NULL OR outer_size <= 1 OR outer_name = '')",
            [it.boxSize, it.productId],
          );
        }
        await txn.insert('purchase_items', it.toMap()..remove('id'));
        await _move(txn,
            productId: it.productId, batchId: batchId, type: 'PURCHASE', qty: units, refType: 'purchase', refId: purchaseId, refLabel: label);
      }
      return purchaseId;
  }

  /// Saved suppliers plus one-off sources typed earlier (e.g. another medical shop
  /// a medicine was brought from), for the "brought from" field.
  static Future<List<Supplier>> purchaseSources(String query, {int limit = 12}) async {
    final saved = await searchSuppliers(query, limit: limit);
    final rows = await _db.rawQuery('''
      SELECT source_name, MAX(created_at) AS last FROM purchases
      WHERE supplier_id IS NULL AND source_name != '' AND source_name LIKE ?
      GROUP BY source_name COLLATE NOCASE ORDER BY last DESC LIMIT ?
    ''', ['%${query.trim()}%', limit]);
    final names = saved.map((s) => s.name.toLowerCase()).toSet();
    return [
      ...saved,
      for (final r in rows)
        if (!names.contains((r['source_name'] as String).toLowerCase())) Supplier(name: r['source_name'] as String, notes: 'one-off'),
    ];
  }

  /// Medicine brought from another shop while billing. Records it as a small
  /// purchase (from a saved [supplier] or a one-off [sourceName]) so it gets a batch
  /// the bill can sell from; whatever isn't sold stays in stock.
  /// A new [product] (id == null) is created first.
  static Future<Batch> addOutsideStock({
    required Product product,
    Supplier? supplier,
    String sourceName = '',
    required String batchNo,
    required DateTime expiry,
    required double mrp, // per pack
    double purchaseRate = 0, // per pack, what the shop paid
    required int units,
    bool paid = true,
    String note = '',
  }) async {
    if (units <= 0) throw RepoException('Enter how much was brought');
    final packSize = product.packSize < 1 ? 1 : product.packSize;
    final item = PurchaseItem(
      productId: product.id ?? 0,
      productName: product.name,
      batchNo: batchNo.trim().isEmpty ? 'OUT${DateTime.now().millisecondsSinceEpoch % 100000}' : batchNo.trim().toUpperCase(),
      expiry: expiry,
      packSize: packSize,
      qtyPacks: units ~/ packSize,
      looseUnits: units % packSize,
      purchaseRate: purchaseRate,
      mrp: mrp,
      gstRate: Settings.instance.gstEnabled ? product.gstRate : 0,
      packName: product.packName,
    );
    final source = supplier?.name ?? sourceName.trim();
    final pu = Purchase(
      supplierId: supplier?.id,
      supplierName: source.isEmpty ? 'Outside purchase' : source,
      invoiceDate: today(),
      grossTotal: round2(item.gross),
      gstTotal: round2(item.gst),
      netTotal: round2(item.total),
      paid: paid,
      notes: note.isEmpty ? 'Brought for a bill' : note,
    );
    final batchId = await _db.transaction((txn) async {
      if (product.id == null) {
        final map = product.toMap()..remove('id');
        map['created_at'] = _now;
        product.id = await txn.insert('products', map);
        item.productId = product.id!;
      }
      await _insertPurchase(txn, pu, [item]);
      return item.batchId!;
    });
    notifyDataChanged();
    return (await batch(batchId))!;
  }

  static Future<List<Purchase>> purchases({String query = '', int? supplierId, DateTime? from, DateTime? to}) async {
    final where = <String>[];
    final args = <Object?>[];
    if (query.trim().isNotEmpty) {
      where.add('(pu.invoice_no LIKE ? OR s.name LIKE ? OR pu.source_name LIKE ?)');
      args.addAll(['%${query.trim()}%', '%${query.trim()}%', '%${query.trim()}%']);
    }
    if (supplierId != null) {
      where.add('pu.supplier_id = ?');
      args.add(supplierId);
    }
    if (from != null) {
      where.add('pu.invoice_date >= ?');
      args.add(isoDate(from));
    }
    if (to != null) {
      where.add('pu.invoice_date <= ?');
      args.add(isoDate(to));
    }
    final rows = await _db.rawQuery('''
      SELECT pu.*, COALESCE(s.name, NULLIF(pu.source_name, ''), '—') AS supplier_name,
        (SELECT COUNT(*) FROM purchase_items pi WHERE pi.purchase_id = pu.id) AS item_count
      FROM purchases pu LEFT JOIN suppliers s ON s.id = pu.supplier_id
      ${where.isEmpty ? '' : 'WHERE ${where.join(' AND ')}'}
      ORDER BY pu.invoice_date DESC, pu.id DESC LIMIT 500
    ''', args);
    return rows.map(Purchase.fromMap).toList();
  }

  static Future<List<PurchaseItem>> purchaseItems(int purchaseId) async {
    final rows = await _db.rawQuery('''
      SELECT i.*, COALESCE(p.pack_name, 'Pack') AS pack_name FROM purchase_items i
      LEFT JOIN products p ON p.id = i.product_id WHERE i.purchase_id = ? ORDER BY i.id
    ''', [purchaseId]);
    return rows.map(PurchaseItem.fromMap).toList();
  }

  static Future<void> setPurchasePaid(int id, bool paid) async {
    await _db.update('purchases', {'paid': paid ? 1 : 0}, where: 'id = ?', whereArgs: [id]);
    notifyDataChanged();
  }

  /// Reverses a purchase entry. Only allowed while none of its stock was sold.
  static Future<void> deletePurchase(int id) async {
    await _db.transaction((txn) async {
      final items = await txn.query('purchase_items', where: 'purchase_id = ?', whereArgs: [id]);
      for (final it in items) {
        final units = ((it['qty_packs'] as int) + (it['free_packs'] as int)) * (it['pack_size'] as int) + ((it['loose_units'] as int?) ?? 0);
        final b = await txn.query('batches', where: 'id = ?', whereArgs: [it['batch_id']]);
        if (b.isEmpty) continue;
        final qty = b.first['qty'] as int;
        if (qty < units) {
          throw RepoException('Cannot delete: some stock of ${it['product_name']} (batch ${it['batch_no']}) is already sold or adjusted.');
        }
        await txn.update('batches', {'qty': qty - units, 'initial_qty': (b.first['initial_qty'] as int) - units},
            where: 'id = ?', whereArgs: [it['batch_id']]);
        await _move(txn,
            productId: it['product_id'] as int,
            batchId: it['batch_id'] as int?,
            type: 'ADJUST',
            qty: -units,
            refType: 'purchase',
            refId: id,
            note: 'Purchase entry deleted');
      }
      await txn.delete('batches', where: 'purchase_id = ? AND qty = 0 AND initial_qty <= 0', whereArgs: [id]);
      await txn.delete('purchases', where: 'id = ?', whereArgs: [id]);
    });
    notifyDataChanged();
  }

  // ============================================================ doctors & customers

  static Future<List<Doctor>> searchDoctors(String q, {int limit = 12}) async {
    final rows = await _db.rawQuery('''
      SELECT d.*, (SELECT COUNT(*) FROM sales s WHERE s.doctor_id = d.id) AS uses FROM doctors d
      WHERE d.name LIKE ?1 OR d.reg_no LIKE ?1 OR d.clinic LIKE ?1
      ORDER BY (d.name LIKE ?2) DESC, uses DESC, d.name COLLATE NOCASE LIMIT $limit
    ''', ['%${q.trim()}%', '${q.trim()}%']);
    return rows.map(Doctor.fromMap).toList();
  }

  /// Outstanding credit for customer alias `c`: unpaid part of credit bills minus payments received.
  static const _balanceSql = '''
    (SELECT COALESCE(SUM(s.grand_total - s.paid_amount), 0) FROM sales s
       WHERE s.customer_id = c.id AND s.status = 'completed' AND s.payment_mode = 'Credit')
    - (SELECT COALESCE(SUM(cp.amount), 0) FROM credit_payments cp WHERE cp.customer_id = c.id)
  ''';

  /// Patient suggestions. Credit customers come first; with an empty query only they are listed.
  static Future<List<Customer>> searchCustomers(String q, {int limit = 12}) async {
    final empty = q.trim().isEmpty;
    final rows = await _db.rawQuery('''
      SELECT * FROM (
        SELECT c.*, ($_balanceSql) AS balance, (SELECT COUNT(*) FROM sales s WHERE s.customer_id = c.id) AS uses FROM customers c
        WHERE c.name LIKE ?1 OR c.phone LIKE ?1
      ) c
      ${empty ? 'WHERE c.credit_allowed = 1 OR c.balance > 0.004' : ''}
      ORDER BY (c.credit_allowed = 1 OR c.balance > 0.004) DESC, (c.name LIKE ?2 OR c.phone LIKE ?2) DESC, c.uses DESC, c.name COLLATE NOCASE
      LIMIT $limit
    ''', ['%${q.trim()}%', '${q.trim()}%']);
    return rows.map(Customer.fromMap).toList();
  }

  static Future<Customer?> customer(int id) async {
    final rows = await _db.rawQuery('SELECT c.*, ($_balanceSql) AS balance FROM customers c WHERE c.id = ?', [id]);
    return rows.isEmpty ? null : Customer.fromMap(rows.first);
  }

  static Future<Doctor?> doctor(int id) async {
    final rows = await _db.query('doctors', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : Doctor.fromMap(rows.first);
  }

  // ============================================================ credit

  /// Customer profiles with credit numbers. [onlyDue] limits to outstanding balances.
  static Future<List<Map<String, Object?>>> creditCustomers(String q, {bool onlyDue = false, bool onlyCredit = true}) => _db.rawQuery('''
      SELECT * FROM (
        SELECT c.*, ($_balanceSql) AS balance,
          (SELECT COUNT(*) FROM sales s WHERE s.customer_id = c.id AND s.status = 'completed' AND s.payment_mode = 'Credit') AS credit_bills,
          (SELECT MAX(s.created_at) FROM sales s WHERE s.customer_id = c.id AND s.status = 'completed') AS last_bill,
          (SELECT MAX(cp.created_at) FROM credit_payments cp WHERE cp.customer_id = c.id) AS last_payment
        FROM customers c WHERE c.name LIKE ?1 OR c.phone LIKE ?1
      ) c
      WHERE 1 = 1 ${onlyCredit ? 'AND (c.credit_allowed = 1 OR c.balance > 0.004)' : ''} ${onlyDue ? 'AND c.balance > 0.004' : ''}
      ORDER BY c.balance DESC, c.name COLLATE NOCASE
    ''', ['%${q.trim()}%']);

  static Future<Map<String, num>> creditStats(DateTime monthStart) async {
    final r = (await _db.rawQuery('''
      SELECT
        (SELECT COALESCE(SUM(grand_total - paid_amount), 0) FROM sales WHERE status = 'completed' AND payment_mode = 'Credit')
          - (SELECT COALESCE(SUM(amount), 0) FROM credit_payments) AS outstanding,
        (SELECT COALESCE(SUM(amount), 0) FROM credit_payments WHERE created_at >= ?1) AS collected,
        (SELECT COALESCE(SUM(grand_total - paid_amount), 0) FROM sales WHERE status = 'completed' AND payment_mode = 'Credit' AND created_at >= ?1) AS given
    ''', [isoDate(monthStart)])).first;
    return {for (final e in r.entries) e.key: e.value as num};
  }

  /// Credit bills and payments for one customer, oldest first, with a running balance.
  static Future<List<CreditEntry>> creditLedger(int customerId) async {
    final bills = await _db.query('sales',
        where: "customer_id = ? AND status = 'completed' AND payment_mode = 'Credit'", whereArgs: [customerId], orderBy: 'created_at');
    final pays = await _db.query('credit_payments', where: 'customer_id = ?', whereArgs: [customerId], orderBy: 'created_at');
    final entries = <CreditEntry>[
      for (final b in bills)
        CreditEntry(
          date: DateTime.parse(b['created_at'] as String),
          kind: 'bill',
          refId: b['id'] as int,
          label: 'Bill ${b['bill_no']}',
          debit: round2((b['grand_total'] as num) - ((b['paid_amount'] as num?) ?? 0)),
          note: ((b['paid_amount'] as num?) ?? 0) > 0 ? 'Total ${money(b['grand_total'] as num)}, paid ${money(b['paid_amount'] as num)} at counter' : '',
        ),
      for (final p in pays)
        CreditEntry(
          date: DateTime.parse(p['created_at'] as String),
          kind: 'payment',
          refId: p['id'] as int,
          label: 'Payment received · ${p['mode']}',
          credit: (p['amount'] as num).toDouble(),
          note: p['note'] as String? ?? '',
        ),
    ]..sort((a, b) => a.date.compareTo(b.date));
    var bal = 0.0;
    for (final e in entries) {
      bal = round2(bal + e.debit - e.credit);
      e.runningBalance = bal;
    }
    return entries;
  }

  static Future<void> receivePayment(int customerId, double amount, {String mode = 'Cash', String note = ''}) async {
    if (amount <= 0) throw RepoException('Enter the amount received');
    await _db.insert('credit_payments', {'customer_id': customerId, 'created_at': _now, 'amount': round2(amount), 'mode': mode, 'note': note});
    notifyDataChanged();
  }

  static Future<void> deletePayment(int id) async {
    await _db.delete('credit_payments', where: 'id = ?', whereArgs: [id]);
    notifyDataChanged();
  }

  static Future<List<Map<String, Object?>>> doctorsWithStats(String q) => _db.rawQuery('''
      SELECT d.*, COUNT(s.id) AS bills, COALESCE(SUM(s.grand_total), 0) AS total, MAX(s.created_at) AS last_bill
      FROM doctors d LEFT JOIN sales s ON s.doctor_id = d.id AND s.status = 'completed'
      WHERE d.name LIKE ?1 OR d.reg_no LIKE ?1 OR d.clinic LIKE ?1
      GROUP BY d.id ORDER BY d.name COLLATE NOCASE
    ''', ['%${q.trim()}%']);

  static Future<List<Map<String, Object?>>> customersWithStats(String q) => _db.rawQuery('''
      SELECT c.*, ($_balanceSql) AS balance, COUNT(s.id) AS bills, COALESCE(SUM(s.grand_total), 0) AS total, MAX(s.created_at) AS last_bill
      FROM customers c LEFT JOIN sales s ON s.customer_id = c.id AND s.status = 'completed'
      WHERE c.name LIKE ?1 OR c.phone LIKE ?1
      GROUP BY c.id ORDER BY c.name COLLATE NOCASE
    ''', ['%${q.trim()}%']);

  static Future<void> saveDoctor(Doctor d) async {
    final map = d.toMap()..remove('id');
    if (d.id == null) {
      map['created_at'] = _now;
      d.id = await _db.insert('doctors', map);
    } else {
      await _db.update('doctors', map, where: 'id = ?', whereArgs: [d.id]);
    }
    notifyDataChanged();
  }

  static Future<void> saveCustomer(Customer c) async {
    final map = c.toMap()..remove('id');
    if (c.id == null) {
      map['created_at'] = _now;
      c.id = await _db.insert('customers', map);
    } else {
      await _db.update('customers', map, where: 'id = ?', whereArgs: [c.id]);
    }
    notifyDataChanged();
  }

  static Future<void> deleteDoctor(int id) async {
    await _db.delete('doctors', where: 'id = ?', whereArgs: [id]);
    notifyDataChanged();
  }

  static Future<void> deleteCustomer(int id) async {
    await _db.delete('customers', where: 'id = ?', whereArgs: [id]);
    notifyDataChanged();
  }

  // ============================================================ sales

  static String formatBillNo(String prefix, int seq) => '$prefix${seq.toString().padLeft(5, '0')}';

  static String peekNextBillNo() =>
      formatBillNo(Settings.instance.get('bill_prefix'), Settings.instance.integer('next_bill_seq'));

  /// Saves a bill atomically: validates and deducts stock, records movements,
  /// remembers the doctor & customer, assigns the next bill number.
  static Future<Sale> createSale(Sale sale) async {
    if (sale.items.isEmpty) throw RepoException('The bill has no items');
    if (sale.isCredit && sale.customerName.trim().isEmpty) throw RepoException('A credit bill needs the patient\'s name');
    final result = await _db.transaction((txn) async {
      // --- stock check per batch (several lines may share one batch)
      final need = <int, int>{};
      for (final it in sale.items) {
        need[it.batchId] = (need[it.batchId] ?? 0) + it.qtyUnits;
      }
      for (final e in need.entries) {
        final rows = await txn.query('batches', where: 'id = ?', whereArgs: [e.key]);
        if (rows.isEmpty) throw RepoException('A selected batch no longer exists');
        final b = Batch.fromMap(rows.first);
        final line = sale.items.firstWhere((i) => i.batchId == e.key);
        final name = line.productName;
        if (b.status != 'active') throw RepoException('Batch ${b.batchNo} of $name is not active');
        if (b.isExpired) throw RepoException('Batch ${b.batchNo} of $name is expired and cannot be sold');
        if (b.qty < e.value) {
          throw RepoException('Only ${fmtQty(b.qty, b.packSize, line.unitName, line.packName)} left in batch ${b.batchNo} of $name');
        }
      }

      // --- doctor & customer memory
      if (sale.doctorName.trim().isNotEmpty) {
        final rows = await txn.query('doctors', where: 'name = ? COLLATE NOCASE', whereArgs: [sale.doctorName.trim()], limit: 1);
        if (rows.isEmpty) {
          sale.doctorId = await txn.insert('doctors', {
            'name': sale.doctorName.trim(),
            'reg_no': sale.doctorRegNo.trim(),
            'clinic': sale.doctorClinic.trim(),
            'created_at': _now,
          });
        } else {
          sale.doctorId = rows.first['id'] as int;
          final upd = <String, Object?>{
            if (sale.doctorRegNo.trim().isNotEmpty) 'reg_no': sale.doctorRegNo.trim(),
            if (sale.doctorClinic.trim().isNotEmpty) 'clinic': sale.doctorClinic.trim(),
          };
          if (upd.isNotEmpty) await txn.update('doctors', upd, where: 'id = ?', whereArgs: [sale.doctorId]);
        }
      }
      if (sale.customerName.trim().isNotEmpty) {
        final rows = await txn.query('customers',
            where: "name = ? COLLATE NOCASE AND (phone = ? OR ? = '' OR phone = '')",
            whereArgs: [sale.customerName.trim(), sale.customerPhone.trim(), sale.customerPhone.trim()],
            limit: 1);
        if (rows.isEmpty) {
          sale.customerId = await txn.insert('customers', {
            'name': sale.customerName.trim(),
            'phone': sale.customerPhone.trim(),
            'address': sale.customerAddress.trim(),
            'created_at': _now,
          });
        } else {
          sale.customerId = rows.first['id'] as int;
          final upd = <String, Object?>{
            if (sale.customerPhone.trim().isNotEmpty) 'phone': sale.customerPhone.trim(),
            if (sale.customerAddress.trim().isNotEmpty) 'address': sale.customerAddress.trim(),
          };
          if (upd.isNotEmpty) await txn.update('customers', upd, where: 'id = ?', whereArgs: [sale.customerId]);
        }
        if (sale.isCredit) await txn.update('customers', {'credit_allowed': 1}, where: 'id = ?', whereArgs: [sale.customerId]);
      }

      // --- bill number
      final prefix = await _setting(txn, 'bill_prefix');
      var seq = int.tryParse(await _setting(txn, 'next_bill_seq')) ?? 1;
      while (true) {
        final no = formatBillNo(prefix, seq);
        final exists = _firstInt(await txn.rawQuery('SELECT COUNT(*) FROM sales WHERE bill_no = ?', [no])) ?? 0;
        if (exists == 0) break;
        seq++;
      }
      sale.billNo = formatBillNo(prefix, seq);
      await txn.rawInsert('INSERT OR REPLACE INTO settings(key, value) VALUES(?, ?)', ['next_bill_seq', '${seq + 1}']);

      // --- write
      sale.createdAt = DateTime.now();
      final saleId = await txn.insert('sales', sale.toMap()..remove('id'));
      sale.id = saleId;
      for (final it in sale.items) {
        it.saleId = saleId;
        it.id = await txn.insert('sale_items', it.toMap()..remove('id'));
        await txn.rawUpdate('UPDATE batches SET qty = qty - ? WHERE id = ?', [it.qtyUnits, it.batchId]);
        await _move(txn,
            productId: it.productId, batchId: it.batchId, type: 'SALE', qty: -it.qtyUnits, refType: 'sale', refId: saleId, refLabel: sale.billNo);
      }
      return sale;
    });
    await Settings.instance.load();
    notifyDataChanged();
    return result;
  }

  static Future<String> _setting(DatabaseExecutor txn, String key) async {
    final rows = await txn.query('settings', where: 'key = ?', whereArgs: [key]);
    return rows.isEmpty ? (Settings.defaults[key] ?? '') : rows.first['value'] as String;
  }

  static Future<void> setSaleFile(int saleId, String path) =>
      _db.update('sales', {'file_path': path}, where: 'id = ?', whereArgs: [saleId]);

  static Future<Sale?> sale(int id) async {
    final rows = await _db.query('sales', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    final s = Sale.fromMap(rows.first);
    final items = await _db.query('sale_items', where: 'sale_id = ?', whereArgs: [id], orderBy: 'id');
    s.items = items.map(SaleItem.fromMap).toList();
    s.itemCount = s.items.length;
    return s;
  }

  static Future<List<Sale>> sales({String query = '', DateTime? from, DateTime? to, String status = 'all', int? customerId, int limit = 1000}) async {
    final where = <String>[];
    final args = <Object?>[];
    final q = query.trim();
    if (q.isNotEmpty) {
      where.add('(s.bill_no LIKE ?1 OR s.customer_name LIKE ?1 OR s.customer_phone LIKE ?1 OR s.doctor_name LIKE ?1 '
          'OR EXISTS (SELECT 1 FROM sale_items i WHERE i.sale_id = s.id AND (i.product_name LIKE ?1 OR i.batch_no LIKE ?1)))');
      args.add('%$q%');
    }
    if (from != null) {
      where.add('s.created_at >= ?${args.length + 1}');
      args.add(isoDate(from));
    }
    if (to != null) {
      where.add('s.created_at < ?${args.length + 1}');
      args.add(isoDate(to.add(const Duration(days: 1))));
    }
    if (status != 'all') {
      where.add('s.status = ?${args.length + 1}');
      args.add(status);
    }
    if (customerId != null) {
      where.add('s.customer_id = ?${args.length + 1}');
      args.add(customerId);
    }
    final rows = await _db.rawQuery('''
      SELECT s.*, (SELECT COUNT(*) FROM sale_items i WHERE i.sale_id = s.id) AS item_count
      FROM sales s ${where.isEmpty ? '' : 'WHERE ${where.join(' AND ')}'}
      ORDER BY s.created_at DESC, s.id DESC LIMIT $limit
    ''', args);
    return rows.map(Sale.fromMap).toList();
  }

  /// Cancels a bill and puts its stock back on the shelf.
  static Future<void> cancelSale(int saleId, String reason) async {
    await _db.transaction((txn) async {
      final rows = await txn.query('sales', where: 'id = ?', whereArgs: [saleId]);
      if (rows.isEmpty) throw RepoException('Bill not found');
      if (rows.first['status'] == 'cancelled') throw RepoException('Bill is already cancelled');
      final billNo = rows.first['bill_no'] as String;
      final items = await txn.query('sale_items', where: 'sale_id = ?', whereArgs: [saleId]);
      for (final it in items) {
        await txn.rawUpdate("UPDATE batches SET qty = qty + ?, status = 'active' WHERE id = ?", [it['qty_units'], it['batch_id']]);
        await _move(txn,
            productId: it['product_id'] as int,
            batchId: it['batch_id'] as int,
            type: 'SALE_CANCEL',
            qty: it['qty_units'] as int,
            refType: 'sale',
            refId: saleId,
            refLabel: billNo,
            note: reason);
      }
      await txn.update('sales', {'status': 'cancelled', 'cancel_reason': reason}, where: 'id = ?', whereArgs: [saleId]);
    });
    notifyDataChanged();
  }

  // ============================================================ templates

  static Future<List<BillTemplate>> templates([String q = '']) async {
    final rows = await _db.rawQuery('''
      SELECT t.*, (SELECT COUNT(*) FROM template_items i WHERE i.template_id = t.id) AS item_count
      FROM templates t WHERE t.code LIKE ?1 OR t.name LIKE ?1 OR t.description LIKE ?1
      ORDER BY CAST(t.code AS INTEGER), t.code COLLATE NOCASE
    ''', ['%${q.trim()}%']);
    return rows.map(BillTemplate.fromMap).toList();
  }

  static Future<BillTemplate?> template({int? id, String? code}) async {
    final rows = id != null
        ? await _db.query('templates', where: 'id = ?', whereArgs: [id])
        : await _db.query('templates', where: 'code = ? COLLATE NOCASE', whereArgs: [code?.trim()]);
    if (rows.isEmpty) return null;
    final t = BillTemplate.fromMap(rows.first);
    final items = await _db.rawQuery('''
      SELECT i.id AS item_id, i.qty_units, p.* FROM template_items i JOIN products p ON p.id = i.product_id
      WHERE i.template_id = ? ORDER BY i.sort, i.id
    ''', [t.id]);
    t.items = items
        .map((r) => BillTemplateItem(id: r['item_id'] as int, productId: r['id'] as int, qtyUnits: r['qty_units'] as int, product: Product.fromMap(r)))
        .toList();
    t.itemCount = t.items.length;
    return t;
  }

  static Future<int> saveTemplate(BillTemplate t) async {
    final dup = await _db.query('templates', where: 'code = ? COLLATE NOCASE AND id != ?', whereArgs: [t.code.trim(), t.id ?? -1]);
    if (dup.isNotEmpty) throw RepoException('Template number "${t.code}" is already used by "${dup.first['name']}"');
    final id = await _db.transaction((txn) async {
      final map = {
        'code': t.code.trim(),
        'name': t.name.trim(),
        'description': t.description.trim(),
        'doctor_name': t.doctorName.trim(),
        'updated_at': _now,
      };
      int id;
      if (t.id == null) {
        id = await txn.insert('templates', {...map, 'created_at': _now});
      } else {
        id = t.id!;
        await txn.update('templates', map, where: 'id = ?', whereArgs: [id]);
        await txn.delete('template_items', where: 'template_id = ?', whereArgs: [id]);
      }
      for (var i = 0; i < t.items.length; i++) {
        await txn.insert('template_items', {'template_id': id, 'product_id': t.items[i].productId, 'qty_units': t.items[i].qtyUnits, 'sort': i});
      }
      return id;
    });
    notifyDataChanged();
    return id;
  }

  static Future<void> deleteTemplate(int id) async {
    await _db.delete('templates', where: 'id = ?', whereArgs: [id]);
    notifyDataChanged();
  }

  static Future<String> suggestTemplateCode() async {
    final v = _firstInt(await _db.rawQuery('SELECT MAX(CAST(code AS INTEGER)) FROM templates')) ?? 0;
    return '${v + 1}';
  }

  // ============================================================ ledger

  static Future<List<StockMovement>> movements({String query = '', String type = 'all', DateTime? from, DateTime? to, int? productId, int limit = 1000}) async {
    final where = <String>[];
    final args = <Object?>[];
    if (query.trim().isNotEmpty) {
      where.add('(p.name LIKE ? OR b.batch_no LIKE ? OR m.ref_label LIKE ?)');
      args.addAll(List.filled(3, '%${query.trim()}%'));
    }
    if (type == 'in') where.add('m.qty > 0');
    if (type == 'out') where.add('m.qty < 0');
    if (productId != null) {
      where.add('m.product_id = ?');
      args.add(productId);
    }
    if (from != null) {
      where.add('m.created_at >= ?');
      args.add(isoDate(from));
    }
    if (to != null) {
      where.add('m.created_at < ?');
      args.add(isoDate(to.add(const Duration(days: 1))));
    }
    final rows = await _db.rawQuery('''
      SELECT m.*, p.name AS product_name, p.unit_name, p.pack_name, COALESCE(b.pack_size, p.pack_size) AS pack_size,
             COALESCE(b.batch_no, '') AS batch_no
      FROM stock_movements m JOIN products p ON p.id = m.product_id
      LEFT JOIN batches b ON b.id = m.batch_id
      ${where.isEmpty ? '' : 'WHERE ${where.join(' AND ')}'}
      ORDER BY m.created_at DESC, m.id DESC LIMIT $limit
    ''', args);
    return rows.map(StockMovement.fromMap).toList();
  }

  // ============================================================ dashboard

  static Future<Map<String, double>> salesTotals(DateTime from, DateTime toExclusive) async {
    final r = (await _db.rawQuery('''
      SELECT COALESCE(SUM(grand_total), 0) AS total, COUNT(*) AS bills, COALESCE(SUM(item_discount + bill_discount), 0) AS discount
      FROM sales WHERE status = 'completed' AND created_at >= ? AND created_at < ?
    ''', [isoDate(from), isoDate(toExclusive)])).first;
    return {
      'total': (r['total'] as num).toDouble(),
      'bills': (r['bills'] as num).toDouble(),
      'discount': (r['discount'] as num).toDouble(),
    };
  }

  /// Daily totals keyed by yyyy-MM-dd.
  static Future<Map<String, double>> dailySales(DateTime from, DateTime toExclusive) async {
    final rows = await _db.rawQuery('''
      SELECT substr(created_at, 1, 10) AS d, SUM(grand_total) AS total FROM sales
      WHERE status = 'completed' AND created_at >= ? AND created_at < ? GROUP BY d
    ''', [isoDate(from), isoDate(toExclusive)]);
    return {for (final r in rows) r['d'] as String: (r['total'] as num).toDouble()};
  }

  /// Monthly totals keyed by yyyy-MM.
  static Future<Map<String, double>> monthlySales(DateTime from) async {
    final rows = await _db.rawQuery('''
      SELECT substr(created_at, 1, 7) AS m, SUM(grand_total) AS total FROM sales
      WHERE status = 'completed' AND created_at >= ? GROUP BY m
    ''', [isoDate(from)]);
    return {for (final r in rows) r['m'] as String: (r['total'] as num).toDouble()};
  }

  static Future<List<Map<String, Object?>>> topProducts(DateTime from, DateTime toExclusive, {int limit = 6}) => _db.rawQuery('''
      SELECT i.product_id, i.product_name, i.unit_name, i.pack_name, MAX(i.pack_size) AS pack_size,
             SUM(i.qty_units) AS units, SUM(i.amount) AS total
      FROM sale_items i JOIN sales s ON s.id = i.sale_id
      WHERE s.status = 'completed' AND s.created_at >= ? AND s.created_at < ?
      GROUP BY i.product_id ORDER BY total DESC LIMIT $limit
    ''', [isoDate(from), isoDate(toExclusive)]);

  static Future<Map<String, num>> expiryStats(DateTime monthStart, DateTime monthEnd) async {
    final s = Settings.instance;
    final handled = (await _db.rawQuery('''
      SELECT COUNT(*) AS n, COALESCE(SUM(CASE WHEN action IN ('returned','disposed') THEN value END), 0) AS value
      FROM expiry_actions WHERE action != 'acknowledged' AND created_at >= ? AND created_at < ?
    ''', [isoDate(monthStart), isoDate(monthEnd)])).first;
    final counts = (await _db.rawQuery('''
      SELECT
        COUNT(CASE WHEN expiry < ?1 THEN 1 END) AS expired,
        COUNT(CASE WHEN expiry >= ?1 AND expiry <= ?2 THEN 1 END) AS critical,
        COUNT(CASE WHEN expiry > ?2 AND expiry <= ?3 THEN 1 END) AS warn
      FROM batches WHERE status = 'active' AND qty > 0
    ''', [_today, isoDate(today().add(Duration(days: s.criticalDays))), isoDate(today().add(Duration(days: s.warnDays)))])).first;
    return {
      'handled': handled['n'] as num,
      'handled_value': handled['value'] as num,
      'expired': counts['expired'] as num,
      'critical': counts['critical'] as num,
      'warn': counts['warn'] as num,
    };
  }

  static Future<Map<String, num>> inventoryStats() async {
    final r = (await _db.rawQuery('''
      SELECT
        (SELECT COUNT(*) FROM products WHERE active = 1) AS products,
        (SELECT COALESCE(SUM(qty * purchase_rate / pack_size), 0) FROM batches WHERE status = 'active' AND qty > 0) AS stock_value,
        (SELECT COALESCE(SUM(qty * mrp / pack_size), 0) FROM batches WHERE status = 'active' AND qty > 0) AS stock_mrp,
        (SELECT COUNT(*) FROM (
            SELECT p.id FROM products p LEFT JOIN batches b ON b.product_id = p.id AND b.status = 'active' AND b.expiry >= ?1
            WHERE p.active = 1 AND p.reorder_level > 0 GROUP BY p.id HAVING COALESCE(SUM(b.qty), 0) <= p.reorder_level)) AS low_stock
    ''', [_today])).first;
    return {for (final e in r.entries) e.key: e.value as num};
  }
}
