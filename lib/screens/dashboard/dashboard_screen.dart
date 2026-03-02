import 'package:ams_mims/screens/admin/thermal_printer_settings_screen.dart';
import 'package:ams_mims/screens/admin/users_admin_screen.dart';
import 'package:ams_mims/screens/customers/customer_list_screen.dart';
import 'package:ams_mims/screens/inventory/inventory_list_screen.dart';
import 'package:ams_mims/screens/inventory/add_inventory_item_screen.dart';
import 'package:ams_mims/screens/notifications/notifications_screen.dart';
import 'package:ams_mims/screens/production/production_dashboard_screen.dart';
import 'package:ams_mims/screens/production/qr_scanner_screen.dart';
import 'package:ams_mims/services/app_current_user_service.dart';
import 'package:ams_mims/widgets/order_row_tile.dart';
import 'package:ams_mims/widgets/operator_assignments_list.dart';
import 'package:ams_mims/widgets/orders_by_date_list.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  static const List<String> stageOrder = [
    'Mecanizado',
    'Soldadura',
    'Pintura',
    'Ensamblaje',
    'Control de Calidad',
  ];

  @override
  Widget build(BuildContext context) {
      final u = FirebaseAuth.instance.currentUser;
debugPrint('AUTH uid=${u?.uid} email=${u?.email}');
   
    final inventoryStream = FirebaseFirestore.instance.collection('inventory').snapshots();
    final productionStream = FirebaseFirestore.instance.collection('production_orders').snapshots();



    // Stream para las secciones nuevas: agrupación por fecha (limit inicial 50)
    final productionByDateStream = FirebaseFirestore.instance
        .collection('production_orders')
        .orderBy('deliveryDate', descending: false)
        .limit(50)
        .snapshots();

    final notificationsStream = FirebaseFirestore.instance
        .collection('notifications')
        .orderBy('createdAt', descending: true)
        .limit(20)
        .snapshots();

    return FutureBuilder<bool>(
      future: AppCurrentUserService().isAdmin(),
      builder: (context, adminSnap) {
        final isAdmin = adminSnap.data == true;

        return Scaffold(
          drawer: Drawer(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                DrawerHeader(
                  decoration: const BoxDecoration(color: Color.fromARGB(255, 190, 134, 11)),
                  child: const Image(image: AssetImage('assets/logo.png'), fit: BoxFit.contain),
                ),
                ListTile(
                  leading: const Icon(Icons.dashboard),
                  title: const Text('Dashboard'),
                  onTap: () => Navigator.pop(context),
                ),
                ListTile(
                  leading: const Icon(Icons.inventory),
                  title: const Text('Inventario'),
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const InventoryListScreen()),
                    );
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.people),
                  title: const Text('Clientes'),
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const CustomerListScreen()),
                    );
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.precision_manufacturing),
                  title: const Text('Producción'),
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const ProductionDashboardScreen()),
                    );
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.qr_code_scanner),
                  title: const Text('Escanear QR'),
                  subtitle: const Text('OP / Inventario'),
                  onTap: () async {
                    Navigator.pop(context);
                    await Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const QrScannerScreen()),
                    );
                  },
                ),
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.notifications),
                  title: const Text('Notificaciones'),
                  subtitle: const Text('Ver todas'),
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const NotificationsScreen()),
                    );
                  },
                ),
                const Divider(),

                // ✅ Administración solo admin
                if (isAdmin) ...[
                  ListTile(
                    leading: const Icon(Icons.settings_bluetooth),
                    title: const Text('Configurar impresora térmica'),
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => const ThermalPrinterSettingsScreen()),
                      );
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.admin_panel_settings),
                    title: const Text('Administración'),
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => const UsersAdminScreen()),
                      );
                    },
                  ),
                  const Divider(),
                ],

                ListTile(
                  leading: const Icon(Icons.logout),
                  title: const Text('Salir'),
                  onTap: () async {
                    Navigator.pop(context);
                    await FirebaseAuth.instance.signOut();
                  },
                ),
              ],
            ),
          ),
         appBar: AppBar(
            title: Image.asset('assets/logo.png', height: 40),
            centerTitle: true, // Opcional: para que quede centrado
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Bienvenido',
                  style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 20),

                // ===== Notificaciones =====
                StreamBuilder<QuerySnapshot>(
                  stream: notificationsStream,
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return Card(
                        elevation: 4.0,
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Text('Error cargando notificaciones: ${snapshot.error}'),
                        ),
                      );
                    }
                    if (!snapshot.hasData) return const CircularProgressIndicator();

                    final docs = snapshot.data!.docs;

                    return Card(
                      elevation: 4.0,
                      child: ExpansionTile(
                        leading: const Icon(Icons.notifications),
                        title: Text(
                          'Notificaciones (${docs.length})',
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        subtitle: const Text('Cambios de etapa / eventos recientes'),
                        children: [
                          if (docs.isEmpty)
                            const ListTile(title: Text('No hay notificaciones aún.'))
                          else
                            ...docs.map((n) {
                              final d = n.data() as Map<String, dynamic>;
                              final type = (d['type'] ?? '').toString();
                              final displayOrderNumber = (d['displayOrderNumber'] ?? '').toString();
                              final stageName = (d['stageName'] ?? '').toString();

                              String title;
                              if (type == 'stage_changed') {
                                title = 'OP #$displayOrderNumber → $stageName';
                              } else if (type == 'order_finished') {
                                title = 'OP #$displayOrderNumber finalizada';
                              } else {
                                title = 'OP #$displayOrderNumber';
                              }

                              return ListTile(
                                dense: true,
                                leading: Icon(type == 'order_finished'
                                    ? Icons.check_circle
                                    : Icons.notifications_active),
                                title: Text(title),
                              );
                            }),
                          const Divider(),
                          ListTile(
                            title: const Text('Ver todas'),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(builder: (_) => const NotificationsScreen()),
                              );
                            },
                          ),
                        ],
                      ),
                    );
                  },
                ),

                const SizedBox(height: 16),

                // ===== Alertas inventario =====
                StreamBuilder<QuerySnapshot>(
                  stream: inventoryStream,
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) return const CircularProgressIndicator();

                    final lowStockItems = snapshot.data!.docs.where((doc) {
                      final data = doc.data() as Map<String, dynamic>;
                      return (data['minStock'] as int? ?? 0) > 0 &&
                          (data['stock'] as num? ?? 0) <= (data['minStock'] as int? ?? 0);
                    }).toList();

                    final lowStockCount = lowStockItems.length;

                    return Card(
                      elevation: 4.0,
                      color: lowStockCount > 0 ? Colors.red.shade50 : null,
                      child: ExpansionTile(
                        leading: Icon(
                          Icons.warning,
                          color: lowStockCount > 0 ? Colors.red.shade700 : Colors.green,
                        ),
                        title: Text(
                          'Alertas Críticas ($lowStockCount)',
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        subtitle: const Text('Toca para ver o editar'),
                        children: [
                          if (lowStockCount == 0) const ListTile(title: Text('No hay alertas de stock bajo.')),
                          ...lowStockItems.map((item) {
                            final itemData = item.data() as Map<String, dynamic>;
                            return ListTile(
                              title: Text(
                                itemData['name'] ?? 'Sin Nombre',
                                style: const TextStyle(fontWeight: FontWeight.w600),
                              ),
                              subtitle: Text(itemData['sku'] ?? 'Sin SKU'),
                              trailing: Text(
                                'Stock: ${itemData['stock']}',
                                style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
                              ),
                              dense: true,
                              onTap: isAdmin
                                  ? () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (context) => AddInventoryItemScreen(itemToEdit: item),
                                        ),
                                      );
                                    }
                                  : null,
                            );
                          }),
                        ],
                      ),
                    );
                  },
                ),

                const SizedBox(height: 16),

                // ===== Producción resumen =====
                StreamBuilder<QuerySnapshot>(
                  stream: productionStream,
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) return const CircularProgressIndicator();

                    final docs = snapshot.data!.docs;

                    final inQueue = docs.where((d) => ((d.data() as Map<String, dynamic>)['status'] ?? '') == 'En Cola').length;
                    final inProcessDocs = docs.where((d) => ((d.data() as Map<String, dynamic>)['status'] ?? '') == 'En Proceso').toList();
                    final inProcess = inProcessDocs.length;

                    final byStage = <String, int>{for (final s in stageOrder) s: 0};
                    for (final d in inProcessDocs) {
                      final data = d.data() as Map<String, dynamic>;
                      final stage = (data['processStage'] ?? '').toString();
                      if (byStage.containsKey(stage)) {
                        byStage[stage] = (byStage[stage] ?? 0) + 1;
                      }
                    }

                    return Card(
                      elevation: 4.0,
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.precision_manufacturing, color: Colors.blue.shade700),
                                const SizedBox(width: 8),
                                const Text(
                                  'Producción',
                                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                            const Divider(),
                            Text('En Cola: $inQueue', style: const TextStyle(fontSize: 16)),
                            Text('En Proceso: $inProcess', style: const TextStyle(fontSize: 16)),
                            const SizedBox(height: 12),
                            const Text('En proceso por etapa:', style: TextStyle(fontWeight: FontWeight.bold)),
                            const SizedBox(height: 6),
                            ...stageOrder.map((s) => Padding(
                                  padding: const EdgeInsets.only(bottom: 4),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(s),
                                      Text('${byStage[s] ?? 0}', style: const TextStyle(fontWeight: FontWeight.bold)),
                                    ],
                                  ),
                                )),
                          ],
                        ),
                      ),
                    );
                  },
                ),

                const SizedBox(height: 16),

                // ===== Sección nueva movida abajo =====
                // Agrupaciones y listas de órdenes por fecha se muestran aquí, después del resumen de producción.
                StreamBuilder<QuerySnapshot>(
                  stream: productionByDateStream,
                  builder: (context, snap) {
                    if (snap.hasError) {
                      return Card(
                        elevation: 4.0,
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Text('Error cargando órdenes: ${snap.error}'),
                        ),
                      );
                    }
                    if (!snap.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    final docs = snap.data!.docs;

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Operarios agrupados
                        OperatorAssignmentsList(orderDocs: docs),
                        const SizedBox(height: 12),

                        // Órdenes sin asignar (si las hay)
                        Builder(builder: (ctx) {
                          final unassigned = docs.where((doc) {
                            final data = doc.data() as Map<String, dynamic>;
                            final processStages = (data['processStages'] as List<dynamic>? ?? []);
                            bool hasAssigned = false;
                            for (final st in processStages) {
                              try {
                                final m = Map<String, dynamic>.from(st as Map);
                                final assigned = (m['assignedUsers'] as List<dynamic>? ?? []);
                                if (assigned.isNotEmpty) {
                                  // if any assigned user has a non-empty id/name we consider it assigned
                                  for (final au in assigned) {
                                    try {
                                      final auMap = Map<String, dynamic>.from(au as Map);
                                      final id = (auMap['id'] ?? '').toString();
                                      final name = (auMap['name'] ?? '').toString();
                                      if (id.isNotEmpty || name.isNotEmpty) {
                                        hasAssigned = true;
                                        break;
                                      }
                                    } catch (_) {}
                                  }
                                }
                              } catch (_) {}
                              if (hasAssigned) break;
                            }
                            return !hasAssigned;
                          }).toList();

                          if (unassigned.isEmpty) return const SizedBox.shrink();

                          return Card(
                            elevation: 2,
                            child: ExpansionTile(
                              leading: const Icon(Icons.person_off),
                              title: Text('Sin asignar (${unassigned.length})', style: const TextStyle(fontWeight: FontWeight.bold)),
                              children: unassigned.map((doc) {
                                final data = doc.data() as Map<String, dynamic>;
                                final id = doc.id;
                                final displayOrderNumber = (data['displayOrderNumber']?.toString().isNotEmpty ?? false)
                                    ? data['displayOrderNumber'].toString()
                                    : (data['orderNumber']?.toString() ?? id);
                                final deliveryTs = data['deliveryDate'] as Timestamp?;
                                final status = (data['status'] ?? '').toString();
                                final processStage = (data['processStage'] ?? '').toString();
                                final customerName = (data['customerName'] ?? '').toString();

                                return OrderRowTile(
                                  orderRef: doc.reference,
                                  displayOrderNumber: displayOrderNumber,
                                  deliveryDate: deliveryTs,
                                  status: status,
                                  processStage: processStage,
                                  assignedNames: const [],
                                  customerName: customerName,
                                );
                              }).toList(),
                            ),
                          );
                        }),

                        const SizedBox(height: 16),

                        // Sección: Órdenes por fecha (paginada / reutilizable)
                        OrdersByDateList(initialLimit: 50),
                        const SizedBox(height: 16),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}