import 'dart:io';

import 'package:ams_mims/screens/production/create_production_order_screen.dart';
import 'package:ams_mims/services/production_process_pdf_service.dart';
import 'package:ams_mims/services/production_stage_advance_service.dart';
import 'package:ams_mims/services/thermal_printer_service.dart';
import 'package:ams_mims/widgets/pdf_viewer_screen.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:ams_mims/screens/production/assign_operators_to_stages_screen.dart';


class ProductionOrderDetailScreen extends StatelessWidget {
  final DocumentReference orderRef;

  const ProductionOrderDetailScreen({super.key, required this.orderRef});

  static const List<String> stageOrder = [
    'Mecanizado',
    'Soldadura',
    'Pintura',
    'Ensamblaje',
    'Control de Calidad',
  ];

  String _fmtQty(num v) => NumberFormat('0.00', 'es').format(v.toDouble());

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

  String _orderTypeLabel(String v) {
    switch (v) {
      case 'for_customer':
        return 'Para cliente';
      case 'for_stock':
        return 'Para stock interno';
      default:
        return v.isEmpty ? 'N/A' : v;
    }
  }

  String _nextStageLabel(String current) {
    final idx = stageOrder.indexOf(current);
    if (idx < 0) return '';
    if (idx >= stageOrder.length - 1) return '';
    return stageOrder[idx + 1];
  }

