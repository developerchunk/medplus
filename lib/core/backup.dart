import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;

import '../data/repo.dart';
import '../models/models.dart';
import 'db.dart';
import 'format.dart';
import 'settings.dart';

/// Full backups (`.mbak` = zip of the database + all saved bill files)
/// and CSV exports that open in Excel.
class BackupService {
  static const extension = 'mbak';

  static Future<Uint8List> _buildBackup() async {
    final tmp = File(p.join(Directory.systemTemp.path, 'medbillings_backup_${DateTime.now().millisecondsSinceEpoch}.db'));
    if (tmp.existsSync()) tmp.deleteSync();
    // VACUUM INTO gives a consistent, compact snapshot while the app keeps running.
    await AppDb.db.execute('VACUUM INTO ?', [tmp.path]);
    final archive = Archive();
    final manifest = {
      'app': 'MedBillings',
      'format': 1,
      'created_at': isoDateTime(DateTime.now()),
      'shop_name': Settings.instance.shopName,
      'schema': AppDb.schemaVersion,
    };
    archive.addFile(ArchiveFile.string('manifest.json', jsonEncode(manifest)));
    archive.addFile(ArchiveFile.bytes('data/medbillings.db', await tmp.readAsBytes()));
    tmp.deleteSync();
    final bills = AppPaths.billsDir;
    if (bills.existsSync()) {
      for (final f in bills.listSync(recursive: true).whereType<File>()) {
        if (!f.path.endsWith('.mbill')) continue;
        final rel = p.relative(f.path, from: AppPaths.root.path).replaceAll('\\', '/');
        archive.addFile(ArchiveFile.bytes(rel, await f.readAsBytes()));
      }
    }
    return ZipEncoder().encodeBytes(archive);
  }

  static String _stamp() => DateTime.now().toIso8601String().substring(0, 16).replaceAll(RegExp(r'[:T]'), '-');

  /// Asks where to save and writes a full backup. Returns the saved path.
  static Future<String?> exportBackup() async {
    final bytes = await _buildBackup();
    final uri = await FilePicker.saveFile(
      dialogTitle: 'Save MedBillings backup',
      fileName: 'MedBillings_Backup_${_stamp()}.$extension',
      bytes: bytes,
      type: FileType.custom,
      allowedExtensions: [extension],
    );
    return uri?.toFilePath();
  }

  /// Quick backup into the app's own Backups folder (no dialog).
  static Future<String> quickBackup() async {
    final bytes = await _buildBackup();
    final f = File(p.join(AppPaths.backupsDir.path, 'MedBillings_Backup_${_stamp()}.$extension'));
    await f.writeAsBytes(bytes, flush: true);
    return f.path;
  }

  /// Replaces all current data with a backup. A safety backup of the current
  /// data is written to the Backups folder first.
  static Future<String> restoreBackup(String path) async {
    final archive = ZipDecoder().decodeBytes(await File(path).readAsBytes());
    final manifestFile = archive.findFile('manifest.json');
    final dbFile = archive.findFile('data/medbillings.db');
    if (manifestFile == null || dbFile == null) throw Exception('This is not a MedBillings backup file');
    final manifest = jsonDecode(utf8.decode(manifestFile.readBytes()!)) as Map;
    if (manifest['app'] != 'MedBillings') throw Exception('This is not a MedBillings backup file');

    final safety = await quickBackup();
    await AppDb.close();
    for (final suffix in ['', '-wal', '-shm']) {
      final f = File('${AppPaths.dbFile}$suffix');
      if (f.existsSync()) f.deleteSync();
    }
    await File(AppPaths.dbFile).writeAsBytes(dbFile.readBytes()!, flush: true);
    for (final f in archive.files) {
      if (!f.isFile || !f.name.startsWith('Bills/')) continue;
      final out = File(p.normalize(p.join(AppPaths.root.path, f.name)));
      if (!p.isWithin(AppPaths.root.path, out.path)) continue;
      out.parent.createSync(recursive: true);
      await out.writeAsBytes(f.readBytes()!);
    }
    await AppDb.open();
    // Bill file paths inside the DB may point at another computer's folders.
    await _relinkBillFiles();
    await Settings.instance.load();
    notifyDataChanged();
    return safety;
  }

  static Future<void> _relinkBillFiles() async {
    final rows = await AppDb.db.query('sales', columns: ['id', 'bill_no', 'created_at', 'file_path']);
    final batch = AppDb.db.batch();
    for (final r in rows) {
      final fp = r['file_path'] as String? ?? '';
      if (fp.isNotEmpty && File(fp).existsSync()) continue;
      final created = DateTime.tryParse(r['created_at'] as String) ?? DateTime.now();
      final name = '${(r['bill_no'] as String).replaceAll(RegExp(r'[^A-Za-z0-9_\-]+'), '_')}.mbill';
      final candidate = p.join(AppPaths.billsDir.path, '${created.year}', created.month.toString().padLeft(2, '0'), name);
      batch.update('sales', {'file_path': File(candidate).existsSync() ? candidate : ''}, where: 'id = ?', whereArgs: [r['id']]);
    }
    await batch.commit(noResult: true);
  }

