import '../core/format.dart';

DateTime? _date(Object? v) => v == null || v == '' ? null : DateTime.tryParse(v as String);
double _d(Object? v) => (v as num?)?.toDouble() ?? 0;
int _i(Object? v) => (v as num?)?.toInt() ?? 0;
String _s(Object? v) => (v as String?) ?? '';

// ------------------------------------------------------------------ forms

class ProductForm {
  final String name;
  final String unit;
  final String pack;
  final int packSize;
  const ProductForm(this.name, this.unit, this.pack, this.packSize);

  static const all = <ProductForm>[
    ProductForm('Tablet', 'Tab', 'Strip', 10),
    ProductForm('Capsule', 'Cap', 'Strip', 10),
    ProductForm('Syrup', 'Bottle', 'Bottle', 1),
    ProductForm('Suspension', 'Bottle', 'Bottle', 1),
    ProductForm('Injection', 'Vial', 'Box', 1),
    ProductForm('IV Fluid / Saline', 'Bottle', 'Bottle', 1),
    ProductForm('Cream', 'Tube', 'Tube', 1),
    ProductForm('Ointment', 'Tube', 'Tube', 1),
    ProductForm('Gel', 'Tube', 'Tube', 1),
    ProductForm('Eye Drops', 'Bottle', 'Bottle', 1),
    ProductForm('Ear Drops', 'Bottle', 'Bottle', 1),
    ProductForm('Nasal Spray', 'Bottle', 'Bottle', 1),
    ProductForm('Inhaler', 'Pc', 'Pc', 1),
    ProductForm('Powder / Sachet', 'Sachet', 'Box', 1),
    ProductForm('Lotion / Soap', 'Pc', 'Pc', 1),
    ProductForm('Surgical / Device', 'Pc', 'Pc', 1),
    ProductForm('Other', 'Pc', 'Pc', 1),
  ];

  static ProductForm of(String name) =>
      all.firstWhere((f) => f.name == name, orElse: () => all.last);
}

/// Indian Drugs & Cosmetics Rules schedules relevant at the counter.
class DrugSchedule {
  static const none = '';
  static const values = ['', 'G', 'H', 'H1', 'X', 'NDPS'];
  static String label(String s) => s.isEmpty ? 'OTC / None' : 'Schedule $s';
  static bool rxByDefault(String s) => ['H', 'H1', 'X', 'NDPS'].contains(s);
}

// ------------------------------------------------------------------ master data

class Supplier {
  int? id;
  String name;
  String contactPerson;
  String phone;
  String email;
  String address;
  String gstin;
  String drugLicense;
  String notes;

  Supplier({
    this.id,
    required this.name,
    this.contactPerson = '',
    this.phone = '',
    this.email = '',
    this.address = '',
    this.gstin = '',
    this.drugLicense = '',
    this.notes = '',
  });

  factory Supplier.fromMap(Map<String, Object?> m) => Supplier(
        id: m['id'] as int?,
        name: _s(m['name']),
        contactPerson: _s(m['contact_person']),
        phone: _s(m['phone']),
        email: _s(m['email']),
        address: _s(m['address']),
        gstin: _s(m['gstin']),
        drugLicense: _s(m['drug_license']),
        notes: _s(m['notes']),
      );

  Map<String, Object?> toMap() => {
        'id': id,
        'name': name,
        'contact_person': contactPerson,
        'phone': phone,
        'email': email,
        'address': address,
        'gstin': gstin,
        'drug_license': drugLicense,
        'notes': notes,
      };
}

class Product {
  int? id;
  String name;
  String genericName;
  String manufacturer;
  String form;
  String unitName;
  String packName;
  int packSize;
  String outerName; // e.g. Box (strips per box); empty = no outer pack
  int outerSize; // packs per outer pack; 0/1 = none
  String hsn;
  double gstRate;
  String schedule;
  bool rxRequired;
  bool isAntibiotic;
  String instructions;
  String rack;
  int reorderLevel; // in units
  bool active;

  Product({
    this.id,
    required this.name,
    this.genericName = '',
    this.manufacturer = '',
    this.form = 'Tablet',
    this.unitName = 'Tab',
    this.packName = 'Strip',
    this.packSize = 10,
    this.outerName = '',
    this.outerSize = 0,
    this.hsn = '3004',
    this.gstRate = 5,
    this.schedule = '',
    this.rxRequired = false,
    this.isAntibiotic = false,
    this.instructions = '',
    this.rack = '',
    this.reorderLevel = 0,
    this.active = true,
  });

