import 'package:ams_mims/screens/production/production_order_detail_screen.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class DashboardNotificationsCard extends StatelessWidget {
  const DashboardNotificationsCard({super.key});

  @override
  Widget build(BuildContext context) {
    final stream = FirebaseFirestore.instance
        .collection('notifications')
        .orderBy('createdAt', descending: true)
        .limit(20)
        .snapshots();

    return Card(
      elevation: 4,
      child: ExpansionTile(
        initiallyExpanded: true,
        title: const Text(
          'Notificaciones',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: const Text('Últimos eventos de producción'),
        children: [
          StreamBuilder<QuerySnapshot>(
            stream: stream,
            builder: (context, snap) {
              if (snap.hasError) {
                return const Padding(
                  padding: EdgeInsets.all(12),
                  child: Text('Error cargando notificaciones.'),
                );
              }
              if (!snap.hasData) {
                return const Padding(
                  padding: EdgeInsets.all(12),
                  child: LinearProgressIndicator(),
                );
              }

              final docs = snap.data!.docs;
              if (docs.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.all(12),
                  child: Text('No hay notificaciones aún.'),
                );
              }

              return ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: docs.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, i) {
                  final d = docs[i];
                  final data = d.data() as Map<String, dynamic>;

                  final displayOrderNumber = (data['displayOrderNumber'] ?? '').toString();
                  final stageName = (data['stageName'] ?? '').toString();
                  final type = (data['type'] ?? '').toString();

                  final createdAt = (data['createdAt'] as Timestamp?)?.toDate();
                  final ts = createdAt == null ? '' : DateFormat('dd/MM HH:mm').format(createdAt);

                  final assignedUsers = (data['assignedUsers'] as List<dynamic>? ?? const [])
                      .map((u) => Map<String, dynamic>.from(u as Map))
                      .toList();
                  final assignedNames = assignedUsers
                      .map((u) => (u['name'] ?? u['id'] ?? '').toString())
                      .where((s) => s.isNotEmpty)
                      .toList();

                  String title;
                  if (type == 'stage_changed') {
                    title = 'OP #$displayOrderNumber → $stageName';
                  } else if (type == 'order_finished') {
                    title = 'OP #$displayOrderNumber finalizada';
                  } else {
                    title = 'OP #$displayOrderNumber';
                  }

                  final subtitle = [
                    if (assignedNames.isNotEmpty) 'Asignado: ${assignedNames.join(', ')}',
                    if (ts.isNotEmpty) ts,
                  ].join(' · ');

                  final orderId = (data['orderId'] ?? '').toString();

                  return ListTile(
                    dense: true,
                    leading: Icon(type == 'order_finished' ? Icons.check_circle : Icons.notifications),
                    title: Text(title),
                    subtitle: subtitle.isEmpty ? null : Text(subtitle),
                    onTap: orderId.isEmpty
                        ? null
                        : () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => ProductionOrderDetailScreen(
                                  orderRef: FirebaseFirestore.instance.collection('production_orders').doc(orderId),
                                ),
                              ),
                            );
                          },
                  );
                },
              );
            },
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}