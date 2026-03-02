// lib/screens/production/production_dashboard_screen.dart

import 'package:flutter/material.dart';
import 'package:ams_mims/screens/production/create_production_order_screen.dart';
import 'package:ams_mims/screens/production/order_list_widget.dart'; // <-- Importación del nuevo widget

class ProductionDashboardScreen extends StatefulWidget {
  const ProductionDashboardScreen({super.key});

  @override
  State<ProductionDashboardScreen> createState() =>
      _ProductionDashboardScreenState();
}

class _ProductionDashboardScreenState extends State<ProductionDashboardScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Organización de la Producción'),
        backgroundColor: Colors.purple,
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'EN COLA', icon: Icon(Icons.list_alt)),
            Tab(text: 'EN PROCESO', icon: Icon(Icons.sync)),
            Tab(text: 'FINALIZADAS', icon: Icon(Icons.check_circle_outline)),
          ],
        ),
      ),
      // El body ahora usa nuestro nuevo widget reutilizable para cada pestaña
      body: TabBarView(
        controller: _tabController,
        children: const [
          // Cada pestaña es una instancia de OrderListWidget,
          // pasándole el estado que debe filtrar y mostrar.
          OrderListWidget(status: 'En Cola'),
          OrderListWidget(status: 'En Proceso'),
          OrderListWidget(status: 'Finalizadas'),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
                builder: (context) => const CreateProductionOrderScreen()),
          );
        },
        backgroundColor: Colors.purple,
        child: const Icon(Icons.add),
      ),
    );
  }
}
