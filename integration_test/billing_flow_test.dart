import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:medical/core/bill_file.dart';
import 'package:medical/core/db.dart';
import 'package:medical/core/format.dart';
import 'package:medical/core/print_service.dart';
import 'package:medical/core/settings.dart';
import 'package:medical/data/repo.dart';
import 'package:medical/main.dart';
import 'package:medical/models/models.dart';
import 'package:medical/ui/nav.dart';

import 'test_window.dart';

/// Drives the real billing screen end to end against a throwaway data folder.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late int azithId;
  late int salineId;

  setUpAll(() async {
    await keepTestWindowVisible();
    PrintService.enabled = false;
    AppPaths.root = Directory.systemTemp.createTempSync('medbillings_it_');
    for (final d in [Directory('${AppPaths.root.path}/data'), AppPaths.billsDir, AppPaths.backupsDir]) {
      d.createSync(recursive: true);
    }
    await AppDb.open();
    await Settings.instance.load();
    // Today's reminder already shown, so no dialog covers the screen.
    await Settings.instance.setAll({'last_expiry_alert': isoDate(today()), 'bill_prefix': 'T-'});

    final supplierId = await Repo.saveSupplier(Supplier(name: 'Mahalaxmi Pharma'));
    azithId = await Repo.saveProduct(Product(name: 'Azithral 500', form: 'Tablet', unitName: 'Tab', packName: 'Strip', packSize: 5, schedule: 'H', isAntibiotic: true));
    salineId = await Repo.saveProduct(Product(name: 'Normal Saline 500ml', form: 'IV Fluid / Saline', unitName: 'Bottle', packName: 'Bottle', packSize: 1));
    await Repo.createPurchase(Purchase(supplierId: supplierId, invoiceNo: 'INV-1', invoiceDate: today()), [
      // Two batches: the one expiring first must be suggested first (FEFO).
      PurchaseItem(productId: azithId, productName: 'Azithral 500', batchNo: 'AZLATE', expiry: DateTime(2028, 6, 30), packSize: 5, qtyPacks: 10, purchaseRate: 80, mrp: 119.5, gstRate: 12),
      PurchaseItem(productId: azithId, productName: 'Azithral 500', batchNo: 'AZSOON', expiry: DateTime(2027, 3, 31), packSize: 5, qtyPacks: 2, purchaseRate: 80, mrp: 119.5, gstRate: 12),
      PurchaseItem(productId: salineId, productName: 'Normal Saline 500ml', batchNo: 'NS001', expiry: DateTime(2027, 12, 31), packSize: 1, qtyPacks: 20, purchaseRate: 18, mrp: 32, gstRate: 12),
    ]);
    await Repo.saveTemplate(BillTemplate(code: '1', name: 'Saline kit', items: [BillTemplateItem(productId: salineId, qtyUnits: 2)]));
  });

  Future<void> settle(WidgetTester t) async {
    for (var i = 0; i < 10; i++) {
      await t.pump(const Duration(milliseconds: 120));
    }
  }

  /// Pumps until [f] shows up (first database queries can be slow on a cold start).
  Future<void> waitFor(WidgetTester t, Finder f, {int tries = 40}) async {
    for (var i = 0; i < tries && f.evaluate().isEmpty; i++) {
      await t.pump(const Duration(milliseconds: 150));
    }
  }

  Finder field(String label) => find.byWidgetPredicate((w) => w is TextField && w.decoration?.labelText == label);

  testWidgets('bill a loose strip of an antibiotic, enforce doctor, save medical copy', (t) async {
    await t.pumpWidget(const MedBillingsApp());
    await settle(t);
    Nav.go(Nav.billing);
    await settle(t);

    // Medicine suggestion
    await t.tap(field('Medicine (F3)'));
    await t.enterText(field('Medicine (F3)'), 'azith');
    await settle(t);
    await waitFor(t, find.text('Azithral 500'));
    expect(find.text('Azithral 500'), findsWidgets);
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await settle(t);

    // Batch field pre-filled with the earliest-expiring batch
    final batchField = t.widget<TextField>(field('Batch'));
    expect(batchField.controller!.text, 'AZSOON');
    await t.sendKeyEvent(LogicalKeyboardKey.enter); // accept highlighted batch
    await settle(t);

    // 3 loose tablets
    await t.enterText(field('Qty'), '3');
    await t.testTextInput.receiveAction(TextInputAction.done);
    await settle(t);
    await t.testTextInput.receiveAction(TextInputAction.done); // Disc → adds the line
    await settle(t);
    expect(find.text('71.70'), findsWidgets); // 3 × 119.50/5

    // Antibiotic → saving without a doctor is blocked
    await t.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await t.sendKeyEvent(LogicalKeyboardKey.keyS);
    await t.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await settle(t);
    expect(find.textContaining("enter the doctor's name"), findsOneWidget);
    expect(await Repo.sales(), isEmpty);

    await t.enterText(field('Doctor name *'), 'Suresh Deshmukh');
    await t.enterText(field('Patient name'), 'Ramesh Jadhav');
    await settle(t);
    await t.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await t.sendKeyEvent(LogicalKeyboardKey.keyS);
    await t.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await settle(t);
    await t.pump(const Duration(seconds: 1));

    final sales = await Repo.sales();
    expect(sales, hasLength(1));
    final sale = (await Repo.sale(sales.single.id!))!;
    expect(sale.billNo, 'T-00001');
    expect(sale.grandTotal, 72); // 71.70 rounded
    expect(sale.items.single.batchNo, 'AZSOON');
    expect(sale.items.single.qtyUnits, 3);

    // Stock: 10 tablets in AZSOON → 7 left (1 strip + 2 tabs)
    final soon = (await Repo.batchesForProduct(azithId)).firstWhere((b) => b.batchNo == 'AZSOON');
    expect(soon.qty, 7);

    // Medical copy written as .mbill and readable
    expect(File(sale.filePath).existsSync(), isTrue);
    final doc = await BillFile.read(sale.filePath);
    expect(doc.sale.doctorName, 'Suresh Deshmukh');
    expect(doc.sale.items.single.rx, isTrue);

    // Doctor & patient remembered for suggestions
    expect((await Repo.searchDoctors('sur')).single.name, 'Suresh Deshmukh');
    expect((await Repo.searchCustomers('ram')).single.name, 'Ramesh Jadhav');

    // Cancelling puts stock back
    await Repo.cancelSale(sale.id!, 'test');
    final after = (await Repo.batchesForProduct(azithId)).firstWhere((b) => b.batchNo == 'AZSOON');
    expect(after.qty, 10);
  });

  testWidgets('template loads with in-stock batches and stays editable', (t) async {
    await t.pumpWidget(const MedBillingsApp());
    await settle(t);
    Nav.billWithTemplate('1');
    await settle(t);
    expect(find.text('Normal Saline 500ml'), findsWidgets);
    expect(find.text('NS001'), findsWidgets);
    expect(find.text('64.00'), findsWidgets); // 2 × 32

    // Change quantity on the bill only
    final qty = find.byWidgetPredicate((w) => w is TextField && w.controller?.text == '2');
    await t.enterText(qty.first, '3');
    await settle(t);
    expect(find.text('96.00'), findsWidgets);
    final tpl = await Repo.template(code: '1');
    expect(tpl!.items.single.qtyUnits, 2, reason: 'central template must not change');

    await t.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await t.sendKeyEvent(LogicalKeyboardKey.keyS);
    await t.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await settle(t);
    await t.pump(const Duration(seconds: 1));
    final s = (await Repo.sales(status: 'completed')).first;
    expect(s.templateCode, '1');
    expect(s.grandTotal, 96);
  });

  testWidgets('batch must belong to the chosen medicine and be in stock', (t) async {
    // An expired batch still on the shelf, and a batch of another medicine.
    await Repo.addOpeningBatch(Batch(productId: azithId, batchNo: 'AZOLD', expiry: DateTime(2025, 1, 31), packSize: 5, mrp: 110, qty: 10));
    await t.pumpWidget(const MedBillingsApp());
    await settle(t);
    Nav.go(Nav.billing);
    await settle(t);

    await t.tap(field('Medicine (F3)'));
    await t.enterText(field('Medicine (F3)'), 'azith');
    await settle(t);
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await settle(t);

    // Suggestions only show this medicine's sellable batches (no expired AZOLD, no saline NS001).
    await t.enterText(field('Batch'), '');
    await settle(t);
    expect(find.text('AZSOON'), findsWidgets);
    expect(find.text('AZLATE'), findsWidgets);
    expect(find.text('AZOLD'), findsNothing);
    expect(find.text('NS001'), findsNothing);

    // Another medicine's batch → error, Add stays blocked
    await t.enterText(field('Batch'), 'NS001');
    await settle(t);
    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await t.testTextInput.receiveAction(TextInputAction.done);
    await settle(t);
    expect(find.textContaining('Batch "NS001" does not exist for Azithral 500'), findsOneWidget);

    // Expired batch → specific error
    await t.tap(field('Batch'));
    await settle(t);
    await t.enterText(field('Batch'), 'AZOLD');
    await settle(t);
    await t.testTextInput.receiveAction(TextInputAction.done);
    await settle(t);
    expect(find.textContaining('expired'), findsWidgets);

    // Correct batch works
    await t.tap(field('Batch'));
    await settle(t);
    await t.enterText(field('Batch'), 'azlate');
    await settle(t);
    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await t.testTextInput.receiveAction(TextInputAction.done);
    await settle(t);
    await t.enterText(field('Qty'), '5');
    await t.testTextInput.receiveAction(TextInputAction.done);
    await settle(t);
    await t.testTextInput.receiveAction(TextInputAction.done); // Disc → adds the line
    await settle(t);
    expect(find.text('119.50'), findsWidgets);

    // Editing the batch on the line to something not in stock marks the row and blocks saving
    final lineBatch = find.byWidgetPredicate((w) => w is TextField && w.controller?.text == 'AZLATE');
    await t.enterText(lineBatch, 'XYZ');
    await settle(t);
    expect(find.textContaining('is not in stock for this medicine'), findsWidgets);
    final before = (await Repo.sales()).length;
    await t.enterText(field('Doctor name *'), 'Suresh Deshmukh');
    await t.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await t.sendKeyEvent(LogicalKeyboardKey.keyS);
    await t.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await settle(t);
    expect((await Repo.sales()).length, before);
  });

  testWidgets('default doctor is pre-filled and credit customers get a badge and a running balance', (t) async {
    final doc = Doctor(name: 'Anjali Kulkarni', regNo: 'MMC 5678', clinic: 'Sai Hospital');
    await Repo.saveDoctor(doc);
    await Settings.instance.set('default_doctor_id', '${doc.id}');
    final cust = Customer(name: 'Vaishali More', phone: '9822044444', creditAllowed: true, creditLimit: 5000);
    await Repo.saveCustomer(cust);

    await t.pumpWidget(const MedBillingsApp());
    await settle(t);
    Nav.go(Nav.billing);
    await settle(t);

    // Default doctor already on the bill
    final docField = t.widget<TextField>(find.byWidgetPredicate((w) => w is TextField && (w.decoration?.labelText ?? '').startsWith('Doctor name')));
    expect(docField.controller!.text, 'Anjali Kulkarni');

    // Focusing the patient field lists credit customers with a badge
    await t.tap(field('Patient name'));
    await settle(t);
    expect(find.text('Vaishali More'), findsWidgets);
    expect(find.text('Credit'), findsWidgets);
    await t.enterText(field('Patient name'), 'vais');
    await settle(t);
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await settle(t);
    expect(t.widget<TextField>(field('Mobile')).controller!.text, '9822044444');

    // 2 bottles of saline on credit, ₹10 paid now
    await t.tap(field('Medicine (F3)'));
    await t.enterText(field('Medicine (F3)'), 'saline');
    await settle(t);
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await settle(t);
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await settle(t);
    await t.enterText(field('Qty'), '2');
    await t.testTextInput.receiveAction(TextInputAction.done);
    await settle(t);
    await t.testTextInput.receiveAction(TextInputAction.done); // Disc → adds the line
    await settle(t);
    await t.tap(find.widgetWithText(ChoiceChip, 'Credit'));
    await settle(t);
    await t.enterText(field('Paid now (optional)'), '10');
    await settle(t);
    await t.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await t.sendKeyEvent(LogicalKeyboardKey.keyS);
    await t.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await settle(t);
    await t.pump(const Duration(seconds: 1));

    final sale = (await Repo.sales(customerId: cust.id)).first;
    expect(sale.isCredit, isTrue);
    expect(sale.grandTotal, 64);
    expect(sale.paidAmount, 10);
    expect(sale.doctorName, 'Anjali Kulkarni');
    expect((await Repo.customer(cust.id!))!.balance, 54);

    // Next bill starts with the default doctor again
    expect(t.widget<TextField>(find.byWidgetPredicate((w) => w is TextField && (w.decoration?.labelText ?? '').startsWith('Doctor name'))).controller!.text,
        'Anjali Kulkarni');

    // Receiving a payment clears the due; the ledger keeps both entries
    await Repo.receivePayment(cust.id!, 54, mode: 'UPI');
    expect((await Repo.customer(cust.id!))!.balance, 0);
    final ledger = await Repo.creditLedger(cust.id!);
    expect(ledger.map((e) => e.kind), ['bill', 'payment']);
    expect(ledger.last.runningBalance, 0);
  });

  testWidgets('box purchase is remembered; stock stays in strips; "1b" bills a full box', (t) async {
    // Medicine created without any box — boxes are optional.
    final pid = await Repo.saveProduct(Product(name: 'Paracip 500', packSize: 10));
    expect((await Repo.product(pid))!.hasOuter, isFalse);
    // Stock entry line bought as 3 full boxes of 10 strips.
    final purchaseId = await Repo.createPurchase(Purchase(invoiceNo: 'INV-BOX', invoiceDate: today()), [
      PurchaseItem(productId: pid, productName: 'Paracip 500', batchNo: 'PX1', expiry: DateTime(2028, 1, 31), packSize: 10, qtyPacks: 30, purchaseRate: 10, mrp: 15, gstRate: 12, boxQty: 3, boxSize: 10),
    ]);
    final saved = (await Repo.purchaseItems(purchaseId)).single;
    expect(saved.qtyLabel, '3 Box × 10 Strip');
    final prod = (await Repo.product(pid))!;
    expect(prod.outerSize, 10, reason: 'box size remembered from the purchase');
    expect(prod.qty(300), '30 Strip', reason: 'everyday stock is shown in strips');
    expect(prod.qtyWithBoxes(300), '3 Box');
    expect(prod.fullBoxes(300), 3);

    await t.pumpWidget(const MedBillingsApp());
    await settle(t);
    Nav.go(Nav.billing);
    await settle(t);
    await t.tap(field('Medicine (F3)'));
    await t.enterText(field('Medicine (F3)'), 'paracip');
    await settle(t);
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await settle(t);
    expect(find.text('Box'), findsWidgets); // Tab / Strip / Box selector
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await settle(t);
    await t.enterText(field('Qty'), '1b');
    await t.testTextInput.receiveAction(TextInputAction.done);
    await settle(t);
    await t.testTextInput.receiveAction(TextInputAction.done); // Disc → adds the line
    await settle(t);
    expect(find.text('10 Strip'), findsWidgets);
    expect(find.text('150.00'), findsWidgets); // 100 tabs × ₹1.50
  });

  testWidgets('billing is keyboard-only: Enter walks every field and checks out', (t) async {
    await Settings.instance.set('default_doctor_id', '');
    await t.pumpWidget(const MedBillingsApp());
    await settle(t);
    Nav.go(Nav.billing);
    await settle(t);
    String? focused() {
      for (final e in find.byType(TextField).evaluate()) {
        final tf = e.widget as TextField;
        if (tf.focusNode?.hasFocus ?? false) return tf.decoration?.labelText;
      }
      return null;
    }

    Future<void> enter() async {
      await t.testTextInput.receiveAction(TextInputAction.done);
      await settle(t);
    }

    await t.tap(field('Patient name'));
    await settle(t);
    await t.enterText(field('Patient name'), 'Kiran Joshi');
    await settle(t);
    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await enter();
    expect(focused(), 'Mobile');
    await t.enterText(field('Mobile'), '9800011111');
    await enter();
    expect(focused(), 'Address (optional)');
    await enter();
    expect(focused(), startsWith('Doctor name'));
    // Empty doctor + Enter must not grab a doctor from the list.
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await settle(t);
    expect(t.widget<TextField>(find.byWidgetPredicate((w) => w is TextField && (w.decoration?.labelText ?? '').startsWith('Doctor name'))).controller!.text, '');
    expect(focused(), 'Reg. no');
    await enter();
    expect(focused(), 'Clinic / hospital');
    await enter();
    expect(focused(), startsWith('Medical details'));
    await enter();
    expect(focused(), 'Medicine (F3)');

    await t.enterText(field('Medicine (F3)'), 'saline');
    await settle(t);
    await t.sendKeyEvent(LogicalKeyboardKey.enter); // pick medicine
    await settle(t);
    expect(focused(), 'Batch');
    await t.sendKeyEvent(LogicalKeyboardKey.enter); // accept FEFO batch
    await settle(t);
    expect(focused(), 'Qty');
    await t.enterText(field('Qty'), '1');
    await enter();
    expect(focused(), 'Disc');
    await enter(); // adds the line
    expect(find.text('32.00'), findsWidgets);
    expect(focused(), 'Medicine (F3)');

    await enter(); // empty medicine → checkout
    expect(focused(), isNull, reason: 'extra discount field has no label');
    await enter(); // extra discount → cash received
    expect(focused(), 'Cash received');
    final before = (await Repo.sales()).length;
    await t.enterText(field('Cash received'), '50');
    await enter(); // Save & Print (printing is switched off in tests)
    await t.pump(const Duration(seconds: 2));
    final sales = await Repo.sales();
    expect(sales.length, before + 1);
    expect(sales.first.customerName, 'Kiran Joshi');
    expect(sales.first.grandTotal, 32);
  });
}
