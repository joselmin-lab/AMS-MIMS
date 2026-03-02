import 'dart:io';


import 'package:ams_mims/screens/inventory/inventory_intake_screen.dart';
import 'package:ams_mims/screens/production/assign_operators_to_stages_screen.dart';
import 'package:ams_mims/screens/production/cancel_production_order_screen.dart' as cancel_ui;
import 'package:ams_mims/screens/production/cancel_production_order_wizard_screen.dart';
import 'package:ams_mims/screens/production/create_production_order_screen.dart';
import 'package:ams_mims/screens/production/production_order_detail_screen.dart';
import 'package:ams_mims/services/production_order_finish_service.dart';
import 'package:ams_mims/services/production_process_pdf_service.dart';
import 'package:ams_mims/services/production_reservation_release_service.dart' as reservation_svc;
import 'package:ams_mims/services/thermal_printer_service.dart';
import 'package:ams_mims/widgets/pdf_viewer_screen.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

class OrderListWidget extends StatelessWidget {
  final String status;

  const OrderListWidget({super.key, required this.status});

  double _parseQty(String v) {
    return double.tryParse(v.trim().replaceAll('.', '').replaceAll(',', '.')) ?? 0.0;
  }

  String _formatQty(num v) {
    final nf = NumberFormat('0.00', 'es');
    return nf.format(v.toDouble());
  }

