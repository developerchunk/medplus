import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:medical/core/db.dart';
import 'package:medical/core/debug_hooks.dart';
import 'package:medical/core/format.dart';
import 'package:medical/core/settings.dart';
import 'package:medical/data/repo.dart';
import 'package:medical/main.dart';
import 'package:medical/models/models.dart';
import 'package:medical/ui/nav.dart';
import 'package:window_manager/window_manager.dart';

import 'test_window.dart';

/// Supplier accounts and "bought from" in inventory, on the shop's 1024×768 screen.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await keepTestWindowVisible();
    await windowManager.setMinimumSize(const Size(800, 600));
    await windowManager.setSize(const Size(1024, 768));
    await windowManager.center();
    AppPaths.root = Directory.systemTemp.createTempSync('medbillings_it_');
    for (final d in [Directory('${AppPaths.root.path}/data'), AppPaths.billsDir, AppPaths.backupsDir]) {
      d.createSync(recursive: true);
    }
    await AppDb.open();
    await Settings.instance.load();
    await Settings.instance.setAll({'last_expiry_alert': isoDate(today())});
    final sup = Supplier(name: 'Mahalaxmi Pharma', contactPerson: 'Sunil', phone: '9822000000');
    await Repo.saveSupplier(sup);
    final pan = Product(name: 'Pan 40', manufacturer: 'Alkem', packSize: 10);
    await Repo.saveProduct(pan);
    await Repo.createPurchase(Purchase(supplierId: sup.id, invoiceNo: 'MP-1021', invoiceDate: DateTime(2026, 10, 1)), [
      PurchaseItem(productId: pan.id!, productName: 'Pan 40', batchNo: 'PN2201', expiry: DateTime(2028, 1, 31), packSize: 10, qtyPacks: 10, purchaseRate: 100, mrp: 150, gstRate: 0),
    ]);
    await Repo.createPurchase(Purchase(supplierId: sup.id, invoiceNo: 'MP-1088', invoiceDate: DateTime(2026, 11, 1), paid: false), [
      PurchaseItem(productId: pan.id!, productName: 'Pan 40', batchNo: 'PN2240', expiry: DateTime(2028, 6, 30), packSize: 10, qtyPacks: 5, purchaseRate: 100, mrp: 150, gstRate: 0),
    ]);
    await Repo.paySupplier(sup, 200, mode: 'UPI');
    await Repo.addOutsideStock(product: pan, sourceName: 'Shree Medical', batchNo: 'SX9', expiry: DateTime(2029, 1, 31), mrp: 150, purchaseRate: 125, units: 6, paid: false);
  });

  Future<void> settle(WidgetTester t) async {
    for (var i = 0; i < 10; i++) {
      await t.pump(const Duration(milliseconds: 120));
    }
  }

  Future<void> waitFor(WidgetTester t, Finder f, {int tries = 40}) async {
    for (var i = 0; i < tries && f.evaluate().isEmpty; i++) {
      await t.pump(const Duration(milliseconds: 150));
    }
  }

  Future<void> shot(WidgetTester t, String name) async {
    final dir = Platform.environment['SHOT_DIR'];
    if (dir == null) return;
    await t.runAsync(() async {
      final b = appBoundaryKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final img = await b.toImage(pixelRatio: 1);
      final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
      File('$dir/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
    });
  }

  testWidgets('suppliers list and account: goods, paid, remaining, medicines', (t) async {
    await t.pumpWidget(const MedBillingsApp());
    await settle(t);
    Nav.go(Nav.suppliers);
    await settle(t);
    await waitFor(t, find.text('Mahalaxmi Pharma'));
    expect(find.text('One-off shop'), findsOneWidget);
    expect(find.text('₹1,500.00'), findsWidgets); // goods received
    expect(find.text('₹300.00'), findsWidgets); // remaining after ₹200 UPI
    await shot(t, 'suppliers_1024');

    await t.tap(find.text('Mahalaxmi Pharma'));
    await settle(t);
    await waitFor(t, find.text('Remaining to pay'));
    expect(find.text('Medicines supplied (1)'.toUpperCase()), findsOneWidget);
    expect(find.text('Payment · UPI'), findsOneWidget);
    await shot(t, 'supplier_account_1024');

    // Record a payment for the rest.
    await t.tap(find.text('Record payment'));
    await settle(t);
    await t.tap(find.text('Save payment'));
    await settle(t);
    await t.pump(const Duration(milliseconds: 500));
    await settle(t);
    expect(find.text('Paid in advance'), findsNothing);
    expect(find.text('₹0.00'), findsWidgets);
    await t.tap(find.text('Close'));
    await settle(t);
  });

  testWidgets('inventory shows where each batch came from', (t) async {
    await t.pumpWidget(const MedBillingsApp());
    await settle(t);
    Nav.go(Nav.inventory);
    await settle(t);
    await waitFor(t, find.text('Pan 40'));
    await t.tap(find.text('Pan 40').first);
    await settle(t);
    await waitFor(t, find.textContaining('from Mahalaxmi Pharma'));
    expect(find.textContaining('from Mahalaxmi Pharma · Inv MP-1088'), findsOneWidget);
    expect(find.textContaining('from Shree Medical'), findsOneWidget);
    await shot(t, 'product_batches_1024');

    await t.tap(find.textContaining('Bought from ('));
    await settle(t);
    expect(find.text('MP-1021'), findsOneWidget);
    expect(find.text('On credit'), findsNWidgets(2));
    await shot(t, 'product_bought_from_1024');
  });
}
