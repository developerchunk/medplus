import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:medical/core/db.dart';
import 'package:medical/core/format.dart';
import 'package:medical/core/settings.dart';
import 'package:medical/data/repo.dart';
import 'package:medical/main.dart';
import 'package:medical/models/models.dart';
import 'package:medical/ui/nav.dart';

import 'test_window.dart';

/// Stock entry: keyboard flow, required dates, Strip/Box switches only for boxed medicines.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late int boxedId;
  late int plainId;

  setUpAll(() async {
    await keepTestWindowVisible();
    AppPaths.root = Directory.systemTemp.createTempSync('medbillings_se_');
    for (final d in [Directory('${AppPaths.root.path}/data'), AppPaths.billsDir, AppPaths.backupsDir]) {
      d.createSync(recursive: true);
    }
    await AppDb.open();
    await Settings.instance.load();
    await Settings.instance.set('last_expiry_alert', isoDate(today()));
    boxedId = await Repo.saveProduct(Product(name: 'O2 Tab', manufacturer: 'Medley', packSize: 10, outerName: 'Box', outerSize: 10));
    plainId = await Repo.saveProduct(Product(name: 'Plain Tab', packSize: 10));
  });

  Future<void> settle(WidgetTester t) async {
    for (var i = 0; i < 8; i++) {
      await t.pump(const Duration(milliseconds: 120));
    }
  }

  Finder field(String label) => find.byWidgetPredicate((w) => w is TextField && w.decoration?.labelText == label);

  String? focused(WidgetTester t) {
    for (final e in find.byType(TextField).evaluate()) {
      final tf = e.widget as TextField;
      if (tf.focusNode?.hasFocus ?? false) return tf.decoration?.labelText;
    }
    return null;
  }

  /// Types into the focused field and presses Enter.
  Future<void> typeEnter(WidgetTester t, String label, String text) async {
    await t.enterText(field(label), text);
    await settle(t);
    await t.testTextInput.receiveAction(TextInputAction.done);
    await settle(t);
  }

  testWidgets('keyboard flow, required mfg, box switches only for boxed medicines', (t) async {
    await t.pumpWidget(const MedBillingsApp());
    await settle(t);
    Nav.go(Nav.purchases);
    await settle(t);
    await t.tap(find.text('New stock entry').first);
    await settle(t);

    // ---- plain medicine (no box)
    await t.tap(field('Medicine'));
    await t.enterText(field('Medicine'), 'plain');
    await settle(t);
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await settle(t);
    expect(focused(t), 'Batch no *');
    expect(find.byIcon(Icons.swap_horiz), findsNothing, reason: 'no box switches for a medicine without boxes');
    expect(find.text('Tabs in Strip'), findsOneWidget);

    await typeEnter(t, 'Batch no *', 'pl1');
    expect(t.widget<TextField>(field('Batch no *')).controller!.text, 'PL1');
    expect(focused(t), 'Mfg *');

    // Leaving Mfg empty is not allowed
    await t.tap(find.text('Add item'));
    await settle(t);
    expect(find.textContaining('Enter the Mfg date'), findsOneWidget);

    await t.enterText(field('Mfg *'), '724');
    await settle(t);
    expect(t.widget<TextField>(field('Mfg *')).controller!.text, '07/24');
    expect(focused(t), 'Expiry *', reason: 'complete Mfg jumps to Expiry');
    await t.enterText(field('Expiry *'), '428');
    await settle(t);
    expect(focused(t), 'Qty *', reason: 'complete Expiry jumps to Qty');
    await typeEnter(t, 'Qty *', '5');
    expect(focused(t), 'Free');
    await t.testTextInput.receiveAction(TextInputAction.done);
    await settle(t);
    expect(focused(t), 'Purchase rate');
    await typeEnter(t, 'Purchase rate', '20');
    expect(focused(t), 'MRP *');
    await typeEnter(t, 'MRP *', '30');
    expect(find.text('GST'), findsNothing, reason: 'GST is off by default (not GST registered)');
    expect(focused(t), 'Disc');
    await t.testTextInput.receiveAction(TextInputAction.done); // Enter on Disc adds the item
    await settle(t);
    expect(find.text('Plain Tab'), findsOneWidget);
    expect(focused(t), 'Medicine');

    // ---- boxed medicine: 10 boxes, 1 free strip, rate per box, MRP per strip
    await t.enterText(field('Medicine'), 'o2');
    await settle(t);
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await settle(t);
    expect(find.byIcon(Icons.swap_horiz), findsNWidgets(4), reason: 'Qty, Free, Rate and MRP each get a Strip/Box switch');
    await typeEnter(t, 'Batch no *', 'e41140');
    await t.enterText(field('Mfg *'), '724');
    await settle(t);
    await t.enterText(field('Expiry *'), '428');
    await settle(t);
    await t.enterText(field('Qty *'), '10');
    await t.tap(find.byIcon(Icons.swap_horiz).at(0)); // Qty in boxes
    await settle(t);
    expect(find.text('= 100 Strip'), findsOneWidget);
    await t.enterText(field('Free'), '1');
    await t.enterText(field('Purchase rate'), '150');
    await t.tap(find.byIcon(Icons.swap_horiz).at(2)); // rate per box
    await settle(t);
    expect(find.text('= ₹15.00 / Strip'), findsOneWidget);
    await t.enterText(field('MRP *'), '25');
    await settle(t);
    await t.tap(find.text('Add item'));
    await settle(t);
    expect(find.text('10 Box × 10 Strip + 1 Strip free'), findsOneWidget);

    await t.tap(find.textContaining('Save entry'));
    await settle(t);
    await t.pump(const Duration(seconds: 1));

    final pu = (await Repo.purchases()).single;
    final items = await Repo.purchaseItems(pu.id!);
    final boxed = items.firstWhere((i) => i.productId == boxedId);
    expect(boxed.qtyPacks, 100);
    expect(boxed.freePacks, 1);
    expect(boxed.boxQty, 10);
    expect(boxed.purchaseRate, 15);
    expect(boxed.mrp, 25);
    expect(boxed.mfgDate, DateTime(2024, 7, 1));
    final plain = items.firstWhere((i) => i.productId == plainId);
    expect(plain.qtyPacks, 5);
    expect(plain.batchNo, 'PL1');
    expect((await Repo.productStock(boxedId))!.stockUnits, 1010);
  });

  testWidgets('template editor: Enter flow and quantity in the medicine\'s own units', (t) async {
    await t.pumpWidget(const MedBillingsApp());
    await settle(t);
    Nav.go(Nav.templates);
    await settle(t);
    await t.tap(find.text('New template').first);
    await settle(t);
    expect(focused(t), 'Name *');
    await typeEnter(t, 'Name *', 'Drip kit');
    expect(focused(t), 'Default doctor (optional)');
    await t.testTextInput.receiveAction(TextInputAction.done);
    await settle(t);
    expect(focused(t), 'Note (optional)');
    await t.testTextInput.receiveAction(TextInputAction.done);
    await settle(t);
    expect(focused(t), 'Add medicine');

    // Tablet with box: Tab / Strip / Box switch; 2 strips
    await t.enterText(field('Add medicine'), 'o2');
    await settle(t);
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await settle(t);
    expect(focused(t), 'Qty');
    expect(find.widgetWithText(SegmentedButton<int>, 'Box'), findsOneWidget);
    await t.tap(find.text('Strip').last);
    await settle(t);
    await typeEnter(t, 'Qty', '2');
    expect(find.text('2 Strip'), findsOneWidget);
    expect(focused(t), 'Add medicine');

    // Plain tablet: Tab / Strip only; 5 tablets
    await t.enterText(field('Add medicine'), 'plain');
    await settle(t);
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await settle(t);
    expect(find.widgetWithText(SegmentedButton<int>, 'Box'), findsNothing);
    await typeEnter(t, 'Qty', '5');
    expect(find.text('5 Tab'), findsOneWidget);

    // Enter on the empty medicine field saves
    await t.testTextInput.receiveAction(TextInputAction.done);
    await settle(t);
    final saved = (await Repo.templates()).firstWhere((x) => x.name == 'Drip kit');
    final full = (await Repo.template(id: saved.id))!;
    expect({for (final i in full.items) i.productId: i.qtyUnits}, {boxedId: 20, plainId: 5});
  });

  testWidgets('new medicine form: Enter walks the fields and saves; no GST fields while GST is off', (t) async {
    await t.pumpWidget(const MedBillingsApp());
    await settle(t);
    Nav.go(Nav.inventory);
    await settle(t);
    await t.tap(find.text('New medicine').first);
    await settle(t);
    expect(focused(t), 'Medicine name *');
    expect(find.text('GST rate'), findsNothing);
    expect(find.text('HSN code'), findsNothing);
    await typeEnter(t, 'Medicine name *', 'Cough Syrup X');
    expect(focused(t), 'Generic / composition');
    await t.testTextInput.receiveAction(TextInputAction.done);
    await settle(t);
    expect(focused(t), 'Manufacturer / company');
    for (final next in ['Loose unit', 'Pack', 'Tabs per Strip', 'Instructions / warning shown at billing', 'Rack / shelf', 'Reorder when stock falls to']) {
      await t.testTextInput.receiveAction(TextInputAction.done);
      await settle(t);
      expect(focused(t), next);
    }
    await t.testTextInput.receiveAction(TextInputAction.done); // last field saves
    await settle(t);
    expect((await Repo.searchProducts('Cough Syrup X')).single.product.gstRate, 5, reason: 'medicines default to 5% GST');
  });

  testWidgets('supplier and credit customer forms: Enter walks every field and saves', (t) async {
    await t.pumpWidget(const MedBillingsApp());
    await settle(t);

    // ---- supplier
    Nav.go(Nav.suppliers);
    await settle(t);
    await t.tap(find.text('New supplier').first);
    await settle(t);
    expect(focused(t), 'Firm name *');
    await typeEnter(t, 'Firm name *', 'Saikrupa Medical Agencies');
    for (final next in ['Contact person', 'Phone', 'GSTIN', 'Drug license no', 'Email', 'Address', 'Notes (credit terms, delivery days…)']) {
      expect(focused(t), next);
      await t.testTextInput.receiveAction(TextInputAction.done);
      await settle(t);
    }
    expect((await Repo.searchSuppliers('Saikrupa')).single.name, 'Saikrupa Medical Agencies');

    // ---- credit customer
    Nav.go(Nav.credit);
    await settle(t);
    await t.tap(find.text('New credit customer').first);
    await settle(t);
    expect(focused(t), 'Name *');
    await typeEnter(t, 'Name *', 'Sunita Shinde');
    expect(focused(t), 'Mobile');
    await typeEnter(t, 'Mobile', '9822022222');
    expect(focused(t), 'Address');
    await t.testTextInput.receiveAction(TextInputAction.done);
    await settle(t);
    expect(focused(t), 'Credit limit (optional)');
    await typeEnter(t, 'Credit limit (optional)', '3000');
    expect(focused(t), 'Notes (e.g. pays on the 1st of every month)');
    await t.testTextInput.receiveAction(TextInputAction.done); // saves
    await settle(t);
    final c = (await Repo.searchCustomers('Sunita')).single;
    expect(c.creditAllowed, isTrue);
    expect(c.creditLimit, 3000);
  });
}
