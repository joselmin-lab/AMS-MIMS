import 'package:ams_mims/services/production_reservation_release_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class ProductionOrderCancelService {
  final FirebaseFirestore db;

  ProductionOrderCancelService({FirebaseFirestore? firestore})
      : db = firestore ?? FirebaseFirestore.instance;

  Future<List<Map<String, dynamic>>> getIssuedMaterialsForOrder({
    required String orderDocId,
  }) async {
    final snap = await db.collection('production_orders').doc(orderDocId).get();
    if (!snap.exists) return [];

    final data = snap.data() as Map<String, dynamic>;

    final issuedBuy = (data['issuedMaterials'] as List<dynamic>? ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();

    final issuedMake = (data['issuedMakeMaterials'] as List<dynamic>? ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();

    final List<Map<String, dynamic>> out = [
      ...issuedBuy.map((m) => {
            'productId': m['productId'],
            'sku': m['sku'],
            'name': m['name'],
            'issuedQty': (m['qty'] as num? ?? 0).toDouble(),
            'type': 'buy',
          }),
      ...issuedMake.map((m) => {
            'productId': m['productId'],
            'sku': m['sku'],
            'name': m['name'],
            'issuedQty': (m['qty'] as num? ?? 0).toDouble(),
            'type': 'make',
          }),
    ];

    final Map<String, Map<String, dynamic>> merged = {};
    for (final m in out) {
      final pid = (m['productId'] ?? '').toString();
      final q = (m['issuedQty'] as num? ?? 0).toDouble();
      if (pid.isEmpty || q == 0) continue;

      if (!merged.containsKey(pid)) {
        merged[pid] = Map<String, dynamic>.from(m);
      } else {
        merged[pid]!['issuedQty'] = ((merged[pid]!['issuedQty'] as num?)?.toDouble() ?? 0.0) + q;
      }
    }

    return merged.values.toList();
  }

  Future<void> cancelOrder({
    required DocumentSnapshot orderDoc,
    required List<Map<String, dynamic>> returnLines,
    required List<Map<String, dynamic>> scrapLines,
    String? note,
  }) async {
    final orderRef = orderDoc.reference;

    final snap = await orderRef.get();
    if (!snap.exists) throw Exception('OP no existe.');

    final data = snap.data() as Map<String, dynamic>;
    final status = (data['status'] ?? '').toString();
    final isChild = data['isChildOrder'] as bool? ?? false;

    if (isChild) {
      throw Exception('No se permite cancelar una OP hija directamente.');
    }

    if (status == 'En Cola') {
      await _cancelQueuedParent(orderData: data, orderRef: orderRef, note: note);
      return;
    }

    if (status == 'En Proceso') {
      await _cancelInProcess(
        orderData: data,
        orderRef: orderRef,
        returnLines: returnLines,
        scrapLines: scrapLines,
        note: note,
      );
      return;
    }

    throw Exception('Solo se puede cancelar desde "En Cola" o "En Proceso". Estado actual: $status');
  }

  Future<void> _cancelQueuedParent({
    required Map<String, dynamic> orderData,
    required DocumentReference orderRef,
    String? note,
  }) async {
    final orderNumber = orderData['orderNumber'];

    final releaseSvc = ProductionReservationReleaseService(firestore: db);
    await releaseSvc.releaseReservedMaterialsFromOrderSnapshot(orderData: orderData);

    if (orderNumber != null) {
      final childrenQuery = await db
          .collection('production_orders')
          .where('parentOrderNumber', isEqualTo: orderNumber)
          .get();

      for (final child in childrenQuery.docs) {
        final childData = child.data();
        final childStatus = (childData['status'] ?? '').toString();

        if (childStatus == 'En Cola') {
          await releaseSvc.releaseReservedMaterialsFromOrderSnapshot(orderData: childData);
        }

        await child.reference.update({
          'status': 'Cancelada',
          'cancelledAt': FieldValue.serverTimestamp(),
          'cancelNote': (note ?? '').trim(),
        });
      }
    }

    await orderRef.update({
      'status': 'Cancelada',
      'cancelledAt': FieldValue.serverTimestamp(),
      'cancelNote': (note ?? '').trim(),
    });
  }

  Future<void> _cancelInProcess({
    required Map<String, dynamic> orderData,
    required DocumentReference orderRef,
    required List<Map<String, dynamic>> returnLines,
    required List<Map<String, dynamic>> scrapLines,
    String? note,
  }) async {
    // Validación básica de retorno
    final Map<String, double> returnById = {
      for (final l in returnLines)
        (l['productId'] ?? '').toString(): (l['qtyReturn'] as num? ?? 0).toDouble()
    };

    final issuedBuy = (orderData['issuedMaterials'] as List<dynamic>? ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();

    final issuedMake = (orderData['issuedMakeMaterials'] as List<dynamic>? ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();

    final Map<String, double> issuedTotal = {};
    void addIssued(List<Map<String, dynamic>> arr) {
      for (final m in arr) {
        final pid = (m['productId'] ?? '').toString();
        final q = (m['qty'] as num? ?? 0).toDouble();
        if (pid.isEmpty || q == 0) continue;
        issuedTotal[pid] = (issuedTotal[pid] ?? 0) + q;
      }
    }

    addIssued(issuedBuy);
    addIssued(issuedMake);

    for (final entry in issuedTotal.entries) {
      final pid = entry.key;
      final issuedQty = entry.value;
      final ret = returnById[pid] ?? 0.0;
      if (ret < -1e-9 || ret > issuedQty + 1e-9) {
        throw Exception('Cantidad de retorno inválida para $pid (0..$issuedQty)');
      }
    }

    final displayOrderNumber = (orderData['displayOrderNumber'] ?? orderData['orderNumber'] ?? '').toString();
    final movementRef = db.collection('inventory_movements').doc();

    // Lines para movimiento (solo retornos > 0)
    final movementLines = returnLines
        .where((l) => ((l['qtyReturn'] as num? ?? 0).toDouble()) > 0)
        .map((l) => {
              'productId': (l['productId'] ?? '').toString(),
              'name': (l['name'] ?? '').toString(),
              'sku': (l['sku'] ?? '').toString(),
              'qty': (l['qtyReturn'] as num? ?? 0).toDouble(),
            })
        .toList();

    // Transacción: actualizar stock + crear movimiento + cancelar OP
    await db.runTransaction((tx) async {
      final snap = await tx.get(orderRef);
      if (!snap.exists) throw Exception('OP no existe.');
      final d = snap.data() as Map<String, dynamic>;
      final status = (d['status'] ?? '').toString();
      if (status != 'En Proceso') throw Exception('La OP ya no está en proceso.');

      // 1) devolver a inventario
      for (final l in returnLines) {
        final pid = (l['productId'] ?? '').toString();
        final qty = (l['qtyReturn'] as num? ?? 0).toDouble();
        if (pid.isEmpty || qty <= 0) continue;

        tx.update(db.collection('inventory').doc(pid), {
          'stock': FieldValue.increment(qty),
        });
      }

      // 2) registrar movimiento si hubo retornos
      if (movementLines.isNotEmpty) {
        tx.set(movementRef, {
          'type': 'intake',
          'direction': 'in',
          'createdAt': FieldValue.serverTimestamp(),
          'note': (note ?? '').trim().isEmpty ? 'Cancelación OP #$displayOrderNumber (retornos)' : (note ?? '').trim(),
          'referenceType': 'production_order',
          'referenceId': orderRef.id,
          'referenceLabel': 'OP #$displayOrderNumber',
          'lines': movementLines,
        });
      }

      // 3) cancelar OP + guardar disposición
      tx.update(orderRef, {
        'status': 'Cancelada',
        'cancelledAt': FieldValue.serverTimestamp(),
        'cancelNote': (note ?? '').trim(),
        'cancellationReturnLines': returnLines,
        'cancellationScrapLines': scrapLines,
      });
    });
  }
}