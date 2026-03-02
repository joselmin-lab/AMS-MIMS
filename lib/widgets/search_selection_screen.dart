// lib/widgets/search_selection_screen.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class SearchSelectionScreen extends StatefulWidget {
  final String collection;
  final String searchField;
  final String displayField;
  final String screenTitle;
  final Map<String, dynamic>? filters;

  const SearchSelectionScreen({
    super.key,
    required this.collection,
    required this.searchField,
    required this.displayField,
    required this.screenTitle,
    this.filters,
  });

  @override
  State<SearchSelectionScreen> createState() => _SearchSelectionScreenState();
}

class _SearchSelectionScreenState extends State<SearchSelectionScreen> {
  final _searchController = TextEditingController();
  // No necesitamos una variable de estado para la búsqueda, podemos leerla directamente.

  @override
  void initState() {
    super.initState();
    // El listener solo necesita llamar a setState para reconstruir la UI
    _searchController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // LA FUNCIÓN _buildStream SE ELIMINA, YA NO SE NECESITA.

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.screenTitle)),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(
              controller: _searchController,
              autofocus: true,
              decoration: InputDecoration(
                labelText: 'Buscar...',
                prefixIcon: const Icon(Icons.search),
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () => _searchController.clear(),
                ),
              ),
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              // 1. CONSTRUIMOS LA CONSULTA INICIAL CON LOS FILTROS
              stream: () {
                Query query = FirebaseFirestore.instance.collection(widget.collection);
                if (widget.filters != null) {
                  widget.filters!.forEach((field, value) {
                    if (value is List) {
                      query = query.where(field, whereIn: value);
                    } else {
                      query = query.where(field, isEqualTo: value);
                    }
                  });
                }
                // Ordenamos por el campo principal para tener una lista consistente
                return query.orderBy(widget.searchField).snapshots();
              }(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(child: Text('Error: ${snapshot.error}. ¿Falta un índice en Firestore?'));
                }
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return const Center(child: Text('No hay artículos que coincidan con los filtros iniciales.'));
                }

                // 2. FILTRADO EN EL LADO DEL CLIENTE
                final allDocs = snapshot.data!.docs;
                final searchQuery = _searchController.text.toLowerCase();

                final filteredDocs = allDocs.where((doc) {
                  if (searchQuery.isEmpty) {
                    return true; // Mostrar todo si no hay búsqueda
                  }
                  final data = doc.data() as Map<String, dynamic>;
                  final name = (data['name'] ?? '').toString().toLowerCase();
                  final sku = (data['sku'] ?? '').toString().toLowerCase();
                  
                  // La condición de búsqueda "contiene"
                  return name.contains(searchQuery) || sku.contains(searchQuery);
                }).toList();

                if (filteredDocs.isEmpty) {
                  return const Center(child: Text('No se encontraron resultados para la búsqueda.'));
                }

                // 3. CONSTRUIR LA LISTA CON LOS RESULTADOS FILTRADOS
                return ListView(
                  children: filteredDocs.map((doc) {
                    final data = doc.data() as Map<String, dynamic>;
                    return ListTile(
                      title: Text(data[widget.displayField] ?? 'Sin Nombre'),
                      subtitle: widget.displayField != 'sku' ? Text('SKU: ${data['sku'] ?? 'N/A'}') : null,
                      onTap: () => Navigator.of(context).pop(doc),
                    );
                  }).toList(),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
