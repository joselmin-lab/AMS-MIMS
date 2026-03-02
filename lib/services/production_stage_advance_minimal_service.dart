import 'package:cloud_firestore/cloud_firestore.dart';

class ProductionStageAdvanceMinimalService {
  final FirebaseFirestore db;

  ProductionStageAdvanceMinimalService({FirebaseFirestore? firestore})
      : db = firestore ?? FirebaseFirestore.instance;

  static const List<String> stageOrder = [
    'Mecanizado',
    'Soldadura',
    'Pintura',
    'Ensamblaje',
    'Control de Calidad',
  ];

  Future<void> advanceStageMinimal({
    required DocumentReference orderRef,
  }) async {
    await db.runTransaction((tx) async {
      final snap = await tx.get(orderRef);
      if (!snap.exists) throw Exception('OP no existe.');

      final data = snap.data() as Map<String, dynamic>;
      final status = (data['status'] ?? '').toString();
      if (status != 'En Proceso') throw Exception('OP no está En Proceso.');

      final current = (data['processStage'] ?? '').toString().trim();
      final idx = current.isEmpty ? 0 : stageOrder.indexOf(current);
      if (idx < 0) throw Exception('Etapa actual inválida: $current');
      if (idx >= stageOrder.length - 1) throw Exception('Ya está en la última etapa.');

      final next = stageOrder[idx + 1];

      tx.update(orderRef, {
        'processStage': next,
        'lastStageAdvancedAt': FieldValue.serverTimestamp(),
      });
    });
  }
}