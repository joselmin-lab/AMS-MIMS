import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'order_row_tile.dart';

class OperatorAssignmentsList extends StatefulWidget {
  /// Docs de production_orders (por ejemplo: snapshot.data!.docs)
  final List<QueryDocumentSnapshot> orderDocs;

  /// Cantidad inicial de operarios a mostrar antes de pulsar "Ver más"
  final int initialOperatorLimit;

  const OperatorAssignmentsList({
    super.key,
    required this.orderDocs,
    this.initialOperatorLimit = 10,
  });

  @override
  State<OperatorAssignmentsList> createState() => _OperatorAssignmentsListState();
}

class _OperatorAssignmentsListState extends State<OperatorAssignmentsList> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final grouped = _groupOrdersByOperator(widget.orderDocs);

    final operatorsList = grouped.values.toList()
      ..sort((a, b) {
        final da = a.nextDelivery;
        final db = b.nextDelivery;
        if (da == null && db == null) return a.name.compareTo(b.name);
        if (da == null) return 1;
        if (db == null) return -1;
        return da.compareTo(db);
      });

    final toShow = _expanded ? operatorsList.length : widget.initialOperatorLimit;
    final showMore = operatorsList.length > widget.initialOperatorLimit;

    if (operatorsList.isEmpty) {
      return const Card(
        elevation: 2,
        child: Padding(
          padding: EdgeInsets.all(16.0),
          child: Text(
            'No hay asignaciones a operarios en las órdenes mostradas.',
            style: TextStyle(color: Colors.black54),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Asignaciones por operario', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        ...operatorsList.take(toShow).map((op) => _OperatorCard(operator: op)),
        if (showMore)
          TextButton.icon(
            onPressed: () => setState(() => _expanded = !_expanded),
            icon: Icon(_expanded ? Icons.expand_less : Icons.expand_more),
            label: Text(_expanded ? 'Ver menos' : 'Ver más (${operatorsList.length - widget.initialOperatorLimit})'),
          ),
      ],
    );
  }

  Map<String, _OperatorGroup> _groupOrdersByOperator(List<QueryDocumentSnapshot> docs) {
    final Map<String, _OperatorGroup> map = {};

    for (final doc in docs) {
      final data = (doc.data() as Map<String, dynamic>);
      final orderId = doc.id;

      final status = (data['status'] ?? '').toString();
      // Omitir órdenes canceladas o finalizadas en la lista de tareas del operario
      if (status == 'Cancelada' || status == 'Finalizada') continue;

      final displayOrderNumber = (data['displayOrderNumber']?.toString().isNotEmpty ?? false)
          ? data['displayOrderNumber'].toString()
          : (data['orderNumber']?.toString() ?? orderId);

      final deliveryTs = data['deliveryDate'] as Timestamp?;
      final processStage = (data['processStage'] ?? '').toString();
      final customerName = (data['customerName'] ?? '').toString();

      final processStagesRaw = (data['processStages'] as List<dynamic>? ?? []);

      // Normalizar etapas
      final processStages = processStagesRaw
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();

      // Para esta orden: map uid -> set(stageName)
      final Map<String, Set<String>> stagesByOperatorUid = {};

      // También (opcional) recolectar nombres asignados globales a la OP (para el preview)
      final Set<String> allAssignedNamesInOrder = {};

      for (final st in processStages) {
        final stageName = (st['name'] ?? '').toString();

        // Si manejas un estado por etapa, puedes filtrar aquí
        final stageState = (st['state'] ?? '').toString(); // e.g. pending/in_progress/done/skipped
        if (stageState == 'skipped') continue;

        final assigned = (st['assignedUsers'] as List<dynamic>? ?? []);
        for (final au in assigned) {
          if (au is! Map) continue;
          final auMap = Map<String, dynamic>.from(au);

          final uid = (auMap['id'] ?? '').toString();
          final uname = (auMap['name'] ?? '').toString();

          if (uname.isNotEmpty) allAssignedNamesInOrder.add(uname);
          if (uid.isEmpty) continue;

          final set = stagesByOperatorUid.putIfAbsent(uid, () => <String>{});
          if (stageName.isNotEmpty) set.add(stageName);
        }
      }

      // Ahora: crear una entrada por cada operador que tenga etapas asignadas en esta OP
      for (final entry in stagesByOperatorUid.entries) {
        final uid = entry.key;
        final stagesForThisOperator = entry.value.toList()..sort();

        // nombre del operario: intenta tomarlo desde alguna asignación (si hay)
        String operatorName = uid;
        // Busca un nombre en assignedUsers que coincida con ese uid
        for (final st in processStages) {
          final assigned = (st['assignedUsers'] as List<dynamic>? ?? []);
          for (final au in assigned) {
            if (au is! Map) continue;
            final auMap = Map<String, dynamic>.from(au);
            final auId = (auMap['id'] ?? '').toString();
            if (auId != uid) continue;
            final auName = (auMap['name'] ?? '').toString();
            if (auName.isNotEmpty) {
              operatorName = auName;
              break;
            }
          }
          if (operatorName != uid) break;
        }

        final op = map.putIfAbsent(uid, () => _OperatorGroup(id: uid, name: operatorName));
        // si ya teníamos name vacío y ahora aparece, lo actualizamos
        if ((op.name.isEmpty || op.name == op.id) && operatorName.isNotEmpty) {
          op.name = operatorName;
        }

        // Dedup por orderId
        if (!op.orderIds.contains(orderId)) {
          op.orderIds.add(orderId);
          op.orders.add(_OrderSummary(
            orderRef: doc.reference,
            id: orderId,
            displayOrderNumber: displayOrderNumber,
            deliveryDate: deliveryTs,
            status: status,
            processStage: processStage,
            assignedNames: allAssignedNamesInOrder.toList()..sort(),
            customerName: customerName,
            assignedStageNamesForOperator: stagesForThisOperator,
          ));
        } else {
          // Si por alguna razón la OP ya estaba, aseguramos merge de etapas
          final idx = op.orders.indexWhere((o) => o.id == orderId);
          if (idx != -1) {
            final existing = op.orders[idx];
            final merged = {...existing.assignedStageNamesForOperator, ...stagesForThisOperator}.toList()..sort();
            op.orders[idx] = existing.copyWith(assignedStageNamesForOperator: merged);
          }
        }
      }
    }

    // Calcular nextDelivery y ordenar órdenes internas
    for (final op in map.values) {
      DateTime? minDate;
      for (final o in op.orders) {
        final d = o.deliveryDate?.toDate();
        if (d == null) continue;
        if (minDate == null || d.isBefore(minDate)) minDate = d;
      }
      op.nextDelivery = minDate;

      op.orders.sort((a, b) {
        final da = a.deliveryDate?.toDate();
        final db = b.deliveryDate?.toDate();
        if (da == null && db == null) return 0;
        if (da == null) return 1;
        if (db == null) return -1;
        return da.compareTo(db);
      });
    }

    return map;
  }
}

