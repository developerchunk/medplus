import 'package:flutter/foundation.dart';

/// App-wide navigation state shared by the shell and pages.
class Nav {
  static const dashboard = 0;
  static const billing = 1;
  static const bills = 2;
  static const credit = 3;
  static const inventory = 4;
  static const purchases = 5;
  static const expiry = 6;
  static const templates = 7;
  static const suppliers = 8;
  static const contacts = 9;
  static const ledger = 10;
  static const settings = 11;

  static final page = ValueNotifier<int>(dashboard);

  /// A template code the billing screen should load when it next appears.
  static final pendingTemplate = ValueNotifier<String?>(null);

  /// A customer the billing screen should start a bill for.
  static final pendingCustomer = ValueNotifier<int?>(null);

  /// A product the inventory screen should open.
  static final pendingProduct = ValueNotifier<int?>(null);

  static void go(int index) => page.value = index;

  static void billWithTemplate(String code) {
    pendingTemplate.value = code;
    page.value = billing;
  }

  static void billForCustomer(int customerId) {
    pendingCustomer.value = customerId;
    page.value = billing;
  }

  static void openProduct(int id) {
    pendingProduct.value = id;
    page.value = inventory;
  }
}
