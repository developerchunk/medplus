import 'package:file_picker/file_picker.dart';
import 'package:printing/printing.dart';

import 'bill_file.dart';
import 'bill_pdf.dart';
import 'settings.dart';

class PrintService {
  static const customerCopy = 'CUSTOMER COPY';
  static const medicalCopy = 'MEDICAL COPY';
  static const duplicateCopy = 'DUPLICATE';

  /// Integration tests turn printing off so no system print dialog opens.
  static bool enabled = true;

  /// Prints straight to the configured printer; falls back to the system
  /// print dialog when no printer is set or the printer can't be reached.
  static Future<bool> printBill(BillDocument doc, {String copyLabel = customerCopy}) async {
    if (!enabled) return false;
    final settings = Settings.instance;
    final paper = settings.get('paper');
    final format = BillPdf.formatFor(paper);
    final bytes = await BillPdf.build(doc, copyLabel: copyLabel, paper: paper);
    final url = settings.get('printer_url');
    final name = 'Bill ${doc.sale.billNo}';
    if (url.isNotEmpty) {
      try {
        final ok = await Printing.directPrintPdf(
          printer: Printer(url: url, name: settings.get('printer_name')),
          onLayout: (_) async => bytes,
          name: name,
          format: format,
          usePrinterSettings: paper == '80mm',
        );
        if (ok) return true;
      } catch (_) {
        // fall through to the dialog
      }
    }
    return Printing.layoutPdf(onLayout: (_) async => bytes, name: name, format: format);
  }

  static Future<List<Printer>> printers() async {
    try {
      final info = await Printing.info();
      if (!info.canListPrinters) return [];
      return await Printing.listPrinters();
    } catch (_) {
      return [];
    }
  }

  /// Lets the user save a PDF copy anywhere (e.g. to send on WhatsApp).
  static Future<String?> exportPdf(BillDocument doc, {String copyLabel = duplicateCopy}) async {
    final bytes = await BillPdf.build(doc, copyLabel: copyLabel);
    final uri = await FilePicker.saveFile(
      dialogTitle: 'Save bill as PDF',
      fileName: 'Bill_${doc.sale.billNo.replaceAll(RegExp(r'[^A-Za-z0-9_\-]'), '_')}.pdf',
      bytes: bytes,
      mimeType: 'application/pdf',
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );
    return uri?.toFilePath();
  }
}
