import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medical/core/bill_file.dart';
import 'package:medical/core/bill_pdf.dart';
import 'package:medical/core/format.dart';
import 'package:medical/models/models.dart';
import 'package:medical/ui/widgets/common.dart' show UpperCaseInputFormatter;
import 'package:medical/ui/widgets/date_input.dart';

void main() {
  group('typed dates', dateInputTests);
  group('expiry / date parsing', () {
    test('MM/YY resolves to the last day of the month', () {
      expect(parseMonthYear('08/27'), DateTime(2027, 8, 31));
      expect(parseMonthYear('02/28'), DateTime(2028, 2, 29));
      expect(parseMonthYear('12/2026'), DateTime(2026, 12, 31));
      expect(parseMonthYear('0827'), DateTime(2027, 8, 31));
    });
    test('mfg dates resolve to the first day', () {
      expect(parseMonthYear('08/25', endOfMonth: false), DateTime(2025, 8, 1));
    });
    test('rejects nonsense', () {
      expect(parseMonthYear('13/27'), isNull);
      expect(parseMonthYear('abc'), isNull);
      expect(parseMonthYear(''), isNull);
    });
    test('financial year', () {
      expect(financialYear(DateTime(2026, 3, 31)), '2025-26');
      expect(financialYear(DateTime(2026, 4, 1)), '2026-27');
    });
  });

  group('quantities', () {
    test('loose units and packs format', () {
      expect(fmtQty(95, 10, 'Tab', 'Strip'), '9 Strip + 5 Tab');
      expect(fmtQty(5, 10, 'Tab', 'Strip'), '5 Tab');
      expect(fmtQty(20, 10, 'Tab', 'Strip'), '2 Strip');
      expect(fmtQty(3, 1, 'Bottle', 'Bottle'), '3 Bottle');
      expect(packsDecimal(95, 10), '9.5');
      expect(fmtQty(235, 10, 'Tab', 'Strip', outerSize: 10, outerName: 'Box'), '2 Box + 3 Strip + 5 Tab');
      expect(fmtQty(100, 10, 'Tab', 'Strip', outerSize: 10, outerName: 'Box'), '1 Box');
      expect(fmtQty(7, 1, 'Vial', 'Vial', outerSize: 5, outerName: 'Box'), '1 Box + 2 Vial');
      expect(Product(name: 'X', packSize: 10, outerName: 'Box', outerSize: 10).packingLabel, '10 Tab per Strip · 10 Strip per Box');
    });
    test('biller quantity input', () {
      expect(parseQty('5', 10), 5);
      expect(parseQty('2s', 10), 20);
      expect(parseQty('1.5 strip', 10), 15);
      expect(parseQty('2', 10, mode: 1), 20);
      expect(parseQty('1b', 10, outerSize: 10), 100);
      expect(parseQty('1 box', 10, outerSize: 10), 100);
      expect(parseQty('2', 10, outerSize: 10, mode: 2), 200);
      expect(parseQty('1b', 1), 1, reason: 'no outer pack: b = bottle/pack');
      expect(parseQty('5 cap', 10, outerSize: 10), 5);
      expect(parseQty('0', 10), isNull);
      expect(parseQty('1.5', 10), isNull);
      expect(parseQty('x', 10), isNull);
    });
  });

  test('amount in words uses the Indian system', () {
    expect(rupeesInWords(467), 'Rupees Four Hundred Sixty Seven Only');
    expect(rupeesInWords(125000.5), 'Rupees One Lakh Twenty Five Thousand and Fifty Paise Only');
    expect(numberInWords(10000000), 'One Crore');
  });

  group('GST is optional', () {
    SaleItem item(double amount, double gst) => SaleItem(
        productId: 1, batchId: 1, productName: 'X', batchNo: 'B', expiry: DateTime(2028), packSize: 1, unitName: 'Pc', packName: 'Pc',
        qtyUnits: 1, mrp: amount, unitRate: amount, amount: amount, gstRate: gst);

    test('no GST charged → Cash Memo / Credit Memo', () {
      final s = Sale(grandTotal: 100, gstTotal: 0, items: [item(100, 0)]);
      expect(BillPdf.isGstBill(s), isFalse);
      expect(BillPdf.billTitle(s, false), 'CASH MEMO');
      expect(BillPdf.billTitle(Sale(paymentMode: 'Credit'), false), 'CREDIT MEMO');
    });

    test('GST bill splits tax per rate (prices include GST)', () {
      final s = Sale(grossTotal: 217, grandTotal: 217, gstTotal: 17, items: [item(105, 5), item(112, 12)]);
      expect(BillPdf.isGstBill(s), isTrue);
      expect(BillPdf.billTitle(s, true), 'TAX INVOICE');
      final split = BillPdf.gstByRate(s);
      expect(split.keys, [5, 12]);
      expect(round2(split[5]!.$1), 100);
      expect(round2(split[5]!.$2), 5);
      expect(round2(split[12]!.$2), 12);
    });

    test('new medicines default to 5% GST', () {
      expect(Product(name: 'X').gstRate, 5);
    });
  });

  test('batch numbers are typed in capitals', () {
    expect(_type(UpperCaseInputFormatter(), 'px77a'), 'PX77A');
  });

  test('box purchase labels: free strips or free boxes', () {
    PurchaseItem item({int freePacks = 0, int freeBoxes = 0}) => PurchaseItem(
        productId: 1, batchNo: 'B', expiry: DateTime(2028), packSize: 10, qtyPacks: 30, freePacks: freePacks, purchaseRate: 20,
        mrp: 30, gstRate: 12, boxQty: 3, boxSize: 10, freeBoxes: freeBoxes, packName: 'Strip');
    expect(item().qtyLabel, '3 Box × 10 Strip');
    expect(item(freePacks: 2).qtyLabel, '3 Box × 10 Strip + 2 Strip free');
    expect(item(freePacks: 10, freeBoxes: 1).qtyLabel, '3 Box × 10 Strip + 1 Box free');
    expect(item(freePacks: 10, freeBoxes: 1).totalUnits, 400);
  });

  test('antibiotics always need a prescription', () {
    expect(Product(name: 'Azithral', isAntibiotic: true).needsPrescription, isTrue);
    expect(Product(name: 'X', schedule: 'H').needsPrescription, isTrue);
    expect(Product(name: 'Dolo').needsPrescription, isFalse);
    expect(Product(name: 'Azithral', isAntibiotic: true).warningText, contains('antibiotic'));
  });

  group('.mbill file', () {
    final sale = Sale(
      id: 7,
      billNo: 'B-00012',
      customerName: 'Ramesh',
      doctorName: 'Deshmukh',
      grandTotal: 120,
      items: [
        SaleItem(
          productId: 1,
          batchId: 2,
          productName: 'Azithral 500',
          batchNo: 'AZ123',
          expiry: DateTime(2027, 4, 30),
          packSize: 5,
          unitName: 'Tab',
          packName: 'Strip',
          qtyUnits: 3,
          mrp: 119.5,
          unitRate: 23.9,
          amount: 71.7,
          rx: true,
        ),
      ],
    );
    final doc = BillDocument(shop: {'shop_name': 'Test Medical'}, sale: sale);

    test('round-trips and stays small', () {
      final bytes = BillFile.encode(doc);
      expect(String.fromCharCodes(bytes.sublist(0, 4)), 'MBIL');
      expect(bytes.length, lessThan(1024));
      final back = BillFile.decode(bytes);
      expect(back.sale.billNo, 'B-00012');
      expect(back.sale.items.single.batchNo, 'AZ123');
      expect(back.sale.items.single.rx, isTrue);
      expect(back.shop['shop_name'], 'Test Medical');
    });

    test('detects damage', () {
      final bytes = BillFile.encode(doc);
      bytes[bytes.length - 3] ^= 0xFF;
      expect(() => BillFile.decode(bytes), throwsA(isA<BillFileException>()));
      expect(() => BillFile.decode(bytes.sublist(0, 10)), throwsA(isA<BillFileException>()));
    });
  });
}

