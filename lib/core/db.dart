import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Where everything lives on disk. All data is local.
class AppPaths {
  static late Directory root;

  static String get dbFile => p.join(root.path, 'data', 'medbillings.db');
  static Directory get billsDir => Directory(p.join(root.path, 'Bills'));
  static Directory get backupsDir => Directory(p.join(root.path, 'Backups'));

  static Future<void> init() async {
    // MEDBILLINGS_DATA_DIR lets the data folder live elsewhere (e.g. a shared drive or a test copy).
    final custom = Platform.environment['MEDBILLINGS_DATA_DIR'];
    if (custom != null && custom.isNotEmpty) {
      root = Directory(custom);
    } else {
      final docs = await getApplicationDocumentsDirectory();
      root = Directory(p.join(docs.path, 'MedBillings'));
    }
    for (final d in [root, Directory(p.join(root.path, 'data')), billsDir, backupsDir]) {
      if (!d.existsSync()) d.createSync(recursive: true);
    }
  }
}

/// Bumped after every write so screens know to reload.
final dataVersion = ValueNotifier<int>(0);
void notifyDataChanged() => dataVersion.value++;

class AppDb {
  AppDb._();
  static Database? _db;
  static const schemaVersion = 5;

  static Database get db {
    final d = _db;
    if (d == null) throw StateError('Database not opened');
    return d;
  }

  static Future<void> open() async {
    sqfliteFfiInit();
    _db = await databaseFactoryFfi.openDatabase(
      AppPaths.dbFile,
      options: OpenDatabaseOptions(
        version: schemaVersion,
        onConfigure: (db) async {
          await db.execute('PRAGMA foreign_keys = ON');
          await db.execute('PRAGMA journal_mode = WAL');
        },
        onCreate: (db, version) async {
          final batch = db.batch();
          for (final stmt in _schema) {
            batch.execute(stmt);
          }
          await batch.commit(noResult: true);
        },
        onUpgrade: (db, from, to) async {
          if (from < 2) {
            // v2: credit accounts for regular customers.
            await db.execute("ALTER TABLE customers ADD COLUMN credit_allowed INTEGER DEFAULT 0");
            await db.execute("ALTER TABLE customers ADD COLUMN credit_limit REAL DEFAULT 0");
            await db.execute("ALTER TABLE customers ADD COLUMN notes TEXT DEFAULT ''");
            await db.execute("ALTER TABLE sales ADD COLUMN paid_amount REAL DEFAULT 0");
            await db.execute("UPDATE sales SET paid_amount = grand_total WHERE payment_mode != 'Credit'");
            await db.execute("UPDATE customers SET credit_allowed = 1 WHERE id IN (SELECT customer_id FROM sales WHERE payment_mode = 'Credit')");
            await db.execute(_creditPayments);
            await db.execute(_creditPaymentsIdx);
          }
          if (from < 3) {
            // v3: outer pack level (e.g. strips per box).
            await db.execute("ALTER TABLE products ADD COLUMN outer_name TEXT DEFAULT ''");
            await db.execute('ALTER TABLE products ADD COLUMN outer_size INTEGER DEFAULT 0');
          }
          if (from < 4) {
            // v4: remember when a stock-entry line was bought as full boxes.
            await db.execute('ALTER TABLE purchase_items ADD COLUMN box_qty INTEGER DEFAULT 0');
            await db.execute('ALTER TABLE purchase_items ADD COLUMN box_size INTEGER DEFAULT 0');
          }
          if (from < 5) {
            // v5: free goods on a box line can be whole boxes.
            await db.execute('ALTER TABLE purchase_items ADD COLUMN free_boxes INTEGER DEFAULT 0');
          }
        },
      ),
    );
  }

  static Future<void> close() async {
    final d = _db;
    _db = null;
    if (d != null) {
      // Fold the WAL into the main file so a copied .db is complete.
      try {
        await d.execute('PRAGMA wal_checkpoint(TRUNCATE)');
      } catch (_) {}
      await d.close();
    }
  }

  static const _creditPayments = '''CREATE TABLE credit_payments(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      customer_id INTEGER NOT NULL REFERENCES customers(id) ON DELETE CASCADE,
      created_at TEXT NOT NULL,
      amount REAL NOT NULL,
      mode TEXT DEFAULT 'Cash',
      note TEXT DEFAULT ''
    )''';
  static const _creditPaymentsIdx = 'CREATE INDEX idx_credit_payments_customer ON credit_payments(customer_id)';