  // ------------------------------------------------------------ CSV

  static String _csvCell(Object? v) {
    final s = '${v ?? ''}';
    if (s.contains(',') || s.contains('"') || s.contains('\n')) return '"${s.replaceAll('"', '""')}"';
    return s;
  }

  static String toCsv(List<String> headers, List<List<Object?>> rows) =>
      '﻿${[headers, ...rows].map((r) => r.map(_csvCell).join(',')).join('\r\n')}\r\n';

  static Future<String?> _saveCsv(String name, String csv) async {
    final uri = await FilePicker.saveFile(
      dialogTitle: 'Export CSV',
      fileName: '$name.csv',
      bytes: Uint8List.fromList(utf8.encode(csv)),
      mimeType: 'text/csv',
      type: FileType.custom,
      allowedExtensions: ['csv'],
    );
    return uri?.toFilePath();
  }

  static Future<String?> exportStockCsv() async {
    final rows = await AppDb.db.rawQuery('''
      SELECT p.name, p.generic_name, p.manufacturer, p.form, p.schedule, b.batch_no, b.expiry, b.pack_size,
             b.qty, b.mrp, b.sale_rate, b.purchase_rate, b.gst_rate, COALESCE(s.name, '') AS supplier, p.rack
      FROM batches b JOIN products p ON p.id = b.product_id LEFT JOIN suppliers s ON s.id = b.supplier_id
      WHERE b.status = 'active' AND b.qty > 0 ORDER BY p.name COLLATE NOCASE, b.expiry
    ''');
    return _saveCsv(
      'MedBillings_Stock_${isoDate(DateTime.now())}',
      toCsv(
        ['Medicine', 'Generic', 'Manufacturer', 'Form', 'Schedule', 'Batch', 'Expiry', 'Pack size', 'Qty (units)', 'Qty (packs)', 'MRP/pack', 'Sale rate/pack', 'Purchase rate/pack', 'GST %', 'Supplier', 'Rack'],
        rows
            .map((r) => [
                  r['name'], r['generic_name'], r['manufacturer'], r['form'], r['schedule'], r['batch_no'], r['expiry'], r['pack_size'], r['qty'],
                  packsDecimal(r['qty'] as int, r['pack_size'] as int), r['mrp'], r['sale_rate'], r['purchase_rate'], r['gst_rate'], r['supplier'], r['rack'],
                ])
            .toList(),
      ),
    );
  }

  static Future<String?> exportSalesCsv(DateTime from, DateTime to) async {
    final sales = await Repo.sales(from: from, to: to);
    return _saveCsv(
      'MedBillings_Sales_${isoDate(from)}_to_${isoDate(to)}',
      toCsv(
        ['Bill No', 'Date', 'Time', 'Patient', 'Mobile', 'Doctor', 'Doctor Reg', 'Items', 'Gross', 'Discount', 'Taxable', 'GST', 'Round off', 'Net', 'Payment', 'Status'],
        sales
            .map((s) => [
                  s.billNo, isoDate(s.createdAt), fmtTime(s.createdAt), s.customerName, s.customerPhone, s.doctorName, s.doctorRegNo, s.itemCount,
                  s.grossTotal, round2(s.totalDiscount), s.taxableTotal, s.gstTotal, s.roundOff, s.grandTotal, s.paymentMode, s.status,
                ])
            .toList(),
      ),
    );
  }

  static Future<String?> exportSaleItemsCsv(DateTime from, DateTime to) async {
    final rows = await AppDb.db.rawQuery('''
      SELECT s.bill_no, s.created_at, s.customer_name, s.doctor_name, i.product_name, i.batch_no, i.expiry, i.qty_units,
             i.pack_size, i.mrp, i.unit_rate, i.discount_pct, i.gst_rate, i.amount, i.rx
      FROM sale_items i JOIN sales s ON s.id = i.sale_id
      WHERE s.status = 'completed' AND s.created_at >= ? AND s.created_at < ? ORDER BY s.created_at, i.id
    ''', [isoDate(from), isoDate(to.add(const Duration(days: 1)))]);
    return _saveCsv(
      'MedBillings_SaleItems_${isoDate(from)}_to_${isoDate(to)}',
      toCsv(
        ['Bill No', 'Date', 'Patient', 'Doctor', 'Medicine', 'Batch', 'Expiry', 'Qty (units)', 'Pack size', 'MRP/pack', 'Rate/unit', 'Disc %', 'GST %', 'Amount', 'Rx'],
        rows
            .map((r) => [
                  r['bill_no'], (r['created_at'] as String).replaceFirst('T', ' '), r['customer_name'], r['doctor_name'], r['product_name'], r['batch_no'],
                  r['expiry'], r['qty_units'], r['pack_size'], r['mrp'], r['unit_rate'], r['discount_pct'], r['gst_rate'], r['amount'], r['rx'] == 1 ? 'Yes' : '',
                ])
            .toList(),
      ),
    );
  }

