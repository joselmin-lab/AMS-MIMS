  import 'package:cloud_firestore/cloud_firestore.dart';

class ProductionIssueService {
  final FirebaseFirestore db;

  ProductionIssueService({FirebaseFirestore? firestore})
      : db = firestore ?? FirebaseFirestore.instance;

  Future<void> issueParentOrderToProduction({
    required DocumentSnapshot orderDoc,
    required List<Map<String, dynamic>> stages, // ya asignadas
  }) async {
    final orderRef = orderDoc.reference;

    await db.runTransaction((tx) async {
      final snap = await tx.get(orderRef);
      if (!snap.exists) throw Exception('OP no existe.');

      final data = snap.data() as Map<String, dynamic>;
      final status = (data['status'] ?? '').toString();
      final isChild = data['isChildOrder'] as bool? ?? false;
      if (isChild) throw Exception('No se puede pasar una OP hija a proceso.');
      if (status != 'En Cola') throw Exception('Solo se puede pasar a proceso desde "En Cola".');

      final hasShortage = data['hasShortage'] as bool? ?? false;
      final shortageResolved = data['shortageResolved'] as bool? ?? false;
      if (hasShortage && !shortageResolved) {
        throw Exception('No se puede pasar a proceso: faltantes no resueltos.');
      }

      final requiredBuy = (data['requiredPartsSnapshot'] as List<dynamic>? ?? const [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

      final reservedBuy = (data['reservedMaterials'] as List<dynamic>? ?? const [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

      final reservedMake = (data['reservedMakeMaterials'] as List<dynamic>? ?? const [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

      // 1) Validar BUY: como política, debe estar todo disponible/reservado
      //    Para no complicar: exigimos que reservedBuy cubra requiredBuy por productId.
      final Map<String, double> reservedBuyById = {
        for (final r in reservedBuy)
          (r['productId'] ?? '').toString(): (r['qty'] as num? ?? 0).toDouble()
      };

      for (final r in requiredBuy) {
        final pid = (r['productId'] ?? '').toString();
        final reqQty = (r['requiredQty'] as num? ?? 0).toDouble();
        final resQty = (reservedBuyById[pid] ?? 0.0);
        if (resQty + 1e-9 < reqQty) {
          throw Exception('No se puede iniciar: material no totalmente reservado: $pid (req=$reqQty res=$resQty)');
        }
      }

      // 2) Consumir BUY: stock -= reqQty, reserved -= reqQty
      final issuedMaterials = <Map<String, dynamic>>[];
      for (final r in requiredBuy) {
        final pid = (r['productId'] ?? '').toString();
        final reqQty = (r['requiredQty'] as num? ?? 0).toDouble();
        if (pid.isEmpty || reqQty <= 0) continue;

        final invRef = db.collection('inventory').doc(pid);
        final invSnap = await tx.get(invRef);
        if (!invSnap.exists) throw Exception('Inventario no existe: $pid');

        final inv = invSnap.data() as Map<String, dynamic>;
        final stock = (inv['stock'] as num? ?? 0).toDouble();
        final reserved = (inv['reserved'] as num? ?? 0).toDouble();
        final available = stock - reserved;

        // Como está reservado, stock debe alcanzar
        if (stock + 1e-9 < reqQty) throw Exception('Stock insuficiente para $pid');

        tx.update(invRef, {
          'stock': FieldValue.increment(-reqQty),
          'reserved': FieldValue.increment(-reqQty),
        });

        issuedMaterials.add({
          'productId': pid,
          'sku': inv['sku'],
          'name': inv['name'],
          'qty': reqQty,
        });
      }

      // 3) Consumir MAKE desde stock (tapas reservadas): stock -= qty, reserved -= qty
      final issuedMakeMaterials = <Map<String, dynamic>>[];
      for (final r in reservedMake) {
        final pid = (r['productId'] ?? '').toString();
        final qty = (r['qty'] as num? ?? 0).toDouble();
        if (pid.isEmpty || qty <= 0) continue;

        final invRef = db.collection('inventory').doc(pid);
        final invSnap = await tx.get(invRef);
        if (!invSnap.exists) throw Exception('Inventario no existe: $pid');

        final inv = invSnap.data() as Map<String, dynamic>;
        final stock = (inv['stock'] as num? ?? 0).toDouble();
        if (stock + 1e-9 < qty) throw Exception('Stock insuficiente (make) para $pid');

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

      // 4) Actualizar OP a En Proceso + stages + snapshots de consumo
      tx.update(orderRef, {
        'status': 'En Proceso',
        'stages': stages,
        'issuedMaterials': issuedMaterials,
        'issuedMakeMaterials': issuedMakeMaterials,
        'issuedAt': FieldValue.serverTimestamp(),
        'startedAt': FieldValue.serverTimestamp(),
      });
    });
  }
}