  /// True when the counter must see a doctor's prescription.
  bool get needsPrescription => rxRequired || isAntibiotic || DrugSchedule.rxByDefault(schedule);

  String get warningText {
    if (instructions.trim().isNotEmpty) return instructions.trim();
    if (isAntibiotic) return 'This is an antibiotic. A doctor\'s prescription is required.';
    if (needsPrescription) return 'Prescription drug. Sell only on a registered medical practitioner\'s prescription.';
    return '';
  }

  bool get hasOuter => outerSize > 1 && outerName.isNotEmpty;
  int get unitsPerOuter => hasOuter ? outerSize * packSize : 0;

  /// Everyday stock/billing quantity: strips + loose tablets (boxes are never used here).
  String qty(int units) => fmtQty(units, packSize, unitName, packName);

  /// Quantity including full boxes, for the few places boxes matter
  /// (stock entry, packing details, expiry of full boxes).
  String qtyWithBoxes(int units) => fmtQty(units, packSize, unitName, packName, outerSize: hasOuter ? outerSize : 0, outerName: outerName);

  /// Number of complete outer packs (boxes) in [units]; 0 when the medicine has no box.
  int fullBoxes(int units) => hasOuter ? units ~/ unitsPerOuter : 0;

  /// "10 Tab per Strip · 10 Strip per Box"
  String get packingLabel => [
        if (packSize > 1 && unitName != packName) '$packSize $unitName per $packName',
        if (hasOuter) '$outerSize $packName per $outerName',
      ].join(' · ');

  factory Product.fromMap(Map<String, Object?> m) => Product(
        id: m['id'] as int?,
        name: _s(m['name']),
        genericName: _s(m['generic_name']),
        manufacturer: _s(m['manufacturer']),
        form: _s(m['form']),
        unitName: _s(m['unit_name']),
        packName: _s(m['pack_name']),
        packSize: _i(m['pack_size']).clamp(1, 100000),
        outerName: _s(m['outer_name']),
        outerSize: _i(m['outer_size']),
        hsn: _s(m['hsn']),
        gstRate: _d(m['gst_rate']),
        schedule: _s(m['schedule']),
        rxRequired: _i(m['rx_required']) == 1,
        isAntibiotic: _i(m['is_antibiotic']) == 1,
        instructions: _s(m['instructions']),
        rack: _s(m['rack']),
        reorderLevel: _i(m['reorder_level']),
        active: _i(m['active']) == 1,
      );

  Map<String, Object?> toMap() => {
        'id': id,
        'name': name,
        'generic_name': genericName,
        'manufacturer': manufacturer,
        'form': form,
        'unit_name': unitName,
        'pack_name': packName,
        'pack_size': packSize,
        'outer_name': outerName,
        'outer_size': outerSize,
        'hsn': hsn,
        'gst_rate': gstRate,
        'schedule': schedule,
        'rx_required': rxRequired ? 1 : 0,
        'is_antibiotic': isAntibiotic ? 1 : 0,
        'instructions': instructions,
        'rack': rack,
        'reorder_level': reorderLevel,
        'active': active ? 1 : 0,
      };
}

/// A product row enriched with live stock numbers, used by lists & suggestions.
class ProductStock {
  final Product product;
  final int stockUnits;
  final int batchCount;
  final DateTime? nearestExpiry;
  final double? mrp; // of the nearest-expiry batch
  final int expiredUnits; // still on the shelf but past expiry

  ProductStock(this.product, this.stockUnits, this.batchCount, this.nearestExpiry, this.mrp, [this.expiredUnits = 0]);

  bool get lowStock => product.reorderLevel > 0 && stockUnits <= product.reorderLevel;
}

class Batch {
  int? id;
  int productId;
  String batchNo;
  DateTime? mfgDate;
  DateTime expiry;
  int packSize;
  double mrp; // per pack, GST inclusive
  double purchaseRate; // per pack
  double saleRate; // per pack, GST inclusive (<= MRP)
  double gstRate;
  double discountPct; // default counter discount for this batch
  int qty; // current stock in units
  int initialQty;
  int? supplierId;
  int? purchaseId;
  String status; // active | returned | disposed
  DateTime? createdAt;

