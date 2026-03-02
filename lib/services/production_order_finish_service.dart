import 'package:ams_mims/services/production_child_materials_service.dart';
import 'package:ams_mims/services/production_parent_shortage_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class ProductionOrderFinishService {
  final FirebaseFirestore db;

  ProductionOrderFinishService({FirebaseFirestore? firestore})
      : db = firestore ?? FirebaseFirestore.instance;

  Future<void> finishChildOrder({
    required DocumentSnapshot orderDoc,
    required double producedQtyOverride,
    String? note,
  }) async {
    final data = orderDoc.data() as Map<String, dynamic>;
    final isChildOrder = data['isChildOrder'] as bool? ?? false;
    if (!isChildOrder) throw Exception('finishChildOrder solo aplica a órdenes hijas.');

    final materialsReady = data['materialsReady'] as bool?;
    if (materialsReady == false) {
      throw Exception('Orden hija bloqueada: faltan materiales por recepcionar.');
    }

    final lineItems = (data['lineItems'] as List<dynamic>? ?? const []);
    if (lineItems.isEmpty) throw Exception('La orden no tiene lineItems.');

    final first = Map<String, dynamic>.from(lineItems.first as Map);
    final makeProductId = (first['productId'] ?? '').toString();
    if (makeProductId.isEmpty) throw Exception('El lineItem no tiene productId.');

    final producedQty = producedQtyOverride;
    if (producedQty <= 0) throw Exception('Cantidad producida inválida ($producedQty).');

    final parentOrderNumber = data['parentOrderNumber'];

    // Leer inventario del producto fabricado (para nombre/sku + bom)
    final makeInvSnap = await db.collection('inventory').doc(makeProductId).get();
    final makeInv = makeInvSnap.data() ?? <String, dynamic>{};

    final productName = (first['productName'] ?? makeInv['name'] ?? '').toString();
    final sku = (first['productSku'] ?? first['sku'] ?? makeInv['sku'] ?? '').toString();

    // Construir consumo (solo componentes origin != make)
    final bom = (makeInv['bom'] as List?) ?? const [];
    final consumptionLines = <Map<String, dynamic>>[];

    for (final c in bom) {
      final comp = Map<String, dynamic>.from((c as Map));
      final compId = (comp['productId'] ?? '').toString();
      if (compId.isEmpty) continue;

      final perUnitQty = ((comp['quantity'] ?? comp['qty']) as num? ?? 0).toDouble();
      if (perUnitQty == 0) continue;

      final compInvSnap = await db.collection('inventory').doc(compId).get();
      final compInv = compInvSnap.data() ?? <String, dynamic>{};
      final origin = (compInv['origin'] ?? 'buy').toString();

      // Evitar doble consumo de subensambles fabricados
      if (origin == 'make') continue;

      final requiredQty = perUnitQty * producedQty;

      consumptionLines.add({
        'productId': compId,
        'sku': (compInv['sku'] ?? '').toString(),
        'name': (compInv['name'] ?? '').toString(),
        'qty': requiredQty, // qty positiva; direction=out
      });
    }

    // ✅ Reservas BUY de la hija (para liberarlas al finalizar)
    final reservedMaterials = (data['reservedMaterials'] as List<dynamic>? ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();

    final batch = db.batch();

    // 1) status hija -> Finalizadas
    batch.update(orderDoc.reference, {
      'status': 'Finalizadas',
      'finishedAt': FieldValue.serverTimestamp(),
      'producedQty': producedQty,
      // útil para auditoría/cancelaciones: qué se consumió por esta hija
      'issuedMaterials': consumptionLines
          .map((l) => {
                'productId': l['productId'],
                'sku': l['sku'],
                'name': l['name'],
                'qty': l['qty'],
              })
          .toList(),
      'issuedAt': FieldValue.serverTimestamp(),
    });

    // 2) ingreso por producción (stock + movimiento)
    batch.update(db.collection('inventory').doc(makeProductId), {
      'stock': FieldValue.increment(producedQty),
    });

    final receiptRef = db.collection('inventory_movements').doc();
    batch.set(receiptRef, {
      'type': 'production_receipt',
      'direction': 'in',
      'createdAt': FieldValue.serverTimestamp(),
      'note': (note == null || note.trim().isEmpty) ? 'Recepción por producción' : note.trim(),
      'referenceType': 'production_order_child',
      'referenceId': orderDoc.id,
      'referenceLabel': (data['displayOrderNumber'] ?? '').toString().isNotEmpty
          ? 'OP #${data['displayOrderNumber']}'
          : (data['orderNumber'] != null ? 'OP #${data['orderNumber']}' : 'OP ${orderDoc.id}'),
      'parentOrderNumber': parentOrderNumber,
      'lines': [
        {'productId': makeProductId, 'sku': sku, 'name': productName, 'qty': producedQty}
      ],
    });

    // 3) consumo de materiales (stock - movimiento)
    if (consumptionLines.isNotEmpty) {
      final consumptionRef = db.collection('inventory_movements').doc();
      batch.set(consumptionRef, {
        'type': 'consumption',
        'direction': 'out',
        'createdAt': FieldValue.serverTimestamp(),
        'note': 'Consumo por producción (${(data['displayOrderNumber'] ?? data['orderNumber'] ?? '').toString()})',
        'referenceType': 'production_order_child',
        'referenceId': orderDoc.id,
        'referenceLabel': (data['displayOrderNumber'] ?? '').toString().isNotEmpty
            ? 'OP #${data['displayOrderNumber']}'
            : (data['orderNumber'] != null ? 'OP #${data['orderNumber']}' : 'OP ${orderDoc.id}'),
        'parentOrderNumber': parentOrderNumber,
        'lines': consumptionLines,
      });

      for (final l in consumptionLines) {
        final compId = (l['productId'] ?? '').toString();
        final q = (l['qty'] as num? ?? 0).toDouble();
        if (compId.isEmpty || q == 0) continue;

        batch.update(db.collection('inventory').doc(compId), {
          'stock': FieldValue.increment(-q),
        });
      }
    }

    // ✅ 4) liberar reservas BUY que estaban tomadas por la hija
    if (reservedMaterials.isNotEmpty) {
      for (final r in reservedMaterials) {
        final pid = (r['productId'] ?? '').toString();
        final qty = (r['qty'] as num? ?? 0).toDouble();
        if (pid.isEmpty || qty == 0) continue;

        batch.update(db.collection('inventory').doc(pid), {
          'reserved': FieldValue.increment(-qty),
        });
      }

      batch.update(orderDoc.reference, {
        'reservedMaterials': [],
        'reservedReleasedAt': FieldValue.serverTimestamp(),
      });
    }

    await batch.commit();

    // 5) recomputes post-producción
    int? parentN;
    if (parentOrderNumber is int) parentN = parentOrderNumber;
    if (parentOrderNumber is num) parentN = parentOrderNumber.toInt();

    if (parentN != null) {
      final childSvc = ProductionChildMaterialsService(firestore: db);
      await childSvc.recomputeChildrenForParentOrderNumber(parentN);

      final parentSvc = ProductionParentShortageService(firestore: db);
      await parentSvc.recomputeForParentOrderNumber(parentN);
    }
  }
}