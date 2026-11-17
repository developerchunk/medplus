import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:medical/core/db.dart';
import 'package:medical/core/format.dart';
import 'package:medical/core/settings.dart';
import 'package:medical/core/updater.dart';
import 'package:medical/data/repo.dart';
import 'package:medical/models/models.dart';
import 'package:medical/ui/billing/billing_page.dart' show BillLine;

void main() {
  group('update versions', () {
    test('parses pubspec, tag and Debian forms', () {
      expect(AppVersion.parse('1.2.3+4')!.build, 4);
      expect(AppVersion.parse('v1.2.3')!.toString(), '1.2.3');
      expect(AppVersion.parse('1.2.3-7')!.build, 7);
      expect(AppVersion.parse('nonsense'), isNull);
    });
    test('compares major, minor, patch, then build', () {
      final v = AppVersion.parse;
      expect(v('1.1.0+2')! > v('1.0.9+40')!, isTrue);
      expect(v('1.0.0-3')! > v('1.0.0+2')!, isTrue);
      expect(v('1.0.0+1')! > v('1.0.0+1')!, isFalse);
      expect(v('2.0.0')! > v('10.0.0')!, isFalse);
    });
  });

  group('discounts in rupees or percent', () {
    Product tab() => Product(id: 1, name: 'Paracetamol 650', packSize: 10);
    Batch batch() => Batch(id: 1, productId: 1, batchNo: 'B1', expiry: DateTime(2030, 1, 31), packSize: 10, mrp: 30, qty: 100);

    test('percent discount', () {
      final l = BillLine(product: tab(), batches: [batch()], batch: batch(), qty: 20, disc: 10);
      expect(l.gross, 60);
      expect(l.amount, 54);
      expect(l.discRupees, 6);
      expect(l.discPct, 10);
    });
    test('rupee discount, shown as a derived percent', () {
      final l = BillLine(product: tab(), batches: [batch()], batch: batch(), qty: 20, disc: 5, discRs: true);
      expect(l.amount, 55);
      expect(l.discRupees, 5);
      expect(l.discPct, 8.33);
    });
    test('a rupee discount never makes a line negative', () {
      final l = BillLine(product: tab(), batches: [batch()], batch: batch(), qty: 2, disc: 50, discRs: true);
      expect(l.amount, 0);
      expect(l.discRupees, 6);
    });
    test('bill prints ₹ or % as given', () {
      SaleItem item({double pct = 0, double rs = 0}) => SaleItem(
          productId: 1, batchId: 1, productName: 'X', batchNo: 'B', expiry: DateTime(2030), packSize: 10, unitName: 'Tab', packName: 'Strip',
          qtyUnits: 10, mrp: 30, unitRate: 3, discountPct: pct, discountRs: rs);
      expect(item(pct: 10).discountLabel, '10%');
      expect(item(pct: 16.67, rs: 5).discountLabel, '₹5');
      expect(item().discountLabel, '');
    });
  });

  test('loose units on a purchase line', () {
    final it = PurchaseItem(productId: 1, batchNo: 'B', expiry: DateTime(2030), packSize: 10, qtyPacks: 1, looseUnits: 6, purchaseRate: 20, mrp: 30, gstRate: 0, packName: 'Strip');
    expect(it.totalUnits, 16);
    expect(it.gross, closeTo(32, 0.001));
    expect(it.qtyLabel, '1 Strip + 6 loose');
  });

  group('medicine brought from outside (database)', () {
    late Directory dir;
    setUpAll(() async {
      dir = await Directory.systemTemp.createTemp('medbillings_test_');
      AppPaths.root = dir;
      for (final d in [Directory('${dir.path}/data'), AppPaths.billsDir, AppPaths.backupsDir]) {
        d.createSync(recursive: true);
      }
      await AppDb.open();
      await Settings.instance.load();
    });
    tearDownAll(() async {
      await AppDb.close();
      dir.deleteSync(recursive: true);
    });

    test('new medicine from a one-off shop: billed part sold, rest kept in stock', () async {
      final p = Product(name: 'Special Inj 40', form: 'Injection', unitName: 'Vial', packName: 'Box', packSize: 1);
      final b = await Repo.addOutsideStock(
          product: p, sourceName: 'Shree Medical', batchNo: 'sx1', expiry: DateTime(2031, 5, 31), mrp: 250, purchaseRate: 200, units: 3);
      expect(p.id, isNotNull);
      expect(b.batchNo, 'SX1');
      expect(b.qty, 3);

      final sources = await Repo.purchaseSources('shree');
      expect(sources.map((s) => s.name), contains('Shree Medical'));
      expect(sources.firstWhere((s) => s.name == 'Shree Medical').id, isNull); // one-off, not a saved supplier

      final sale = await Repo.createSale(Sale(paymentMode: 'Cash', items: [
        SaleItem(
            productId: p.id!, batchId: b.id!, productName: p.name, batchNo: b.batchNo, expiry: b.expiry, packSize: 1, unitName: 'Vial', packName: 'Box',
            qtyUnits: 1, mrp: 250, unitRate: 250, discountPct: 4, discountRs: 10, amount: 240),
      ], grossTotal: 250, itemDiscount: 10, grandTotal: 240, paidAmount: 240));
      expect(sale.billNo, isNotEmpty);
      expect((await Repo.batch(b.id!))!.qty, 2); // leftover stays in stock
      final saved = await Repo.sale(sale.id!);
      expect(saved!.items.single.discountRs, 10);
    });

    test('loose tablets from a saved supplier, and deleting that purchase', () async {
      final sup = Supplier(name: 'City Distributors');
      await Repo.saveSupplier(sup);
      final p = Product(name: 'Rare Tab 5', packSize: 10);
      await Repo.saveProduct(p);
      final b = await Repo.addOutsideStock(product: p, supplier: sup, batchNo: '', expiry: DateTime(2030, 12, 31), mrp: 45, units: 6);
      expect(b.qty, 6);
      expect(b.batchNo, startsWith('OUT'));
      final purchases = await Repo.purchases(supplierId: sup.id);
      expect(purchases, hasLength(1));
      final items = await Repo.purchaseItems(purchases.single.id!);
      expect(items.single.looseUnits, 6);
      expect(items.single.qtyPacks, 0);
      await Repo.deletePurchase(purchases.single.id!);
      expect((await Repo.batchesForProduct(p.id!, sellableOnly: true)), isEmpty);
    });

    test('nothing brought is rejected', () async {
      expect(
          () => Repo.addOutsideStock(product: Product(name: 'Zero', packSize: 1), sourceName: 'X', batchNo: 'Z', expiry: today(), mrp: 1, units: 0),
          throwsA(isA<RepoException>()));
    });
  });
}