  Batch({
    this.id,
    required this.productId,
    required this.batchNo,
    this.mfgDate,
    required this.expiry,
    required this.packSize,
    required this.mrp,
    this.purchaseRate = 0,
    double? saleRate,
    this.gstRate = 5,
    this.discountPct = 0,
    this.qty = 0,
    this.initialQty = 0,
    this.supplierId,
    this.purchaseId,
    this.status = 'active',
    this.createdAt,
  }) : saleRate = saleRate ?? mrp;

  double get unitRate => saleRate / packSize;
  double get unitMrp => mrp / packSize;
  int get daysLeft => daysUntil(expiry);
  bool get isExpired => daysLeft < 0;

  factory Batch.fromMap(Map<String, Object?> m) => Batch(
        id: m['id'] as int?,
        productId: _i(m['product_id']),
        batchNo: _s(m['batch_no']),
        mfgDate: _date(m['mfg_date']),
        expiry: _date(m['expiry']) ?? today(),
        packSize: _i(m['pack_size']).clamp(1, 100000),
        mrp: _d(m['mrp']),
        purchaseRate: _d(m['purchase_rate']),
        saleRate: _d(m['sale_rate']),
        gstRate: _d(m['gst_rate']),
        discountPct: _d(m['discount_pct']),
        qty: _i(m['qty']),
        initialQty: _i(m['initial_qty']),
        supplierId: m['supplier_id'] as int?,
        purchaseId: m['purchase_id'] as int?,
        status: _s(m['status']),
        createdAt: _date(m['created_at']),
      );

  Map<String, Object?> toMap() => {
        'id': id,
        'product_id': productId,
        'batch_no': batchNo,
        'mfg_date': mfgDate == null ? null : isoDate(mfgDate!),
        'expiry': isoDate(expiry),
        'pack_size': packSize,
        'mrp': mrp,
        'purchase_rate': purchaseRate,
        'sale_rate': saleRate,
        'gst_rate': gstRate,
        'discount_pct': discountPct,
        'qty': qty,
        'initial_qty': initialQty,
        'supplier_id': supplierId,
        'purchase_id': purchaseId,
        'status': status,
        'created_at': isoDateTime(createdAt ?? DateTime.now()),
      };
}

class BatchWithProduct {
  final Batch batch;
  final Product product;
  final String supplierName;
  BatchWithProduct(this.batch, this.product, [this.supplierName = '']);
}

class Doctor {
  int? id;
  String name;
  String qualification;
  String regNo;
  String clinic;
  String phone;

  Doctor({this.id, required this.name, this.qualification = '', this.regNo = '', this.clinic = '', this.phone = ''});

  factory Doctor.fromMap(Map<String, Object?> m) => Doctor(
        id: m['id'] as int?,
        name: _s(m['name']),
        qualification: _s(m['qualification']),
        regNo: _s(m['reg_no']),
        clinic: _s(m['clinic']),
        phone: _s(m['phone']),
      );

  Map<String, Object?> toMap() => {
        'id': id,
        'name': name,
        'qualification': qualification,
        'reg_no': regNo,
        'clinic': clinic,
        'phone': phone,
      };
}

class Customer {
  int? id;
  String name;
  String phone;
  String address;
  bool creditAllowed;
  double creditLimit; // 0 = no limit
  String notes;
  double balance; // outstanding credit, computed (not stored)

  Customer({
    this.id,
    required this.name,
    this.phone = '',
    this.address = '',
    this.creditAllowed = false,
    this.creditLimit = 0,
    this.notes = '',
    this.balance = 0,
  });

  bool get isCreditCustomer => creditAllowed || balance > 0.004;

  factory Customer.fromMap(Map<String, Object?> m) => Customer(
        id: m['id'] as int?,
        name: _s(m['name']),
        phone: _s(m['phone']),
        address: _s(m['address']),
        creditAllowed: _i(m['credit_allowed']) == 1,
        creditLimit: _d(m['credit_limit']),
        notes: _s(m['notes']),
        balance: _d(m['balance']),
      );

