import 'package:flutter/services.dart';

/// Formats month/year as the biller types digits: `724` -> `07/24`, `1227` -> `12/27`,
/// `072027` -> `07/2027`. Used for expiry and manufacturing dates.
class MonthYearInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    var d = newValue.text.replaceAll(RegExp(r'\D'), '');
    final deleting = newValue.text.length < oldValue.text.length;
    if (!deleting && d.isNotEmpty) {
      // A first digit above 1 can only be a single-digit month: 7 -> 07.
      if (int.parse(d[0]) > 1) d = '0$d';
      // 13..19 can't be a month: 1 then 3 -> 01/3…
      if (d.length >= 2 && d[0] == '1' && int.parse(d[1]) > 2) d = '0$d';
      if (d.startsWith('00')) d = '0${d.substring(2)}';
    }
    if (d.length > 6) d = d.substring(0, 6);
    final String text;
    if (d.length < 2) {
      text = d;
    } else if (d.length == 2) {
      text = deleting ? d : '$d/';
    } else {
      text = '${d.substring(0, 2)}/${d.substring(2)}';
    }
    return TextEditingValue(text: text, selection: TextSelection.collapsed(offset: text.length));
  }
}

/// Formats a full date as digits are typed: `24092026` -> `24/09/2026`, `5` -> `05/`.
class DateInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    var d = newValue.text.replaceAll(RegExp(r'\D'), '');
    final deleting = newValue.text.length < oldValue.text.length;
    if (!deleting && d.isNotEmpty) {
      if (int.parse(d[0]) > 3) d = '0$d';
      if (d.length >= 3 && int.parse(d[2]) > 1) d = '${d.substring(0, 2)}0${d.substring(2)}';
      if (d.length >= 4 && d[2] == '1' && int.parse(d[3]) > 2) d = '${d.substring(0, 2)}0${d.substring(2)}';
    }
    if (d.length > 8) d = d.substring(0, 8);
    final b = StringBuffer();
    for (var i = 0; i < d.length; i++) {
      b.write(d[i]);
      if ((i == 1 || i == 3) && (i < d.length - 1 || !deleting)) b.write('/');
    }
    final text = b.toString();
    return TextEditingValue(text: text, selection: TextSelection.collapsed(offset: text.length));
  }
}

final monthYearInput = <TextInputFormatter>[MonthYearInputFormatter()];
final dateInput = <TextInputFormatter>[DateInputFormatter()];
