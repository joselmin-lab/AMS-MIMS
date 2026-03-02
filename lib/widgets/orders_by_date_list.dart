import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'order_row_tile.dart';

class OrdersByDateList extends StatefulWidget {
  /// Límite inicial (primer batch que se muestra en stream)
  final int initialLimit;

  /// Texto del título de la sección (opcional)
  final String title;

  const OrdersByDateList({
    super.key,
    this.initialLimit = 50,
    this.title = 'Órdenes por fecha',
  });

  @override
  State<OrdersByDateList> createState() => _OrdersByDateListState();
}

class _OrdersByDateListState extends State<OrdersByDateList> {
  final List<QueryDocumentSnapshot> _extraDocs = [];
  bool _loadingMore = false;
  bool _hasMore = true;

  // Helper para evitar duplicados por id
  bool _containsId(String id, List<QueryDocumentSnapshot> base, List<QueryDocumentSnapshot> extra) {
    for (final d in base) {
      if (d.id == id) return true;
    }
    for (final d in extra) {
      if (d.id == id) return true;
    }
    return false;
  }

  Future<void> _loadMore(QueryDocumentSnapshot lastDoc) async {
    if (_loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    try {
      final q = FirebaseFirestore.instance
          .collection('production_orders')
          .orderBy('deliveryDate', descending: false)
          .startAfterDocument(lastDoc)
          .limit(widget.initialLimit);
      final snap = await q.get();

      if (snap.docs.isEmpty) {
        setState(() => _hasMore = false);
      } else {
        // Evitar duplicados
        final newDocs = snap.docs.where((d) => !_containsId(d.id, [], _extraDocs)).toList();
        setState(() => _extraDocs.addAll(newDocs));
      }
    } catch (e) {
      // Puedes manejar errores aquí (ej. mostrar SnackBar)
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  List<String> _collectAssignedNames(Map<String, dynamic> data) {
    final assigned = <String>{};
    final processStages = (data['processStages'] as List<dynamic>? ?? []);
    for (final st in processStages) {
      try {
        final m = Map<String, dynamic>.from(st as Map);
        final assignedUsers = (m['assignedUsers'] as List<dynamic>? ?? []);
        for (final au in assignedUsers) {
          try {
            final mu = Map<String, dynamic>.from(au as Map);
            final name = (mu['name'] ?? '').toString();
            if (name.isNotEmpty) assigned.add(name);
          } catch (_) {
            // ignore malformed user
          }
        }
      } catch (_) {
        // ignore malformed stage
      }
    }
    return assigned.toList();
  }

  @override
  Widget build(BuildContext context) {
    final stream = FirebaseFirestore.instance
        .collection('production_orders')
        .orderBy('deliveryDate', descending: false)
        .limit(widget.initialLimit)
        .snapshots();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(widget.title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        StreamBuilder<QuerySnapshot>(
          stream: stream,
          builder: (context, snap) {
            if (snap.hasError) {
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text('Error cargando órdenes: ${snap.error}'),
                ),
              );
            }
            if (!snap.hasData) {
              return const Center(child: CircularProgressIndicator());
            }

             final baseDocs = snap.data!.docs.where((d) {
              final st = ((d.data() as Map<String, dynamic>)['status'] ?? '').toString();
              return st != 'Cancelada' && st != 'Finalizada';
            }).toList();
            
            // Combinar base (stream) + extraDocs (paginadas)
            final combined = <QueryDocumentSnapshot>[...baseDocs];
            
            // Añadir extraDocs evitando duplicados por id y que no estén canceladas
            for (final d in _extraDocs) {
              final st = ((d.data() as Map<String, dynamic>)['status'] ?? '').toString();
              if (st != 'Cancelada' && st != 'Finalizada') {
                if (!combined.any((b) => b.id == d.id)) combined.add(d);
              }
            }

            if (combined.isEmpty) {
              return const Card(
                child: Padding(
                  padding: EdgeInsets.all(12),
                  child: Text('No hay órdenes con fecha asignada.'),
                ),
              );
            }

            return Column(
              children: [
                ListView.builder(
                  physics: const NeverScrollableScrollPhysics(),
                  shrinkWrap: true,
                  itemCount: combined.length,
                   itemBuilder: (context, index) {
                    final doc = combined[index];
                    final data = doc.data() as Map<String, dynamic>;
                    
                    // AGREGAR ESTAS DOS LÍNEAS AQUÍ:
                    final status = (data['status'] ?? '').toString();
                    if (status == 'Cancelada' || status == 'Finalizada') return const SizedBox.shrink();

                    final id = doc.id;
                    final displayOrderNumber = (data['displayOrderNumber']?.toString().isNotEmpty ?? false)
                        ? data['displayOrderNumber'].toString()
                        : (data['orderNumber']?.toString() ?? id);
                    final deliveryTs = data['deliveryDate'] as Timestamp?;
                    final processStage = (data['processStage'] ?? '').toString();
                    final customerName = (data['customerName'] ?? '').toString();

                    final assignedNames = _collectAssignedNames(data);

                    return OrderRowTile(
                      orderRef: doc.reference,
                      displayOrderNumber: displayOrderNumber,
                      deliveryDate: deliveryTs,
                      status: status,
                      processStage: processStage,
                      assignedNames: assignedNames,
                      customerName: customerName,
                    );
                  },
                ),

                const SizedBox(height: 8),

                if (_hasMore)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: _loadingMore
                        ? const CircularProgressIndicator()
                        : ElevatedButton.icon(
                            onPressed: () {
                              // Determinar último doc conocido (prioriza extraDocs si existen)
                              final lastDoc = (_extraDocs.isNotEmpty ? _extraDocs.last : (baseDocs.isNotEmpty ? baseDocs.last : null));
                              if (lastDoc != null) {
                                _loadMore(lastDoc);
                              } else {
                                // no hay más docs para paginar
                                setState(() => _hasMore = false);
                              }
                            },
                            icon: const Icon(Icons.download),
                            label: const Text('Cargar más'),
                          ),
                  ),

                if (!_hasMore)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text('No hay más órdenes.', style: TextStyle(color: Colors.black54)),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}