  Map<String, Object?> toMap() => {
        'id': id,
        'name': name,
        'phone': phone,
        'address': address,
        'credit_allowed': creditAllowed ? 1 : 0,
        'credit_limit': creditLimit,
        'notes': notes,
      };
}

/// One line of a customer's credit account: a credit bill (debit) or a payment (credit).
class CreditEntry {
  final DateTime date;
  final String kind; // bill | payment
  final int refId;
  final String label;
  final double debit;
  final double credit;
  final String note;
  double runningBalance = 0;

  CreditEntry({required this.date, required this.kind, required this.refId, required this.label, this.debit = 0, this.credit = 0, this.note = ''});
}

// ------------------------------------------------------------------ purchases

class Purchase {
  int? id;
  int? supplierId;
  String supplierName;
  String invoiceNo;
  DateTime invoiceDate;
  DateTime createdAt;
  double grossTotal;
  double discountTotal;
  double gstTotal;
  double netTotal;
  bool paid;
  String notes;
  int itemCount;

  Purchase({
    this.id,
    this.supplierId,
    this.supplierName = '',
    this.invoiceNo = '',
    required this.invoiceDate,
    DateTime? createdAt,
    this.grossTotal = 0,
    this.discountTotal = 0,
    this.gstTotal = 0,
    this.netTotal = 0,
    this.paid = true,
    this.notes = '',
    this.itemCount = 0,
  }) : createdAt = createdAt ?? DateTime.now();

  factory Purchase.fromMap(Map<String, Object?> m) => Purchase(
        id: m['id'] as int?,
        supplierId: m['supplier_id'] as int?,
        supplierName: _s(m['supplier_name']),
        invoiceNo: _s(m['invoice_no']),
        invoiceDate: _date(m['invoice_date']) ?? today(),
        createdAt: _date(m['created_at']),
        grossTotal: _d(m['gross_total']),
        discountTotal: _d(m['discount_total']),
        gstTotal: _d(m['gst_total']),
        netTotal: _d(m['net_total']),
        paid: _i(m['paid']) == 1,
        notes: _s(m['notes']),
        itemCount: _i(m['item_count']),
      );

  Map<String, Object?> toMap() => {
        'id': id,
        'supplier_id': supplierId,
        'invoice_no': invoiceNo,
        'invoice_date': isoDate(invoiceDate),
        'created_at': isoDateTime(createdAt),
        'gross_total': grossTotal,
        'discount_total': discountTotal,
        'gst_total': gstTotal,
        'net_total': netTotal,
        'paid': paid ? 1 : 0,
        'notes': notes,
      };
}

class PurchaseItem {
  int? id;
  int? purchaseId;
  int productId;
  String productName;
  int? batchId;
  String batchNo;
  DateTime? mfgDate;
  DateTime expiry;
  int packSize;
  int qtyPacks;
  int freePacks;
  double purchaseRate; // per pack, before GST
  double mrp;
  double saleRate;
  double gstRate;
  double discountPct;
  int boxQty; // > 0 when bought as full boxes (paid boxes)
  int boxSize; // packs (strips) per box for this purchase
  int freeBoxes; // free goods given as whole boxes (already included in freePacks)
  String packName; // display only (joined from the medicine)

  PurchaseItem({
    this.id,
    this.purchaseId,
    required this.productId,
    this.productName = '',
    this.batchId,
    required this.batchNo,
    this.mfgDate,
    required this.expiry,
    required this.packSize,
    required this.qtyPacks,
    this.freePacks = 0,
    required this.purchaseRate,
    required this.mrp,
    double? saleRate,
    required this.gstRate,
    this.discountPct = 0,
    this.boxQty = 0,
    this.boxSize = 0,
    this.freeBoxes = 0,
    this.packName = 'Pack',
  }) : saleRate = saleRate ?? mrp;

  bool get boughtInBoxes => boxQty > 0 && boxSize > 0;

  /// "3 Box × 10 + 1 free" or "30 + 2 free" (packs), for invoice lists.
  String get qtyLabel {
    final free = freeBoxes > 0
        ? ' + $freeBoxes Box free'
        : freePacks > 0
            ? ' + $freePacks $packName free'
            : '';
    if (boughtInBoxes) return '$boxQty Box × $boxSize $packName$free';
    return '$qtyPacks $packName$free';
  }

