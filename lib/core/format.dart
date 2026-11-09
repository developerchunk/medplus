import 'package:intl/intl.dart';

final _inr = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 2);
final _inr0 = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);
final _plain = NumberFormat('#,##,##0.00', 'en_IN');
final _int = NumberFormat('#,##,##0', 'en_IN');

String money(num v) => _inr.format(v);
String money0(num v) => _inr0.format(v);
String amount(num v) => _plain.format(v);
String intFmt(num v) => _int.format(v);

/// Short money for chart axes: ₹950, ₹1.2K, ₹3.4L.
String moneyShort(num v) {
  final a = v.abs();
  if (a >= 10000000) return '₹${(v / 10000000).toStringAsFixed(1)}Cr';
  if (a >= 100000) return '₹${(v / 100000).toStringAsFixed(1)}L';
  if (a >= 1000) return '₹${(v / 1000).toStringAsFixed(1)}K';
  return '₹${v.toStringAsFixed(0)}';
}

double round2(num v) => (v * 100).roundToDouble() / 100;

/// Trims trailing zeros: 12.50 -> 12.5, 5.00 -> 5.
String trimNum(num v) {
  if (v == v.roundToDouble()) return v.toInt().toString();
  return v.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '');
}

double parseNum(String s, [double fallback = 0]) =>
    double.tryParse(s.trim().replaceAll(',', '')) ?? fallback;

// ---------------------------------------------------------------- dates

final _dmy = DateFormat('dd MMM yyyy');
final _dmyShort = DateFormat('dd/MM/yy');
final _dmyt = DateFormat('dd MMM yyyy, hh:mm a');
final _time = DateFormat('hh:mm a');
final _iso = DateFormat('yyyy-MM-dd');
final _isoT = DateFormat("yyyy-MM-dd'T'HH:mm:ss");
final _my = DateFormat('MM/yy');
final _dmyInput = DateFormat('dd/MM/yyyy');

String fmtDate(DateTime d) => _dmy.format(d);
String fmtDateShort(DateTime d) => _dmyShort.format(d);
String fmtDateTime(DateTime d) => _dmyt.format(d);
String fmtTime(DateTime d) => _time.format(d);
String isoDate(DateTime d) => _iso.format(d);
String isoDateTime(DateTime d) => _isoT.format(d);
String fmtExpiry(DateTime d) => _my.format(d);
String fmtDateInput(DateTime d) => _dmyInput.format(d);

DateTime today() {
  final n = DateTime.now();
  return DateTime(n.year, n.month, n.day);
}

DateTime lastDayOfMonth(int year, int month) => DateTime(year, month + 1, 0);

/// Parses what a biller types for expiry / mfg dates.
/// Accepts MM/YY, MM/YYYY, MM-YY, MMYY, DD/MM/YYYY and yyyy-MM-dd.
/// Month-only values resolve to the last day of that month for expiry
/// ([endOfMonth] = true) or the first day for manufacturing dates.
DateTime? parseMonthYear(String input, {bool endOfMonth = true}) {
  final s = input.trim();
  if (s.isEmpty) return null;
  final iso = DateTime.tryParse(s);
  if (iso != null && s.contains('-') && s.length >= 8) return iso;
  final parts = s.split(RegExp(r'[/\-. ]+')).where((p) => p.isNotEmpty).toList();
  int? d, m, y;
  if (parts.length == 1 && RegExp(r'^\d{4}$').hasMatch(parts[0])) {
    m = int.parse(parts[0].substring(0, 2));
    y = int.parse(parts[0].substring(2));
  } else if (parts.length == 1 && RegExp(r'^\d{6}$').hasMatch(parts[0])) {
    m = int.parse(parts[0].substring(0, 2));
    y = int.parse(parts[0].substring(2));
  } else if (parts.length == 2) {
    m = int.tryParse(parts[0]);
    y = int.tryParse(parts[1]);
  } else if (parts.length == 3) {
    d = int.tryParse(parts[0]);
    m = int.tryParse(parts[1]);
    y = int.tryParse(parts[2]);
  }
  if (m == null || y == null || m < 1 || m > 12) return null;
  if (y < 100) y += 2000;
  if (y < 2000 || y > 2100) return null;
  if (d != null) {
    final dt = DateTime(y, m, d);
    if (dt.month != m) return null;
    return dt;
  }
  return endOfMonth ? lastDayOfMonth(y, m) : DateTime(y, m, 1);
}

int daysUntil(DateTime d) => DateTime(d.year, d.month, d.day).difference(today()).inDays;

String expiryPhrase(DateTime exp) {
  final days = daysUntil(exp);
  if (days < 0) return 'Expired ${-days}d ago';
  if (days == 0) return 'Expires today';
  if (days < 31) return 'Expires in $days days';
  final months = (days / 30).floor();
  return 'Expires in $months mo';
}

/// Financial year label for India (Apr–Mar), e.g. 2026-27.
String financialYear(DateTime d) {
  final start = d.month >= 4 ? d.year : d.year - 1;
  return '$start-${((start + 1) % 100).toString().padLeft(2, '0')}';
}

// ---------------------------------------------------------------- quantity

/// 95 units in packs of 10 -> "9 Strip + 5 Tab".
/// With an outer pack (e.g. 10 strips per box): 235 -> "2 Box + 3 Strip + 5 Tab".
String fmtQty(int units, int packSize, String unitName, String packName, {int outerSize = 0, String outerName = ''}) {
  final parts = <String>[];
  var rest = units;
  final hasPack = packSize > 1 && unitName != packName;
  if (outerSize > 1 && outerName.isNotEmpty) {
    final perOuter = outerSize * (hasPack ? packSize : 1);
    final outers = rest ~/ perOuter;
    rest %= perOuter;
    if (outers > 0) parts.add('$outers $outerName');
  }
  if (hasPack) {
    final packs = rest ~/ packSize;
    rest %= packSize;
    if (packs > 0) parts.add('$packs $packName');
  }
  if (rest > 0 || parts.isEmpty) parts.add('$rest $unitName');
  return parts.join(' + ');
}

/// Parses what a biller types as a quantity and returns units.
///   "5" -> 5 units, "2s"/"2p"/"2 strip" -> 2 packs, "1b"/"1 box" -> 1 outer pack,
///   "1.5s" -> 15 (packs of 10). [mode]: 0 = plain numbers are units, 1 = packs, 2 = outer packs.
int? parseQty(String input, int packSize, {int outerSize = 0, int mode = 0}) {
  final s = input.trim().toLowerCase();
  if (s.isEmpty) return null;
  final m = RegExp(r'^(\d+(?:\.\d+)?)\s*([a-z]*)$').firstMatch(s);
  if (m == null) return null;
  final n = double.parse(m.group(1)!);
  final suffix = m.group(2)!;
  final hasOuter = outerSize > 1;
  var level = suffix.isEmpty ? mode : 0;
  if (suffix.startsWith('s') || suffix.startsWith('p')) level = 1;
  if (suffix.startsWith('b')) level = hasOuter ? 2 : 1;
  if (level == 2 && !hasOuter) level = 1;
  final units = switch (level) {
    2 => n * outerSize * packSize,
    1 => n * packSize,
    _ => n,
  };
  if (units <= 0 || units != units.roundToDouble()) return null;
  return units.round();
}

/// 95 units in packs of 10 -> "9.5".
String packsDecimal(int units, int packSize) =>
    packSize <= 1 ? '$units' : trimNum(units / packSize);
