import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

class QrDisplayScreen extends StatelessWidget {
  final DocumentSnapshot itemDocument;

  const QrDisplayScreen({super.key, required this.itemDocument});

  String _qrPayload() => 'INV:${itemDocument.id}';

  Future<void> _generatePdf(BuildContext context) async {
    final data = itemDocument.data() as Map<String, dynamic>;
    final String qrData = _qrPayload();

    final pdf = pw.Document();

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (pw.Context context) {
          return pw.Center(
            child: pw.Column(
              mainAxisAlignment: pw.MainAxisAlignment.center,
              children: [
                pw.BarcodeWidget(
                  barcode: pw.Barcode.qrCode(),
                  data: qrData,
                  width: 200,
                  height: 200,
                ),
                pw.SizedBox(height: 24),
                pw.Text(
                  data['name'] ?? 'Nombre no disponible',
                  style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold),
                ),
                pw.SizedBox(height: 8),
                pw.Text(
                  'SKU: ${data['sku'] ?? 'N/A'}',
                  style: const pw.TextStyle(fontSize: 18),
                ),
                pw.SizedBox(height: 8),
                pw.Text(
                  'Ubicación: ${data['location'] ?? 'Sin definir'}',
                  style: const pw.TextStyle(fontSize: 16),
                ),
                pw.SizedBox(height: 24),
                pw.Text(
                  qrData,
                  textAlign: pw.TextAlign.center,
                  style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey),
                ),
              ],
            ),
          );
        },
      ),
    );

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final data = itemDocument.data() as Map<String, dynamic>;
    final String qrData = _qrPayload();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Código QR del Artículo'),
        actions: [
          IconButton(
            icon: const Icon(Icons.print_outlined),
            onPressed: () => _generatePdf(context),
            tooltip: 'Generar PDF / Imprimir',
          ),
        ],
      ),
      body: Center(
        child: SingleChildScrollView(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              QrImageView(
                data: qrData,
                version: QrVersions.auto,
                size: 250.0,
                gapless: false,
              ),
              const SizedBox(height: 24),
              Text(
                data['name'] ?? '...',
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                'SKU: ${data['sku'] ?? 'N/A'}',
                style: const TextStyle(fontSize: 18, color: Colors.grey),
              ),
              const SizedBox(height: 8),
              Text(
                'Ubicación: ${data['location'] ?? '...'}',
                style: const TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 24),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 40.0),
                child: Text(
                  'QR Data: $qrData',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}