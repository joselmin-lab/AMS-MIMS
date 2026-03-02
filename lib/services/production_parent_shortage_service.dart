import 'package:cloud_firestore/cloud_firestore.dart';

class ProductionParentShortageService {
  final FirebaseFirestore db;

  ProductionParentShortageService({FirebaseFirestore? firestore})
      : db = firestore ?? FirebaseFirestore.instance;

  /// Recalcula el estado de faltantes del padre por:
  /// - compra pendiente (purchaseRequestId != null)
  /// - hijas bloqueadas (materialsReady == false) o hijas no finalizadas
  ///
  /// Regla sugerida:
  /// - shortageResolved = true si NO hay compra pendiente y NO hay hijas bloqueadas y NO hay hijas pendientes
  Future<void> recomputeForParentDocId(String parentDocId) async {
    final parentRef = db.collection('production_orders').doc(parentDocId);
    final parentSnap = await parentRef.get();
    if (!parentSnap.exists) return;

    final parent = parentSnap.data() as Map<String, dynamic>;
    final orderNumber = parent['orderNumber'];
    if (orderNumber == null) return;

    final purchaseRequestId = parent['purchaseRequestId'] as String?;
    final hasPendingPurchase = purchaseRequestId != null && purchaseRequestId.isNotEmpty;

    // Hijas del padre (por parentOrderNumber)
    final childrenSnap = await db
        .collection('production_orders')
        .where('isChildOrder', isEqualTo: true)
        .where('parentOrderNumber', isEqualTo: orderNumber)
        .get();

    bool anyChildBlocked = false;
    bool anyChildNotFinished = false;

    for (final c in childrenSnap.docs) {
      final d = c.data();
      final status = (d['status'] ?? '').toString();
      if (status != 'Finalizadas') anyChildNotFinished = true;

      final materialsReady = d['materialsReady'] as bool?;
      if (materialsReady == false) anyChildBlocked = true;
    }

    final shortageResolved = !hasPendingPurchase && !anyChildBlocked && !anyChildNotFinished;

    await parentRef.update({
      'shortageResolved': shortageResolved,
      'hasShortage': !shortageResolved,
      'pendingChildrenCount': childrenSnap.docs.where((c) => (c.data()['status'] ?? '') != 'Finalizadas').length,
      'blockedChildrenCount': childrenSnap.docs.where((c) => (c.data()['materialsReady'] as bool?) == false).length,
      'shortageRecomputedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Helper: recompute por orderNumber (int)
  Future<void> recomputeForParentOrderNumber(int parentOrderNumber) async {
    final parentQuery = await db
        .collection('production_orders')
        .where('isChildOrder', isEqualTo: false)
        .where('orderNumber', isEqualTo: parentOrderNumber)
        .limit(1)
        .get();

    if (parentQuery.docs.isEmpty) return;
    await recomputeForParentDocId(parentQuery.docs.first.id);
  }
}