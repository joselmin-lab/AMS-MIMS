import 'dart:typed_data';

import 'package:ams_mims/services/cloudinary_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:barcode/barcode.dart';

class ProductionProcessPdfService {
  final FirebaseFirestore db;
  final CloudinaryService cloudinary;

  ProductionProcessPdfService({
    FirebaseFirestore? firestore,
    CloudinaryService? cloudinaryService,
  })  : db = firestore ?? FirebaseFirestore.instance,
        cloudinary = cloudinaryService ?? CloudinaryService();

  /// Genera el PDF A4 de proceso, lo sube a Cloudinary y guarda processPdfUrl en la OP.
  /// Devuelve la URL final.
  Future<String> generateAndUploadProcessPdf({
    required DocumentReference orderRef,
    String deeplinkBase = 'myapp://production-order/', // confirmar
  }) async {
    final snap = await orderRef.get();
    if (!snap.exists) throw Exception('OP no existe.');

    final data = snap.data() as Map<String, dynamic>;
    final orderId = orderRef.id;

    final bytes = await buildProcessPdfBytes(
      orderId: orderId,
      orderData: data,
      deeplink: '$deeplinkBase$orderId',
    );

    // Subida: como ya haces en purchase_request
    final fileName = 'process_${(data['displayOrderNumber'] ?? data['orderNumber'] ?? orderId).toString()}.pdf';

    // Tu CloudinaryService ya soporta uploadBytes en web; la usamos siempre para simplificar.
    final url = await cloudinary.uploadBytes(
      bytes,
      fileName: fileName,
      folder: 'process_pdfs',
    );

    await orderRef.update({
      'processPdfUrl': url,
      'processPdfGeneratedAt': FieldValue.serverTimestamp(),
    });

    return url;
  }

  Future<Uint8List> buildProcessPdfBytes({
    required String orderId,
    required Map<String, dynamic> orderData,
    required String deeplink,
  }) async {
    final pdf = pw.Document();

    final displayOrderNumber = (orderData['displayOrderNumber'] ?? orderData['orderNumber'] ?? orderId).toString();

    final customerName = (orderData['customerName'] ?? '').toString();
    final orderType = (orderData['orderType'] ?? '').toString(); // for_customer/for_stock
    final deliveryDateTs = orderData['deliveryDate'] as Timestamp?;
    final deliveryDateStr = deliveryDateTs == null
        ? ''
        : '${deliveryDateTs.toDate().day.toString().padLeft(2, '0')}/${deliveryDateTs.toDate().month.toString().padLeft(2, '0')}/${deliveryDateTs.toDate().year}';

    final lineItems = (orderData['lineItems'] as List<dynamic>? ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();

    final requiredBuy = (orderData['requiredPartsSnapshot'] as List<dynamic>? ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();

    final makeReserved = (orderData['reservedMakeMaterials'] as List<dynamic>? ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();

    final processStages = (orderData['processStages'] as List<dynamic>? ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();

    // QR
    final bc = Barcode.qrCode(errorCorrectLevel: BarcodeQRCorrectionLevel.high);
    final qrSvg = bc.toSvg('OP:$orderId', width: 140, height: 140);

    pw.Widget buildHeader() {
      return pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('Orden de Proceso', style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 6),
                pw.Text('OP: #$displayOrderNumber', style: pw.TextStyle(fontSize: 14)),
                pw.SizedBox(height: 4),
                pw.Text('OrderId: $orderId', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
                pw.SizedBox(height: 8),
                pw.Text(
                  orderType == 'for_customer' ? 'Cliente: $customerName' : 'Tipo: Stock interno',
                  style: const pw.TextStyle(fontSize: 12),
                ),
                if (deliveryDateStr.isNotEmpty) pw.Text('Entrega: $deliveryDateStr', style: const pw.TextStyle(fontSize: 12)),
              ],
            ),
          ),
          pw.Column(
            children: [
              pw.SvgImage(svg: qrSvg),
              pw.SizedBox(height: 4),
              pw.Text('Escanear para abrir', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
            ],
          ),
        ],
      );
    }

    pw.Widget buildLineItems() {
      final rows = lineItems.map((li) {
        final name = (li['productName'] ?? '').toString();
        final sku = (li['productSku'] ?? '').toString();
        final qty = (li['quantity'] as num? ?? 0).toDouble();
        return [name, sku, qty.toStringAsFixed(2)];
      }).toList();

      if (rows.isEmpty) {
        return pw.Text('Sin lineItems', style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700));
      }

      return pw.Table.fromTextArray(
        headers: const ['Producto', 'SKU', 'Cantidad'],
        data: rows,
        headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
        headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
        cellStyle: const pw.TextStyle(fontSize: 10),
        cellAlignment: pw.Alignment.centerLeft,
        columnWidths: {
          0: const pw.FlexColumnWidth(4),
          1: const pw.FlexColumnWidth(2),
          2: const pw.FlexColumnWidth(1),
        },
      );
    }

    pw.Widget buildRequiredParts() {
      final combined = <Map<String, dynamic>>[];

      // BUY parts
      for (final r in requiredBuy) {
        combined.add({
          'type': 'BUY',
          'name': (r['name'] ?? '').toString(),
          'sku': (r['sku'] ?? '').toString(),
          'qty': (r['requiredQty'] as num? ?? 0).toDouble(),
        });
      }

      // MAKE reserved (tapas/subensambles desde stock)
      for (final r in makeReserved) {
        combined.add({
          'type': 'MAKE(stock)',
          'name': (r['name'] ?? '').toString(),
          'sku': (r['sku'] ?? '').toString(),
          'qty': (r['qty'] as num? ?? 0).toDouble(),
        });
      }

      final rows = combined.map((m) {
        return [
          (m['type'] ?? '').toString(),
          (m['name'] ?? '').toString(),
          (m['sku'] ?? '').toString(),
          ((m['qty'] as num?)?.toDouble() ?? 0).toStringAsFixed(2),
        ];
      }).toList();

      if (rows.isEmpty) {
        return pw.Text('Sin partes requeridas', style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700));
      }

      return pw.Table.fromTextArray(
        headers: const ['Tipo', 'Parte', 'SKU', 'Cantidad'],
        data: rows,
        headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
        headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
        cellStyle: const pw.TextStyle(fontSize: 9),
        cellAlignment: pw.Alignment.centerLeft,
        columnWidths: {
          0: const pw.FlexColumnWidth(1.2),
          1: const pw.FlexColumnWidth(4),
          2: const pw.FlexColumnWidth(2),
          3: const pw.FlexColumnWidth(1),
        },
      );
    }

