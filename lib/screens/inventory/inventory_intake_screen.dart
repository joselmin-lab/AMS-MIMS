import 'package:ams_mims/services/production_child_materials_service.dart';
import 'package:ams_mims/widgets/search_selection_screen.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:ams_mims/services/production_parent_shortage_service.dart';


class InventoryMovementLine {
  final String productId;
  final String name;
  final String sku;
  double qty;

  InventoryMovementLine({
    required this.productId,
    required this.name,
    required this.sku,
    this.qty = 1.0,
  });
}

enum InventoryMovementType { intake, outtake }

class InventoryMovementScreen extends StatefulWidget {
  /// referenceType: 'production_order' | 'purchase_request' | 'manual'
  final String referenceType;
  final String? referenceId;
  final String? referenceLabel;

  const InventoryMovementScreen({
    super.key,
    this.referenceType = 'manual',
    this.referenceId,
    this.referenceLabel,
  });

  @override
  State<InventoryMovementScreen> createState() => _InventoryMovementScreenState();
}

class _InventoryMovementScreenState extends State<InventoryMovementScreen> {
  InventoryMovementType _type = InventoryMovementType.intake;

  final List<InventoryMovementLine> _lines = [];
  bool _saving = false;
  final _noteCtrl = TextEditingController();

  @override
  void dispose() {
    _noteCtrl.dispose();
    super.dispose();
  }

  String get _movementTypeString => _type == InventoryMovementType.intake ? 'intake' : 'outtake';
  String get _directionString => _type == InventoryMovementType.intake ? 'in' : 'out';

  double _parseDouble(String v) {
    return double.tryParse(v.trim().replaceAll(',', '.')) ?? 0.0;
  }

  Future<void> _addItem() async {
    final selected = await Navigator.of(context).push<DocumentSnapshot>(
      MaterialPageRoute(
        builder: (_) => const SearchSelectionScreen(
          collection: 'inventory',
          searchField: 'name',
          displayField: 'name',
          screenTitle: 'Seleccionar ítem',
        ),
      ),
    );

    if (selected == null) return;

    final data = selected.data() as Map<String, dynamic>;
    final name = (data['name'] ?? '').toString();
    final sku = (data['sku'] ?? '').toString();

    final existingIndex = _lines.indexWhere((l) => l.productId == selected.id);
    setState(() {
      if (existingIndex >= 0) {
        _lines[existingIndex].qty += 1.0;
      } else {
        _lines.add(
          InventoryMovementLine(
            productId: selected.id,
            name: name,
            sku: sku,
            qty: 1.0,
          ),
        );
      }
    });
  }

  void _removeLine(InventoryMovementLine line) {
    setState(() => _lines.remove(line));
  }

  Future<void> _save() async {
    if (_lines.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Agrega al menos un ítem.')),
      );
      return;
    }

