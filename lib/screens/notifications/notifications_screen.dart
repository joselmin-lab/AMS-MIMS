import 'package:ams_mims/screens/production/production_order_detail_screen.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final stream = FirebaseFirestore.instance
        .collection('notifications')
        .orderBy('createdAt', descending: true)
        .limit(200)
        .snapshots();

    return Scaffold(
      appBar: AppBar(title: const Text('Notificaciones')),
      body: StreamBuilder<QuerySnapshot>(
        stream: stream,
        builder: (context, snap) {
          if (snap.hasError) return Center(child: Text('Error: ${snap.error}'));
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());

          final docs = snap.data!.docs;
          if (docs.isEmpty) return const Center(child: Text('No hay notificaciones aún.'));

          return ListView.separated(
            itemCount: docs.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final d = docs[i].data() as Map<String, dynamic>;
              final type = (d['type'] ?? '').toString();
              final orderId = (d['orderId'] ?? '').toString();
              final displayOrderNumber = (d['displayOrderNumber'] ?? '').toString();
              final stageName = (d['stageName'] ?? '').toString();

              final createdAt = (d['createdAt'] as Timestamp?)?.toDate();
              final ts = createdAt == null ? '' : DateFormat('dd/MM HH:mm').format(createdAt);

              final assignedUsers = (d['assignedUsers'] as List<dynamic>? ?? const [])
                  .whereType<Map>()
                  .map((m) => Map<String, dynamic>.from(m))
                  .toList();
              final assignedNames = assignedUsers
                  .map((u) => (u['name'] ?? u['id'] ?? '').toString())
                  .where((s) => s.trim().isNotEmpty)
                  .toList();

              String title;
              if (type == 'stage_changed') {
                title = 'OP #$displayOrderNumber → $stageName';
              } else if (type == 'order_finished') {
                title = 'OP #$displayOrderNumber finalizada';
              } else {
                title = 'OP #$displayOrderNumber';
              }

              final subtitleParts = <String>[];
              if (assignedNames.isNotEmpty) subtitleParts.add('Asignado: ${assignedNames.join(', ')}');
              if (ts.isNotEmpty) subtitleParts.add(ts);

              return ListTile(
                leading: Icon(type == 'order_finished' ? Icons.check_circle : Icons.notifications),
                title: Text(title),
                subtitle: subtitleParts.isEmpty ? null : Text(subtitleParts.join(' · ')),
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
    );
  }
}