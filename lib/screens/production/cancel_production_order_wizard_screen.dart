import 'package:ams_mims/services/production_order_cancel_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class CancelProductionOrderWizardScreen extends StatefulWidget {
  final DocumentSnapshot orderDoc;

  const CancelProductionOrderWizardScreen({
    super.key,
    required this.orderDoc,
  });

  @override
  State<CancelProductionOrderWizardScreen> createState() => _CancelProductionOrderWizardScreenState();
}

class _CancelProductionOrderWizardScreenState extends State<CancelProductionOrderWizardScreen> {
  final _noteCtrl = TextEditingController();

  bool _loading = true;
  bool _saving = false;

  int _index = 0;

  final _nf = NumberFormat('0.00', 'es');
  String _fmt(num v) => _nf.format(v.toDouble());

  List<Map<String, dynamic>> _issued = [];

  /// productId -> 'return' | 'scrap'
  final Map<String, String> _decisionByProductId = {};

  @override
  void initState() {
    super.initState();
    _loadIssued();
  }

  Future<void> _loadIssued() async {
    try {
      final svc = ProductionOrderCancelService();
      final issued = await svc.getIssuedMaterialsForOrder(orderDocId: widget.orderDoc.id);

      // Orden estable por nombre/sku para que el wizard sea consistente
      issued.sort((a, b) {
        final an = (a['name'] ?? '').toString();
        final bn = (b['name'] ?? '').toString();
        return an.compareTo(bn);
      });

      // default: return (más seguro)
      for (final m in issued) {
        final pid = (m['productId'] ?? '').toString();
        if (pid.isEmpty) continue;
        _decisionByProductId[pid] = 'return';
      }

      setState(() {
        _issued = issued;
        _loading = false;
        _index = 0;
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

  @override
  void dispose() {
    _noteCtrl.dispose();
    super.dispose();
  }

  bool get _isLast => _index >= (_issued.length - 1);
  bool get _isFirst => _index <= 0;

  void _next() {
    if (_isLast) return;
    setState(() => _index += 1);
  }

  void _prev() {
    if (_isFirst) return;
    setState(() => _index -= 1);
  }

  void _setDecision(String productId, String decision) {
    setState(() {
      _decisionByProductId[productId] = decision;
    });
  }

  Future<void> _confirmCancel() async {
    // if (_issued.isEmpty) return;

    setState(() => _saving = true);

    try {
      final returnLines = <Map<String, dynamic>>[];
      final scrapLines = <Map<String, dynamic>>[];

      for (final m in _issued) {
        final pid = (m['productId'] ?? '').toString();
        final issuedQty = (m['issuedQty'] as num? ?? 0).toDouble();
        final decision = _decisionByProductId[pid] ?? 'return';

        final qtyReturn = decision == 'return' ? issuedQty : 0.0;
        final qtyScrap = issuedQty - qtyReturn;

        returnLines.add({
          'productId': pid,
          'sku': m['sku'],
          'name': m['name'],
          'qtyReturn': qtyReturn,
        });

        scrapLines.add({
          'productId': pid,
          'sku': m['sku'],
          'name': m['name'],
          'qtyScrap': qtyScrap,
        });
      }

      final svc = ProductionOrderCancelService();
      await svc.cancelOrder(
        orderDoc: widget.orderDoc,
        returnLines: returnLines,
        scrapLines: scrapLines,
        note: _noteCtrl.text,
      );

      if (mounted) Navigator.of(context).pop(true);
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
          : _issued.isEmpty
              ? ListView(
                  padding: const EdgeInsets.all(12),
                  children: [
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(12),
                        child: Text('No hay materiales emitidos a producción para esta OP. Puedes cancelarla de todos modos.'),
                      ),
                    ),
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
                      onPressed: _saving ? null : _confirmCancel,
                      icon: _saving
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.block),
                      label: Text(_saving ? 'Cancelando...' : 'Confirmar Cancelación'),
                      style: FilledButton.styleFrom(backgroundColor: Colors.red),
                    ),
                  ],
                )
              : ListView(
                  padding: const EdgeInsets.all(12),
                  children: [
                    Text('Estado actual: $currentStatus', style: const TextStyle(color: Colors.black54)),
                    const SizedBox(height: 8),
                    Text(
                      'Parte ${_index + 1} de ${_issued.length}. Selecciona si retorna a inventario o se va a SCRAP.',
                      style: const TextStyle(color: Colors.black54),
                    ),
                    const SizedBox(height: 12),

                    _buildStepCard(_issued[_index]),

                    const SizedBox(height: 12),

                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _isFirst ? null : _prev,
                            icon: const Icon(Icons.arrow_back),
                            label: const Text('Anterior'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: _isLast ? null : _next,
                            icon: const Icon(Icons.arrow_forward),
                            label: const Text('Siguiente'),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 16),

                    TextField(
                      controller: _noteCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Nota (opcional)',
                        border: OutlineInputBorder(),
                      ),
                    ),

                    const SizedBox(height: 12),

                    FilledButton.icon(
                      onPressed: _saving ? null : _confirmCancel,
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

  Widget _buildStepCard(Map<String, dynamic> m) {
    final pid = (m['productId'] ?? '').toString();
    final name = (m['name'] ?? '').toString();
    final sku = (m['sku'] ?? '').toString();
    final issuedQty = (m['issuedQty'] as num? ?? 0).toDouble();

    final decision = _decisionByProductId[pid] ?? 'return';
    final returnQty = decision == 'return' ? issuedQty : 0.0;
    final scrapQty = issuedQty - returnQty;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$name${sku.isEmpty ? '' : ' ($sku)'}', style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Text('Emitido: ${_fmt(issuedQty)}'),
            const Divider(height: 20),

            RadioListTile<String>(
              value: 'return',
              groupValue: decision,
              onChanged: (v) => _setDecision(pid, v!),
              title: const Text('Retornar a inventario'),
              subtitle: Text('Retorna: ${_fmt(issuedQty)}'),
            ),
            RadioListTile<String>(
              value: 'scrap',
              groupValue: decision,
              onChanged: (v) => _setDecision(pid, v!),
              title: const Text('SCRAP'),
              subtitle: Text('No retorna: ${_fmt(issuedQty)}'),
            ),

            const SizedBox(height: 8),
            Text('Resumen:', style: TextStyle(color: Colors.grey.shade700)),
            Text('• Retorna: ${_fmt(returnQty)}'),
            Text('• Scrap: ${_fmt(scrapQty)}'),
          ],
        ),
      ),
    );
  }
}