  @override
  Widget build(BuildContext context) {
    final Stream<QuerySnapshot> stream = FirebaseFirestore.instance
        .collection('production_orders')
        .where('status', isEqualTo: status)
        .orderBy('orderNumber', descending: true)
        .orderBy('isChildOrder') // false (padre) primero
        .orderBy('childSequence') // 0 (padre), 1..N (hijas)
        .snapshots();

    return StreamBuilder<QuerySnapshot>(
      stream: stream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          // ignore: avoid_print
          print(snapshot.error);
          return const Center(child: Text('Error. ¿Creaste el índice?'));
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.data!.docs.isEmpty) {
          return Center(
            child: Text(
              'No hay órdenes en estado "$status".',
              style: const TextStyle(fontSize: 18, color: Colors.grey),
            ),
          );
        }

        return ListView.builder(
          itemCount: snapshot.data!.docs.length,
          padding: const EdgeInsets.all(8.0),
          itemBuilder: (context, index) {
            final document = snapshot.data!.docs[index];
            final data = document.data()! as Map<String, dynamic>;

            final lineItems = data['lineItems'] as List<dynamic>? ?? [];
            final deliveryDate = data['deliveryDate'] as Timestamp?;
            final currentStatus = data['status'] as String? ?? 'Desconocido';
            final hasShortage = data['hasShortage'] as bool? ?? false;
            final purchaseRequestId = data['purchaseRequestId'] as String?;
            final isChildOrder = data['isChildOrder'] as bool? ?? false;

            final materialsReady = data['materialsReady'] as bool?; // solo existe en hijas
            final materialsShortage = (data['materialsShortage'] as List<dynamic>? ?? const []);

            final displayOrderNumber = (data['displayOrderNumber']?.toString().isNotEmpty ?? false)
                ? data['displayOrderNumber'].toString()
                : (data['orderNumber']?.toString() ?? 'S/N');

            final double indent = isChildOrder ? 18.0 : 0.0;
            final Color? childTint = isChildOrder ? Colors.blueGrey.withValues(alpha: 0.06) : null;
            final String titlePrefix = isChildOrder ? '↳ ' : '';

            String shortagePreview() {
              if (!isChildOrder || materialsShortage.isEmpty) return '';
              final take = materialsShortage.take(2).map((e) {
                final m = Map<String, dynamic>.from(e as Map);
                final name = (m['name'] ?? '').toString();
                final missing = (m['missingQty'] as num? ?? 0).toDouble();
                return '${name.isEmpty ? 'Material' : name}: ${_formatQty(missing)}';
              }).join(' · ');
              final extra = materialsShortage.length - 2;
              return extra > 0 ? '$take · +$extra más' : take;
            }

            return InkWell(
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => ProductionOrderDetailScreen(orderRef: document.reference),
                  ),
                );
              },
              child: Card(
                elevation: isChildOrder ? 1 : 3,
                color: childTint,
                margin: EdgeInsets.fromLTRB(8 + indent, 6, 8, 6),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: isChildOrder
                      ? BorderSide(color: Colors.blueGrey.withValues(alpha: 0.25), width: 1)
                      : BorderSide.none,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    Text(
                                      '${titlePrefix}OP: #$displayOrderNumber',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 18,
                                        color: isChildOrder ? Colors.blueGrey.shade800 : Colors.black,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    if (hasShortage)
                                      Tooltip(
                                        message: isChildOrder
                                            ? 'Orden hija bloqueada por materiales'
                                            : 'Esta orden tiene faltantes',
                                        child: const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 20),
                                      ),
                                    if (!isChildOrder)
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          if (purchaseRequestId != null)
                                            Tooltip(
                                              message: 'Ver Solicitud de Compra',
                                              child: IconButton(
                                                padding: EdgeInsets.zero,
                                                constraints: const BoxConstraints(),
                                                icon: const Icon(
                                                  Icons.shopping_cart_outlined,
                                                  color: Colors.indigo,
                                                  size: 22,
                                                ),
                                                onPressed: () async {
                                                  try {
                                                    final purchaseDoc = await FirebaseFirestore.instance
                                                        .collection('purchase_requests')
                                                        .doc(purchaseRequestId)
                                                        .get();
                                                    if (!purchaseDoc.exists) return;

                                                    final pdfUrl = purchaseDoc.data()?['pdfUrl'] as String?;
                                                    if (pdfUrl == null || pdfUrl.isEmpty) {
                                                      if (!context.mounted) return;
                                                      ScaffoldMessenger.of(context).showSnackBar(
                                                        const SnackBar(
                                                          content: Text('La solicitud de compra no tiene un PDF adjunto.'),
                                                        ),
                                                      );
                                                      return;
                                                    }

                                                    if (kIsWeb) {
                                                      final uri = Uri.parse(pdfUrl);
                                                      if (await canLaunchUrl(uri)) {
                                                        await launchUrl(uri, mode: LaunchMode.externalApplication);
                                                      }
                                                    } else {
                                                      if (!context.mounted) return;
                                                      Navigator.of(context).push(
                                                        MaterialPageRoute(
                                                          builder: (context) => PdfViewerScreen(
                                                            pdfUrl: pdfUrl,
                                                            title: 'Solicitud de Compra (OP: #$displayOrderNumber)',
                                                          ),
                                                        ),
                                                      );
                                                    }
                                                  } catch (e) {
                                                    if (!context.mounted) return;
                                                    ScaffoldMessenger.of(context).showSnackBar(
                                                      SnackBar(content: Text('Error al abrir PDF: $e')),
                                                    );
                                                  }
                                                },
                                              ),
                                            ),
                                          Tooltip(
                                            message: 'Recepcionar / Ajustar inventario para esta OP',
                                            child: IconButton(
                                              padding: EdgeInsets.zero,
                                              constraints: const BoxConstraints(),
                                              icon: const Icon(
                                                Icons.playlist_add_check_circle_outlined,
                                                color: Colors.teal,
                                                size: 22,
                                              ),
                                              onPressed: () async {
                                                if (!context.mounted) return;
                                                await Navigator.of(context).push(
                                                  MaterialPageRoute(
                                                    builder: (_) => InventoryMovementScreen(
                                                      referenceType: 'production_order',
                                                      referenceId: document.id,
                                                      referenceLabel: 'OP #$displayOrderNumber',
                                                    ),
                                                  ),
                                                );
                                              },
                                            ),
                                          ),
                                        ],
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Chip(
                                  label: Text(
                                    currentStatus,
                                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                                  ),
                                  backgroundColor: _getStatusColor(currentStatus),
                                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  visualDensity: VisualDensity.compact,
                                ),
                                if (isChildOrder && materialsReady == false)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 6.0),
                                    child: Text(
                                      'Bloqueada: faltan materiales · ${shortagePreview()}',
                                      style: TextStyle(color: Colors.orange.shade900, fontSize: 12),
                                    ),
                                  ),
                              ],
                            ),
                          ),

                          if (isChildOrder && currentStatus != 'Finalizadas')
                            IconButton(
                              tooltip: materialsReady == false
                                  ? 'No se puede finalizar: faltan materiales'
                                  : 'Finalizar orden hija (ingresa stock)',
                              icon: Icon(
                                Icons.check_circle_outline,
                                color: materialsReady == false ? Colors.grey : Colors.green,
                              ),
                              onPressed: (materialsReady == false)
                                  ? () {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(
                                          content: Text('No puedes finalizar esta orden hija: faltan materiales.'),
                                        ),
                                      );
                                    }
                                  : () async {
                                      final qtyCtrl = TextEditingController(
                                        text: (() {
                                          if (lineItems.isEmpty) return '0,00';
                                          final q = (lineItems.first as Map)['quantity'];
                                          final qd = (q as num? ?? 0).toDouble();
                                          return _formatQty(qd);
                                        })(),
                                      );
                                      final noteCtrl = TextEditingController(text: 'Recepción por producción');

                                      final ok = await showDialog<bool>(
                                        context: context,
                                        builder: (ctx) => AlertDialog(
                                          title: const Text('Finalizar OP hija'),
                                          content: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              TextField(
                                                controller: qtyCtrl,
                                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                                decoration: const InputDecoration(
                                                  labelText: 'Cantidad producida',
                                                  border: OutlineInputBorder(),
                                                ),
                                              ),
                                              const SizedBox(height: 12),
                                              TextField(
                                                controller: noteCtrl,
                                                decoration: const InputDecoration(
                                                  labelText: 'Nota (opcional)',
                                                  border: OutlineInputBorder(),
                                                ),
                                              ),
                                            ],
                                          ),
                                          actions: [
                                            TextButton(
                                              onPressed: () => Navigator.of(ctx).pop(false),
                                              child: const Text('Cancelar'),
                                            ),
                                            FilledButton(
                                              onPressed: () => Navigator.of(ctx).pop(true),
                                              child: const Text('Finalizar'),
                                            ),
                                          ],
                                        ),
                                      );

                                      if (ok != true) return;

                                      final qty = _parseQty(qtyCtrl.text);
                                      if (qty <= 0) {
                                        if (!context.mounted) return;
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          const SnackBar(content: Text('La cantidad debe ser mayor a 0.')),
                                        );
                                        return;
                                      }

                                      try {
                                        final svc = ProductionOrderFinishService();
                                        await svc.finishChildOrder(
                                          orderDoc: document,
                                          producedQtyOverride: qty,
                                          note: noteCtrl.text,
                                        );

                                        if (!context.mounted) return;
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          const SnackBar(content: Text('OP hija finalizada y stock ingresado.')),
                                        );
                                      } catch (e) {
                                        if (!context.mounted) return;
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(content: Text('Error finalizando OP hija: $e')),
                                        );
                                      }
                                    },
                            ),

                          // ✅ MENÚ AJUSTADO
                          PopupMenuButton<String>(
                            onSelected: (value) async {
                              if (value == 'edit') {
                                if (!context.mounted) return;
                                Navigator.of(context).push(
                                  MaterialPageRoute(builder: (_) => CreateProductionOrderScreen(orderToEdit: document)),
                                );
                                return;
                              }

                              if (value == 'to_process') {
                                await Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => AssignOperatorsToStagesScreen(parentOrderDoc: document),
                                  ),
                                );

                                if (!context.mounted) return;
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => ProductionOrderDetailScreen(orderRef: document.reference),
                                  ),
                                );
                                return;
                              }

                              if (value == 'cancel') {
                                if (currentStatus == 'En Proceso') {
                                  await Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => CancelProductionOrderWizardScreen(orderDoc: document),
                                    ),
                                  );
                                } else if (currentStatus == 'En Cola') {
                                  await Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => cancel_ui.CancelProductionOrderScreen(orderDoc: document),
                                    ),
                                  );
                                }
                                return;
                              }

                              if (value == 'delete') {
                                _showDeleteConfirmation(context, document);
                                return;
                              }

                              if (value == 'process_pdf_generate') {
                                try {
                                  final svc = ProductionProcessPdfService();
                                  final url = await svc.generateAndUploadProcessPdf(orderRef: document.reference);

                                  if (!context.mounted) return;

                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('PDF de proceso generado.')),
                                  );

                                  if (kIsWeb) {
                                    final uri = Uri.parse(url);
                                    if (await canLaunchUrl(uri)) {
                                      await launchUrl(uri, mode: LaunchMode.externalApplication);
                                    }
                                  } else {
                                    Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (_) => PdfViewerScreen(
                                          pdfUrl: url,
                                          title: 'PDF Proceso (OP #$displayOrderNumber)',
                                        ),
                                      ),
                                    );
                                  }
                                } catch (e) {
                                  if (!context.mounted) return;
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('Error generando PDF: $e')),
                                  );
                                }
                                return;
                              }

                              if (value == 'process_pdf_view') {
                                final url = (data['processPdfUrl'] ?? '').toString();
                                if (url.isEmpty) return;

                                try {
                                  if (kIsWeb) {
                                    final uri = Uri.parse(url);
                                    if (await canLaunchUrl(uri)) {
                                      await launchUrl(uri, mode: LaunchMode.externalApplication);
                                    }
                                  } else {
                                    if (!context.mounted) return;
                                    Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (_) => PdfViewerScreen(
                                          pdfUrl: url,
                                          title: 'PDF Proceso (OP #$displayOrderNumber)',
                                        ),
                                      ),
                                    );
                                  }
                                } catch (e) {
                                  if (!context.mounted) return;
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('Error abriendo PDF: $e')),
                                  );
                                }
                                return;
                              }

                              if (value == 'thermal_print') {
                                try {
                                  final svc = ThermalPrinterService();
                                  final mac = await svc.getDefaultPrinterMac();

                                  if (mac.isEmpty) {
                                    if (!context.mounted) return;
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text('No hay impresora configurada.')),
                                    );
                                    return;
                                  }

                                  await svc.printProductionOrderLabel(orderRef: document.reference, printerMac: mac);

                                  if (!context.mounted) return;
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Etiqueta enviada a la impresora.')),
                                  );
                                } catch (e) {
                                  if (!context.mounted) return;
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('Error imprimiendo: $e')),
                                  );
                                }
                                return;
                              }
                            },
                            itemBuilder: (BuildContext context) {
                              final items = <PopupMenuEntry<String>>[];

                              // Solo padre
                              if (!isChildOrder && currentStatus == 'En Cola') {
                                items.addAll(const [
                                  PopupMenuItem<String>(
                                    value: 'edit',
                                    child: ListTile(
                                      leading: Icon(Icons.edit_outlined),
                                      title: Text('Editar (cliente/fecha/notas)'),
                                    ),
                                  ),
                                  PopupMenuItem<String>(
                                    value: 'to_process',
                                    child: ListTile(
                                      leading: Icon(Icons.play_arrow),
                                      title: Text('Pasar a Proceso (asignar personal)'),
                                    ),
                                  ),
                                  PopupMenuItem<String>(
                                    value: 'delete',
                                    child: ListTile(
                                      leading: Icon(Icons.delete_outline, color: Colors.red),
                                      title: Text('Eliminar (libera reservas)'),
                                    ),
                                  ),
                                  PopupMenuItem<String>(
                                    value: 'cancel',
                                    child: ListTile(
                                      leading: Icon(Icons.block, color: Colors.red),
                                      title: Text('Cancelar OP'),
                                    ),
                                  ),
                                ]);
                              }

                              if (!isChildOrder && currentStatus == 'En Proceso') {
                                items.addAll([
                                  const PopupMenuItem<String>(
                                    value: 'process_pdf_generate',
                                    child: ListTile(
                                      leading: Icon(Icons.picture_as_pdf_outlined),
                                      title: Text('Generar PDF Proceso'),
                                    ),
                                  ),
                                  if (((data['processPdfUrl'] as String?)?.isNotEmpty ?? false))
                                    const PopupMenuItem<String>(
                                      value: 'process_pdf_view',
                                      child: ListTile(
                                        leading: Icon(Icons.open_in_new),
                                        title: Text('Ver PDF Proceso'),
                                      ),
                                    ),
                                  if (!kIsWeb && Platform.isAndroid) ...const [
                                    PopupMenuItem<String>(
                                      value: 'thermal_print',
                                      child: ListTile(
                                        leading: Icon(Icons.print),
                                        title: Text('Imprimir etiqueta térmica'),
                                      ),
                                    ),
                                  ],
                                  const PopupMenuItem<String>(
                                    value: 'cancel',
                                    child: ListTile(
                                      leading: Icon(Icons.block, color: Colors.red),
                                      title: Text('Cancelar OP (retorno/scrap 1x1)'),
                                    ),
                                  ),
                                ]);
                              }

                              return items;
                            },
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 12, indent: 16, endIndent: 16),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            data['orderType'] == 'for_customer'
                                ? 'Cliente: ${data['customerName'] ?? 'N/A'}'
                                : 'Para Stock Interno',
                            style: TextStyle(
                              fontStyle: FontStyle.italic,
                              fontSize: 14,
                              color: isChildOrder ? Colors.blueGrey.shade800 : Colors.black87,
                            ),
                          ),
                          if (deliveryDate != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 4.0),
                              child: Text(
                                'Fecha Entrega: ${DateFormat('dd/MM/yyyy').format(deliveryDate.toDate())}',
                                style: const TextStyle(color: Colors.black54, fontSize: 14),
                              ),
                            ),
                          const SizedBox(height: 12),
                          const Text('Artículos:', style: TextStyle(fontWeight: FontWeight.w600)),
                          Padding(
                            padding: const EdgeInsets.only(left: 8.0, top: 4.0),
                            child: Column(
                              children: lineItems.map((item) {
                                final m = item as Map;
                                final qty = (m['quantity'] as num? ?? 0).toDouble();
                                return Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(child: Text('- ${m['productName'] ?? '...'}')),
                                    Text('Cant: ${_formatQty(qty)}'),
                                  ],
                                );
                              }).toList(),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _showDeleteConfirmation(BuildContext context, DocumentSnapshot document) async {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Confirmar Eliminación'),
          content: const SingleChildScrollView(
            child: ListBody(
              children: <Widget>[
                Text('¿Estás seguro de que quieres eliminar esta orden?'),
                Text('Esto liberará las reservas y eliminará la OP (y sus hijas).'),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Cancelar'),
              onPressed: () => Navigator.of(dialogContext).pop(),
            ),
            TextButton(
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('Eliminar'),
              onPressed: () async {
                Navigator.of(dialogContext).pop();

                final data = document.data() as Map<String, dynamic>;
                final isChildOrder = data['isChildOrder'] as bool? ?? false;

                if (isChildOrder) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('No se puede eliminar una orden hija individualmente.')),
                  );
                  return;
                }

                final parentOrderNumber = data['orderNumber'];
                final purchaseRequestId = data['purchaseRequestId'] as String?;

                try {
                  final releaseSvc = reservation_svc.ProductionReservationReleaseService();
                  await releaseSvc.releaseReservedMaterialsFromOrderSnapshot(orderData: data);

                  if (parentOrderNumber != null) {
                    final childrenQuery = await FirebaseFirestore.instance
                        .collection('production_orders')
                        .where('parentOrderNumber', isEqualTo: parentOrderNumber)
                        .get();

                    for (final child in childrenQuery.docs) {
                      final childData = child.data();
                      final childStatus = (childData['status'] as String?) ?? '';

                      if (childStatus == 'En Cola') {
                        final releaseSvc2 = reservation_svc.ProductionReservationReleaseService();
                        await releaseSvc2.releaseReservedMaterialsFromOrderSnapshot(orderData: childData);
                      }

                      await child.reference.delete();
                    }
                  }

                  await document.reference.delete();

                  if (purchaseRequestId != null && purchaseRequestId.isNotEmpty) {
                    await FirebaseFirestore.instance.collection('purchase_requests').doc(purchaseRequestId).delete();
                  }

                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Orden #${data['orderNumber']} eliminada y reservas liberadas.')),
                  );
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error al eliminar: $e')),
                  );
                }
              },
            ),
          ],
        );
      },
    );
  }

  Color _getStatusColor(String? status) {
    switch (status) {
      case 'En Cola':
        return Colors.blueGrey;
      case 'En Proceso':
        return Colors.blue;
      case 'Finalizadas':
        return Colors.green;
      case 'Cancelada':
        return Colors.red;
      default:
        return Colors.black;
    }
  }
}