  static const _schema = <String>[
    '''CREATE TABLE settings(
      key TEXT PRIMARY KEY,
      value TEXT NOT NULL
    )''',
    '''CREATE TABLE suppliers(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      contact_person TEXT DEFAULT '',
      phone TEXT DEFAULT '',
      email TEXT DEFAULT '',
      address TEXT DEFAULT '',
      gstin TEXT DEFAULT '',
      drug_license TEXT DEFAULT '',
      notes TEXT DEFAULT '',
      created_at TEXT
    )''',
    '''CREATE TABLE products(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      generic_name TEXT DEFAULT '',
      manufacturer TEXT DEFAULT '',
      form TEXT DEFAULT 'Tablet',
      unit_name TEXT DEFAULT 'Tab',
      pack_name TEXT DEFAULT 'Strip',
      pack_size INTEGER NOT NULL DEFAULT 1,
      outer_name TEXT DEFAULT '',
      outer_size INTEGER DEFAULT 0,
      hsn TEXT DEFAULT '',
      gst_rate REAL DEFAULT 5,
      schedule TEXT DEFAULT '',
      rx_required INTEGER DEFAULT 0,
      is_antibiotic INTEGER DEFAULT 0,
      instructions TEXT DEFAULT '',
      rack TEXT DEFAULT '',
      reorder_level INTEGER DEFAULT 0,
      active INTEGER DEFAULT 1,
      created_at TEXT
    )''',
    'CREATE INDEX idx_products_name ON products(name COLLATE NOCASE)',
    '''CREATE TABLE purchases(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      supplier_id INTEGER REFERENCES suppliers(id) ON DELETE SET NULL,
      invoice_no TEXT DEFAULT '',
      invoice_date TEXT,
      created_at TEXT,
      gross_total REAL DEFAULT 0,
      discount_total REAL DEFAULT 0,
      gst_total REAL DEFAULT 0,
      net_total REAL DEFAULT 0,
      paid INTEGER DEFAULT 1,
      notes TEXT DEFAULT ''
    )''',
    '''CREATE TABLE batches(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      product_id INTEGER NOT NULL REFERENCES products(id) ON DELETE CASCADE,
      batch_no TEXT NOT NULL,
      mfg_date TEXT,
      expiry TEXT NOT NULL,
      pack_size INTEGER NOT NULL DEFAULT 1,
      mrp REAL NOT NULL DEFAULT 0,
      purchase_rate REAL DEFAULT 0,
      sale_rate REAL DEFAULT 0,
      gst_rate REAL DEFAULT 0,
      discount_pct REAL DEFAULT 0,
      qty INTEGER NOT NULL DEFAULT 0,
      initial_qty INTEGER DEFAULT 0,
      supplier_id INTEGER REFERENCES suppliers(id) ON DELETE SET NULL,
      purchase_id INTEGER REFERENCES purchases(id) ON DELETE SET NULL,
      status TEXT DEFAULT 'active',
      created_at TEXT
    )''',
    'CREATE INDEX idx_batches_product ON batches(product_id)',
    'CREATE INDEX idx_batches_expiry ON batches(expiry)',
    '''CREATE TABLE purchase_items(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      purchase_id INTEGER NOT NULL REFERENCES purchases(id) ON DELETE CASCADE,
      product_id INTEGER NOT NULL REFERENCES products(id),
      product_name TEXT,
      batch_id INTEGER REFERENCES batches(id) ON DELETE SET NULL,
      batch_no TEXT,
      mfg_date TEXT,
      expiry TEXT,
      pack_size INTEGER,
      qty_packs INTEGER,
      free_packs INTEGER DEFAULT 0,
      purchase_rate REAL,
      mrp REAL,
      sale_rate REAL,
      gst_rate REAL,
      discount_pct REAL DEFAULT 0,
      amount REAL,
      box_qty INTEGER DEFAULT 0,
      box_size INTEGER DEFAULT 0,
      free_boxes INTEGER DEFAULT 0
    )''',
    '''CREATE TABLE doctors(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      qualification TEXT DEFAULT '',
      reg_no TEXT DEFAULT '',
      clinic TEXT DEFAULT '',
      phone TEXT DEFAULT '',
      created_at TEXT
    )''',
    '''CREATE TABLE customers(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      phone TEXT DEFAULT '',
      address TEXT DEFAULT '',
      credit_allowed INTEGER DEFAULT 0,
      credit_limit REAL DEFAULT 0,
      notes TEXT DEFAULT '',
      created_at TEXT
    )''',
    _creditPayments,
    _creditPaymentsIdx,
    '''CREATE TABLE sales(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      bill_no TEXT NOT NULL UNIQUE,
      created_at TEXT NOT NULL,
      customer_id INTEGER REFERENCES customers(id) ON DELETE SET NULL,
      customer_name TEXT DEFAULT '',
      customer_phone TEXT DEFAULT '',
      customer_address TEXT DEFAULT '',
      doctor_id INTEGER REFERENCES doctors(id) ON DELETE SET NULL,
      doctor_name TEXT DEFAULT '',
      doctor_reg_no TEXT DEFAULT '',
      doctor_clinic TEXT DEFAULT '',
      rx_notes TEXT DEFAULT '',
      payment_mode TEXT DEFAULT 'Cash',
      gross_total REAL DEFAULT 0,
      item_discount REAL DEFAULT 0,
      bill_discount_pct REAL DEFAULT 0,
      bill_discount REAL DEFAULT 0,
      taxable_total REAL DEFAULT 0,
      gst_total REAL DEFAULT 0,
      round_off REAL DEFAULT 0,
      grand_total REAL DEFAULT 0,
      paid_amount REAL DEFAULT 0,
      status TEXT DEFAULT 'completed',
      cancel_reason TEXT DEFAULT '',
      file_path TEXT DEFAULT '',
      template_code TEXT DEFAULT ''
    )''',
    'CREATE INDEX idx_sales_created ON sales(created_at)',
    '''CREATE TABLE sale_items(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      sale_id INTEGER NOT NULL REFERENCES sales(id) ON DELETE CASCADE,
      product_id INTEGER NOT NULL,
      batch_id INTEGER NOT NULL,
      product_name TEXT,
      form TEXT,
      batch_no TEXT,
      expiry TEXT,
      pack_size INTEGER,
      unit_name TEXT,
      pack_name TEXT,
      qty_units INTEGER,
      mrp REAL,
      unit_rate REAL,
      discount_pct REAL,
      gst_rate REAL,
      amount REAL,
      hsn TEXT,
      rx INTEGER DEFAULT 0
    )''',
    'CREATE INDEX idx_sale_items_sale ON sale_items(sale_id)',
    '''CREATE TABLE stock_movements(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      created_at TEXT NOT NULL,
      product_id INTEGER NOT NULL,
      batch_id INTEGER,
      type TEXT NOT NULL,
      qty INTEGER NOT NULL,
      ref_type TEXT DEFAULT '',
      ref_id INTEGER,
      ref_label TEXT DEFAULT '',
      note TEXT DEFAULT ''
    )''',
    'CREATE INDEX idx_mov_created ON stock_movements(created_at)',
    'CREATE INDEX idx_mov_product ON stock_movements(product_id)',
    '''CREATE TABLE templates(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      code TEXT NOT NULL UNIQUE COLLATE NOCASE,
      name TEXT NOT NULL,
      description TEXT DEFAULT '',
      doctor_name TEXT DEFAULT '',
      created_at TEXT,
      updated_at TEXT
    )''',
    '''CREATE TABLE template_items(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      template_id INTEGER NOT NULL REFERENCES templates(id) ON DELETE CASCADE,
      product_id INTEGER NOT NULL REFERENCES products(id) ON DELETE CASCADE,
      qty_units INTEGER NOT NULL,
      sort INTEGER DEFAULT 0
    )''',
    '''CREATE TABLE expiry_actions(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      created_at TEXT NOT NULL,
      batch_id INTEGER REFERENCES batches(id) ON DELETE SET NULL,
      product_id INTEGER,
      action TEXT NOT NULL,
      qty INTEGER DEFAULT 0,
      value REAL DEFAULT 0,
      note TEXT DEFAULT ''
    )''',
  ];
}