  Future<void> _openPdf(BuildContext context, String url, String title) async {
    if (url.trim().isEmpty) return;

    if (kIsWeb) {
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
      return;
    }

    if (!context.mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => PdfViewerScreen(pdfUrl: url, title: title)),
    );
  }

  List<Map<String, dynamic>> _readIssued(Map<String, dynamic> data) {
    final issuedBuy = (data['issuedMaterials'] as List<dynamic>? ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();

    final issuedMake = (data['issuedMakeMaterials'] as List<dynamic>? ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();

    final all = <Map<String, dynamic>>[
      ...issuedBuy.map((m) => {
            'productId': m['productId'],
            'sku': m['sku'],
            'name': m['name'],
            'qty': (m['qty'] as num? ?? 0).toDouble(),
            'type': 'buy',
          }),
      ...issuedMake.map((m) => {
            'productId': m['productId'],
            'sku': m['sku'],
            'name': m['name'],
            'qty': (m['qty'] as num? ?? 0).toDouble(),
            'type': 'make',
          }),
    ];

    final Map<String, Map<String, dynamic>> merged = {};
    for (final m in all) {
      final pid = (m['productId'] ?? '').toString();
      final q = (m['qty'] as num? ?? 0).toDouble();
      if (pid.isEmpty || q == 0) continue;

      if (!merged.containsKey(pid)) {
        merged[pid] = Map<String, dynamic>.from(m);
      } else {
        merged[pid]!['qty'] = ((merged[pid]!['qty'] as num?)?.toDouble() ?? 0.0) + q;
      }
    }

    final out = merged.values.toList();
    out.sort((a, b) => (a['name'] ?? '').toString().compareTo((b['name'] ?? '').toString()));
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('dd/MM/yyyy');

    return StreamBuilder<DocumentSnapshot>(
      stream: orderRef.snapshots(),
      builder: (context, snap) {
        if (snap.hasError) return const Scaffold(body: Center(child: Text('Error cargando OP')));
        if (!snap.hasData) return const Scaffold(body: Center(child: CircularProgressIndicator()));
        if (!(snap.data?.exists ?? false)) return const Scaffold(body: Center(child: Text('OP no encontrada.')));

        final doc = snap.data!;
        final data = doc.data() as Map<String, dynamic>;

        final displayOrderNumber = (data['displayOrderNumber']?.toString().isNotEmpty ?? false)
            ? data['displayOrderNumber'].toString()
            : (data['orderNumber']?.toString() ?? doc.id);

        final orderType = (data['orderType'] ?? '').toString();
        final orderTypeLabel = _orderTypeLabel(orderType);

        final status = (data['status'] ?? '').toString();
        final isChildOrder = data['isChildOrder'] as bool? ?? false;

        final customerName = (data['customerName'] ?? '').toString();
        final deliveryDate = data['deliveryDate'] as Timestamp?;

        final notes = (data['notes'] ?? '').toString();

        final lineItems = (data['lineItems'] as List<dynamic>? ?? const [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();

        final processStage = (data['processStage'] ?? '').toString();
        final processStages = (data['processStages'] as List<dynamic>? ?? const [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();

        final issued = _readIssued(data);
        final processPdfUrl = (data['processPdfUrl'] ?? '').toString();

        final productSummary = lineItems.isEmpty
            ? 'N/A'
            : (lineItems.length == 1
                ? (lineItems.first['productName'] ?? '').toString()
                : '${(lineItems.first['productName'] ?? '').toString()} +${lineItems.length - 1}');

        final canAdvanceStage = !isChildOrder && status == 'En Proceso' && processStages.isNotEmpty;
        final nextStage = _nextStageLabel(processStage);

        return Scaffold(
          appBar: AppBar(
            title: Text('OP #$displayOrderNumber'),
            backgroundColor: Colors.blueGrey.shade900,
            actions: [
              if (!isChildOrder && status == 'En Cola')
                IconButton(
                  tooltip: 'Editar',
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => CreateProductionOrderScreen(orderToEdit: doc)),
                    );
                  },
                ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Chip(
                            label: Text(
                              status,
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                            ),
                            backgroundColor: _getStatusColor(status),
                          ),
                          Chip(
                            label: Text(orderTypeLabel, style: const TextStyle(fontWeight: FontWeight.w600)),
                          ),
                          if (processStage.isNotEmpty)
                            Chip(
                              label: Text('Etapa: $processStage'),
                              backgroundColor: Colors.blueGrey.withValues(alpha: 0.12),
                            ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _InfoRow(label: 'Orden', value: '#$displayOrderNumber'),
                      _InfoRow(label: 'Tipo', value: orderTypeLabel),
                      _InfoRow(
                        label: 'Cliente',
                        value: orderType == 'for_customer'
                            ? (customerName.isEmpty ? 'N/A' : customerName)
                            : '—',
                      ),
                      _InfoRow(label: 'Producto', value: productSummary.isEmpty ? 'N/A' : productSummary),
                      _InfoRow(
                        label: 'Fecha entrega',
                        value: deliveryDate == null ? '—' : df.format(deliveryDate.toDate()),
                      ),
                      if (canAdvanceStage) ...[
                        const SizedBox(height: 12),
                        FilledButton.icon(
                          icon: const Icon(Icons.skip_next),
                          label: Text(
                            processStage == 'Control de Calidad'
                                ? 'Finalizar (Cerrar Control de Calidad)'
                                : (nextStage.isEmpty ? 'Avanzar etapa' : 'Avanzar a: $nextStage'),
                          ),
                          onPressed: () async {
                            final isFinal = processStage == 'Control de Calidad';

                            final ok = await showDialog<bool>(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                title: Text(isFinal ? 'Finalizar OP' : 'Avanzar etapa'),
                                content: Text(
                                  isFinal
                                      ? 'Esto cerrará "Control de Calidad", pasará la OP a "Finalizadas" e ingresará el producto terminado a inventario.'
                                      : (nextStage.isEmpty
                                          ? '¿Confirmas avanzar etapa?'
                                          : '¿Confirmas pasar a la etapa "$nextStage"?'),
                                ),
                                actions: [
                                  TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancelar')),
                                  FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Confirmar')),
                                ],
                              ),
                            );

                            if (ok != true) return;

                            try {
                              final svc = ProductionStageAdvanceService();
                              await svc.advanceParentOrderStage(
                                orderRef: orderRef,
                                note: 'Cambio de etapa desde detalle OP',
                              );

                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text(isFinal ? 'OP finalizada.' : 'Etapa actualizada.')),
                              );
                            } catch (e) {
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Error avanzando etapa: $e')),
                              );
                            }
                          },
                        ),
                      ],
                    ],
                  ),
                ),
              ),

              if (notes.trim().isNotEmpty) ...[
                const SizedBox(height: 12),
                const Text('Notas', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                Card(child: Padding(padding: const EdgeInsets.all(12), child: Text(notes))),
              ],

              const Divider(height: 32),

              const Text('Productos / Line items', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              if (lineItems.isEmpty)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(12),
                    child: Text('No hay productos en esta OP.'),
                  ),
                )
              else
                ...lineItems.map((m) {
                  final name = (m['productName'] ?? '').toString();
                  final sku = (m['productSku'] ?? '').toString();
                  final qty = (m['quantity'] as num? ?? 0).toDouble();
                  return Card(
                    child: ListTile(
                      leading: const Icon(Icons.shopping_bag_outlined),
                      title: Text(name.isEmpty ? '(Sin nombre)' : name),
                      subtitle: Text('SKU: ${sku.isEmpty ? 'N/A' : sku}'),
                      trailing: Text(_fmtQty(qty)),
                    ),
                  );
                }),

              const Divider(height: 32),

              const Text('Etapas / Asignación', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              if (processStages.isEmpty)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(12),
                    child: Text('Aún no hay etapas asignadas para esta OP.'),
                  ),
                )
              else
                ...processStages.map((st) {
                  final name = (st['name'] ?? '').toString();
                  final state = (st['state'] ?? '').toString();

                  final assignedUsers = (st['assignedUsers'] as List<dynamic>? ?? const [])
                      .map((u) => Map<String, dynamic>.from(u as Map))
                      .toList();

                  final assignedNames = assignedUsers
                      .map((u) => (u['name'] ?? u['id'] ?? '').toString())
                      .where((s) => s.isNotEmpty)
                      .toList();

                  final isCurrent = processStage.isNotEmpty && processStage == name;

                  return Card(
                    child: ListTile(
                      leading: Icon(isCurrent ? Icons.play_circle_fill : Icons.radio_button_unchecked),
                      title: Text(name.isEmpty ? '(Etapa)' : name),
                      subtitle: Text(
                        [
                          if (state.isNotEmpty) 'Estado: $state',
                          if (assignedNames.isNotEmpty) 'Operarios: ${assignedNames.join(', ')}',
                          if (assignedNames.isEmpty) 'Operarios: (sin asignar)',
                        ].join(' · '),
                      ),
                    ),
                  );
                }),

                const SizedBox(height: 8),
                ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).push(MaterialPageRoute(
                      builder: (context) => AssignOperatorsToStagesScreen(
                        parentOrderDoc: doc, // La variable que ya tienes con los datos de la OP
                      ),
                    ));
                  },
                  child: const Text('Editar Asignaciones'),
                ),

              const Divider(height: 32),

              ExpansionTile(
                initiallyExpanded: false,
                title: const Text(
                  'Partes / Materiales (emitidos a producción)',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: Text('${issued.length} ítem(s)'),
                childrenPadding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
                children: [
                  if (issued.isEmpty)
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(12),
                        child: Text('Aún no hay materiales emitidos (solo aparece al pasar a En Proceso).'),
                      ),
                    )
                  else
                    ...issued.map((m) {
                      final name = (m['name'] ?? '').toString();
                      final sku = (m['sku'] ?? '').toString();
                      final type = (m['type'] ?? '').toString();
                      final qty = (m['qty'] as num? ?? 0).toDouble();
                      return Card(
                        child: ListTile(
                          dense: true,
                          leading: Icon(type == 'make' ? Icons.precision_manufacturing : Icons.inventory_2_outlined),
                          title: Text(name.isEmpty ? 'Material' : name),
                          subtitle: Text('SKU: ${sku.isEmpty ? 'N/A' : sku} · Tipo: $type'),
                          trailing: Text(_fmtQty(qty)),
                        ),
                      );
                    }),
                ],
              ),

              const Divider(height: 32),

              const Text('Documentación PDF', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              FutureBuilder<List<Map<String, dynamic>>>(
                future: () async {
                  final List<Map<String, dynamic>> docs = [];

                  Future<void> addDocByProductId({
                    required String productId,
                    required String fallbackName,
                    required String fallbackSku,
                    required String docTypeLabel,
                  }) async {
                    if (productId.trim().isEmpty) return;

                    final invSnap = await FirebaseFirestore.instance.collection('inventory').doc(productId).get();
                    final inv = invSnap.data() ?? <String, dynamic>{};

                    final url = (inv['documentUrl'] ?? '').toString().trim();
                    if (url.isEmpty) return;

                    docs.add({
                      'productId': productId,
                      'name': (inv['name'] ?? fallbackName).toString(),
                      'sku': (inv['sku'] ?? fallbackSku).toString(),
                      'documentUrl': url,
                      'docTypeLabel': docTypeLabel,
                    });
                  }

                  for (final li in lineItems) {
                    await addDocByProductId(
                      productId: (li['productId'] ?? '').toString(),
                      fallbackName: (li['productName'] ?? '').toString(),
                      fallbackSku: (li['productSku'] ?? '').toString(),
                      docTypeLabel: 'Producto',
                    );
                  }

                  for (final m in issued) {
                    await addDocByProductId(
                      productId: (m['productId'] ?? '').toString(),
                      fallbackName: (m['name'] ?? '').toString(),
                      fallbackSku: (m['sku'] ?? '').toString(),
                      docTypeLabel: 'Parte',
                    );
                  }

                  final seen = <String>{};
                  final out = <Map<String, dynamic>>[];
                  for (final d in docs) {
                    final key = '${d['docTypeLabel']}|${d['productId']}';
                    if (seen.add(key)) out.add(d);
                  }

                  out.sort((a, b) {
                    final ta = (a['docTypeLabel'] ?? '').toString();
                    final tb = (b['docTypeLabel'] ?? '').toString();
                    final na = (a['name'] ?? '').toString();
                    final nb = (b['name'] ?? '').toString();
                    final t = ta.compareTo(tb);
                    return t != 0 ? t : na.compareTo(nb);
                  });

                  return out;
                }(),
                builder: (context, docsSnap) {
                  if (!docsSnap.hasData) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 10),
                      child: LinearProgressIndicator(),
                    );
                  }

                  final docs = docsSnap.data!;
                  if (docs.isEmpty) {
                    return const Card(
                      child: Padding(
                        padding: EdgeInsets.all(12),
                        child: Text('No hay PDFs asociados (ni producto ni partes).'),
                      ),
                    );
                  }

                  return Column(
                    children: docs.map((d) {
                      final name = (d['name'] ?? '').toString();
                      final sku = (d['sku'] ?? '').toString();
                      final url = (d['documentUrl'] ?? '').toString();
                      final typeLabel = (d['docTypeLabel'] ?? '').toString();

                      return Card(
                        child: ListTile(
                          leading: const Icon(Icons.picture_as_pdf_outlined),
                          title: Text(name.isEmpty ? 'Item' : name),
                          subtitle: Text('${typeLabel.isEmpty ? '' : '$typeLabel · '}SKU: ${sku.isEmpty ? 'N/A' : sku}'),
                          trailing: const Icon(Icons.open_in_new),
                          onTap: () => _openPdf(context, url, 'Documentación: $name'),
                        ),
                      );
                    }).toList(),
                  );
                },
              ),

              const Divider(height: 32),

              const Text('PDF de proceso', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              if (processPdfUrl.isEmpty && status == 'En Proceso' && !isChildOrder)
                ListTile(
                  leading: const Icon(Icons.picture_as_pdf_outlined),
                  title: const Text('Generar PDF Proceso'),
                  onTap: () async {
                    try {
                      final svc = ProductionProcessPdfService();
                      final url = await svc.generateAndUploadProcessPdf(orderRef: orderRef);

                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('PDF de proceso generado.')),
                      );
                      await _openPdf(context, url, 'PDF Proceso OP #$displayOrderNumber');
                    } catch (e) {
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Error generando PDF: $e')),
                      );
                    }
                  },
                )
              else if (processPdfUrl.isNotEmpty)
                ListTile(
                  leading: const Icon(Icons.open_in_new),
                  title: const Text('Ver PDF Proceso'),
                  subtitle: Text(processPdfUrl),
                  onTap: () => _openPdf(context, processPdfUrl, 'PDF Proceso OP #$displayOrderNumber'),
                ),

              const SizedBox(height: 16),

              if (!kIsWeb && Platform.isAndroid)
                FilledButton.icon(
                  icon: const Icon(Icons.print),
                  label: const Text('Imprimir etiqueta térmica'),
                  onPressed: () async {
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
                      await svc.printProductionOrderLabel(orderRef: orderRef, printerMac: mac);

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
                  },
                ),
            ],
          ),
        );
      },
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              '$label:',
              style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.black54),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}