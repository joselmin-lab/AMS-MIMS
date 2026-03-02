import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:image/image.dart' as img;
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';
import 'package:qr_flutter/qr_flutter.dart';

class ThermalPrinterService {
  final FirebaseFirestore db;

  ThermalPrinterService({FirebaseFirestore? firestore})
      : db = firestore ?? FirebaseFirestore.instance;

  DocumentReference<Map<String, dynamic>> get _settingsRef =>
      db.collection('app_settings').doc('thermal_printer');

  Future<String> getDefaultPrinterMac() async {
    final doc = await _settingsRef.get();
    if (!doc.exists) return '';
    final data = doc.data() ?? {};
    return (data['defaultMac'] ?? '').toString();
  }

  Future<void> setDefaultPrinterMac(String mac) async {
    await _settingsRef.set({
      'enabled': true,
      'androidEnabled': true,
      'defaultMac': mac,
      'paper': 'receipt_58mm',
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<List<BluetoothInfo>> getPairedDevices() async {
    return await PrintBluetoothThermal.pairedBluetooths;
  }

  Future<void> _ensureConnected(String printerMac) async {
    final alreadyConnected = await PrintBluetoothThermal.connectionStatus;
    if (alreadyConnected) return;

    try {
      await PrintBluetoothThermal.disconnect;
    } catch (_) {}

    var connected = await PrintBluetoothThermal.connect(macPrinterAddress: printerMac);
    if (!connected) {
      await Future.delayed(const Duration(milliseconds: 900));
      connected = await PrintBluetoothThermal.connect(macPrinterAddress: printerMac);
    }
    if (!connected) {
      throw Exception('No se pudo conectar a la impresora ($printerMac).');
    }
  }

  Future<img.Image> _buildQrImage(String data, {double size = 220}) async {
    final painter = QrPainter(
      data: data,
      version: QrVersions.auto,
      gapless: true,
      eyeStyle: const QrEyeStyle(
        eyeShape: QrEyeShape.square,
        color: ui.Color(0xFF000000),
      ),
      dataModuleStyle: const QrDataModuleStyle(
        dataModuleShape: QrDataModuleShape.square,
        color: ui.Color(0xFF000000),
      ),
    );

    final ui.Image qrUiImage = await painter.toImage(size);
    final ByteData? byteData = await qrUiImage.toByteData(format: ui.ImageByteFormat.png);
    if (byteData == null) throw Exception('No se pudo generar PNG del QR.');

    final Uint8List pngBytes = byteData.buffer.asUint8List();
    final decoded = img.decodePng(pngBytes);
    if (decoded == null) throw Exception('No se pudo decodificar PNG del QR.');

    return img.grayscale(decoded);
  }

  // Reemplaza la función entera con esta nueva versión
// Reemplaza la función entera con esta versión sin 'cut'
Future<void> printProductionOrderLabel({
  required DocumentReference orderRef,
  required String printerMac,
}) async {
  final snap = await orderRef.get();
  if (!snap.exists) throw Exception('OP no existe.');
  final data = snap.data() as Map<String, dynamic>;

  final displayOrderNumber =
      (data['displayOrderNumber'] ?? data['orderNumber'] ?? orderRef.id).toString();

  final qrData = 'OP:${orderRef.id}';

  await _ensureConnected(printerMac);
  final profile = await CapabilityProfile.load();
  final generator = Generator(PaperSize.mm58, profile);
  final List<int> bytes = [];

  bytes.addAll(generator.reset());

  // Línea 1: "Parte de:"
  bytes.addAll(generator.text(
    'Parte de:',
    styles: const PosStyles(
      align: PosAlign.center,
      bold: true,
    ),
  ));
  bytes.addAll(generator.feed(0));

  // Línea 2: "# de OP" (en grande)
  bytes.addAll(generator.text(
    'OP #$displayOrderNumber',
    styles: const PosStyles(
      align: PosAlign.center,
      bold: true,
      height: PosTextSize.size2,
      width: PosTextSize.size2,
    ),
  ));
  bytes.addAll(generator.feed(1));

  // Línea 3: El Código QR
  final qrImg = await _buildQrImage(qrData, size: 140);
  bytes.addAll(generator.image(qrImg, align: PosAlign.center));
  
  // --- CORRECCIÓN ---
  // Espacio final generoso para facilitar el corte manual
  bytes.addAll(generator.feed(1)); // Aumentado a 4 (puedes ajustar este valor)

  final okWrite = await PrintBluetoothThermal.writeBytes(bytes);
  if (!okWrite) throw Exception('No se pudo enviar a la impresora.');
}

}