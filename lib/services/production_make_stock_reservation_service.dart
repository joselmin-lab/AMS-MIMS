// lib/services/production_make_stock_reservation_service.dart

import 'package:cloud_firestore/cloud_firestore.dart';

class ProductionMakeStockReservationService {
  final FirebaseFirestore db;

  ProductionMakeStockReservationService({FirebaseFirestore? firestore})
      : db = firestore ?? FirebaseFirestore.instance;

  /// Reserva stock de items origin=make que serán consumidos desde inventario para cumplir la OP.
  ///
  /// requirements: [{productId, requiredQty}]
  /// available = stock - reserved
  /// reserveQty = min(requiredQty, max(available,0))
  ///
  /// Actualiza:
  /// - inventory/<id>.reserved += reserveQty
  /// - production_orders/<op>.reservedMakeMaterials = [{productId, sku, name, qty, requiredQty}]
  /// - production_orders/<op>.reservedMakeAt
  Future<List<Map<String, dynamic>>> reserveMakeStockForOrder({
    required DocumentReference orderRef,
    required List<Map<String, dynamic>> requirements,
  }) async {
    final batch = db.batch();
    final reservedMakeMaterials = <Map<String, dynamic>>[];

    for (final r in requirements) {
      final productId = (r['productId'] ?? '').toString();
      final requiredQty = (r['requiredQty'] as num? ?? 0).toDouble();
      if (productId.isEmpty || requiredQty <= 0) continue;

      final invRef = db.collection('inventory').doc(productId);
      final invSnap = await invRef.get();
      if (!invSnap.exists) continue;

      final inv = invSnap.data() as Map<String, dynamic>;
      final origin = (inv['origin'] ?? 'buy').toString();
      if (origin != 'make') continue;

      final stock = (inv['stock'] as num? ?? 0).toDouble();
      final reserved = (inv['reserved'] as num? ?? 0).toDouble();
      final available = stock - reserved;

      final reserveQty = available <= 0 ? 0.0 : (available >= requiredQty ? requiredQty : available);
      if (reserveQty <= 0) continue;

      batch.update(invRef, {'reserved': FieldValue.increment(reserveQty)});

      reservedMakeMaterials.add({
        'productId': productId,
        'sku': inv['sku'],
        'name': inv['name'],
        'qty': reserveQty,
        'requiredQty': requiredQty,
      });
    }

    batch.update(orderRef, {
      'reservedMakeMaterials': reservedMakeMaterials,
      'reservedMakeAt': FieldValue.serverTimestamp(),
    });

    await batch.commit();
    return reservedMakeMaterials;
  }
}