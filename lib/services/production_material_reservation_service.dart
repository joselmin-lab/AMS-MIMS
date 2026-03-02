import 'package:cloud_firestore/cloud_firestore.dart';

class ProductionMaterialReservationService {
  final FirebaseFirestore db;

  ProductionMaterialReservationService({FirebaseFirestore? firestore})
      : db = firestore ?? FirebaseFirestore.instance;

  /// requiredParts: [{productId, sku, name, requiredQty}]
  /// Reserva lo que esté disponible (stock - reserved) y guarda snapshot en la OP:
  /// reservedMaterials: [{productId, sku, name, qty}]
  Future<List<Map<String, dynamic>>> reserveAvailableMaterialsForOrder({
    required DocumentReference orderRef,
    required List<Map<String, dynamic>> requiredParts,
  }) async {
    final batch = db.batch();
    final reservedMaterials = <Map<String, dynamic>>[];

    for (final p in requiredParts) {
      final productId = (p['productId'] ?? '').toString();
      final requiredQty = (p['requiredQty'] as num? ?? 0).toDouble();
      if (productId.isEmpty || requiredQty <= 0) continue;

      final invRef = db.collection('inventory').doc(productId);
      final invSnap = await invRef.get();
      if (!invSnap.exists) continue;

      final inv = invSnap.data() as Map<String, dynamic>;
      final stock = (inv['stock'] as num? ?? 0).toDouble();
      final reserved = (inv['reserved'] as num? ?? 0).toDouble();

      final available = stock - reserved;
      final reserveQty = available <= 0 ? 0.0 : (available >= requiredQty ? requiredQty : available);

      if (reserveQty > 0) {
        batch.update(invRef, {'reserved': FieldValue.increment(reserveQty)});
        reservedMaterials.add({
          'productId': productId,
          'sku': p['sku'],
          'name': p['name'],
          'qty': reserveQty,
        });
      }
    }

    batch.update(orderRef, {
      'reservedMaterials': reservedMaterials,
      'reservedAt': FieldValue.serverTimestamp(),
    });

    await batch.commit();
    return reservedMaterials;
  }
}