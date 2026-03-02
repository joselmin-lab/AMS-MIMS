import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class InventoryMovementsHistoryScreen extends StatelessWidget {
  const InventoryMovementsHistoryScreen({super.key});

  String _titleFor(Map<String, dynamic> m) {
    final type = (m['type'] ?? '').toString();
    switch (type) {
      case 'intake':
        return 'Ingreso';
      case 'outtake':
        return 'Salida';
      case 'adjustment':
        return 'Ajuste';
      case 'production_receipt':
        return 'Ingreso por Producción';
      case 'consumption':
        return 'Consumo';
      default:
        return type.isEmpty ? 'Movimiento' : type;
    }
  }

  Color _colorFor(Map<String, dynamic> m) {
    final direction = (m['direction'] ?? '').toString();
    if (direction == 'in') return Colors.teal;
    if (direction == 'out') return Colors.deepOrange;
    return Colors.blueGrey;
  }

  String _previewLines(List<dynamic> lines) {
    if (lines.isEmpty) return '';

    final preview = lines.take(3).map((l) {
      final line = Map<String, dynamic>.from(l as Map);
      final name = (line['name'] ?? '').toString();
      final qty = (line['qty'] as num? ?? 0).toInt();
      final qtyText = qty >= 0 ? '+$qty' : '$qty';
      return '${name.isEmpty ? 'Item' : name} ($qtyText)';
    }).join(', ');

    final extra = lines.length - 3;
    return extra > 0 ? '$preview … (+$extra más)' : preview;
  }

  @override
  Widget build(BuildContext context) {
    final stream = FirebaseFirestore.instance
        .collection('inventory_movements')
        .orderBy('createdAt', descending: true)
        .limit(200)
        .snapshots();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Historial de Movimientos'),
        backgroundColor: Colors.indigo,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: stream,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            // ignore: avoid_print
            print(snapshot.error);
            return const Center(child: Text('Error cargando movimientos.'));
          }
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final docs = snapshot.data!.docs;
          if (docs.isEmpty) {
            return const Center(child: Text('Aún no hay movimientos.'));
          }

          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final doc = docs[index];
              final m = doc.data()! as Map<String, dynamic>;

              final createdAt = (m['createdAt'] as Timestamp?)?.toDate();
              final note = (m['note'] ?? '').toString();
              final refType = (m['referenceType'] ?? '').toString();
              final refLabel = (m['referenceLabel'] ?? '').toString();
              final lines = (m['lines'] as List<dynamic>? ?? const []);

              final title = _titleFor(m);
              final color = _colorFor(m);

              int totalQty = 0;
              for (final l in lines) {
                final line = Map<String, dynamic>.from(l as Map);
                totalQty += (line['qty'] as num? ?? 0).toInt().abs();
              }

              final previewText = _previewLines(lines);

              return Card(
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: color.withValues(alpha: 0.15),
                    child: Icon(Icons.swap_vert, color: color),
                  ),
                  title: Text('$title · $totalQty u. · ${lines.length} ítems'),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (createdAt != null) Text(DateFormat('yyyy-MM-dd HH:mm').format(createdAt)),
                      if (refType.isNotEmpty || refLabel.isNotEmpty)
                        Text('Ref: ${refType.isEmpty ? 'N/A' : refType} ${refLabel.isEmpty ? '' : '· $refLabel'}'),
                      if (previewText.isNotEmpty) Text(previewText),
                      if (note.isNotEmpty) Text('Nota: $note'),
                    ],
                  ),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => _MovementDetailScreen(movementId: doc.id)),
                    );
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _MovementDetailScreen extends StatelessWidget {
  final String movementId;

  const _MovementDetailScreen({required this.movementId});

  @override
  Widget build(BuildContext context) {
    final ref = FirebaseFirestore.instance.collection('inventory_movements').doc(movementId);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Detalle de Movimiento'),
        backgroundColor: Colors.indigo,
      ),
      body: FutureBuilder<DocumentSnapshot>(
        future: ref.get(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(child: Text('Error cargando detalle.'));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.data!.exists) {
            return const Center(child: Text('Movimiento no encontrado.'));
          }

          final m = snapshot.data!.data() as Map<String, dynamic>;
          final createdAt = (m['createdAt'] as Timestamp?)?.toDate();
          final note = (m['note'] ?? '').toString();
          final type = (m['type'] ?? '').toString();
          final direction = (m['direction'] ?? '').toString();
          final refType = (m['referenceType'] ?? '').toString();
          final refLabel = (m['referenceLabel'] ?? '').toString();
          final lines = (m['lines'] as List<dynamic>? ?? const []);

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text('Tipo: $type  |  Dirección: $direction'),
              if (createdAt != null) Text('Fecha: ${DateFormat('yyyy-MM-dd HH:mm').format(createdAt)}'),
              if (refType.isNotEmpty || refLabel.isNotEmpty) Text('Referencia: $refType $refLabel'),
              if (note.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Text('Nota: $note')),
              const Divider(height: 24),
              const Text('Líneas', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              ...lines.map((l) {
                final line = Map<String, dynamic>.from(l as Map);
                final sku = (line['sku'] ?? '').toString();
                final name = (line['name'] ?? '').toString();
                final qty = (line['qty'] as num? ?? 0).toInt();
                return ListTile(
                  dense: true,
                  title: Text(name.isEmpty ? '(Sin nombre)' : name),
                  subtitle: Text('SKU: ${sku.isEmpty ? 'N/A' : sku}'),
                  trailing: Text(qty.toString()),
                );
              }),
            ],
          );
        },
      ),
    );
  }
}