  double get gross => qtyPacks * purchaseRate;
  double get discount => gross * discountPct / 100;
  double get taxable => gross - discount;
  double get gst => taxable * gstRate / 100;
  double get total => taxable + gst;
  int get totalUnits => (qtyPacks + freePacks) * packSize;

  factory PurchaseItem.fromMap(Map<String, Object?> m) => PurchaseItem(
        id: m['id'] as int?,
        purchaseId: m['purchase_id'] as int?,
        productId: _i(m['product_id']),
        productName: _s(m['product_name']),
        batchId: m['batch_id'] as int?,
        batchNo: _s(m['batch_no']),
        mfgDate: _date(m['mfg_date']),
        expiry: _date(m['expiry']) ?? today(),
        packSize: _i(m['pack_size']),
        qtyPacks: _i(m['qty_packs']),
        freePacks: _i(m['free_packs']),
        purchaseRate: _d(m['purchase_rate']),
        mrp: _d(m['mrp']),
        saleRate: _d(m['sale_rate']),
        gstRate: _d(m['gst_rate']),
        discountPct: _d(m['discount_pct']),
        boxQty: _i(m['box_qty']),
        boxSize: _i(m['box_size']),
        freeBoxes: _i(m['free_boxes']),
        packName: m['pack_name'] as String? ?? 'Pack',
      );

  Map<String, Object?> toMap() => {
        'id': id,
        'purchase_id': purchaseId,
        'product_id': productId,
        'product_name': productName,
        'batch_id': batchId,
        'batch_no': batchNo,
        'mfg_date': mfgDate == null ? null : isoDate(mfgDate!),
        'expiry': isoDate(expiry),
        'pack_size': packSize,
        'qty_packs': qtyPacks,
        'free_packs': freePacks,
        'purchase_rate': purchaseRate,
        'mrp': mrp,
        'sale_rate': saleRate,
        'gst_rate': gstRate,
        'discount_pct': discountPct,
        'amount': round2(total),
        'box_qty': boxQty,
        'box_size': boxSize,
        'free_boxes': freeBoxes,
      };
}

// ------------------------------------------------------------------ sales

class SaleItem {
  int? id;
  int? saleId;
  int productId;
  int batchId;
  String productName;
  String form;
  String batchNo;
  DateTime expiry;
  int packSize;
  String unitName;
  String packName;
  int qtyUnits;
  double mrp; // per pack
  double unitRate; // per unit, GST inclusive
  double discountPct;
  double gstRate;
  double amount; // after discount, GST inclusive
  String hsn;
  bool rx;

  SaleItem({
    this.id,
    this.saleId,
    required this.productId,
    required this.batchId,
    required this.productName,
    this.form = '',
    required this.batchNo,
    required this.expiry,
    required this.packSize,
    required this.unitName,
    required this.packName,
    required this.qtyUnits,
    required this.mrp,
    required this.unitRate,
    this.discountPct = 0,
    this.gstRate = 0,
    this.amount = 0,
    this.hsn = '',
    this.rx = false,
  });

  double get gross => qtyUnits * unitRate;
  String get qtyLabel => fmtQty(qtyUnits, packSize, unitName, packName);

  factory SaleItem.fromMap(Map<String, Object?> m) => SaleItem(
        id: m['id'] as int?,
        saleId: m['sale_id'] as int?,
        productId: _i(m['product_id']),
        batchId: _i(m['batch_id']),
        productName: _s(m['product_name']),
        form: _s(m['form']),
        batchNo: _s(m['batch_no']),
        expiry: _date(m['expiry']) ?? today(),
        packSize: _i(m['pack_size']).clamp(1, 100000),
        unitName: _s(m['unit_name']),
        packName: _s(m['pack_name']),
        qtyUnits: _i(m['qty_units']),
        mrp: _d(m['mrp']),
        unitRate: _d(m['unit_rate']),
        discountPct: _d(m['discount_pct']),
        gstRate: _d(m['gst_rate']),
        amount: _d(m['amount']),
        hsn: _s(m['hsn']),
        rx: _i(m['rx']) == 1,
      );

