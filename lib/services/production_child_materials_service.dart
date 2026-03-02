import 'package:cloud_firestore/cloud_firestore.dart';

class ProductionChildMaterialsService {
  final FirebaseFirestore db;

  ProductionChildMaterialsService({FirebaseFirestore? firestore})
      : db = firestore ?? FirebaseFirestore.instance;

  Future<void> recomputeChildrenForParentOrderNumber(int parentOrderNumber) async {
    final childrenSnap = await db
        .collection('production_orders')
        .where('isChildOrder', isEqualTo: true)
        .where('parentOrderNumber', isEqualTo: parentOrderNumber)
        .get();

    if (childrenSnap.docs.isEmpty) return;

    final Map<String, Map<String, dynamic>> invCache = {};

    Future<Map<String, dynamic>?> getInv(String productId) async {
      if (invCache.containsKey(productId)) return invCache[productId];
      final snap = await db.collection('inventory').doc(productId).get();
      if (!snap.exists) return null;
      final data = snap.data() as Map<String, dynamic>;
      invCache[productId] = data;
      return data;
    }

    for (final child in childrenSnap.docs) {
      final data = child.data();
      final status = (data['status'] ?? '').toString();

      // Si ya está finalizada o cancelada, no recalcular
      if (status == 'Finalizadas' || status == 'Cancelada') continue;

      final requiredMaterials = (data['requiredMaterials'] as List<dynamic>? ?? const [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

      if (requiredMaterials.isEmpty) {
        await child.reference.update({
          'materialsShortage': const [],
          'materialsReady': true,
          'hasShortage': false,
          'materialsRecomputedAt': FieldValue.serverTimestamp(),
        });
        continue;
      }

      final shortage = <Map<String, dynamic>>[];

      for (final req in requiredMaterials) {
        final productId = (req['productId'] ?? '').toString();
        if (productId.isEmpty) continue;

        final requiredQty = (req['requiredQty'] as num? ?? 0).toDouble();

        final inv = await getInv(productId);
       final stock = (inv?['stock'] as num?)?.toDouble() ?? 0.0;
      final reserved = (inv?['reserved'] as num?)?.toDouble() ?? 0.0;
      final available = stock - reserved;

      if (available + 1e-9 < requiredQty) {
        shortage.add({
          'productId': productId,
          'sku': (req['sku'] ?? inv?['sku'] ?? '').toString(),
          'name': (req['name'] ?? inv?['name'] ?? '').toString(),
          'missingQty': requiredQty - available,
        });
      }
      }

      final ready = shortage.isEmpty;

      await child.reference.update({
        'materialsShortage': shortage,
        'materialsReady': ready,
        'hasShortage': !ready,
        'materialsRecomputedAt': FieldValue.serverTimestamp(),
      });
    }
  }
}