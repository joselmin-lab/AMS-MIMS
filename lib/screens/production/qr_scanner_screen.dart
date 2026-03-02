import 'package:ams_mims/screens/inventory/add_inventory_item_screen.dart';
import 'package:ams_mims/screens/production/production_order_detail_screen.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

class QrScannerScreen extends StatefulWidget {
  const QrScannerScreen({super.key});

  @override
  State<QrScannerScreen> createState() => _QrScannerScreenState();
}

class _QrScannerScreenState extends State<QrScannerScreen> {
  final MobileScannerController _controller = MobileScannerController();
  bool _handled = false;

  String _normalize(String raw) => raw.trim();

  // Devuelve (type, id)
  (String type, String id)? _parse(String raw) {
    final v = _normalize(raw);

    if (v.toUpperCase().startsWith('OP:')) {
      final id = v.substring(3).trim();
      if (id.isEmpty) return null;
      return ('op', id);
    }

    if (v.toUpperCase().startsWith('INV:')) {
      final id = v.substring(4).trim();
      if (id.isEmpty) return null;
      return ('inv', id);
    }

    // Sin prefijo (compatibilidad con QRs antiguos):
    // intentaremos decidir por existencia en Firestore luego.
    return ('unknown', v);
  }

  Future<void> _routeFromScan(BuildContext context, String raw) async {
    if (_handled) return;
    _handled = true;

    final parsed = _parse(raw);
    if (parsed == null) {
      _handled = false;
      return;
    }

    final type = parsed.$1;
    final id = parsed.$2;

    try {
      if (type == 'op') {
        final ref = FirebaseFirestore.instance.collection('production_orders').doc(id);
        final snap = await ref.get();
        if (!snap.exists) {
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('OP no encontrada: $id')));
          _handled = false;
          return;
        }

        if (!context.mounted) return;
        await Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => ProductionOrderDetailScreen(orderRef: ref)),
        );
        if (context.mounted) Navigator.of(context).pop(); // cerrar scanner
        return;
      }

      if (type == 'inv') {
        final ref = FirebaseFirestore.instance.collection('inventory').doc(id);
        final snap = await ref.get();
        if (!snap.exists) {
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Artículo no encontrado: $id')));
          _handled = false;
          return;
        }

        if (!context.mounted) return;
        await Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => AddInventoryItemScreen(itemToEdit: snap)),
        );
        if (context.mounted) Navigator.of(context).pop(); // cerrar scanner
        return;
      }

      // unknown: intentar OP primero, luego INV
      final opRef = FirebaseFirestore.instance.collection('production_orders').doc(id);
      final opSnap = await opRef.get();
      if (opSnap.exists) {
        if (!context.mounted) return;
        await Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => ProductionOrderDetailScreen(orderRef: opRef)),
        );
        if (context.mounted) Navigator.of(context).pop();
        return;
      }

      final invRef = FirebaseFirestore.instance.collection('inventory').doc(id);
      final invSnap = await invRef.get();
      if (invSnap.exists) {
        if (!context.mounted) return;
        await Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => AddInventoryItemScreen(itemToEdit: invSnap)),
        );
        if (context.mounted) Navigator.of(context).pop();
        return;
      }

      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('QR no reconocido / no existe en sistema: $id')),
      );
      _handled = false;
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error procesando QR: $e')),
      );
      _handled = false;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Escanear QR'),
        actions: [
          IconButton(
            tooltip: 'Flash',
            onPressed: () => _controller.toggleTorch(),
            icon: const Icon(Icons.flash_on),
          ),
          IconButton(
            tooltip: 'Cambiar cámara',
            onPressed: () => _controller.switchCamera(),
            icon: const Icon(Icons.cameraswitch),
          ),
        ],
      ),
      body: MobileScanner(
        controller: _controller,
        onDetect: (capture) {
          final barcodes = capture.barcodes;
          if (barcodes.isEmpty) return;

          final raw = barcodes.first.rawValue;
          if (raw == null || raw.trim().isEmpty) return;

          _routeFromScan(context, raw);
        },
      ),
    );
  }
}