  static Future<String?> exportProductsCsv() async {
    final rows = await AppDb.db.query('products', where: 'active = 1', orderBy: 'name COLLATE NOCASE');
    return _saveCsv('MedBillings_Medicines', toCsv(_productCols, rows.map((r) => _productCols.map((c) => r[c]).toList()).toList()));
  }

  static const _productCols = [
    'name', 'generic_name', 'manufacturer', 'form', 'unit_name', 'pack_name', 'pack_size', 'outer_name', 'outer_size', 'hsn', 'gst_rate',
    'schedule', 'rx_required', 'is_antibiotic', 'instructions', 'rack', 'reorder_level',
  ];

  static List<List<String>> parseCsv(String text) {
    final rows = <List<String>>[];
    var row = <String>[];
    final cell = StringBuffer();
    var quoted = false;
    for (var i = 0; i < text.length; i++) {
      final c = text[i];
      if (quoted) {
        if (c == '"') {
          if (i + 1 < text.length && text[i + 1] == '"') {
            cell.write('"');
            i++;
          } else {
            quoted = false;
          }
        } else {
          cell.write(c);
        }
      } else if (c == '"') {
        quoted = true;
      } else if (c == ',') {
        row.add(cell.toString());
        cell.clear();
      } else if (c == '\n' || c == '\r') {
        if (c == '\r' && i + 1 < text.length && text[i + 1] == '\n') i++;
        row.add(cell.toString());
        cell.clear();
        if (row.any((x) => x.trim().isNotEmpty)) rows.add(row);
        row = <String>[];
      } else {
        cell.write(c);
      }
    }
    if (cell.isNotEmpty || row.isNotEmpty) {
      row.add(cell.toString());
      if (row.any((x) => x.trim().isNotEmpty)) rows.add(row);
    }
    return rows;
  }

  /// Imports the medicine master from CSV (same columns as the export;
  /// only `name` is required). Existing names are updated, not duplicated.
  static Future<({int added, int updated})> importProductsCsv() async {
    final file = await FilePicker.pickFile(dialogTitle: 'Import medicines CSV', type: FileType.custom, allowedExtensions: ['csv']);
    final path = file?.path;
    if (path == null) return (added: 0, updated: 0);
    final rows = parseCsv(utf8.decode(await File(path).readAsBytes(), allowMalformed: true).replaceFirst('﻿', ''));
    if (rows.isEmpty) return (added: 0, updated: 0);
    final header = rows.first.map((h) => h.trim().toLowerCase().replaceAll(' ', '_')).toList();
    final nameIdx = header.indexOf('name');
    if (nameIdx < 0) throw Exception('CSV must have a "name" column');
    var added = 0, updated = 0;
    for (final r in rows.skip(1)) {
      String col(String c) {
        final i = header.indexOf(c);
        return i >= 0 && i < r.length ? r[i].trim() : '';
      }

      final name = col('name');
      if (name.isEmpty) continue;
      final form = ProductForm.of(col('form').isEmpty ? 'Tablet' : col('form'));
      final existing = await AppDb.db.query('products', where: 'name = ? COLLATE NOCASE', whereArgs: [name], limit: 1);
      final prod = existing.isEmpty ? Product(name: name) : Product.fromMap(existing.first);
      bool truthy(String v) => ['1', 'yes', 'y', 'true'].contains(v.toLowerCase());
      if (col('generic_name').isNotEmpty) prod.genericName = col('generic_name');
      if (col('manufacturer').isNotEmpty) prod.manufacturer = col('manufacturer');
      if (col('form').isNotEmpty || existing.isEmpty) {
        prod.form = form.name;
        prod.unitName = col('unit_name').isEmpty ? form.unit : col('unit_name');
        prod.packName = col('pack_name').isEmpty ? form.pack : col('pack_name');
        prod.packSize = int.tryParse(col('pack_size')) ?? form.packSize;
      }
      if (col('outer_size').isNotEmpty) {
        prod.outerSize = int.tryParse(col('outer_size')) ?? 0;
        prod.outerName = col('outer_name').isEmpty ? 'Box' : col('outer_name');
      }
      if (col('hsn').isNotEmpty) prod.hsn = col('hsn');
      if (col('gst_rate').isNotEmpty) prod.gstRate = parseNum(col('gst_rate'), 5);
      if (col('schedule').isNotEmpty) prod.schedule = col('schedule').toUpperCase();
      if (col('rx_required').isNotEmpty) prod.rxRequired = truthy(col('rx_required'));
      if (col('is_antibiotic').isNotEmpty) prod.isAntibiotic = truthy(col('is_antibiotic'));
      if (col('instructions').isNotEmpty) prod.instructions = col('instructions');
      if (col('rack').isNotEmpty) prod.rack = col('rack');
      if (col('reorder_level').isNotEmpty) prod.reorderLevel = int.tryParse(col('reorder_level')) ?? 0;
      prod.active = true;
      await Repo.saveProduct(prod);
      existing.isEmpty ? added++ : updated++;
    }
    return (added: added, updated: updated);
  }
}