class _OrderSummary {
  final DocumentReference orderRef;
  final String id;
  final String displayOrderNumber;
  final Timestamp? deliveryDate;
  final String status;
  final String processStage;
  final List<String> assignedNames;
  final String customerName;

  /// Etapas asignadas específicamente a ESTE operario (lo que faltaba)
  final List<String> assignedStageNamesForOperator;

  _OrderSummary({
    required this.orderRef,
    required this.id,
    required this.displayOrderNumber,
    required this.deliveryDate,
    required this.status,
    required this.processStage,
    required this.assignedNames,
    required this.customerName,
    required this.assignedStageNamesForOperator,
  });

  _OrderSummary copyWith({
    List<String>? assignedStageNamesForOperator,
  }) {
    return _OrderSummary(
      orderRef: orderRef,
      id: id,
      displayOrderNumber: displayOrderNumber,
      deliveryDate: deliveryDate,
      status: status,
      processStage: processStage,
      assignedNames: assignedNames,
      customerName: customerName,
      assignedStageNamesForOperator: assignedStageNamesForOperator ?? this.assignedStageNamesForOperator,
    );
  }
}

class _OperatorGroup {
  final String id;
  String name;
  final List<_OrderSummary> orders = [];
  final Set<String> orderIds = {};
  DateTime? nextDelivery;

  _OperatorGroup({required this.id, required this.name});
}

class _OperatorCard extends StatelessWidget {
  final _OperatorGroup operator;

  const _OperatorCard({required this.operator});

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('dd/MM/yyyy');
    final nextDeliveryText = operator.nextDelivery == null ? '—' : df.format(operator.nextDelivery!);

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: ExpansionTile(
        initiallyExpanded: false,
        title: Row(
          children: [
            Expanded(
              child: Text(
                operator.name.isEmpty ? '(Operario)' : operator.name,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.blueGrey.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text('${operator.orders.length} OP', style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
            const SizedBox(width: 10),
            Text(nextDeliveryText, style: const TextStyle(color: Colors.black54)),
          ],
        ),
        children: [
          if (operator.orders.isEmpty)
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text('No hay órdenes asignadas.'),
            )
          else
            Column(
              children: operator.orders.map((o) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    OrderRowTile(
                      orderRef: o.orderRef,
                      displayOrderNumber: o.displayOrderNumber,
                      deliveryDate: o.deliveryDate,
                      status: o.status,
                      processStage: o.processStage,
                      assignedNames: o.assignedNames,
                      customerName: o.customerName,
                    ),
                    if (o.assignedStageNamesForOperator.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(left: 16, right: 16, bottom: 10),
                        child: Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: o.assignedStageNamesForOperator
                              .map((s) => Chip(
                                    visualDensity: VisualDensity.compact,
                                    label: Text(s),
                                  ))
                              .toList(),
                        ),
                      ),
                    const Divider(height: 0),
                  ],
                );
              }).toList(),
            ),
        ],
      ),
    );
  }
}