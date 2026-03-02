import 'package:cloud_firestore/cloud_firestore.dart';

class ProductionReservationReleaseService {
  final FirebaseFirestore db;

  ProductionReservationReleaseService({FirebaseFirestore? firestore})
      : db = firestore ?? FirebaseFirestore.instance;

  Future<void> releaseReservedMaterialsFromOrderSnapshot({
    required Map<String, dynamic> orderData,
  }) async {
    final reservedBuy = (orderData['reservedMaterials'] as List<dynamic>? ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();

    final reservedMake = (orderData['reservedMakeMaterials'] as List<dynamic>? ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();

    final all = <Map<String, dynamic>>[
      ...reservedBuy,
      ...reservedMake,
    ];

    if (all.isEmpty) return;

    final batch = db.batch();
    for (final r in all) {
      final pid = (r['productId'] ?? '').toString();
      final qty = (r['qty'] as num? ?? 0).toDouble();
      if (pid.isEmpty || qty == 0) continue;

      batch.update(db.collection('inventory').doc(pid), {
        'reserved': FieldValue.increment(-qty),
      });
    }

    await batch.commit();
  }
}