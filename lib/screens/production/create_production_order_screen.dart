import 'dart:io';

import 'package:ams_mims/models/production_models.dart';
import 'package:ams_mims/services/bom_explosion_service.dart';
import 'package:ams_mims/services/cloudinary_service.dart';
import 'package:ams_mims/services/production_make_stock_reservation_service.dart';
import 'package:ams_mims/services/production_material_reservation_service.dart';
import 'package:ams_mims/widgets/search_selection_screen.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

class CreateProductionOrderScreen extends StatefulWidget {
  final DocumentSnapshot? orderToEdit;
  final Map<String, dynamic>? initialData;

  const CreateProductionOrderScreen({super.key, this.orderToEdit, this.initialData});

  @override
  State<CreateProductionOrderScreen> createState() => _CreateProductionOrderScreenState();
}

class _CreateProductionOrderScreenState extends State<CreateProductionOrderScreen> {
  final _formKey = GlobalKey<FormState>();
  String _orderType = 'for_stock';
  DocumentSnapshot? _selectedCustomer;
  DateTime? _deliveryDate;
  bool _isLoading = false;
  final List<ProductionLineItem> _lineItems = [];
  final _cloudinaryService = CloudinaryService();

  // ✅ Notas
  final TextEditingController _notesController = TextEditingController();

  final NumberFormat _qtyFormat = NumberFormat('0.00', 'es');
  String _fmtQty(double v) => _qtyFormat.format(v);

  double _parseQty(String v) {
    return double.tryParse(v.trim().replaceAll('.', '').replaceAll(',', '.')) ?? 0.0;
  }

