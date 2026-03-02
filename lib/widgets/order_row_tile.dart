import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:ams_mims/screens/production/production_order_detail_screen.dart';

class OrderRowTile extends StatelessWidget {
  final DocumentReference orderRef;
  final String displayOrderNumber;
  final Timestamp? deliveryDate;
  final String status;
  final String processStage;
  final List<String> assignedNames;
  final String? customerName;

  const OrderRowTile({
    super.key,
    required this.orderRef,
    required this.displayOrderNumber,
    this.deliveryDate,
    this.status = '',
    this.processStage = '',
    this.assignedNames = const [],
    this.customerName,
  });

  bool get _isUrgent {
    if (deliveryDate == null) return false;
    final now = DateTime.now();
    final diff = deliveryDate!.toDate().difference(now);
    return diff.inHours >= 0 && diff.inHours <= 24;
  }

  bool get _isOverdue {
    if (deliveryDate == null) return false;
    final todayStart = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
    return deliveryDate!.toDate().isBefore(todayStart);
  }

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('dd/MM/yyyy');
    final dateText = deliveryDate == null ? '—' : df.format(deliveryDate!.toDate());
    final assignedPreview = assignedNames.isEmpty ? 'Sin asignar' : assignedNames.take(3).join(', ') + (assignedNames.length > 3 ? ' · +${assignedNames.length - 3}' : '');

    return InkWell(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => ProductionOrderDetailScreen(orderRef: orderRef)),
        );
      },
      child: Card(
        margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
          child: Row(
            children: [
              // Date / badge
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(dateText, style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  if (_isOverdue)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(color: Colors.red.shade100, borderRadius: BorderRadius.circular(12)),
                      child: const Text('Vencida', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 12)),
                    )
                  else if (_isUrgent)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(color: Colors.orange.shade100, borderRadius: BorderRadius.circular(12)),
                      child: const Text('Próxima', style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold, fontSize: 12)),
                    ),
                ],
              ),
              const SizedBox(width: 12),
              // Main info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text('OP #$displayOrderNumber', style: const TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(width: 8),
                        Chip(
                          label: Text(status, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
                          backgroundColor: _statusColor(status),
                          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          visualDensity: VisualDensity.compact,
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(processStage.isEmpty ? 'Etapa: —' : 'Etapa: $processStage', style: const TextStyle(color: Colors.black54)),
                    const SizedBox(height: 6),
                    Text('Operarios: $assignedPreview', style: const TextStyle(color: Colors.black54, fontSize: 13)),
                    if (customerName != null && customerName!.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text('Cliente: $customerName', style: const TextStyle(color: Colors.black54, fontSize: 12)),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }

  Color _statusColor(String? status) {
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
        return Colors.black54;
    }
  }
}