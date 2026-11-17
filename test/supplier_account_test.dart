import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:medical/core/db.dart';
import 'package:medical/core/settings.dart';
import 'package:medical/data/repo.dart';
import 'package:medical/models/models.dart';

/// Supplier accounts (goods received, paid, remaining) and where batches came from.
void main() {
  late Directory dir;
  late Supplier sup;
  late Product tab;

  setUpAll(() async {
    dir = await Directory.systemTemp.createTemp('medbillings_sup_');
    AppPaths.root = dir;
    for (final d in [Directory('${dir.path}/data'), AppPaths.billsDir, AppPaths.backupsDir]) {
      d.createSync(recursive: true);
    }
    await AppDb.open();
    await Settings.instance.load();
    sup = Supplier(name: 'Mahalaxmi Pharma');
    await Repo.saveSupplier(sup);
    tab = Product(name: 'Pan 40', packSize: 10, gstRate: 0);
    await Repo.saveProduct(tab);
    // ₹1000 paid at purchase, ₹500 on credit.
    await Repo.createPurchase(Purchase(supplierId: sup.id, invoiceNo: 'A1', invoiceDate: DateTime(2026, 10, 1), paid: true), [
      PurchaseItem(productId: tab.id!, productName: 'Pan 40', batchNo: 'P1', expiry: DateTime(2028, 1, 31), packSize: 10, qtyPacks: 10, purchaseRate: 100, mrp: 150, gstRate: 0),
    ]);
    await Repo.createPurchase(Purchase(supplierId: sup.id, invoiceNo: 'A2', invoiceDate: DateTime(2026, 11, 1), paid: false), [
      PurchaseItem(productId: tab.id!, productName: 'Pan 40', batchNo: 'P2', expiry: DateTime(2028, 6, 30), packSize: 10, qtyPacks: 5, purchaseRate: 100, mrp: 150, gstRate: 0),
    ]);
  });

  tearDownAll(() async {
    await AppDb.close();
    dir.deleteSync(recursive: true);
  });

  Future<Map<String, Object?>> row(String name) async => (await Repo.suppliersWithStats('')).firstWhere((r) => r['name'] == name);

  test('goods received, paid and remaining per supplier', () async {
    final r = await row('Mahalaxmi Pharma');
    expect(r['purchase_total'], 1500);
    expect(r['paid_total'], 1000);
    expect(r['remaining'], 500);
  });

  test('a part payment lowers what is owed; deleting it restores it', () async {
    await Repo.paySupplier(sup, 200, mode: 'UPI', note: 'part');
    var r = await row('Mahalaxmi Pharma');
    expect(r['paid_total'], 1200);
    expect(r['remaining'], 300);

    final acc = await Repo.supplierAccount(sup);
    expect(acc.goods, 1500);
    expect(acc.paid, 1200);
    expect(acc.remaining, 300);
    final a2 = acc.bills.first; // newest first
    expect(a2.label, 'Invoice A2');
    expect(a2.status, 'Part paid');
    expect(a2.paid, 200);
    expect(a2.remaining, 300);
    expect(a2.payments.single.$1.mode, 'UPI');
    final a1 = acc.bills.last;
    expect(a1.status, 'Cleared');
    expect(a1.paidAtEntry, isTrue);
    expect(a1.clearedAt, isNotNull);

    await Repo.deleteSupplierPayment(acc.payments.single.id);
    r = await row('Mahalaxmi Pharma');
    expect(r['remaining'], 500);
  });

  test('payments clear the oldest bills first; a payment can be for one bill', () async {
    final sup2 = Supplier(name: 'Ganesh Agencies');
    await Repo.saveSupplier(sup2);
    PurchaseItem item(int packs) =>
        PurchaseItem(productId: tab.id!, productName: 'Pan 40', batchNo: 'G$packs', expiry: DateTime(2029, 1, 31), packSize: 10, qtyPacks: packs, purchaseRate: 100, mrp: 150, gstRate: 0);
    await Repo.createPurchase(Purchase(supplierId: sup2.id, invoiceNo: 'G1', invoiceDate: DateTime(2026, 9, 1), paid: false), [item(3)]); // 300
    await Repo.createPurchase(Purchase(supplierId: sup2.id, invoiceNo: 'G2', invoiceDate: DateTime(2026, 10, 1), paid: false), [item(4)]); // 400
    await Repo.createPurchase(Purchase(supplierId: sup2.id, invoiceNo: 'G3', invoiceDate: DateTime(2026, 11, 1), paid: false), [item(2)]); // 200

    var acc = await Repo.supplierAccount(sup2);
    final g3 = acc.bills.firstWhere((b) => b.label == 'Invoice G3');
    await Repo.paySupplier(sup2, 200, mode: 'Cash', purchaseId: g3.purchase.id); // pays G3 exactly
    await Repo.paySupplier(sup2, 500, mode: 'Cheque', note: 'chq 1234'); // G1 300 + G2 200

    acc = await Repo.supplierAccount(sup2);
    SupplierBill bill(String l) => acc.bills.firstWhere((b) => b.label == 'Invoice $l');
    expect(bill('G3').status, 'Cleared');
    expect(bill('G1').status, 'Cleared');
    expect(bill('G1').clearedAt, acc.payments.firstWhere((p) => p.mode == 'Cheque').date);
    // G3 was paid by the earlier Cash payment; cleared on that date even though FIFO ran later.
    expect(bill('G3').clearedAt, acc.payments.firstWhere((p) => p.mode == 'Cash').date);
    expect(bill('G2').status, 'Part paid');
    expect(bill('G2').remaining, 200);
    expect(acc.openBills, 1);
    expect(acc.remaining, 200);
    final chq = acc.payments.firstWhere((p) => p.mode == 'Cheque');
    expect(chq.appliedTo.map((e) => (e.$1.label, e.$2)), [('Invoice G1', 300.0), ('Invoice G2', 200.0)]);

    // Paying more than owed leaves an advance.
    await Repo.paySupplier(sup2, 250);
    acc = await Repo.supplierAccount(sup2);
    expect(acc.openBills, 0);
    expect(acc.advance, 50);
    expect(acc.payments.first.advance, 50);
  });

  test('medicines supplied add up across stock entries', () async {
    final items = await Repo.supplierProducts(sup);
    expect(items, hasLength(1));
    expect(items.single['units'], 150); // 15 strips of 10
    expect(items.single['times'], 2);
    expect(items.single['value'], 1500);
  });

  test('each batch knows where it came from', () async {
    final origins = (await Repo.batchOrigins(tab.id!)).where((o) => o.source.id == sup.id).toList();
    expect(origins.map((o) => o.batchNo), ['P2', 'P1']); // newest first
    expect(origins.first.source.id, sup.id);
    expect(origins.first.sourceLabel, 'Mahalaxmi Pharma');
    expect(origins.first.paid, isFalse);
    expect(origins.first.units, 50);
  });

  test('one-off shops have their own account and can be paid', () async {
    await Repo.addOutsideStock(product: tab, sourceName: 'Shree Medical', batchNo: 'S1', expiry: DateTime(2029, 1, 31), mrp: 150, purchaseRate: 120, units: 20, paid: false);
    await Repo.addOutsideStock(product: tab, sourceName: 'shree medical', batchNo: 'S2', expiry: DateTime(2029, 1, 31), mrp: 150, purchaseRate: 120, units: 10, paid: true);
    var r = await row('Shree Medical');
    expect(r['one_off'], 1);
    expect(r['id'], isNull);
    expect(r['purchase_count'], 2);
    expect(r['purchase_total'], 360);
    expect(r['remaining'], 240);

    final shop = Supplier(name: 'Shree Medical');
    await Repo.paySupplier(shop, 240);
    r = await row('Shree Medical');
    expect(r['remaining'], 0);
    expect((await Repo.supplierAccount(shop)).remaining, 0);
    expect((await Repo.supplierAccount(shop)).openBills, 0);
    expect((await Repo.supplierProducts(shop)).single['units'], 30);
    // Saved supplier untouched by the one-off payment.
    expect((await row('Mahalaxmi Pharma'))['remaining'], 500);
  });
}
