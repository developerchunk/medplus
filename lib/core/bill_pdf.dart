import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/models.dart';
import 'bill_file.dart';
import 'format.dart';
import 'settings.dart';

/// Renders a [BillDocument] to PDF for A4, A5 or 80 mm thermal paper.
class BillPdf {
  static pw.ThemeData? _theme;

  static Future<pw.ThemeData> _loadTheme() async {
    if (_theme != null) return _theme!;
    final regular = pw.Font.ttf(await rootBundle.load('assets/fonts/NotoSans-Regular.ttf'));
    final medium = pw.Font.ttf(await rootBundle.load('assets/fonts/NotoSans-SemiBold.ttf'));
    final bold = pw.Font.ttf(await rootBundle.load('assets/fonts/NotoSans-Bold.ttf'));
    _theme = pw.ThemeData.withFont(base: regular, bold: bold, fontFallback: [medium]);
    return _theme!;
  }

  static PdfPageFormat formatFor(String paper) => switch (paper) {
        'A4' => PdfPageFormat.a4.copyWith(marginLeft: 28, marginRight: 28, marginTop: 28, marginBottom: 28),
        '80mm' => PdfPageFormat.roll80.copyWith(marginLeft: 8, marginRight: 8, marginTop: 10, marginBottom: 10),
        _ => PdfPageFormat.a5.copyWith(marginLeft: 20, marginRight: 20, marginTop: 20, marginBottom: 20),
      };

  static Future<Uint8List> build(BillDocument doc, {required String copyLabel, String? paper}) async {
    final theme = await _loadTheme();
    final pp = paper ?? Settings.instance.get('paper');
    // A bill is a GST (tax) invoice only if GST was charged on it — decided by the bill itself,
    // so old bills keep their format even if the GST setting changes later.
    final showGst = isGstBill(doc.sale);
    final pdf = pw.Document(title: 'Bill ${doc.sale.billNo}', author: doc.shop['shop_name'] ?? 'MedBillings', creator: 'MedBillings');
    final format = formatFor(pp);
    if (pp == '80mm') {
      pdf.addPage(pw.Page(pageFormat: format, theme: theme, build: (_) => _thermal(doc, copyLabel, showGst)));
    } else {
      final small = pp == 'A5';
      pdf.addPage(pw.MultiPage(
        pageFormat: format,
        theme: theme.copyWith(defaultTextStyle: theme.defaultTextStyle.copyWith(fontSize: small ? 7.5 : 9)),
        header: (ctx) => ctx.pageNumber == 1 ? _header(doc, copyLabel, small, showGst) : pw.SizedBox(),
        footer: (ctx) => _footer(doc, ctx, small),
        build: (ctx) => [
          _parties(doc, small),
          pw.SizedBox(height: 8),
          _itemsTable(doc, small, showGst),
          pw.SizedBox(height: 8),
          _totals(doc, small, showGst),
        ],
      ));
    }
    return pdf.save();
  }

  // ------------------------------------------------------------ A4 / A5

  static const _ink = PdfColor.fromInt(0xFF1F2937);
  static const _muted = PdfColor.fromInt(0xFF6B7280);
  static const _line = PdfColor.fromInt(0xFFD1D5DB);
  static const _accent = PdfColor.fromInt(0xFF0F766E);
  static const _fill = PdfColor.fromInt(0xFFF3F4F6);

  static bool isGstBill(Sale s) => s.gstTotal > 0.004;

  static String billTitle(Sale s, bool gst) => gst ? 'TAX INVOICE' : (s.isCredit ? 'CREDIT MEMO' : 'CASH MEMO');

  /// GST split per rate: rate -> (taxable, gst). Prices are GST-inclusive.
  static Map<double, (double, double)> gstByRate(Sale s) {
    final out = <double, (double, double)>{};
    final factor = s.grossTotal - s.itemDiscount > 0 ? (1 - s.billDiscount / (s.grossTotal - s.itemDiscount)) : 1.0;
    for (final it in s.items.where((i) => i.gstRate > 0)) {
      final value = it.amount * factor;
      final taxable = value / (1 + it.gstRate / 100);
      final prev = out[it.gstRate] ?? (0.0, 0.0);
      out[it.gstRate] = (prev.$1 + taxable, prev.$2 + value - taxable);
    }
    return Map.fromEntries(out.entries.toList()..sort((a, b) => a.key.compareTo(b.key)));
  }