// ---------------------------------------------------------------- typed dates

String _type(TextInputFormatter f, String keys) {
  var v = TextEditingValue.empty;
  for (final ch in keys.split('')) {
    v = f.formatEditUpdate(v, TextEditingValue(text: v.text + ch));
  }
  return v.text;
}

void dateInputTests() {
  final my = MonthYearInputFormatter();
  final dt = DateInputFormatter();
  test('month/year auto-formats while typing', () {
    expect(_type(my, '724'), '07/24');
    expect(_type(my, '1227'), '12/27');
    expect(_type(my, '0827'), '08/27');
    expect(_type(my, '132'), '01/32');
    expect(_type(my, '072027'), '07/2027');
    expect(_type(my, '7'), '07/');
    expect(parseMonthYear(_type(my, '724')), DateTime(2024, 7, 31));
  });
  test('backspace removes the auto slash cleanly', () {
    final v = my.formatEditUpdate(const TextEditingValue(text: '07/'), const TextEditingValue(text: '07'));
    expect(v.text, '07');
  });
  test('full dates auto-format while typing', () {
    expect(_type(dt, '24092026'), '24/09/2026');
    expect(_type(dt, '5926'), '05/09/26');
    expect(parseMonthYear(_type(dt, '24092026')), DateTime(2026, 9, 24));
  });
}
