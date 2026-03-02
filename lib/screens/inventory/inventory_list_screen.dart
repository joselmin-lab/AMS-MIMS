// lib/screens/inventory/inventory_list_screen.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:ams_mims/screens/inventory/add_inventory_item_screen.dart';
import 'package:ams_mims/screens/inventory/qr_display_screen.dart';
import 'package:ams_mims/screens/inventory/inventory_intake_screen.dart';
import 'package:ams_mims/screens/inventory/inventory_movements_history_screen.dart';
import 'package:ams_mims/services/inventory_csv_service_factory.dart';
import 'package:ams_mims/widgets/search_selection_screen.dart'; // Asegúrate de importar esto

class InventoryListScreen extends StatefulWidget {
  const InventoryListScreen({super.key});

  @override
  InventoryListScreenState createState() => InventoryListScreenState();
}

class InventoryListScreenState extends State<InventoryListScreen> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() {});
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }
  
  String get _searchQuery => _searchController.text;

  String _getCategoryInSpanish(String category) {
    switch (category) {
      case 'final_product': return 'Producto Final';
      case 'part': return 'Parte';
      case 'raw_material': return 'Materia Prima';
      case 'consumable': return 'Insumo';
      default: return 'Desconocido';
    }
  }

  Widget _buildLeadingImageOrIcon(Map<String, dynamic> data) {
    final url = (data['photoUrl'] ?? '').toString().trim();
    if (url.isEmpty) return const Icon(Icons.inventory_2_outlined, color: Colors.indigo);
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.network(
        url, width: 44, height: 44, fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => const Icon(Icons.inventory_2_outlined, color: Colors.indigo),
        loadingBuilder: (context, child, progress) {
          if (progress == null) return child;
          return const SizedBox(width: 44, height: 44, child: Center(child: CircularProgressIndicator(strokeWidth: 2)));
        },
      ),
    );
  }

  void _openFabMenu() {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.swap_vert),
              title: const Text('Movimiento (Ingreso/Salida)'),
              onTap: () async {
                Navigator.of(ctx).pop();
                await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const InventoryMovementScreen(referenceType: 'manual')));
              },
            ),
            ListTile(
              leading: const Icon(Icons.add),
              title: const Text('Crear producto'),
              onTap: () {
                Navigator.of(ctx).pop();
                Navigator.of(context).push(MaterialPageRoute(builder: (context) => const AddInventoryItemScreen()));
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _exportCsv() async {
    try {
      final svc = createInventoryCsvService();
      await svc.exportInventoryCsv();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error al exportar: $e')));
    }
  }

  Future<void> _importCsv() async {
    final noteCtrl = TextEditingController(text: 'Sincronización completa por CSV');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Importar/Sincronizar CSV'),
        content: TextField(controller: noteCtrl, decoration: const InputDecoration(labelText: 'Nota del movimiento', border: OutlineInputBorder())),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Seleccionar CSV')),
        ],
      ),
    );

    if (ok != true || !mounted) return;

    try {
      final svc = createInventoryCsvService();
      final result = await svc.importInventoryCsvAsAdjustment(note: noteCtrl.text);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Sincronización aplicada. Ítems afectados: ${result.changedCount}.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error al importar: $e')));
    }
  }

  // --- NUEVA FUNCIÓN PARA INICIAR EL CLONADO ---
  Future<void> _cloneItem() async {
    final itemToClone = await Navigator.of(context).push<DocumentSnapshot>(
      MaterialPageRoute(
        builder: (context) => SearchSelectionScreen(
          collection: 'inventory',
          searchField: 'name',
          displayField: 'name',
          screenTitle: 'Seleccionar Ítem para Clonar',
        ),
      ),
    );

    if (itemToClone != null && mounted) {
      Navigator.of(context).push(MaterialPageRoute(
        builder: (context) => AddInventoryItemScreen(itemToClone: itemToClone),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Gestión de Inventario'),
        backgroundColor: Colors.indigo,
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) async {
              if (value == 'history') {
                Navigator.of(context).push(MaterialPageRoute(builder: (_) => const InventoryMovementsHistoryScreen()));
              } else if (value == 'clone') {
                await _cloneItem();
              } else if (value == 'export_csv') {
                await _exportCsv();
              } else if (value == 'import_csv') {
                await _importCsv();
              }
            },
            itemBuilder: (ctx) => const [
              PopupMenuItem(value: 'history', child: ListTile(leading: Icon(Icons.history), title: Text('Historial movimientos'))),
              PopupMenuItem(value: 'clone', child: ListTile(leading: Icon(Icons.copy), title: Text('Clonar Ítem...'))),
              PopupMenuDivider(),
              PopupMenuItem(value: 'export_csv', child: ListTile(leading: Icon(Icons.download), title: Text('Exportar inventario CSV (Web)'))),
              PopupMenuItem(value: 'import_csv', child: ListTile(leading: Icon(Icons.upload_file), title: Text('Importar/Sincronizar CSV (Web)'))),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                labelText: 'Buscar por palabra...',
                prefixIcon: const Icon(Icons.search),
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(icon: const Icon(Icons.clear), onPressed: () => _searchController.clear()),
              ),
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance.collection('inventory').orderBy('name').snapshots(),
              builder: (BuildContext context, AsyncSnapshot<QuerySnapshot> snapshot) {
                if (snapshot.hasError) return Center(child: Text('Error: ${snapshot.error}'));
                if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
                
                final allDocs = snapshot.data!.docs;
                final searchQueryLower = _searchQuery.toLowerCase();
                final filteredDocs = allDocs.where((doc) {
                  if (searchQueryLower.isEmpty) return true;
                  final data = doc.data() as Map<String, dynamic>;
                  final name = (data['name'] ?? '').toString().toLowerCase();
                  final sku = (data['sku'] ?? '').toString().toLowerCase();
                  return name.contains(searchQueryLower) || sku.contains(searchQueryLower);
                }).toList();

                if (filteredDocs.isEmpty) return const Center(child: Text('No se encontraron artículos.'));

                return ListView(
                  padding: const EdgeInsets.all(8.0),
                  children: filteredDocs.map((DocumentSnapshot document) {
                    final data = document.data()! as Map<String, dynamic>;
                    return Card(
                      child: ListTile(
                        leading: _buildLeadingImageOrIcon(data),
                        title: Text(data['name'] ?? 'Sin Nombre', style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text('SKU: ${data['sku'] ?? 'N/A'} | Cat: ${_getCategoryInSpanish(data['category'] ?? '')}'),
                        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (context) => AddInventoryItemScreen(itemToEdit: document))),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('Stock: ${data['stock'] ?? 0}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                            IconButton(
                              icon: const Icon(Icons.qr_code_2, color: Colors.black54),
                              onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (context) => QrDisplayScreen(itemDocument: document))),
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _openFabMenu,
        backgroundColor: Colors.indigo,
        child: const Icon(Icons.add),
      ),
    );
  }
}
