import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:medical/core/db.dart';
import 'package:medical/core/debug_hooks.dart';
import 'package:medical/core/format.dart';
import 'package:medical/core/print_service.dart';
import 'package:medical/core/settings.dart';
import 'package:medical/core/unsaved_work.dart';
import 'package:medical/data/repo.dart';
import 'package:medical/main.dart';
import 'package:medical/models/models.dart';
import 'package:medical/ui/nav.dart';
import 'package:window_manager/window_manager.dart';

import 'test_window.dart';

/// Small shop screen (1024×768), medicine brought from another shop, and ₹ discounts.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late int doloId;

  setUpAll(() async {
    await keepTestWindowVisible();
    // The shop PC's screen: 1024×768.
    await windowManager.setMinimumSize(const Size(800, 600));
    await windowManager.setSize(const Size(1024, 768));
    await windowManager.center();
    PrintService.enabled = false;
    AppPaths.root = Directory.systemTemp.createTempSync('medbillings_it_');
    for (final d in [Directory('${AppPaths.root.path}/data'), AppPaths.billsDir, AppPaths.backupsDir]) {
      d.createSync(recursive: true);
    }
    await AppDb.open();
    await Settings.instance.load();
    await Settings.instance.setAll({'last_expiry_alert': isoDate(today()), 'bill_prefix': 'O-'});
    doloId = await Repo.saveProduct(Product(name: 'Dolo 650', packSize: 15)); // never stocked
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

  Finder field(String label) => find.byWidgetPredicate((w) => w is TextField && w.decoration?.labelText == label);

  /// Saves a picture of the app to [name] in SHOT_DIR (when set), for checking layouts by eye.
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

  Future<void> ctrlS(WidgetTester t) async {
    await t.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await t.sendKeyEvent(LogicalKeyboardKey.keyS);
    await t.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await settle(t);
    await t.pump(const Duration(seconds: 1));
  }

  testWidgets('new medicine brought from a shop, ₹ discounts, readable on 1024×768', (t) async {
    await t.pumpWidget(const MedBillingsApp());
    await settle(t);
    Nav.go(Nav.billing);
    await settle(t);

    // Table header stays on one line on the small screen.
    final header = find.text('MEDICINE');
    expect(header, findsOneWidget);
    expect(t.getSize(header).height, lessThan(30));
    expect(t.getSize(header).width, greaterThan(50));

    // Not in the list → "Add brought medicine" from the empty suggestions.
    await t.tap(field('Medicine (F3)'));
    await t.enterText(field('Medicine (F3)'), 'Ultracet Special');
    await settle(t);
    await waitFor(t, find.text('Add brought medicine (F8)'));
    await t.tap(find.text('Add brought medicine (F8)'));
    await settle(t);
    expect(find.text('Medicine brought from outside'), findsOneWidget);
    await shot(t, 'dialog_1024');
    expect(t.widget<TextField>(field('Medicine name *')).controller!.text, 'Ultracet Special');

    await t.enterText(field('Supplier or shop name *'), 'Shree Medical');
    await t.enterText(field('Expiry *'), '1230');
    await t.enterText(field('MRP / Strip *'), '150');
    await t.enterText(field('Paid / Strip'), '120');
    await t.enterText(field('Brought *'), '2'); // 2 strips
    await t.enterText(field('For this bill'), '1'); // 1 strip on this bill
    await settle(t);
    expect(find.textContaining('left over after this bill'), findsOneWidget);
    await t.tap(find.text('Add to bill'));
    await settle(t);
    await t.pump(const Duration(seconds: 1));
    await settle(t);

    expect(find.text('Medicine brought from outside'), findsNothing);
    expect(find.text('150.00'), findsWidgets); // 1 strip of 10 @ 150
    await shot(t, 'bill_1024');

    // Line discount in rupees: switch % → ₹ and give ₹15 off.
    // Discount fields with a %/₹ switch and no label: the bill line's, then the extra discount.
    Finder discFields() =>
        find.byWidgetPredicate((w) => w is TextField && w.decoration?.labelText == null && w.decoration?.hintText == '0' && w.decoration?.suffixIcon != null);
    final lineDisc = discFields().first;
    await t.tap(find.descendant(of: lineDisc, matching: find.text('%')));
    await settle(t);
    await t.enterText(lineDisc, '15');
    await settle(t);
    expect(find.text('135.00'), findsWidgets);

    // Extra discount in rupees: ₹5 off the bill.
    final billDisc = discFields().last;
    await t.tap(find.descendant(of: billDisc, matching: find.text('%')));
    await settle(t);
    await t.enterText(billDisc, '5');
    await settle(t);
    expect(find.text('₹130.00'), findsWidgets);

    // A started bill blocks the update restart.
    expect(UnsavedWork.pending().single.where, 'New Bill');

    await ctrlS(t);
    final sales = await Repo.sales();
    expect(sales, hasLength(1));
    final sale = (await Repo.sale(sales.single.id!))!;
    expect(sale.grandTotal, 130);
    expect(sale.billDiscount, 5);
    expect(sale.items.single.discountRs, 15);
    expect(sale.items.single.discountLabel, '₹15');
    expect(UnsavedWork.pending(), isEmpty);

    // The other strip stays in stock; the shop is remembered as a one-off source.
    final p = (await Repo.searchProducts('Ultracet')).single;
    expect(p.stockUnits, 10);
    expect((await Repo.purchaseSources('shree')).single.name, 'Shree Medical');
  });

  testWidgets('out-of-stock medicine opens the brought-stock popup', (t) async {
    await t.pumpWidget(const MedBillingsApp());
    await settle(t);
    Nav.go(Nav.billing);
    await settle(t);

    await t.tap(field('Medicine (F3)'));
    await t.enterText(field('Medicine (F3)'), 'dolo');
    await settle(t);
    await waitFor(t, find.text('Dolo 650'));
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await settle(t);
    await waitFor(t, find.text('Add brought stock'));
    expect(find.text('Add brought stock'), findsOneWidget);
    expect(find.textContaining('out of stock'), findsWidgets);

    // Pick the shop used before from the suggestions.
    await t.tap(field('Supplier or shop name *'));
    await settle(t);
    await waitFor(t, find.text('Used before (one-off)'));
    await t.tap(find.text('Shree Medical').last);
    await settle(t);
    await t.enterText(field('Expiry *'), '0629');
    await t.enterText(field('MRP / Strip *'), '33');
    await t.enterText(field('Brought *'), '1');
    await settle(t);
    await t.tap(find.text('Add to bill'));
    await settle(t);
    await t.pump(const Duration(seconds: 1));
    await settle(t);
    expect(find.text('33.00'), findsWidgets);

    final stock = await Repo.batchesForProduct(doloId, sellableOnly: true);
    expect(stock.single.qty, 15);
    await ctrlS(t);
    expect((await Repo.batchesForProduct(doloId, includeEmpty: true)).single.qty, 0);
  });
}