  @override
  void initState() {
    super.initState();

    if (widget.orderToEdit != null) {
      final data = widget.orderToEdit!.data() as Map<String, dynamic>;
      _orderType = (data['orderType'] as String?) ?? 'for_stock';
      _deliveryDate = (data['deliveryDate'] as Timestamp?)?.toDate();

      // ✅ cargar notas si existen
      _notesController.text = (data['notes'] ?? '').toString();

      final itemsFromDb = (data['lineItems'] as List<dynamic>? ?? const []);
      _lineItems
        ..clear()
        ..addAll(itemsFromDb.map((itemData) {
          final m = Map<String, dynamic>.from(itemData as Map);
          return ProductionLineItem(
            productId: (m['productId'] ?? '').toString(),
            productName: (m['productName'] ?? '').toString(),
            productSku: (m['productSku'] ?? '').toString(),
            quantity: (m['quantity'] as num? ?? 1).toDouble(),
          );
        }));
    } else if (widget.initialData != null) {
      _lineItems.add(
        ProductionLineItem(
          productId: (widget.initialData!['productId'] ?? '').toString(),
          productName: (widget.initialData!['productName'] ?? '').toString(),
          productSku: (widget.initialData!['productSku'] ?? '').toString(),
          quantity: (widget.initialData!['quantity'] as num? ?? 1).toDouble(),
        ),
      );
      _orderType = 'for_stock';
    }
  }

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _addArticle() async {
    final selectedItem = await Navigator.of(context).push<DocumentSnapshot>(
      MaterialPageRoute(
        builder: (context) => const SearchSelectionScreen(
          collection: 'inventory',
          searchField: 'name',
          displayField: 'name',
          screenTitle: 'Seleccionar Artículo a Fabricar',
          filters: {'category': ['final_product', 'part']},
        ),
      ),
    );

    if (selectedItem == null) return;

    final data = selectedItem.data() as Map<String, dynamic>;
    final existingIndex = _lineItems.indexWhere((item) => item.productId == selectedItem.id);

    setState(() {
      if (existingIndex >= 0) {
        _lineItems[existingIndex].quantity += 1.0;
      } else {
        _lineItems.add(
          ProductionLineItem(
            productId: selectedItem.id,
            productName: (data['name'] ?? '').toString(),
            productSku: (data['sku'] ?? '').toString(),
            quantity: 1.0,
          ),
        );
      }
    });
  }

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _deliveryDate ?? DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime(2101),
    );
    if (picked != null && picked != _deliveryDate) {
      setState(() => _deliveryDate = picked);
    }
  }

  // ===========================================================================
  // Reserva MAKE: cuánto stock de subensambles make se consumirá desde inventario
  // ===========================================================================
  Future<List<Map<String, dynamic>>> computeMakeStockConsumptionForOrder() async {
    final Map<String, double> consumption = {};

    Future<void> walk(String productId, double requiredQty) async {
      final doc = await FirebaseFirestore.instance.collection('inventory').doc(productId).get();
      if (!doc.exists) return;

      final data = doc.data()!;
      final origin = (data['origin'] ?? 'buy').toString();
      if (origin != 'make') return;

      final bom = (data['bom'] as List<dynamic>? ?? const []);
      for (final c in bom) {
        final cid = (c['productId'] ?? '').toString();
        final per = ((c['quantity'] ?? c['qty']) as num? ?? 0).toDouble();
        if (cid.isEmpty || per <= 0) continue;

        final compRequired = per * requiredQty;

        final compDoc = await FirebaseFirestore.instance.collection('inventory').doc(cid).get();
        if (!compDoc.exists) continue;

        final comp = compDoc.data()!;
        final compOrigin = (comp['origin'] ?? 'buy').toString();

        if (compOrigin == 'make') {
          final stock = (comp['stock'] as num? ?? 0).toDouble();
          final reserved = (comp['reserved'] as num? ?? 0).toDouble();
          final available = stock - reserved;

          final consumeFromStock =
              available <= 0 ? 0.0 : (available >= compRequired ? compRequired : available);

          if (consumeFromStock > 0) {
            consumption[cid] = (consumption[cid] ?? 0) + consumeFromStock;
          }
        }

        await walk(cid, compRequired);
      }
    }

    for (final li in _lineItems) {
      await walk(li.productId, li.quantity);
    }

    return consumption.entries
        .map((e) => {
              'productId': e.key,
              'requiredQty': e.value,
            })
        .toList();
  }

  // ===========================================================================
  // Para órdenes hijas: BUY materials necesarios
  // ===========================================================================
  Future<List<Map<String, dynamic>>> _computeRequiredBuyMaterialsForMake({
    required String makeProductId,
    required double makeQty,
  }) async {
    final Map<String, double> req = {};

    Future<void> walk(String productId, double qty) async {
      final doc = await FirebaseFirestore.instance.collection('inventory').doc(productId).get();
      if (!doc.exists) return;

      final data = doc.data()!;
      final origin = (data['origin'] ?? 'buy').toString();

      if (origin == 'make') {
        final bom = data['bom'] as List<dynamic>? ?? const [];
        for (final component in bom) {
          await walk(
            (component['productId'] ?? '').toString(),
            ((component['quantity'] ?? component['qty']) as num? ?? 0).toDouble() * qty,
          );
        }
      } else {
        req[productId] = (req[productId] ?? 0) + qty;
      }
    }

    await walk(makeProductId, makeQty);

    final out = <Map<String, dynamic>>[];
    for (final entry in req.entries) {
      final inv = await FirebaseFirestore.instance.collection('inventory').doc(entry.key).get();
      final d = inv.data() ?? {};
      out.add({
        'productId': entry.key,
        'sku': d['sku'],
        'name': d['name'],
        'requiredQty': entry.value,
      });
    }
    return out;
  }

  Future<List<Map<String, dynamic>>> _computeShortageForRequiredMaterials(List<Map<String, dynamic>> required) async {
    final shortage = <Map<String, dynamic>>[];

    for (final r in required) {
      final productId = (r['productId'] ?? '').toString();
      if (productId.isEmpty) continue;

      final requiredQty = (r['requiredQty'] as num? ?? 0).toDouble();
      final inv = await FirebaseFirestore.instance.collection('inventory').doc(productId).get();

      final stock = (inv.data()?['stock'] as num?)?.toDouble() ?? 0.0;
      final reserved = (inv.data()?['reserved'] as num?)?.toDouble() ?? 0.0;
      final available = stock - reserved;

      if (available < requiredQty) {
        shortage.add({
          'productId': productId,
          'sku': r['sku'],
          'name': r['name'],
          'missingQty': requiredQty - available,
        });
      }
    }

    return shortage;
  }

  // ===========================================================================
  // Verificación BOM + Stock
  // ===========================================================================
  Future<Map<String, List<Map<String, dynamic>>>> checkBomAndStock() async {
    final bomSvc = BomExplosionService();
    final Map<String, double> buyReqTotals = {};

    for (final lineItem in _lineItems) {
      final parts = await bomSvc.requiredBuyPartsConsideringMakeStock(
        productId: lineItem.productId,
        qty: lineItem.quantity,
      );
      for (final p in parts) {
        final pid = (p['productId'] ?? '').toString();
        final rq = (p['requiredQty'] as num? ?? 0).toDouble();
        if (pid.isEmpty || rq <= 0) continue;
        buyReqTotals[pid] = (buyReqTotals[pid] ?? 0) + rq;
      }
    }

    final List<Map<String, dynamic>> missingBuyItems = [];
    for (final entry in buyReqTotals.entries) {
      final doc = await FirebaseFirestore.instance.collection('inventory').doc(entry.key).get();
      final d = doc.data() ?? <String, dynamic>{};

      final stock = (d['stock'] as num? ?? 0).toDouble();
      final reserved = (d['reserved'] as num? ?? 0).toDouble();
      final available = stock - reserved;

      if (available < entry.value) {
        missingBuyItems.add({
          'productId': doc.id,
          'sku': d['sku'],
          'name': d['name'],
          'missingQty': entry.value - available,
        });
      }
    }

    final Map<String, Map<String, dynamic>> makeRequirements = {};

    Future<void> explodeMake(String productId, double requiredQty, bool isTopLevelItem) async {
      final doc = await FirebaseFirestore.instance.collection('inventory').doc(productId).get();
      if (!doc.exists) return;

      final data = doc.data()!;
      final origin = (data['origin'] ?? 'buy').toString();
      if (origin != 'make') return;

      final stock = (data['stock'] as num? ?? 0).toDouble();
      final reserved = (data['reserved'] as num? ?? 0).toDouble();
      final available = stock - reserved;

      if (available < requiredQty) {
        if (!isTopLevelItem) {
          final missingQty = requiredQty - available;
          makeRequirements[doc.id] = {
            'productId': doc.id,
            'sku': data['sku'],
            'name': data['name'],
            'missingQty': (makeRequirements[doc.id]?['missingQty'] ?? 0.0) + missingQty,
          };
        }
      }

      final bom = (data['bom'] as List<dynamic>? ?? const []);
      for (final component in bom) {
        final cid = (component['productId'] ?? '').toString();
        final perUnit = ((component['quantity'] ?? component['qty']) as num? ?? 0).toDouble();
        if (cid.isEmpty || perUnit <= 0) continue;

        await explodeMake(cid, perUnit * requiredQty, false);
      }
    }

    for (final lineItem in _lineItems) {
      await explodeMake(lineItem.productId, lineItem.quantity, true);
    }

    return {'toBuy': missingBuyItems, 'toMake': makeRequirements.values.toList()};
  }

  Future<void> _saveOrder() async {
    if (!_formKey.currentState!.validate()) return;

    // ✅ edición: permitir también notas
    if (widget.orderToEdit != null) {
      setState(() => _isLoading = true);
      try {
        final existingData = widget.orderToEdit!.data() as Map<String, dynamic>;
        final existingOrderType = (existingData['orderType'] as String?) ?? 'for_stock';

        final updateData = <String, dynamic>{
          'deliveryDate': _deliveryDate,
          'notes': _notesController.text.trim(),
          'updatedAt': FieldValue.serverTimestamp(),
        };

        if (existingOrderType == 'for_customer') {
          if (_selectedCustomer != null) {
            final customerData = _selectedCustomer!.data() as Map<String, dynamic>;
            updateData['customerId'] = _selectedCustomer!.id;
            updateData['customerName'] = customerData['name'];
          }
        } else {
          updateData['customerId'] = null;
          updateData['customerName'] = null;
        }

        await widget.orderToEdit!.reference.update(updateData);
        if (mounted) Navigator.of(context).pop();
      } catch (e) {
        if (mounted) {
          setState(() => _isLoading = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error al actualizar la orden: $e')),
          );
        }
      }
      return;
    }

    if (_lineItems.isEmpty) return;

    setState(() => _isLoading = true);

    final results = await checkBomAndStock();
    final toBuy = results['toBuy']!;
    final toMake = results['toMake']!;
    final hasAnyShortage = toBuy.isNotEmpty || toMake.isNotEmpty;

    if (hasAnyShortage) {
      final userAuthorized = await showDialog<bool>(
        context: context,
        builder: (BuildContext dialogContext) => _buildShortageDialog(dialogContext, toBuy, toMake),
      );

      if (userAuthorized != true) {
        setState(() => _isLoading = false);
        return;
      }
    }

    await _createOrderInDatabase(hasAnyShortage, toBuy: toBuy, toMake: toMake);

    if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
  }

  Future<void> _createOrderInDatabase(
    bool hasShortage, {
    List<Map<String, dynamic>>? toBuy,
    List<Map<String, dynamic>>? toMake,
  }) async {
    try {
      int parentOrderNumber = 0;
      String purchaseRequestId = '';
      String? createdParentOrderDocId;

      if (toBuy != null && toBuy.isNotEmpty) {
        final counterDoc = await FirebaseFirestore.instance.collection('counters').doc('order_counter').get();
        parentOrderNumber = (counterDoc.data()!['lastOrderNumber'] as int) + 1;
        purchaseRequestId = await _createPurchaseRequest(toBuy, parentOrderNumber);
      }

      await FirebaseFirestore.instance.runTransaction((transaction) async {
        final counterRef = FirebaseFirestore.instance.collection('counters').doc('order_counter');
        final ordersCollection = FirebaseFirestore.instance.collection('production_orders');

        if (parentOrderNumber == 0) {
          final counterDoc = await transaction.get(counterRef);
          if (!counterDoc.exists) throw Exception("El documento contador no existe.");
          parentOrderNumber = (counterDoc.data()!['lastOrderNumber'] as int) + 1;
        }

        final lineItemsForDb = _lineItems
            .map((item) => {
                  'productId': item.productId,
                  'productName': item.productName,
                  'productSku': item.productSku,
                  'quantity': item.quantity,
                })
            .toList();

        final newOrderRef = ordersCollection.doc();
        createdParentOrderDocId = newOrderRef.id;

        final newOrderData = <String, dynamic>{
          'orderNumber': parentOrderNumber,
          'displayOrderNumber': parentOrderNumber.toString(),
          'isChildOrder': false,
          'childSequence': 0,
          'lineItems': lineItemsForDb,
          'status': 'En Cola',
          'hasShortage': hasShortage,
          'shortageResolved': !hasShortage,
          'orderType': _orderType,
          'deliveryDate': _deliveryDate,
          'notes': _notesController.text.trim(),
          'createdAt': FieldValue.serverTimestamp(),
          'purchaseRequestId': purchaseRequestId.isNotEmpty ? purchaseRequestId : null,
        };

        if (_orderType == 'for_customer') {
          final customerData = _selectedCustomer?.data() as Map<String, dynamic>?;
          newOrderData['customerId'] = _selectedCustomer?.id;
          newOrderData['customerName'] = customerData?['name'];
        } else {
          newOrderData['customerId'] = null;
          newOrderData['customerName'] = null;
        }

        transaction.set(newOrderRef, newOrderData);
        transaction.update(counterRef, {'lastOrderNumber': parentOrderNumber});
      });

      if (createdParentOrderDocId == null) return;

      final parentRef = FirebaseFirestore.instance.collection('production_orders').doc(createdParentOrderDocId);
      final parentSnap = await parentRef.get();
      final parentData = parentSnap.data() as Map<String, dynamic>;

      final bomSvc = BomExplosionService();
      final requiredPartsSnapshot = await bomSvc.requiredBuyPartsForOrderConsideringMakeStock(parentData);

      await parentRef.update({
        'requiredPartsSnapshot': requiredPartsSnapshot,
        'requiredPartsSnapshotAt': FieldValue.serverTimestamp(),
      });

      final reservSvc = ProductionMaterialReservationService();
      await reservSvc.reserveAvailableMaterialsForOrder(
        orderRef: parentRef,
        requiredParts: requiredPartsSnapshot,
      );

      final makeConsumption = await computeMakeStockConsumptionForOrder();
      final makeReserveSvc = ProductionMakeStockReservationService();
      await makeReserveSvc.reserveMakeStockForOrder(
        orderRef: parentRef,
        requirements: makeConsumption,
      );

      if (toMake != null && toMake.isNotEmpty) {
        await _createChildProductionOrders(toMake, parentOrderNumber);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al guardar tareas: $e')),
        );
      }
    }
  }

  Future<void> _createChildProductionOrders(List<Map<String, dynamic>> toMake, int parentOrderNumber) async {
    final ordersCollection = FirebaseFirestore.instance.collection('production_orders');
    final reservSvc = ProductionMaterialReservationService();

    for (int i = 0; i < toMake.length; i++) {
      final makeItem = toMake[i];
      final seq = i + 1;

      final makeProductId = (makeItem['productId'] ?? '').toString();
      final missingQty = (makeItem['missingQty'] as num? ?? 0).toDouble();

      if (makeProductId.isEmpty || missingQty <= 0) continue;

      final requiredMaterials = await _computeRequiredBuyMaterialsForMake(
        makeProductId: makeProductId,
        makeQty: missingQty,
      );

      final childRef = ordersCollection.doc();

      await childRef.set({
        'orderNumber': parentOrderNumber,
        'displayOrderNumber': '$parentOrderNumber-P$seq',
        'isChildOrder': true,
        'childSequence': seq,
        'parentOrderNumber': parentOrderNumber,
        'lineItems': [
          {
            'productId': makeItem['productId'],
            'productName': makeItem['name'],
            'productSku': makeItem['sku'],
            'quantity': missingQty,
          }
        ],
        'status': 'En Cola',
        'orderType': 'for_stock',
        'deliveryDate': null,
        'createdAt': FieldValue.serverTimestamp(),
        'notes': _notesController.text.trim(),

        'requiredMaterials': requiredMaterials,
        'materialsComputedAt': FieldValue.serverTimestamp(),

        'materialsReady': false,
        'materialsShortage': const [],
        'hasShortage': true,
      });

      if (requiredMaterials.isNotEmpty) {
        await reservSvc.reserveAvailableMaterialsForOrder(
          orderRef: childRef,
          requiredParts: requiredMaterials,
        );
      } else {
        await childRef.update({
          'reservedMaterials': const [],
          'reservedAt': FieldValue.serverTimestamp(),
        });
      }

      final materialsShortage = await _computeShortageForRequiredMaterials(requiredMaterials);
      final materialsReady = materialsShortage.isEmpty;

      await childRef.update({
        'materialsShortage': materialsShortage,
        'materialsReady': materialsReady,
        'hasShortage': !materialsReady,
        'materialsRecomputedAt': FieldValue.serverTimestamp(),
      });
    }
  }

  Future<String> _createPurchaseRequest(List<Map<String, dynamic>> toBuy, int parentOrderNumber) async {
    if (toBuy.isEmpty) return '';

    final pdfBytes = await _generatePurchaseRequestPdfBytes(toBuy, parentOrderNumber);

    late final String pdfUrl;
    if (kIsWeb) {
      pdfUrl = await _cloudinaryService.uploadBytes(
        pdfBytes,
        fileName: 'req_$parentOrderNumber.pdf',
        folder: 'purchase_requests',
      );
    } else {
      final tempDir = await getTemporaryDirectory();
      final file = await File('${tempDir.path}/req_$parentOrderNumber.pdf').create();
      await file.writeAsBytes(pdfBytes);
      pdfUrl = await _cloudinaryService.uploadFile(file, 'purchase_requests');
    }

    final purchaseCollection = FirebaseFirestore.instance.collection('purchase_requests');
    final newDocRef = await purchaseCollection.add({
      'parentOrderNumber': parentOrderNumber,
      'createdAt': FieldValue.serverTimestamp(),
      'status': 'pending',
      'items': toBuy
          .map((item) => {
                'productId': item['productId'],
                'name': item['name'],
                'quantity': (item['missingQty'] as num? ?? 0).toDouble(),
              })
          .toList(),
      'pdfUrl': pdfUrl,
    });

    return newDocRef.id;
  }

  Future<Uint8List> _generatePurchaseRequestPdfBytes(List<Map<String, dynamic>> toBuy, int parentOrderNumber) async {
    final pdf = pw.Document();

    pdf.addPage(
      pw.Page(
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Header(
                level: 0,
                child: pw.Text(
                  'Solicitud de Compra (Ref OP: #$parentOrderNumber)',
                  style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold),
                ),
              ),
              pw.Paragraph(
                text: 'Se requiere la compra de los siguientes materiales para la Orden de Producción #$parentOrderNumber:',
              ),
              pw.Table.fromTextArray(
                headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                headers: ['Artículo', 'SKU', 'Cantidad Requerida'],
                data: toBuy
                    .map(
                      (item) => [
                        item['name'] ?? 'N/A',
                        item['sku'] ?? 'N/A',
                        _fmtQty((item['missingQty'] as num? ?? 0).toDouble()),
                      ],
                    )
                    .toList(),
              ),
            ],
          );
        },
      ),
    );

    return pdf.save();
  }

  Widget _buildShortageDialog(
    BuildContext dialogContext,
    List<Map<String, dynamic>> toBuy,
    List<Map<String, dynamic>> toMake,
  ) {
    return AlertDialog(
      title: const Text('Centro de Mando de Faltantes'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Se han detectado faltantes. Revisa las acciones requeridas:'),
            if (toBuy.isNotEmpty) ...[
              const Divider(height: 24),
              Text(
                '1. Lista de Compras (${toBuy.length} items):',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              ...toBuy.map(
                (c) => ListTile(
                  dense: true,
                  title: Text(c['name'] ?? 'N/A'),
                  subtitle: Text('Faltan: ${_fmtQty((c['missingQty'] as num? ?? 0).toDouble())}'),
                ),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  icon: const Icon(Icons.picture_as_pdf, size: 18),
                  label: const Text('Previsualizar'),
                  onPressed: () async {
                    final counterDoc =
                        await FirebaseFirestore.instance.collection('counters').doc('order_counter').get();
                    final nextOrderNumber = (counterDoc.data()!['lastOrderNumber'] as int) + 1;
                    final pdfBytes = await _generatePurchaseRequestPdfBytes(toBuy, nextOrderNumber);
                    await Printing.layoutPdf(onLayout: (format) => pdfBytes);
                  },
                ),
              ),
            ],
            if (toMake.isNotEmpty) ...[
              const Divider(height: 24),
              Text(
                '2. Órdenes de Fab. Hijas (${toMake.length} items):',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              ...toMake.map(
                (c) => ListTile(
                  dense: true,
                  title: Text(c['name'] ?? 'N/A'),
                  subtitle: Text('Faltan: ${_fmtQty((c['missingQty'] as num? ?? 0).toDouble())}'),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(child: const Text('Cancelar'), onPressed: () => Navigator.of(dialogContext).pop(false)),
        FilledButton(
          child: const Text('Autorizar y Generar Tareas'),
          onPressed: () => Navigator.of(dialogContext).pop(true),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.orderToEdit != null;
    final existingData = widget.orderToEdit?.data() as Map<String, dynamic>?;
    final existingOrderType = existingData?['orderType'] as String?;
    final showCustomer = isEditing ? (existingOrderType == 'for_customer') : (_orderType == 'for_customer');
    final existingCustomerName = existingData?['customerName'] as String?;

    return Scaffold(
      appBar: AppBar(
        title: Text(isEditing ? 'Editar Orden' : 'Crear Orden'),
        backgroundColor: Colors.purple,
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16.0),
          children: [
            DropdownButtonFormField<String>(
              initialValue: _orderType,
              decoration: const InputDecoration(labelText: 'Tipo de Orden', border: OutlineInputBorder()),
              items: const [
                DropdownMenuItem(value: 'for_stock', child: Text('Para Stock Interno')),
                DropdownMenuItem(value: 'for_customer', child: Text('Para un Cliente')),
              ],
              onChanged: isEditing ? null : (value) => setState(() => _orderType = value!),
            ),
            const SizedBox(height: 16),
            if (showCustomer) _buildCustomerSelector(existingCustomerName: existingCustomerName),
            if (showCustomer) const SizedBox(height: 16),
            TextFormField(
              readOnly: true,
              decoration: InputDecoration(
                labelText: 'Fecha de Entrega (Opcional)',
                hintText: _deliveryDate == null ? 'Toca para seleccionar' : DateFormat('dd/MM/yyyy').format(_deliveryDate!),
                border: const OutlineInputBorder(),
              ),
              onTap: () => _selectDate(context),
            ),

            // ✅ Notas
            const SizedBox(height: 16),
            TextFormField(
              controller: _notesController,
              minLines: 2,
              maxLines: 6,
              decoration: const InputDecoration(
                labelText: 'Notas (opcional)',
                hintText: 'Ej: prioridad, instrucciones, observaciones…',
                border: OutlineInputBorder(),
              ),
            ),

            const Divider(height: 32, thickness: 1),
            Row(
              mainAxisSize: MainAxisSize.max,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Artículos a Producir', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                FilledButton.tonal(onPressed: isEditing ? null : _addArticle, child: const Text('Añadir Artículo')),
              ],
            ),
            const SizedBox(height: 8),
            if (_lineItems.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24.0),
                child: Center(child: Text('Añade artículos a la orden.', style: TextStyle(color: Colors.grey))),
              ),
            ..._lineItems.map(
              (item) => Card(
                margin: const EdgeInsets.symmetric(vertical: 4),
                child: ListTile(
                  title: Text(item.productName),
                  subtitle: Text('SKU: ${item.productSku}'),
                  trailing: SizedBox(
                    width: 190,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        SizedBox(
                          width: 90,
                          child: TextFormField(
                            enabled: !isEditing,
                            initialValue: _fmtQty(item.quantity),
                            textAlign: TextAlign.center,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            decoration: const InputDecoration(border: UnderlineInputBorder()),
                            onChanged: isEditing ? null : (value) => item.quantity = _parseQty(value),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline, color: Colors.red),
                          onPressed: isEditing ? null : () => setState(() => _lineItems.remove(item)),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: _isLoading ? null : _saveOrder,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.purple,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: _isLoading
                  ? const CircularProgressIndicator(color: Colors.white)
                  : Text(isEditing ? 'Guardar Cambios' : 'Verificar y Crear Orden'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCustomerSelector({String? existingCustomerName}) {
    return TextFormField(
      readOnly: true,
      decoration: InputDecoration(
        labelText: 'Cliente',
        hintText: _selectedCustomer != null
            ? (_selectedCustomer!.data() as Map<String, dynamic>)['name']
            : (existingCustomerName ?? 'Toca para seleccionar un cliente'),
        border: const OutlineInputBorder(),
        suffixIcon: const Icon(Icons.search),
      ),
      validator: (v) {
        if (_orderType != 'for_customer' && widget.orderToEdit == null) return null;
        final hasExisting = existingCustomerName != null && existingCustomerName.toString().isNotEmpty;
        if (_selectedCustomer == null && !hasExisting) return 'Debes seleccionar un cliente.';
        return null;
      },
      onTap: () async {
        final c = await Navigator.of(context).push<DocumentSnapshot>(
          MaterialPageRoute(
            builder: (ctx) => const SearchSelectionScreen(
              collection: 'customers',
              searchField: 'name',
              displayField: 'name',
              screenTitle: 'Seleccionar Cliente',
            ),
          ),
        );
        if (c != null) setState(() => _selectedCustomer = c);
      },
    );
  }
}