// lib/screens/production/cancel_production_order_screen.dart

import 'package:ams_mims/services/production_order_cancel_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class CancelProductionOrderScreen extends StatefulWidget {
  final DocumentSnapshot orderDoc;

  const CancelProductionOrderScreen({
    super.key,
    required this.orderDoc,
  });

  @override
  State<CancelProductionOrderScreen> createState() => _CancelProductionOrderScreenState();
}

class _CancelProductionOrderScreenState extends State<CancelProductionOrderScreen> {
  final _noteCtrl = TextEditingController();

  bool _loading = true;
  bool _saving = false;

  final _nf = NumberFormat('0.00', 'es');
  String _fmt(num v) => _nf.format(v.toDouble());

  List<Map<String, dynamic>> _issued = [];
  final Map<String, TextEditingController> _returnCtrls = {}; // productId -> ctrl

  @override
  void initState() {
    super.initState();
    _loadIssued();
  }

  Future<void> _loadIssued() async {
    try {
      final svc = ProductionOrderCancelService();
      final issued = await svc.getIssuedMaterialsForOrder(orderDocId: widget.orderDoc.id);

      for (final m in issued) {
        final pid = (m['productId'] ?? '').toString();
        _returnCtrls[pid] = TextEditingController(text: '0,00'); // default 0
      }

      setState(() {
        _issued = issued;
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error cargando emitidos: $e')),
        );
      }
    }
  }

  double _parse(String s) {
    return double.tryParse(s.trim().replaceAll('.', '').replaceAll(',', '.')) ?? 0.0;
  }

  @override
  void dispose() {
    _noteCtrl.dispose();
    for (final c in _returnCtrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.orderDoc.data() as Map<String, dynamic>;
    final displayOrderNumber = (data['displayOrderNumber'] ?? data['orderNumber'] ?? '').toString();
    final currentStatus = (data['status'] ?? '').toString();

    return Scaffold(
      appBar: AppBar(
        title: Text('Cancelar OP #$displayOrderNumber'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(12),
              children: [
                Text(
                  'Estado actual: $currentStatus',
                  style: const TextStyle(color: Colors.black54),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Selecciona cuánto retorna a inventario (default 0). '
                  'Lo que no retorna se considera SCRAP (no vuelve).',
                  style: TextStyle(color: Colors.black54),
                ),
                const SizedBox(height: 12),

                if (_issued.isEmpty)
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(12),
                      child: Text('No hay materiales emitidos a producción para esta OP.'),
                    ),
                  ),

                ..._issued.map((m) {
                  final pid = (m['productId'] ?? '').toString();
                  final name = (m['name'] ?? '').toString();
                  final sku = (m['sku'] ?? '').toString();
                  final issuedQty = (m['issuedQty'] as num? ?? 0).toDouble();

                  final ctrl = _returnCtrls[pid]!;
                  final returnQty = _parse(ctrl.text);
                  final scrapQty = (issuedQty - returnQty) < 0 ? 0.0 : (issuedQty - returnQty);

                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '$name${sku.isEmpty ? '' : ' ($sku)'}',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 6),
                          Text('Emitido: ${_fmt(issuedQty)}'),
                          const SizedBox(height: 10),
                          TextField(
                            controller: ctrl,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            decoration: const InputDecoration(
                              labelText: 'Cantidad que retorna a inventario',
                              border: OutlineInputBorder(),
                            ),
                            onChanged: (_) => setState(() {}),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'SCRAP (no retorna): ${_fmt(scrapQty)}',
                            style: const TextStyle(color: Colors.black54),
                          ),
                        ],
                      ),
                    ),
                  );
                }),

                const SizedBox(height: 12),

                TextField(
                  controller: _noteCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Nota (opcional)',
                    border: OutlineInputBorder(),
                  ),
                ),

                const SizedBox(height: 12),

                  FilledButton.icon(
                  onPressed: _saving ? null : _confirmCancel, // <-- Quitar _issued.isEmpty
                  icon: _saving
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.block),
                  label: Text(_saving ? 'Cancelando...' : 'Confirmar Cancelación'),
                  style: FilledButton.styleFrom(backgroundColor: Colors.red),
                ),

                const SizedBox(height: 8),

                const Text(
                  'Nota: Esto NO elimina la OP; la marca como "Cancelada".',
                  style: TextStyle(color: Colors.black54, fontSize: 12),
                ),
              ],
            ),
    );
  }

  Future<void> _confirmCancel() async {
    setState(() => _saving = true);

    try {
      final returnLines = <Map<String, dynamic>>[];
      final scrapLines = <Map<String, dynamic>>[];

      for (final m in _issued) {
        final pid = (m['productId'] ?? '').toString();
        final issuedQty = (m['issuedQty'] as num? ?? 0).toDouble();
        final ctrl = _returnCtrls[pid]!;
        final returnQty = _parse(ctrl.text);

        if (returnQty < 0 || returnQty > issuedQty) {
          throw Exception('Cantidad retorno inválida para ${(m['name'] ?? pid)} (0..${_fmt(issuedQty)})');
        }

        final scrapQty = issuedQty - returnQty;

        returnLines.add({
          'productId': pid,
          'sku': m['sku'],
          'name': m['name'],
          'qtyReturn': returnQty,
        });

        scrapLines.add({
          'productId': pid,
          'sku': m['sku'],
          'name': m['name'],
          'qtyScrap': scrapQty,
        });
      }

      final svc = ProductionOrderCancelService();
      await svc.cancelOrder(
        orderDoc: widget.orderDoc,
        returnLines: returnLines,
        scrapLines: scrapLines,
        note: _noteCtrl.text,
      );

      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error cancelando: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}