  static pw.Widget _header(BillDocument doc, String copyLabel, bool small, bool gst) {
    final s = doc.shop;
    final sale = doc.sale;
    final lines = <String>[
      if ((s['address'] ?? '').isNotEmpty) s['address']!,
      [if ((s['phone'] ?? '').isNotEmpty) 'Ph: ${s['phone']}', if ((s['email'] ?? '').isNotEmpty) s['email']!].join('  ·  '),
      [if (gst && (s['gstin'] ?? '').isNotEmpty) 'GSTIN: ${s['gstin']}', if ((s['dl_no'] ?? '').isNotEmpty) 'D.L. No: ${s['dl_no']}'].join('  ·  '),
    ].where((l) => l.isNotEmpty).toList();
    return pw.Column(children: [
      pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Expanded(
          child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Text(s['shop_name'] ?? '', style: pw.TextStyle(fontSize: small ? 14 : 18, fontWeight: pw.FontWeight.bold, color: _accent)),
            if ((s['shop_tagline'] ?? '').isNotEmpty) pw.Text(s['shop_tagline']!, style: const pw.TextStyle(color: _muted)),
            pw.SizedBox(height: 2),
            for (final l in lines) pw.Text(l, style: const pw.TextStyle(color: _ink)),
          ]),
        ),
        pw.SizedBox(width: 12),
        pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: pw.BoxDecoration(border: pw.Border.all(color: sale.isCancelled ? PdfColors.red : _accent, width: 0.8), borderRadius: pw.BorderRadius.circular(3)),
            child: pw.Text(sale.isCancelled ? 'CANCELLED' : copyLabel,
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: sale.isCancelled ? PdfColors.red : _accent, fontSize: small ? 7 : 8)),
          ),
          pw.SizedBox(height: 4),
          pw.Text(billTitle(sale, gst), style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: small ? 9 : 11)),
          pw.Text('Bill No: ${sale.billNo}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
          pw.Text('Date: ${fmtDate(sale.createdAt)}  ${fmtTime(sale.createdAt)}'),
          if (sale.paymentMode.isNotEmpty) pw.Text('Payment: ${sale.paymentMode}'),
        ]),
      ]),
      pw.SizedBox(height: 6),
      pw.Divider(color: _line, thickness: 0.8, height: 1),
      pw.SizedBox(height: 6),
    ]);
  }

  static pw.Widget _kv(String k, String v, {bool bold = false}) => pw.RichText(
        text: pw.TextSpan(children: [
          pw.TextSpan(text: '$k: ', style: const pw.TextStyle(color: _muted)),
          pw.TextSpan(text: v.isEmpty ? '—' : v, style: pw.TextStyle(fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal)),
        ]),
      );

  static pw.Widget _parties(BillDocument doc, bool small) {
    final s = doc.sale;
    return pw.Container(
      padding: const pw.EdgeInsets.all(6),
      decoration: pw.BoxDecoration(color: _fill, borderRadius: pw.BorderRadius.circular(4)),
      child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Expanded(
            child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              _kv('Patient', s.customerName.isEmpty ? 'Walk-in customer' : s.customerName, bold: true),
              if (s.customerPhone.isNotEmpty) _kv('Mobile', s.customerPhone),
              if (s.customerAddress.isNotEmpty) _kv('Address', s.customerAddress),
            ]),
          ),
          pw.SizedBox(width: 10),
          pw.Expanded(
            child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              _kv('Doctor', s.doctorName.isEmpty ? '' : 'Dr. ${s.doctorName.replaceFirst(RegExp(r'^dr\.?\s*', caseSensitive: false), '')}', bold: true),
              if (s.doctorRegNo.isNotEmpty) _kv('Reg. No', s.doctorRegNo),
              if (s.doctorClinic.isNotEmpty) _kv('Clinic', s.doctorClinic),
            ]),
          ),
        ]),
        if (s.rxNotes.isNotEmpty) ...[pw.SizedBox(height: 3), _kv('Medical details', s.rxNotes)],
      ]),
    );
  }

  static pw.Widget _itemsTable(BillDocument doc, bool small, bool gst) {
    final headers = ['#', 'Medicine', if (gst) 'HSN', 'Batch', 'Exp', 'Qty', 'MRP', 'Rate', 'Disc', if (gst) 'GST', 'Amount'];
    final rows = <List<String>>[];
    var i = 0;
    for (final it in doc.sale.items) {
      i++;
      rows.add([
        '$i',
        '${it.productName}${it.rx ? '  (Rx)' : ''}',
        if (gst) it.hsn,
        it.batchNo,
        fmtExpiry(it.expiry),
        it.qtyLabel,
        amount(it.mrp),
        amount(it.unitRate),
        it.discountPct > 0 ? '${trimNum(it.discountPct)}%' : '',
        if (gst) '${trimNum(it.gstRate)}%',
        amount(it.amount),
      ]);
    }
    // Column indexes shift by one when the HSN column is present.
    final o = gst ? 1 : 0;
    final last = headers.length - 1;
    final right = <int>{5 + o, 6 + o, 7 + o, if (gst) 8 + o, last};
    return pw.TableHelper.fromTextArray(
      headers: headers,
      data: rows,
      border: const pw.TableBorder(horizontalInside: pw.BorderSide(color: _line, width: 0.5), bottom: pw.BorderSide(color: _line, width: 0.8)),
      headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white, fontSize: small ? 7 : 8.5),
      headerDecoration: const pw.BoxDecoration(color: _accent),
      cellStyle: pw.TextStyle(fontSize: small ? 7 : 8.5),
      cellPadding: pw.EdgeInsets.symmetric(horizontal: 3, vertical: small ? 2.5 : 3.5),
      columnWidths: {
        0: const pw.FixedColumnWidth(14),
        1: pw.FlexColumnWidth(gst ? 3.2 : 4),
        if (gst) 2: const pw.FixedColumnWidth(28),
        2 + o: const pw.FlexColumnWidth(1.6),
        3 + o: const pw.FixedColumnWidth(30),
        4 + o: const pw.FlexColumnWidth(1.9),
        5 + o: const pw.FlexColumnWidth(1.3),
        6 + o: const pw.FlexColumnWidth(1.4),
        7 + o: const pw.FixedColumnWidth(24),
        if (gst) 8 + o: const pw.FixedColumnWidth(24),
        last: const pw.FlexColumnWidth(1.6),
      },
      cellAlignments: {for (final c in right) c: pw.Alignment.centerRight},
      headerAlignments: {for (final c in right) c: pw.Alignment.centerRight},
    );
  }

  static pw.Widget _totals(BillDocument doc, bool small, bool gst) {
    final s = doc.sale;
    pw.Widget row(String k, String v, {bool strong = false}) => pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 1),
          child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
            pw.Text(k, style: strong ? pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: small ? 10 : 12) : const pw.TextStyle(color: _muted)),
            pw.Text(v, style: strong ? pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: small ? 10 : 12) : null),
          ]),
        );
    final rxLines = s.items.where((i) => i.rx).toList();
    return pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
      pw.Expanded(
        flex: 5,
        child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Text('Amount in words', style: const pw.TextStyle(color: _muted)),
          pw.Text(rupeesInWords(s.grandTotal), style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 6),
          if (rxLines.isNotEmpty)
            pw.Text('(Rx) Prescription medicines dispensed against the prescription of the doctor named above.',
                style: const pw.TextStyle(color: _muted)),
          if (s.isCancelled) ...[
            pw.SizedBox(height: 4),
            pw.Text('This bill was cancelled${s.cancelReason.isEmpty ? '' : ': ${s.cancelReason}'}', style: const pw.TextStyle(color: PdfColors.red)),
          ],
        ]),
      ),
      pw.SizedBox(width: 16),
      pw.Expanded(
        flex: 4,
        child: pw.Column(children: [
          if (gst) ...[
            row('Taxable amount', amount(s.taxableTotal)),
            for (final e in gstByRate(s).entries) ...[
              row('CGST @ ${trimNum(e.key / 2)}%', amount(e.value.$2 / 2)),
              row('SGST @ ${trimNum(e.key / 2)}%', amount(e.value.$2 / 2)),
            ],
            row('Total GST', amount(s.gstTotal)),
            if (s.roundOff != 0) row('Round off', '${s.roundOff > 0 ? '+' : '-'} ${amount(s.roundOff.abs())}'),
            pw.Divider(color: _line, height: 6),
            row('Net amount payable', money(s.grandTotal), strong: true),
          ] else
            row('Total amount', money(s.grandTotal), strong: true),
          if (s.isCredit) ...[
            row('Paid now', money(s.paidAmount)),
            row('Balance on credit', money(s.dueAmount)),
          ],
          if (s.totalDiscount > 0)
            pw.Align(
              alignment: pw.Alignment.centerRight,
              child: pw.Text('You saved ${money(s.totalDiscount)}', style: pw.TextStyle(color: _accent, fontWeight: pw.FontWeight.bold)),
            ),
        ]),
      ),
    ]);
  }

  static pw.Widget _footer(BillDocument doc, pw.Context ctx, bool small) {
    final s = doc.shop;
    return pw.Column(children: [
      pw.SizedBox(height: 8),
      pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
        pw.Expanded(
          child: pw.Text(s['footer_note'] ?? '', style: const pw.TextStyle(color: _muted)),
        ),
        pw.SizedBox(width: 16),
        pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.center, children: [
          pw.SizedBox(height: small ? 14 : 22),
          pw.Container(width: 110, height: 0.6, color: _ink),
          pw.Text((s['pharmacist_name'] ?? '').isEmpty ? 'Pharmacist' : s['pharmacist_name']!),
          if ((s['pharmacist_reg'] ?? '').isNotEmpty) pw.Text('Reg. ${s['pharmacist_reg']}', style: const pw.TextStyle(color: _muted)),
        ]),
      ]),
      pw.SizedBox(height: 4),
      pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
        pw.Text('Computer generated bill · MedBillings', style: const pw.TextStyle(color: _muted, fontSize: 6.5)),
        pw.Text('Page ${ctx.pageNumber} of ${ctx.pagesCount}', style: const pw.TextStyle(color: _muted, fontSize: 6.5)),
      ]),
    ]);
  }

  // ------------------------------------------------------------ 80 mm thermal

  static pw.Widget _thermal(BillDocument doc, String copyLabel, bool showGst) {
    final s = doc.sale;
    final shop = doc.shop;
    const f = 7.5;
    pw.Widget dash() => pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 3),
          child: pw.Row(children: List.generate(46, (_) => pw.Expanded(child: pw.Text('-', style: const pw.TextStyle(fontSize: 6), textAlign: pw.TextAlign.center)))),
        );
    pw.Widget lr(String l, String r, {bool bold = false}) => pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
          pw.Text(l, style: pw.TextStyle(fontSize: bold ? 10 : f, fontWeight: bold ? pw.FontWeight.bold : null)),
          pw.Text(r, style: pw.TextStyle(fontSize: bold ? 10 : f, fontWeight: bold ? pw.FontWeight.bold : null)),
        ]);
    return pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
      pw.Text(shop['shop_name'] ?? '', textAlign: pw.TextAlign.center, style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
      if ((shop['address'] ?? '').isNotEmpty) pw.Text(shop['address']!, textAlign: pw.TextAlign.center, style: const pw.TextStyle(fontSize: f)),
      if ((shop['phone'] ?? '').isNotEmpty) pw.Text('Ph: ${shop['phone']}', textAlign: pw.TextAlign.center, style: const pw.TextStyle(fontSize: f)),
      if (showGst && (shop['gstin'] ?? '').isNotEmpty) pw.Text('GSTIN: ${shop['gstin']}', textAlign: pw.TextAlign.center, style: const pw.TextStyle(fontSize: f)),
      if ((shop['dl_no'] ?? '').isNotEmpty) pw.Text('DL: ${shop['dl_no']}', textAlign: pw.TextAlign.center, style: const pw.TextStyle(fontSize: f)),
      pw.SizedBox(height: 2),
      pw.Text(billTitle(s, showGst), textAlign: pw.TextAlign.center, style: pw.TextStyle(fontSize: f + 1, fontWeight: pw.FontWeight.bold)),
      pw.Text(s.isCancelled ? '*** CANCELLED ***' : copyLabel, textAlign: pw.TextAlign.center, style: pw.TextStyle(fontSize: f, fontWeight: pw.FontWeight.bold)),
      dash(),
      lr('Bill: ${s.billNo}', fmtDateShort(s.createdAt)),
      lr('Patient: ${s.customerName.isEmpty ? 'Walk-in' : s.customerName}', fmtTime(s.createdAt)),
      if (s.doctorName.isNotEmpty) pw.Text('Dr: ${s.doctorName}${s.doctorRegNo.isEmpty ? '' : ' (${s.doctorRegNo})'}', style: const pw.TextStyle(fontSize: f)),
      dash(),
      for (final it in s.items) ...[
        pw.Text('${it.productName}${it.rx ? ' (Rx)' : ''}', style: pw.TextStyle(fontSize: f, fontWeight: pw.FontWeight.bold)),
        lr('  B:${it.batchNo} E:${fmtExpiry(it.expiry)}  ${it.qtyLabel}${it.discountPct > 0 ? ' -${trimNum(it.discountPct)}%' : ''}', amount(it.amount)),
      ],
      dash(),
      if (showGst) ...[
        lr('Taxable amount', amount(s.taxableTotal)),
        for (final e in gstByRate(s).entries) lr('CGST+SGST @ ${trimNum(e.key)}%', amount(e.value.$2)),
        lr('Total GST', amount(s.gstTotal)),
        if (s.roundOff != 0) lr('Round off', amount(s.roundOff)),
        pw.SizedBox(height: 2),
        lr('NET PAYABLE', money(s.grandTotal), bold: true),
      ] else
        lr('TOTAL', money(s.grandTotal), bold: true),
      if (s.isCredit) lr('Paid ${amount(s.paidAmount)}', 'Balance ${amount(s.dueAmount)}'),
      if (s.totalDiscount > 0) lr('You saved', money(s.totalDiscount)),
      pw.Text(rupeesInWords(s.grandTotal), style: const pw.TextStyle(fontSize: 6.5)),
      dash(),
      if ((shop['footer_note'] ?? '').isNotEmpty) pw.Text(shop['footer_note']!, textAlign: pw.TextAlign.center, style: const pw.TextStyle(fontSize: 6.5)),
      pw.SizedBox(height: 4),
      pw.Text('Thank you!', textAlign: pw.TextAlign.center, style: pw.TextStyle(fontSize: f, fontWeight: pw.FontWeight.bold)),
    ]);
  }
}

