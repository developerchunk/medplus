import 'dart:io';

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../../core/bill_file.dart';
import '../../core/bill_pdf.dart';
import '../../core/format.dart';
import '../../core/print_service.dart';
import '../../core/settings.dart';
import '../../data/repo.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// Opens a bill either from the database ([saleId]) or straight from a
/// `.mbill` file on disk ([filePath]).
Future<void> showBillViewer(BuildContext context, {int? saleId, String? filePath}) async {
  BillDocument? doc;
  String? source;
  String? error;
  try {
    if (filePath != null) {
      doc = await BillFile.read(filePath);
      source = filePath;
    } else if (saleId != null) {
      final sale = await Repo.sale(saleId);
      if (sale == null) throw Exception('Bill not found');
      if (sale.filePath.isNotEmpty && File(sale.filePath).existsSync()) {
        final fromFile = await BillFile.read(sale.filePath);
        // The DB is the source of truth for status (e.g. cancelled later).
        fromFile.sale.status = sale.status;
        fromFile.sale.cancelReason = sale.cancelReason;
        fromFile.sale.id = sale.id;
        doc = fromFile;
        source = sale.filePath;
      } else {
        doc = BillDocument.fromSale(sale);
      }
    }
  } catch (e) {
    error = '$e';
  }
  if (!context.mounted) return;
  if (doc == null) {
    showSnack(context, error ?? 'Could not open bill', error: true);
    return;
  }
  await showDialog(context: context, builder: (_) => _BillViewer(doc: doc!, source: source, saleId: saleId ?? doc.sale.id));
}

class _BillViewer extends StatefulWidget {
  const _BillViewer({required this.doc, this.source, this.saleId});
  final BillDocument doc;
  final String? source;
  final int? saleId;

  @override
  State<_BillViewer> createState() => _BillViewerState();
}

class _BillViewerState extends State<_BillViewer> {
  late String _paper = Settings.instance.get('paper');

  Future<void> _cancelBill() async {
    final reason = await promptText(context, title: 'Cancel bill ${widget.doc.sale.billNo}?', label: 'Reason (e.g. returned, wrong entry)', confirmLabel: 'Cancel bill');
    if (reason == null || widget.saleId == null) return;
    try {
      await Repo.cancelSale(widget.saleId!, reason);
      widget.doc.sale.status = 'cancelled';
      widget.doc.sale.cancelReason = reason;
      // Keep the medical copy file in sync.
      if (widget.source != null) {
        await File(widget.source!).writeAsBytes(BillFile.encode(BillDocument(shop: widget.doc.shop, sale: widget.doc.sale, savedAt: widget.doc.savedAt)));
      }
      if (!mounted) return;
      setState(() {});
      showSnack(context, 'Bill cancelled and stock returned to inventory');
    } catch (e) {
      if (mounted) showSnack(context, '$e', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.doc.sale;
    final size = MediaQuery.sizeOf(context);
    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      child: SizedBox(
        width: (size.width * 0.8).clamp(700, 1100),
        height: size.height * 0.9,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 16, 12, 12),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Text('Bill ${s.billNo}', style: context.tt.titleLarge),
                    const SizedBox(width: 10),
                    if (s.isCancelled) const Pill('Cancelled', color: AppColors.danger) else const Pill('Medical copy', color: AppColors.brand),
                  ]),
                  Text(
                    '${fmtDateTime(s.createdAt)} · ${s.customerName.isEmpty ? 'Walk-in' : s.customerName}'
                    '${s.doctorName.isEmpty ? '' : ' · Dr. ${s.doctorName}'} · ${money(s.grandTotal)}',
                    style: TextStyle(color: context.muted, fontSize: 12.5),
                  ),
                ]),
              ),
              SegmentedButton<String>(
                showSelectedIcon: false,
                segments: const [ButtonSegment(value: 'A4', label: Text('A4')), ButtonSegment(value: 'A5', label: Text('A5')), ButtonSegment(value: '80mm', label: Text('80mm'))],
                selected: {_paper},
                onSelectionChanged: (v) => setState(() => _paper = v.first),
              ),
              const SizedBox(width: 8),
              IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
            ]),
          ),
          const Divider(),
          Expanded(
            child: Container(
              color: context.cs.surfaceContainer,
              child: PdfPreview(
                key: ValueKey('$_paper-${s.status}'),
                build: (_) => BillPdf.build(widget.doc, copyLabel: PrintService.medicalCopy, paper: _paper),
                useActions: false,
                canChangePageFormat: false,
                canChangeOrientation: false,
                canDebug: false,
                allowPrinting: false,
                allowSharing: false,
                maxPageWidth: _paper == '80mm' ? 380 : 720,
                pdfPreviewPageDecoration: BoxDecoration(color: Colors.white, boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 12)]),
                scrollViewDecoration: BoxDecoration(color: context.cs.surfaceContainer),
              ),
            ),
          ),
          const Divider(),
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 12, 22, 14),
            child: Row(children: [
              if (widget.source != null)
                Expanded(
                  child: Text('Saved at ${widget.source}', style: TextStyle(fontSize: 11.5, color: context.muted), overflow: TextOverflow.ellipsis),
                )
              else
                const Spacer(),
              if (widget.saleId != null && !s.isCancelled)
                TextButton.icon(
                  onPressed: _cancelBill,
                  icon: const Icon(Icons.block, size: 18),
                  label: const Text('Cancel bill'),
                  style: TextButton.styleFrom(foregroundColor: AppColors.danger),
                ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: () async {
                  final p = await PrintService.exportPdf(widget.doc);
                  if (p != null && context.mounted) showSnack(context, 'PDF saved to $p');
                },
                icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
                label: const Text('Save PDF'),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: () => PrintService.printBill(widget.doc, copyLabel: PrintService.medicalCopy),
                icon: const Icon(Icons.local_hospital_outlined, size: 18),
                label: const Text('Print medical copy'),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: () => PrintService.printBill(widget.doc, copyLabel: PrintService.duplicateCopy),
                icon: const Icon(Icons.print_outlined, size: 18),
                label: const Text('Reprint for customer'),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}
