import 'package:cloud_firestore/cloud_firestore.dart';

class ProductionStageAdvanceService {
  final FirebaseFirestore db;

  ProductionStageAdvanceService({FirebaseFirestore? firestore})
      : db = firestore ?? FirebaseFirestore.instance;

  static const List<String> stageOrder = [
    'Mecanizado',
    'Soldadura',
    'Pintura',
    'Ensamblaje',
    'Control de Calidad',
  ];

  Map<String, dynamic> _stripNulls(Map<String, dynamic> m) {
    final out = <String, dynamic>{};
    for (final e in m.entries) {
      if (e.value == null) continue;
      out[e.key] = e.value;
    }
    return out;
  }

  List<Map<String, dynamic>> _sanitizeStages(List<Map<String, dynamic>> stages) {
    return stages.map(_stripNulls).toList();
  }

  List<Map<String, dynamic>> _sanitizeAssignedUsers(dynamic raw) {
    final list = raw is List ? raw : const <dynamic>[];
    return list
        .whereType<Map>()
        .map((e) {
          final m = Map<String, dynamic>.from(e);
          final id = (m['id'] ?? '').toString().trim();
          final name = (m['name'] ?? '').toString().trim();
          if (id.isEmpty && name.isEmpty) return null;
          return <String, dynamic>{
            'id': id,
            'name': name.isEmpty ? id : name,
          };
        })
        .whereType<Map<String, dynamic>>()
        .toList();
  }

  Future<void> advanceParentOrderStage({
    required DocumentReference orderRef,
    String? note,
  }) async {
    final snap = await orderRef.get();
    if (!snap.exists) throw Exception('OP no existe.');

    final data = snap.data() as Map<String, dynamic>;
    if (data['isChildOrder'] == true) throw Exception('Solo aplica a OP padre.');

    final status = (data['status'] ?? '').toString();
    if (status != 'En Proceso') throw Exception('OP no está En Proceso.');

    final displayOrderNumber = (data['displayOrderNumber'] ?? data['orderNumber'] ?? '').toString();
    final currentStageName = (data['processStage'] ?? '').toString().trim();

    final stages = (data['processStages'] as List<dynamic>? ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    if (stages.isEmpty) throw Exception('OP no tiene processStages.');

    final int currentIndex = currentStageName.isEmpty ? 0 : stageOrder.indexOf(currentStageName);
    if (currentIndex < 0) throw Exception('Etapa actual inválida: "$currentStageName"');

    final bool isLast = currentIndex >= stageOrder.length - 1;
    final String stageToFinish = stageOrder[currentIndex];
    final String? nextStage = isLast ? null : stageOrder[currentIndex + 1];

    final notifRef = db.collection('notifications').doc();
    final movementRef = db.collection('inventory_movements').doc();

    final noteTrim = (note ?? '').trim();
    final hasNote = noteTrim.isNotEmpty;

    await db.runTransaction((tx) async {
      final s2 = await tx.get(orderRef);
      if (!s2.exists) throw Exception('OP no existe.');

      final d2 = s2.data() as Map<String, dynamic>;
      if ((d2['status'] ?? '').toString() != 'En Proceso') throw Exception('La OP ya no está En Proceso.');

      var stages2 = (d2['processStages'] as List<dynamic>? ?? const [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

      int idxOf(String name) => stages2.indexWhere((s) => (s['name'] ?? '').toString() == name);

      final finishIdx = idxOf(stageToFinish);
      if (finishIdx < 0) throw Exception('No se encontró etapa actual.');

      // terminar etapa actual
      final cur = Map<String, dynamic>.from(stages2[finishIdx]);
      stages2[finishIdx] = _stripNulls({
        ...cur,
        'state': 'finished',
        'startedAt': cur['startedAt'] ?? Timestamp.now(), // ✅ evita FieldValue nested
        'finishedAt': Timestamp.now(), // ✅ evita FieldValue nested
      });

      if (nextStage != null) {
        final nextIdx = idxOf(nextStage);
        if (nextIdx < 0) throw Exception('No se encontró etapa siguiente.');

        final nxt = Map<String, dynamic>.from(stages2[nextIdx]);
        stages2[nextIdx] = _stripNulls({
          ...nxt,
          'state': 'in_progress',
          'startedAt': nxt['startedAt'] ?? Timestamp.now(), // ✅ evita FieldValue nested
        });

        stages2 = _sanitizeStages(stages2);

        tx.update(orderRef, {
          'processStages': stages2,
          'processStage': nextStage,
          'lastStageAdvancedAt': FieldValue.serverTimestamp(), // top-level OK
        });

        final assignedUsersNext = _sanitizeAssignedUsers(stages2[nextIdx]['assignedUsers']);

        final notif = <String, dynamic>{
          'type': 'stage_changed',
          'createdAt': FieldValue.serverTimestamp(),
          'orderId': orderRef.id,
          'displayOrderNumber': displayOrderNumber,
          'stageName': nextStage,
          'assignedUsers': assignedUsersNext,
          'message': 'En la OP #$displayOrderNumber se pasó a etapa $nextStage',
        };
        if (hasNote) notif['note'] = noteTrim;

        tx.set(notifRef, notif);
      } else {
        stages2 = _sanitizeStages(stages2);

        tx.update(orderRef, {
          'processStages': stages2,
          'processStage': stageToFinish,
          'status': 'Finalizadas',
          'finishedAt': FieldValue.serverTimestamp(),
        });

        final lineItems = (d2['lineItems'] as List<dynamic>? ?? const [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();

        final lines = <Map<String, dynamic>>[];
        for (final li in lineItems) {
          final pid = (li['productId'] ?? '').toString();
          final qty = (li['quantity'] as num? ?? 0).toDouble();
          if (pid.isEmpty || qty <= 0) continue;

          final sku = (li['productSku'] ?? li['sku'] ?? '').toString();
          final name = (li['productName'] ?? li['name'] ?? '').toString();

          lines.add({'productId': pid, 'sku': sku, 'name': name, 'qty': qty});

          tx.set(
            db.collection('inventory').doc(pid),
            {
              'stock': FieldValue.increment(qty),
              if (name.trim().isNotEmpty) 'name': name,
              if (sku.trim().isNotEmpty) 'sku': sku,
              'updatedAt': FieldValue.serverTimestamp(),
            },
            SetOptions(merge: true),
          );
        }

        if (lines.isNotEmpty) {
          tx.set(movementRef, {
            'type': 'production_receipt',
            'direction': 'in',
            'createdAt': FieldValue.serverTimestamp(),
            'note': hasNote ? noteTrim : 'Recepción por producción (OP padre)',
            'referenceType': 'production_order',
            'referenceId': orderRef.id,
            'referenceLabel': displayOrderNumber.isEmpty ? 'OP ${orderRef.id}' : 'OP #$displayOrderNumber',
            'lines': lines,
          });
        }

        final assignedFinished = _sanitizeAssignedUsers(stages2.last['assignedUsers']);

        final notif = <String, dynamic>{
          'type': 'order_finished',
          'createdAt': FieldValue.serverTimestamp(),
          'orderId': orderRef.id,
          'displayOrderNumber': displayOrderNumber,
          'stageName': stageToFinish,
          'assignedUsers': assignedFinished,
          'message': 'La OP #$displayOrderNumber fue finalizada (Control de Calidad).',
        };
        if (hasNote) notif['note'] = noteTrim;

        tx.set(notifRef, notif);
      }
    });
  }
}