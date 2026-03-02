import 'package:cloud_firestore/cloud_firestore.dart';

class ProductionParentMaterialsGateService {
  final FirebaseFirestore db;

  ProductionParentMaterialsGateService({FirebaseFirestore? firestore})
      : db = firestore ?? FirebaseFirestore.instance;

  /// Valida si la OP padre puede pasar a "En Proceso".
  ///
  /// Reglas:
  /// - BUY: requiredPartsSnapshot debe estar totalmente disponible como (stock - reserved)
  /// - MAKE desde stock: reservedMakeMaterials debe existir y ser consumible (stock >= qty y reserved >= qty)
  ///
  /// Retorna:
  /// { ok: bool, toBuy: [ {productId, sku, name, missingQty, type} ] }
  Future<Map<String, dynamic>> checkParentMaterialsReady({
    required DocumentSnapshot parentOrderDoc,
  }) async {
    final data = parentOrderDoc.data() as Map<String, dynamic>;

    final requiredBuy = (data['requiredPartsSnapshot'] as List<dynamic>? ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();

    final reservedMake = (data['reservedMakeMaterials'] as List<dynamic>? ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();

    final missing = <Map<String, dynamic>>[];

    // 1) BUY: validar disponible (stock - reserved) >= required
    for (final r in requiredBuy) {
      final pid = (r['productId'] ?? '').toString();
      final reqQty = (r['requiredQty'] as num? ?? 0).toDouble();
      if (pid.isEmpty || reqQty <= 0) continue;

      final inv = await db.collection('inventory').doc(pid).get();
      final d = inv.data() ?? {};

      final stock = (d['stock'] as num? ?? 0).toDouble();
      final reserved = (d['reserved'] as num? ?? 0).toDouble();
      final available = stock - reserved;

      if (available + 1e-9 < reqQty) {
        missing.add({
          'productId': pid,
          'sku': d['sku'],
          'name': d['name'],
          'missingQty': reqQty - available,
          'type': 'buy',
        });
      }
    }

    // 2) MAKE reservadas (tapas/subensambles desde stock): validar que existan y estén reservadas
    for (final r in reservedMake) {
      final pid = (r['productId'] ?? '').toString();
      final qty = (r['qty'] as num? ?? 0).toDouble();
      if (pid.isEmpty || qty <= 0) continue;

      final inv = await db.collection('inventory').doc(pid).get();
      final d = inv.data() ?? {};

      final stock = (d['stock'] as num? ?? 0).toDouble();
      final reserved = (d['reserved'] as num? ?? 0).toDouble();

      if (stock + 1e-9 < qty) {
        missing.add({
          'productId': pid,
          'sku': d['sku'],
          'name': d['name'],
          'missingQty': qty - stock,
          'type': 'make_stock',
        });
      } else if (reserved + 1e-9 < qty) {
        missing.add({
          'productId': pid,
          'sku': d['sku'],
          'name': d['name'],
          'missingQty': qty - reserved,
          'type': 'make_reserved',
        });
      }
    }

    return {
      'ok': missing.isEmpty,
      'toBuy': missing,
    };
  }
}