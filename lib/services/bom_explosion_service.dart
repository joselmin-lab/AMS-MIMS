// lib/services/bom_explosion_service.dart

import 'package:cloud_firestore/cloud_firestore.dart';

class BomExplosionService {
  final FirebaseFirestore db;

  BomExplosionService({FirebaseFirestore? firestore})
      : db = firestore ?? FirebaseFirestore.instance;

  /// Explota BOM y devuelve SOLO componentes "buy" con cantidades requeridas.
  ///
  /// NOTA: Este método NO descuenta stock de subensambles make; explota todo el árbol.
  /// Se mantiene por compatibilidad con otras partes del sistema.
  Future<List<Map<String, dynamic>>> requiredBuyParts({
    required String productId,
    required double qty,
  }) async {
    final Map<String, double> acc = {};

    Future<void> walk(String pid, double requiredQty) async {
      final snap = await db.collection('inventory').doc(pid).get();
      if (!snap.exists) return;
      final inv = snap.data()!;
      final origin = (inv['origin'] ?? 'buy').toString();

      if (origin == 'make') {
        final bom = (inv['bom'] as List<dynamic>? ?? const []);
        for (final c in bom) {
          final m = Map<String, dynamic>.from(c as Map);
          final cid = (m['productId'] ?? '').toString();
          final per = ((m['quantity'] ?? m['qty']) as num? ?? 0).toDouble();
          if (cid.isEmpty || per <= 0) continue;
          await walk(cid, per * requiredQty);
        }
      } else {
        acc[pid] = (acc[pid] ?? 0) + requiredQty;
      }
    }

    await walk(productId, qty);

    final out = <Map<String, dynamic>>[];
    for (final e in acc.entries) {
      final invSnap = await db.collection('inventory').doc(e.key).get();
      final d = invSnap.data() ?? <String, dynamic>{};
      out.add({
        'productId': e.key,
        'sku': d['sku'],
        'name': d['name'],
        'requiredQty': e.value,
      });
    }

    out.sort((a, b) => (a['name'] ?? '').toString().compareTo((b['name'] ?? '').toString()));
    return out;
  }

  /// ✅ Explota BOM para componentes "buy", pero cuando encuentra un item origin=make:
  /// - calcula disponible = stock - reserved
  /// - solo explota componentes para la parte faltante (qtyToMake)
  ///
  /// Esto evita que el sistema pida comprar materiales para tapas (make) que ya existen en stock.
  Future<List<Map<String, dynamic>>> requiredBuyPartsConsideringMakeStock({
    required String productId,
    required double qty,
  }) async {
    final Map<String, double> acc = {};

    Future<void> walk(String pid, double requiredQty) async {
      final snap = await db.collection('inventory').doc(pid).get();
      if (!snap.exists) return;

      final inv = snap.data()!;
      final origin = (inv['origin'] ?? 'buy').toString();

      if (origin == 'make') {
        final stock = (inv['stock'] as num? ?? 0).toDouble();
        final reserved = (inv['reserved'] as num? ?? 0).toDouble();
        final available = stock - reserved;

        // Solo fabricamos (y por tanto compramos insumos) para el faltante real
        final qtyToMake = (requiredQty - available) <= 0 ? 0.0 : (requiredQty - available);
        if (qtyToMake <= 0) return;

        final bom = (inv['bom'] as List<dynamic>? ?? const []);
        for (final c in bom) {
          final m = Map<String, dynamic>.from(c as Map);
          final cid = (m['productId'] ?? '').toString();
          final per = ((m['quantity'] ?? m['qty']) as num? ?? 0).toDouble();
          if (cid.isEmpty || per <= 0) continue;
          await walk(cid, per * qtyToMake);
        }
      } else {
        acc[pid] = (acc[pid] ?? 0) + requiredQty;
      }
    }

    await walk(productId, qty);

    final out = <Map<String, dynamic>>[];
    for (final e in acc.entries) {
      final invSnap = await db.collection('inventory').doc(e.key).get();
      final d = invSnap.data() ?? <String, dynamic>{};
      out.add({
        'productId': e.key,
        'sku': d['sku'],
        'name': d['name'],
        'requiredQty': e.value,
      });
    }

    out.sort((a, b) => (a['name'] ?? '').toString().compareTo((b['name'] ?? '').toString()));
    return out;
  }

  /// Genera requiredPartsSnapshot para una OP padre, pero descontando stock de make (y sus reservas)
  /// para no inflar compras.
  ///
  /// Espera orderData con:
  /// - lineItems: [{productId, quantity, ...}]
  Future<List<Map<String, dynamic>>> requiredBuyPartsForOrderConsideringMakeStock(
    Map<String, dynamic> orderData,
  ) async {
    final items = (orderData['lineItems'] as List<dynamic>? ?? const []);
    final Map<String, double> acc = {};

    for (final it in items) {
      final m = Map<String, dynamic>.from(it as Map);
      final pid = (m['productId'] ?? '').toString();
      final qty = (m['quantity'] as num? ?? 0).toDouble();
      if (pid.isEmpty || qty <= 0) continue;

      final parts = await requiredBuyPartsConsideringMakeStock(productId: pid, qty: qty);
      for (final p in parts) {
        final pId = (p['productId'] ?? '').toString();
        final rq = (p['requiredQty'] as num? ?? 0).toDouble();
        if (pId.isEmpty || rq <= 0) continue;
        acc[pId] = (acc[pId] ?? 0) + rq;
      }
    }

    final out = <Map<String, dynamic>>[];
    for (final e in acc.entries) {
      final invSnap = await db.collection('inventory').doc(e.key).get();
      final d = invSnap.data() ?? <String, dynamic>{};
      out.add({
        'productId': e.key,
        'sku': d['sku'],
        'name': d['name'],
        'requiredQty': e.value,
      });
    }

    out.sort((a, b) => (a['name'] ?? '').toString().compareTo((b['name'] ?? '').toString()));
    return out;
  }
}