    pw.Widget buildStagesTable() {
      final rows = processStages.map((s) {
        final name = (s['name'] ?? '').toString();

        // preferir assignedUsers (id+name)
        final assignedUsers = (s['assignedUsers'] as List<dynamic>? ?? const [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();

        final names = assignedUsers.map((u) => (u['name'] ?? u['id'] ?? '').toString()).where((x) => x.isNotEmpty).toList();

        final state = (s['state'] ?? '').toString();

        return [
          name,
          names.isEmpty ? '-' : names.join(', '),
          state.isEmpty ? '-' : state,
        ];
      }).toList();

      if (rows.isEmpty) {
        return pw.Text('Sin etapas', style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700));
      }

      return pw.Table.fromTextArray(
        headers: const ['Etapa', 'Operarios', 'Estado'],
        data: rows,
        headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
        headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
        cellStyle: const pw.TextStyle(fontSize: 10),
        cellAlignment: pw.Alignment.centerLeft,
        columnWidths: {
          0: const pw.FlexColumnWidth(2),
          1: const pw.FlexColumnWidth(4),
          2: const pw.FlexColumnWidth(1.2),
        },
      );
    }

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(24),
        build: (ctx) => [
          buildHeader(),
          pw.SizedBox(height: 14),

          pw.Text('Line items', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 6),
          buildLineItems(),
          pw.SizedBox(height: 12),

          pw.Text('Partes requeridas (receta)', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 6),
          buildRequiredParts(),
          pw.SizedBox(height: 12),

          pw.Text('Etapas', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 6),
          buildStagesTable(),
        ],
        footer: (ctx) => pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text('Página ${ctx.pageNumber} / ${ctx.pagesCount}', style: const pw.TextStyle(fontSize: 9)),
        ),
      ),
    );

    return pdf.save();
  }
}