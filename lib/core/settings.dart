import 'package:flutter/material.dart';

import 'db.dart';

/// Key/value shop settings persisted in the `settings` table.
class Settings extends ChangeNotifier {
  Settings._();
  static final instance = Settings._();

  final Map<String, String> _v = {};

  static const defaults = <String, String>{
    'shop_name': 'My Medical Store',
    'shop_tagline': 'Chemist & Druggist',
    'address': '',
    'phone': '',
    'email': '',
    'gstin': '',
    'dl_no': '',
    'pharmacist_name': '',
    'pharmacist_reg': '',
    'bill_prefix': 'B-',
    'next_bill_seq': '1',
    'paper': 'A5',
    'printer_url': '',
    'printer_name': '',
    'print_on_save': 'true',
    'gst_enabled': 'false', // small shops needn't register for GST; bills then carry no GST
    'footer_note': 'Get well soon! Medicines once sold will be taken back only with the bill, within 7 days, if unopened.',
    'expiry_warn_days': '60',
    'expiry_critical_days': '30',
    'last_expiry_alert': '',
    'theme_mode': 'light',
    'require_doctor_for_rx': 'true',
    'default_doctor_id': '',
  };

  Future<void> load() async {
    _v
      ..clear()
      ..addAll(defaults);
    final rows = await AppDb.db.query('settings');
    for (final r in rows) {
      _v[r['key'] as String] = r['value'] as String;
    }
    notifyListeners();
  }

  String get(String key) => _v[key] ?? defaults[key] ?? '';
  bool flag(String key) => get(key) == 'true';
  int integer(String key) => int.tryParse(get(key)) ?? int.tryParse(defaults[key] ?? '') ?? 0;

  Future<void> set(String key, String value) => setAll({key: value});

  Future<void> setAll(Map<String, String> values) async {
    final batch = AppDb.db.batch();
    values.forEach((k, v) {
      _v[k] = v;
      batch.rawInsert('INSERT OR REPLACE INTO settings(key, value) VALUES(?, ?)', [k, v]);
    });
    await batch.commit(noResult: true);
    notifyListeners();
  }

  String get shopName => get('shop_name');
  bool get gstEnabled => flag('gst_enabled');
  int get warnDays => integer('expiry_warn_days');
  int get criticalDays => integer('expiry_critical_days');

  ThemeMode get themeMode => switch (get('theme_mode')) {
        'dark' => ThemeMode.dark,
        'system' => ThemeMode.system,
        _ => ThemeMode.light,
      };

  /// Snapshot of shop details embedded into every saved bill file so the
  /// medical copy stays accurate even if settings change later.
  Map<String, String> shopSnapshot() => {
        for (final k in ['shop_name', 'shop_tagline', 'address', 'phone', 'email', 'gstin', 'dl_no', 'pharmacist_name', 'pharmacist_reg', 'footer_note'])
          k: get(k),
      };
}