  Map<String, Object?> toMap() => {
        'id': id,
        'sale_id': saleId,
        'product_id': productId,
        'batch_id': batchId,
        'product_name': productName,
        'form': form,
        'batch_no': batchNo,
        'expiry': isoDate(expiry),
        'pack_size': packSize,
        'unit_name': unitName,
        'pack_name': packName,
        'qty_units': qtyUnits,
        'mrp': mrp,
        'unit_rate': unitRate,
        'discount_pct': discountPct,
        'gst_rate': gstRate,
        'amount': amount,
        'hsn': hsn,
        'rx': rx ? 1 : 0,
      };
}

class Sale {
  int? id;
  String billNo;
  DateTime createdAt;
  int? customerId;
  String customerName;
  String customerPhone;
  String customerAddress;
  int? doctorId;
  String doctorName;
  String doctorRegNo;
  String doctorClinic;
  String rxNotes;
  String paymentMode;
  double grossTotal;
  double itemDiscount;
  double billDiscountPct;
  double billDiscount;
  double taxableTotal;
  double gstTotal;
  double roundOff;
  double grandTotal;
  double paidAmount; // < grandTotal on a credit bill
  String status; // completed | cancelled
  String cancelReason;
  String filePath;
  String templateCode;
  int itemCount;
  List<SaleItem> items;

  Sale({
    this.id,
    this.billNo = '',
    DateTime? createdAt,
    this.customerId,
    this.customerName = '',
    this.customerPhone = '',
    this.customerAddress = '',
    this.doctorId,
    this.doctorName = '',
    this.doctorRegNo = '',
    this.doctorClinic = '',
    this.rxNotes = '',
    this.paymentMode = 'Cash',
    this.grossTotal = 0,
    this.itemDiscount = 0,
    this.billDiscountPct = 0,
    this.billDiscount = 0,
    this.taxableTotal = 0,
    this.gstTotal = 0,
    this.roundOff = 0,
    this.grandTotal = 0,
    double? paidAmount,
    this.status = 'completed',
    this.cancelReason = '',
    this.filePath = '',
    this.templateCode = '',
    this.itemCount = 0,
    List<SaleItem>? items,
  })  : createdAt = createdAt ?? DateTime.now(),
        paidAmount = paidAmount ?? grandTotal,
        items = items ?? [];

  bool get isCancelled => status == 'cancelled';
  bool get isCredit => paymentMode == 'Credit';
  double get dueAmount => isCredit ? round2(grandTotal - paidAmount) : 0;
  double get totalDiscount => itemDiscount + billDiscount;

  factory Sale.fromMap(Map<String, Object?> m) => Sale(
        id: m['id'] as int?,
        billNo: _s(m['bill_no']),
        createdAt: _date(m['created_at']),
        customerId: m['customer_id'] as int?,
        customerName: _s(m['customer_name']),
        customerPhone: _s(m['customer_phone']),
        customerAddress: _s(m['customer_address']),
        doctorId: m['doctor_id'] as int?,
        doctorName: _s(m['doctor_name']),
        doctorRegNo: _s(m['doctor_reg_no']),
        doctorClinic: _s(m['doctor_clinic']),
        rxNotes: _s(m['rx_notes']),
        paymentMode: _s(m['payment_mode']),
        grossTotal: _d(m['gross_total']),
        itemDiscount: _d(m['item_discount']),
        billDiscountPct: _d(m['bill_discount_pct']),
        billDiscount: _d(m['bill_discount']),
        taxableTotal: _d(m['taxable_total']),
        gstTotal: _d(m['gst_total']),
        roundOff: _d(m['round_off']),
        grandTotal: _d(m['grand_total']),
        paidAmount: m['paid_amount'] == null ? null : _d(m['paid_amount']),
        status: _s(m['status']),
        cancelReason: _s(m['cancel_reason']),
        filePath: _s(m['file_path']),
        templateCode: _s(m['template_code']),
        itemCount: _i(m['item_count']),
      );

