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
    // A second medicine from a different supplier, for sorting / filtering.
    final city = Supplier(name: 'City Distributors');
    await Repo.saveSupplier(city);
    final azee = Product(name: 'Azee 500', packSize: 3);
    await Repo.saveProduct(azee);
    await Repo.createPurchase(Purchase(supplierId: city.id, invoiceNo: 'CD-7', invoiceDate: DateTime(2026, 9, 1)), [
      PurchaseItem(productId: azee.id!, productName: 'Azee 500', batchNo: 'AZ1', expiry: DateTime(2028, 3, 31), packSize: 3, qtyPacks: 4, purchaseRate: 60, mrp: 90, gstRate: 0),
    ]);
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

    // Supplier dashboard (full screen).
    await t.tap(find.text('Mahalaxmi Pharma'));
    await settle(t);
    await waitFor(t, find.text('Remaining to pay'));
    expect(find.text('Bills (2)'), findsOneWidget);
    expect(find.text('Payments (1)'), findsOneWidget);
    expect(find.text('Medicines (1)'), findsOneWidget);
    expect(find.text('Part paid'), findsOneWidget); // MP-1088: ₹200 of ₹500 paid
    expect(find.textContaining('Cleared '), findsOneWidget); // MP-1021 paid at purchase
    await shot(t, 'supplier_dashboard_1024');

    // Bill detail: payments with dates.
    await t.tap(find.text('Invoice MP-1088'));
    await settle(t);
    await waitFor(t, find.text('PAYMENTS FOR THIS BILL'));
    expect(find.text('UPI'), findsOneWidget);
    expect(find.text('Remaining ₹300.00'), findsOneWidget);
    await shot(t, 'supplier_bill_1024');
    await t.tap(find.text('Pay ₹300.00'));
    await settle(t);
    await t.tap(find.text('Save payment'));
    await settle(t);
    await t.pump(const Duration(milliseconds: 500));
    await settle(t);
    expect(find.text('All bills cleared'), findsOneWidget);
    expect(find.text('Part paid'), findsNothing);

    await t.tap(find.text('Payments (2)'));
    await settle(t);
    expect(find.textContaining('Invoice MP-1088 ₹300.00 (cleared)'), findsOneWidget);
    await shot(t, 'supplier_payments_1024');
    await t.tap(find.byTooltip('Back to suppliers'));
    await settle(t);
    expect(find.text('New supplier'), findsOneWidget);
  });

  testWidgets('inventory list: supplier column, filter by supplier with totals, sort by supplier', (t) async {
    await t.pumpWidget(const MedBillingsApp());
    await settle(t);
    Nav.go(Nav.inventory);
    await settle(t);
    await waitFor(t, find.text('Azee 500'));
    expect(find.text('SUPPLIER'), findsOneWidget);
    expect(find.text('City Distributors'), findsOneWidget);
    expect(find.text('Shree Medical  +1'), findsOneWidget); // Pan 40: latest from Shree, also Mahalaxmi

    // Sort by supplier: City Distributors (Azee) before Shree Medical (Pan).
    await t.tap(find.textContaining('Sort: '));
    await settle(t);
    await t.tap(find.text('Supplier').last);
    await settle(t);
    expect(t.getTopLeft(find.text('Azee 500')).dy, lessThan(t.getTopLeft(find.text('Pan 40')).dy));
    await shot(t, 'inventory_sorted_1024');

    // Filter to Mahalaxmi Pharma: only Pan 40, with the supplier's money summary.
    await t.tap(find.text('All suppliers'));
    await settle(t);
    await t.tap(find.text('Mahalaxmi Pharma').last);
    await settle(t);
    expect(find.text('Azee 500'), findsNothing);
    expect(find.text('Pan 40'), findsOneWidget);
    expect(find.text('Goods ₹1,500.00'), findsOneWidget);
    expect(find.text('Nothing owed'), findsOneWidget); // paid off in the previous test
    await shot(t, 'inventory_filtered_1024');
    await t.tap(find.byTooltip('Show all suppliers'));
    await settle(t);
    expect(find.text('Azee 500'), findsOneWidget);
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