// ------------------------------------------------------------ number to words (Indian)

const _ones = ['', 'One', 'Two', 'Three', 'Four', 'Five', 'Six', 'Seven', 'Eight', 'Nine', 'Ten', 'Eleven', 'Twelve', 'Thirteen', 'Fourteen', 'Fifteen', 'Sixteen', 'Seventeen', 'Eighteen', 'Nineteen'];
const _tens = ['', '', 'Twenty', 'Thirty', 'Forty', 'Fifty', 'Sixty', 'Seventy', 'Eighty', 'Ninety'];

String _below100(int n) => n < 20 ? _ones[n] : '${_tens[n ~/ 10]}${n % 10 > 0 ? ' ${_ones[n % 10]}' : ''}';

String _below1000(int n) {
  final h = n ~/ 100, r = n % 100;
  return [if (h > 0) '${_ones[h]} Hundred', if (r > 0) _below100(r)].join(' ');
}

String numberInWords(int n) {
  if (n == 0) return 'Zero';
  final parts = <String>[];
  final crore = n ~/ 10000000;
  n %= 10000000;
  final lakh = n ~/ 100000;
  n %= 100000;
  final thousand = n ~/ 1000;
  n %= 1000;
  if (crore > 0) parts.add('${numberInWords(crore)} Crore');
  if (lakh > 0) parts.add('${_below100(lakh)} Lakh');
  if (thousand > 0) parts.add('${_below100(thousand)} Thousand');
  if (n > 0) parts.add(_below1000(n));
  return parts.join(' ');
}

String rupeesInWords(double v) {
  final rupees = v.floor();
  final paise = ((v - rupees) * 100).round();
  final r = 'Rupees ${numberInWords(rupees)}';
  return paise > 0 ? '$r and ${_below100(paise)} Paise Only' : '$r Only';
}