  Map<String, Object?> toMap() => {
        'id': id,
        'bill_no': billNo,
        'created_at': isoDateTime(createdAt),
        'customer_id': customerId,
        'customer_name': customerName,
        'customer_phone': customerPhone,
        'customer_address': customerAddress,
        'doctor_id': doctorId,
        'doctor_name': doctorName,
        'doctor_reg_no': doctorRegNo,
        'doctor_clinic': doctorClinic,
        'rx_notes': rxNotes,
        'payment_mode': paymentMode,
        'gross_total': grossTotal,
        'item_discount': itemDiscount,
        'bill_discount_pct': billDiscountPct,
        'bill_discount': billDiscount,
        'taxable_total': taxableTotal,
        'gst_total': gstTotal,
        'round_off': roundOff,
        'grand_total': grandTotal,
        'paid_amount': paidAmount,
        'status': status,
        'cancel_reason': cancelReason,
        'file_path': filePath,
        'template_code': templateCode,
      };
}

// ------------------------------------------------------------------ templates

class BillTemplateItem {
  int? id;
  int productId;
  int qtyUnits;
  Product? product; // joined

  BillTemplateItem({this.id, required this.productId, required this.qtyUnits, this.product});
}

class BillTemplate {
  int? id;
  String code;
  String name;
  String description;
  String doctorName;
  DateTime? updatedAt;
  List<BillTemplateItem> items;
  int itemCount;

  BillTemplate({
    this.id,
    required this.code,
    required this.name,
    this.description = '',
    this.doctorName = '',
    this.updatedAt,
    List<BillTemplateItem>? items,
    this.itemCount = 0,
  }) : items = items ?? [];

  factory BillTemplate.fromMap(Map<String, Object?> m) => BillTemplate(
        id: m['id'] as int?,
        code: _s(m['code']),
        name: _s(m['name']),
        description: _s(m['description']),
        doctorName: _s(m['doctor_name']),
        updatedAt: _date(m['updated_at']),
        itemCount: _i(m['item_count']),
      );
}

// ------------------------------------------------------------------ ledger

class StockMovement {
  final int id;
  final DateTime createdAt;
  final int productId;
  final String productName;
  final int? batchId;
  final String batchNo;
  final String type;
  final int qty;
  final String refType;
  final int? refId;
  final String refLabel;
  final String note;
  final int packSize;
  final String unitName;
  final String packName;

  StockMovement.fromMap(Map<String, Object?> m)
      : id = _i(m['id']),
        createdAt = _date(m['created_at']) ?? DateTime.now(),
        productId = _i(m['product_id']),
        productName = _s(m['product_name']),
        batchId = m['batch_id'] as int?,
        batchNo = _s(m['batch_no']),
        type = _s(m['type']),
        qty = _i(m['qty']),
        refType = _s(m['ref_type']),
        refId = m['ref_id'] as int?,
        refLabel = _s(m['ref_label']),
        note = _s(m['note']),
        packSize = _i(m['pack_size']).clamp(1, 100000),
        unitName = _s(m['unit_name']),
        packName = _s(m['pack_name']);

  bool get isEntry => qty > 0;

  static String typeLabel(String t) => switch (t) {
        'PURCHASE' => 'Stock entry',
        'SALE' => 'Sale',
        'SALE_CANCEL' => 'Bill cancelled',
        'ADJUST' => 'Adjustment',
        'OPENING' => 'Opening stock',
        'EXPIRY_RETURN' => 'Returned (expiry)',
        'EXPIRY_DISPOSE' => 'Disposed (expiry)',
        _ => t,
      };
}

class ExpiryAction {
  final int id;
  final DateTime createdAt;
  final String action;
  final int qty;
  final double value;
  final String note;
  final String productName;
  final String batchNo;
  final DateTime? expiry;
  final int packSize;
  final String unitName;
  final String packName;

  ExpiryAction.fromMap(Map<String, Object?> m)
      : id = _i(m['id']),
        createdAt = _date(m['created_at']) ?? DateTime.now(),
        action = _s(m['action']),
        qty = _i(m['qty']),
        value = _d(m['value']),
        note = _s(m['note']),
        productName = _s(m['product_name']),
        batchNo = _s(m['batch_no']),
        expiry = _date(m['expiry']),
        packSize = _i(m['pack_size']).clamp(1, 100000),
        unitName = _s(m['unit_name']),
        packName = _s(m['pack_name']);

  static String label(String a) => switch (a) {
        'returned' => 'Returned to supplier',
        'disposed' => 'Disposed',
        'discounted' => 'Clearance discount',
        'acknowledged' => 'Acknowledged',
        _ => a,
      };
}
