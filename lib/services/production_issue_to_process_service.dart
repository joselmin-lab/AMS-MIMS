import 'package:cloud_firestore/cloud_firestore.dart';

class ProductionIssueToProcessService {
  final FirebaseFirestore db;

  ProductionIssueToProcessService({FirebaseFirestore? firestore})
      : db = firestore ?? FirebaseFirestore.instance;

  /// Consume todos los materiales requeridos para iniciar producción:
  /// - BUY: desde requiredPartsSnapshot (requiredQty)
  /// - MAKE desde stock: desde reservedMakeMaterials (qty)
  ///
  /// Efecto en inventory:
  /// - stock -= qty
  /// - reserved -= qty
  ///
  /// Guarda en OP:
  /// - issuedMaterials, issuedMakeMaterials, issuedAt
  Future<void> issueAllRequiredPartsToProduction({
    required DocumentSnapshot parentOrderDoc,
  }) async {
    final orderRef = parentOrderDoc.reference;

    await db.runTransaction((tx) async {
      final snap = await tx.get(orderRef);
      if (!snap.exists) throw Exception('OP no existe.');

      final data = snap.data() as Map<String, dynamic>;
      final status = (data['status'] ?? '').toString();
      final isChild = data['isChildOrder'] as bool? ?? false;

      if (isChild) throw Exception('No se puede emitir una OP hija a proceso.');
      if (status != 'En Cola') throw Exception('Solo se puede emitir desde "En Cola".');

      final requiredBuy = (data['requiredPartsSnapshot'] as List<dynamic>? ?? const [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

      final reservedMake = (data['reservedMakeMaterials'] as List<dynamic>? ?? const [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

      final issuedMaterials = <Map<String, dynamic>>[];
      final issuedMakeMaterials = <Map<String, dynamic>>[];

      // 1) Consumir BUY
      for (final r in requiredBuy) {
        final pid = (r['productId'] ?? '').toString();
        final qty = (r['requiredQty'] as num? ?? 0).toDouble();
        if (pid.isEmpty || qty <= 0) continue;

        final invRef = db.collection('inventory').doc(pid);
        final invSnap = await tx.get(invRef);
        if (!invSnap.exists) throw Exception('Inventario no existe: $pid');

        final inv = invSnap.data() as Map<String, dynamic>;
        final stock = (inv['stock'] as num? ?? 0).toDouble();
        final reserved = (inv['reserved'] as num? ?? 0).toDouble();

        if (reserved + 1e-9 < qty) {
          throw Exception('Material no reservado completamente: ${inv['name'] ?? pid}');
        }
        if (stock + 1e-9 < qty) {
          throw Exception('Stock insuficiente para consumir: ${inv['name'] ?? pid}');
        }

        tx.update(invRef, {
          'stock': FieldValue.increment(-qty),
          'reserved': FieldValue.increment(-qty),
        });

        issuedMaterials.add({
          'productId': pid,
          'sku': inv['sku'],
          'name': inv['name'],
          'qty': qty,
        });
      }

      // 2) Consumir MAKE desde stock (tapas/subensambles)
      for (final r in reservedMake) {
        final pid = (r['productId'] ?? '').toString();
        final qty = (r['qty'] as num? ?? 0).toDouble();
        if (pid.isEmpty || qty <= 0) continue;

        final invRef = db.collection('inventory').doc(pid);
        final invSnap = await tx.get(invRef);
        if (!invSnap.exists) throw Exception('Inventario no existe: $pid');

        final inv = invSnap.data() as Map<String, dynamic>;
        final stock = (inv['stock'] as num? ?? 0).toDouble();
        final reserved = (inv['reserved'] as num? ?? 0).toDouble();

        if (reserved + 1e-9 < qty) {
          throw Exception('Make no reservado completamente: ${inv['name'] ?? pid}');
        }
        if (stock + 1e-9 < qty) {
          throw Exception('Stock insuficiente (make) para consumir: ${inv['name'] ?? pid}');
        }

        tx.update(invRef, {
          'stock': FieldValue.increment(-qty),
          'reserved': FieldValue.increment(-qty),
        });

        issuedMakeMaterials.add({
          'productId': pid,
          'sku': inv['sku'],
          'name': inv['name'],
          'qty': qty,
        });
      }

      // 3) Snapshot de emisión
      tx.update(orderRef, {
        'issuedMaterials': issuedMaterials,
        'issuedMakeMaterials': issuedMakeMaterials,
        'issuedAt': FieldValue.serverTimestamp(),
      });
    });
  }
}