    for (final l in _lines) {
      if (l.qty <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Las cantidades deben ser mayores a 0.')),
        );
        return;
      }
    }

    setState(() => _saving = true);

    try {
      final db = FirebaseFirestore.instance;

      int? parentOrderNumberToRecompute;
            String? purchaseRequestIdToAutoReceive;

            if (_type == InventoryMovementType.intake &&
                widget.referenceType == 'production_order' &&
                widget.referenceId != null) {
              final parentSnap = await db.collection('production_orders').doc(widget.referenceId).get();
              if (parentSnap.exists) {
                final parent = parentSnap.data() as Map<String, dynamic>;
                final n = parent['orderNumber'];
                if (n is int) parentOrderNumberToRecompute = n;
                if (n is num) parentOrderNumberToRecompute = n.toInt();

                final prId = (parent['purchaseRequestId'] as String?)?.trim();
                if (prId != null && prId.isNotEmpty) {
                  purchaseRequestIdToAutoReceive = prId;
                }
              }
            }
      final movementRef = db.collection('inventory_movements').doc();

      final linesForDb = _lines
          .map(
            (l) => {
              'productId': l.productId,
              'name': l.name,
              'sku': l.sku,
              'qty': l.qty, // ✅ double
            },
          )
          .toList();

      final batch = db.batch();

      batch.set(movementRef, {
        'type': _movementTypeString,
        'direction': _directionString,
        'createdAt': FieldValue.serverTimestamp(),
        'note': _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
        'referenceType': widget.referenceType,
        'referenceId': widget.referenceId,
        'referenceLabel': widget.referenceLabel,
        'lines': linesForDb,
      });

      final sign = _type == InventoryMovementType.intake ? 1.0 : -1.0;

      for (final l in _lines) {
        final invRef = db.collection('inventory').doc(l.productId);
        batch.update(invRef, {'stock': FieldValue.increment(sign * l.qty)});
      }

      await batch.commit();

      // 3) Post-commit: si fue ingreso vinculado a OP, auto-receive PR + recomputes
        if (purchaseRequestIdToAutoReceive != null) {
          final prRef = db.collection('purchase_requests').doc(purchaseRequestIdToAutoReceive);

          final prSnap = await prRef.get();
          if (prSnap.exists) {
            final pr = prSnap.data() as Map<String, dynamic>;
            final prStatus = (pr['status'] ?? 'pending').toString().toLowerCase().trim();

            if (prStatus == 'pending') {
              await prRef.update({
                'status': 'received',
                'receivedAt': FieldValue.serverTimestamp(),
              });
            }
          }
        }

if (parentOrderNumberToRecompute != null) {
  final childSvc = ProductionChildMaterialsService(firestore: db);
  await childSvc.recomputeChildrenForParentOrderNumber(parentOrderNumberToRecompute);

  final parentSvc = ProductionParentShortageService(firestore: db);
  await parentSvc.recomputeForParentOrderNumber(parentOrderNumberToRecompute);
}
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al guardar movimiento: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final subtitle = widget.referenceId == null
        ? 'Movimiento manual'
        : 'Vinculado a ${widget.referenceType}: ${widget.referenceLabel ?? widget.referenceId}';

    final title = _type == InventoryMovementType.intake ? 'Ingreso de Inventario' : 'Salida de Inventario';
    final themeColor = _type == InventoryMovementType.intake ? Colors.teal : Colors.deepOrange;

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        backgroundColor: themeColor,
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: Text(
              _saving ? 'Guardando...' : 'Guardar',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _saving ? null : _addItem,
        icon: const Icon(Icons.add),
        label: const Text('Agregar ítem'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(subtitle, style: const TextStyle(color: Colors.black54)),
          const SizedBox(height: 12),
          SegmentedButton<InventoryMovementType>(
            segments: const [
              ButtonSegment(value: InventoryMovementType.intake, label: Text('Ingreso'), icon: Icon(Icons.arrow_downward)),
              ButtonSegment(value: InventoryMovementType.outtake, label: Text('Salida'), icon: Icon(Icons.arrow_upward)),
            ],
            selected: {_type},
            onSelectionChanged: _saving ? null : (s) => setState(() => _type = s.first),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _noteCtrl,
            decoration: const InputDecoration(
              labelText: 'Nota (opcional)',
              border: OutlineInputBorder(),
            ),
            minLines: 1,
            maxLines: 3,
            enabled: !_saving,
          ),
          const SizedBox(height: 16),
          const Text('Ítems', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 8),
          if (_lines.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: Text('Agrega ítems para registrar el movimiento.')),
            ),
          ..._lines.map((l) {
            return Card(
              margin: const EdgeInsets.symmetric(vertical: 6),
              child: ListTile(
                title: Text(l.name.isEmpty ? '(Sin nombre)' : l.name),
                subtitle: Text('SKU: ${l.sku.isEmpty ? 'N/A' : l.sku}'),
                trailing: SizedBox(
                  width: 160,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      SizedBox(
                        width: 80,
                        child: TextFormField(
                          initialValue: l.qty.toString(),
                          enabled: !_saving,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          textAlign: TextAlign.center,
                          decoration: const InputDecoration(
                            labelText: 'Cant.',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          onChanged: (v) => l.qty = _parseDouble(v),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        onPressed: _saving ? null : () => _removeLine(l),
                        icon: const Icon(Icons.delete_outline, color: Colors.red),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
          const SizedBox(height: 80),
        ],
      ),
    );
  }
}