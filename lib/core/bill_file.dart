import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart' show getCrc32;
import 'package:path/path.dart' as p;

import '../models/models.dart';
import 'db.dart';
import 'format.dart';
import 'settings.dart';

/// A complete, self-contained bill: shop details at the time of billing
/// plus the sale and its items. This is what the medical copy stores.
class BillDocument {
  final Map<String, String> shop;
  final Sale sale;
  final DateTime savedAt;

  BillDocument({required this.shop, required this.sale, DateTime? savedAt}) : savedAt = savedAt ?? DateTime.now();

  factory BillDocument.fromSale(Sale sale) => BillDocument(shop: Settings.instance.shopSnapshot(), sale: sale);

  Map<String, Object?> toJson() => {
        'app': 'MedBillings',
        'saved_at': isoDateTime(savedAt),
        'shop': shop,
        'sale': sale.toMap(),
        'items': sale.items.map((i) => i.toMap()).toList(),
      };

  factory BillDocument.fromJson(Map<String, Object?> j) {
    final sale = Sale.fromMap((j['sale'] as Map).cast<String, Object?>());
    sale.items = ((j['items'] as List?) ?? []).map((m) => SaleItem.fromMap((m as Map).cast<String, Object?>())).toList();
    sale.itemCount = sale.items.length;
    return BillDocument(
      shop: ((j['shop'] as Map?) ?? {}).map((k, v) => MapEntry(k as String, '${v ?? ''}')),
      sale: sale,
      savedAt: DateTime.tryParse('${j['saved_at']}'),
    );
  }
}

class BillFileException implements Exception {
  final String message;
  BillFileException(this.message);
  @override
  String toString() => message;
}

/// `.mbill` — MedBillings bill file.
///
/// Layout (little-endian):
///   0  4  magic "MBIL"
///   4  1  format version
///   5  3  reserved
///   8  4  payload length
///  12  4  CRC-32 of payload
///  16  n  payload = gzip(UTF-8 JSON of [BillDocument])
///
/// A typical bill is well under 1 KB on disk.
class BillFile {
  static const extension = 'mbill';
  static const _magic = [0x4D, 0x42, 0x49, 0x4C];
  static const _version = 1;

  static Uint8List encode(BillDocument doc) {
    final payload = gzip.encode(utf8.encode(jsonEncode(doc.toJson())));
    final header = ByteData(16);
    for (var i = 0; i < 4; i++) {
      header.setUint8(i, _magic[i]);
    }
    header.setUint8(4, _version);
    header.setUint32(8, payload.length, Endian.little);
    header.setUint32(12, getCrc32(payload), Endian.little);
    return Uint8List.fromList([...header.buffer.asUint8List(), ...payload]);
  }

  static BillDocument decode(Uint8List bytes) {
    if (bytes.length < 16) throw BillFileException('Not a bill file (too small)');
    for (var i = 0; i < 4; i++) {
      if (bytes[i] != _magic[i]) throw BillFileException('Not a MedBillings bill file');
    }
    final version = bytes[4];
    if (version > _version) throw BillFileException('This bill was saved by a newer version of MedBillings');
    final header = ByteData.sublistView(bytes, 0, 16);
    final len = header.getUint32(8, Endian.little);
    final crc = header.getUint32(12, Endian.little);
    if (bytes.length < 16 + len) throw BillFileException('Bill file is truncated');
    final payload = bytes.sublist(16, 16 + len);
    if (getCrc32(payload) != crc) throw BillFileException('Bill file is damaged (checksum mismatch)');
    final json = jsonDecode(utf8.decode(gzip.decode(payload)));
    return BillDocument.fromJson((json as Map).cast<String, Object?>());
  }

  static String _safe(String s) => s.replaceAll(RegExp(r'[^A-Za-z0-9_\-]+'), '_');

  /// Writes the medical copy to `Bills/yyyy/MM/<billNo>.mbill` and returns the path.
  static Future<String> save(BillDocument doc) async {
    final d = doc.sale.createdAt;
    final dir = Directory(p.join(AppPaths.billsDir.path, '${d.year}', d.month.toString().padLeft(2, '0')));
    if (!dir.existsSync()) dir.createSync(recursive: true);
    final file = File(p.join(dir.path, '${_safe(doc.sale.billNo)}.$extension'));
    await file.writeAsBytes(encode(doc), flush: true);
    return file.path;
  }

  static Future<BillDocument> read(String path) async => decode(await File(path).readAsBytes());
}
