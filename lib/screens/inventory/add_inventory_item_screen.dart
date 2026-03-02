// lib/screens/inventory/add_inventory_item_screen.dart

import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:ams_mims/models/production_models.dart';
import 'package:ams_mims/services/cloudinary_service.dart';
import 'package:ams_mims/widgets/search_selection_screen.dart';

class AddInventoryItemScreen extends StatefulWidget {
  final DocumentSnapshot? itemToEdit;
  final DocumentSnapshot? itemToClone; // Nuevo parámetro para clonar

  const AddInventoryItemScreen({super.key, this.itemToEdit, this.itemToClone});

  @override
  State<AddInventoryItemScreen> createState() => _AddInventoryItemScreenState();
}

class _AddInventoryItemScreenState extends State<AddInventoryItemScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _skuController = TextEditingController();
  final _stockController = TextEditingController();
  final _locationController = TextEditingController();
  final _supplierController = TextEditingController();
  final _unitController = TextEditingController();
  final _minStockController = TextEditingController();
  bool _isLoading = false;
  String _origin = 'buy';
  String _category = 'part';
  File? _selectedImage;
  String? _existingImageUrl;
  File? _selectedDocument;
  String? _existingDocumentUrl;
  final _cloudinaryService = CloudinaryService();
  final List<BomComponent> _bomComponents = [];

  @override
  void initState() {
    super.initState();
    _unitController.text = 'pz';

    // Prioriza el item a clonar sobre el item a editar para rellenar los datos.
    final sourceDocument = widget.itemToClone ?? widget.itemToEdit;

    if (sourceDocument != null) {
      final data = sourceDocument.data() as Map<String, dynamic>;

      // Lógica para rellenar los campos
      if (widget.itemToClone != null) {
        // --- MODO CLONACIÓN ---
        _nameController.text = '${data['name'] ?? ''} (Copia)';
        _skuController.text = '${data['sku'] ?? ''}_copia';
        _stockController.text = '0'; // El clon empieza con stock 0
      } else {
        // --- MODO EDICIÓN ---
        _nameController.text = data['name'] ?? '';
        _skuController.text = data['sku'] ?? '';
        _stockController.text = (data['stock'] ?? 0).toString();
      }
      
      // Rellenar el resto de los campos en ambos modos (edición y clonación)
      _origin = data['origin'] ?? 'buy';
      _category = data['category'] ?? 'part';
      _existingImageUrl = data['photoUrl'];
      _existingDocumentUrl = data['documentUrl'];
      _locationController.text = data['location'] ?? '';
      _supplierController.text = data['supplier'] ?? '';
      _unitController.text = data['unit'] ?? 'pz';
      _minStockController.text = (data['minStock'] ?? 0).toString();

      if (data['bom'] != null) {
        final bomFromDb = data['bom'] as List<dynamic>;
        for (var componentData in bomFromDb) {
          _bomComponents.add(BomComponent(
            productId: componentData['productId'],
            productName: componentData['productName'],
            productSku: componentData['productSku'],
            quantity: (componentData['quantity'] as num).toDouble(),
          ));
        }
      }
    }
  }

  Future<void> _pickImage() async {
    final pickedFile = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (pickedFile != null) setState(() => _selectedImage = File(pickedFile.path));
  }

  Future<void> _pickDocument() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['pdf']);
    if (result != null && result.files.single.path != null) {
      setState(() => _selectedDocument = File(result.files.single.path!));
    }
  }

  Future<void> _addComponent() async {
    final selectedComponent = await Navigator.of(context).push<DocumentSnapshot>(
      MaterialPageRoute(
        builder: (context) => SearchSelectionScreen(
          collection: 'inventory',
          searchField: 'name',
          displayField: 'name',
          screenTitle: 'Seleccionar Componente',
          filters: {'category': ['raw_material', 'part']},
        ),
      ),
    );
    if (selectedComponent != null) {
      final data = selectedComponent.data() as Map<String, dynamic>;
      final isAlreadyInBom = _bomComponents.any((c) => c.productId == selectedComponent.id);
      if (isAlreadyInBom) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Este componente ya está en la receta.')));
        return;
      }
      setState(() {
        _bomComponents.add(BomComponent(
          productId: selectedComponent.id,
          productName: data['name'] ?? '',
          productSku: data['sku'] ?? '',
        ));
      });
    }
  }

  Future<void> _saveItem() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

    String imageUrl = _existingImageUrl ?? '';
    String documentUrl = _existingDocumentUrl ?? '';

    try {
      if (_selectedImage != null) imageUrl = await _cloudinaryService.uploadFile(_selectedImage!, 'inventory_photos');
      if (_selectedDocument != null) documentUrl = await _cloudinaryService.uploadFile(_selectedDocument!, 'inventory_documents');
      
      final bomForDb = _bomComponents.map((c) => {
        'productId': c.productId, 'productName': c.productName,
        'productSku': c.productSku, 'quantity': c.quantity,
      }).toList();
      
      final itemData = {
        'name': _nameController.text,
        'searchKeywords': _nameController.text.toLowerCase().split(' '),
        'sku': _skuController.text, 'location': _locationController.text,
        'stock': int.tryParse(_stockController.text) ?? 0,
        'minStock': int.tryParse(_minStockController.text) ?? 0,
        'supplier': _supplierController.text, 'unit': _unitController.text,
        'origin': _origin, 'category': _category, 'photoUrl': imageUrl,
        'documentUrl': documentUrl, 'bom': bomForDb,
      };

      // Si estamos editando (y no clonando), actualizamos.
      // Si estamos creando o clonando, creamos un nuevo documento.
      if (widget.itemToEdit != null && widget.itemToClone == null) {
        await FirebaseFirestore.instance.collection('inventory').doc(widget.itemToEdit!.id).update(itemData);
      } else {
        await FirebaseFirestore.instance.collection('inventory').add(itemData);
      }

      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      setState(() => _isLoading = false);
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error al guardar: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    bool isFabricable = _category == 'final_product' || _category == 'part';
    
    // Determinar el título de la pantalla
    String screenTitle;
    if (widget.itemToEdit != null) {
      screenTitle = 'Editar Artículo';
    } else if (widget.itemToClone != null) {
      screenTitle = 'Clonar Artículo';
    } else {
      screenTitle = 'Añadir Nuevo Artículo';
    }

    return Scaffold(
      appBar: AppBar(title: Text(screenTitle)),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16.0),
          children: [
            // ... (El resto del `build` no necesita cambios, puedes copiarlo de tu archivo original)
            DropdownButtonFormField<String>(
              value: _category,
              decoration: const InputDecoration(labelText: 'Categoría del Artículo', border: OutlineInputBorder()),
              items: const [
                DropdownMenuItem(value: 'final_product', child: Text('Producto Final')),
                DropdownMenuItem(value: 'part', child: Text('Parte')),
                DropdownMenuItem(value: 'raw_material', child: Text('Materia Prima')),
                DropdownMenuItem(value: 'consumable', child: Text('Insumo')),
              ],
              onChanged: (value) => setState(() => _category = value!),
              validator: (value) => value == null ? 'Selecciona una categoría' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(controller: _nameController, decoration: const InputDecoration(labelText: 'Nombre del Artículo', border: OutlineInputBorder()), validator: (v) => v!.isEmpty ? 'Ingresa un nombre.' : null),
            const SizedBox(height: 16),
            TextFormField(controller: _skuController, decoration: const InputDecoration(labelText: 'SKU', border: OutlineInputBorder()), validator: (v) => v!.isEmpty ? 'Ingresa un SKU.' : null),
            const SizedBox(height: 16),
            TextFormField(controller: _locationController, decoration: const InputDecoration(labelText: 'Ubicación', hintText: 'Ej: Estante B-4', border: OutlineInputBorder())),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(child: TextFormField(controller: _stockController, decoration: const InputDecoration(labelText: 'Stock Actual', border: OutlineInputBorder()), keyboardType: TextInputType.number, validator: (v) { if (v == null || v.isEmpty) return 'Ingresa stock.'; if (int.tryParse(v) == null) return 'Nro. inválido.'; return null; })),
              const SizedBox(width: 8),
              Expanded(child: TextFormField(controller: _minStockController, decoration: const InputDecoration(labelText: 'Stock Mínimo', border: OutlineInputBorder()), keyboardType: TextInputType.number, validator: (v) { if (v == null || v.isEmpty) return 'Ingresa stock mín.'; if (int.tryParse(v) == null) return 'Nro. inválido.'; return null; })),
            ]),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(child: TextFormField(controller: _supplierController, decoration: const InputDecoration(labelText: 'Proveedor', border: OutlineInputBorder()))),
              const SizedBox(width: 8),
              SizedBox(width: 100, child: TextFormField(controller: _unitController, decoration: const InputDecoration(labelText: 'Unidad', border: OutlineInputBorder()))),
            ]),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(value: _origin, decoration: const InputDecoration(labelText: 'Origen del Artículo', border: OutlineInputBorder()), items: const [DropdownMenuItem(value: 'buy', child: Text('Compra Externa')), DropdownMenuItem(value: 'make', child: Text('Fabricación Interna'))], onChanged: (value) => setState(() => _origin = value!)),
            const SizedBox(height: 24),
            Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
              Column(children: [ const Text('Foto del Artículo'), IconButton(icon: Icon(Icons.photo_camera, size: 40, color: Theme.of(context).primaryColor), onPressed: _pickImage), if (_selectedImage != null) Text(_selectedImage!.path.split('/').last, style: const TextStyle(fontSize: 10)) else if (_existingImageUrl != null && _existingImageUrl!.isNotEmpty) const Text('Imagen existente', style: TextStyle(fontSize: 10, color: Colors.grey))]),
              Column(children: [ const Text('Plano / PDF'), IconButton(icon: Icon(Icons.picture_as_pdf, size: 40, color: Colors.red.shade700), onPressed: _pickDocument), if (_selectedDocument != null) Text(_selectedDocument!.path.split('/').last, style: const TextStyle(fontSize: 10)) else if (_existingDocumentUrl != null && _existingDocumentUrl!.isNotEmpty) const Text('PDF existente', style: TextStyle(fontSize: 10, color: Colors.grey))]),
            ]),
            if (isFabricable)
              Padding(
                padding: const EdgeInsets.only(top: 16.0),
                child: Column(
                  children: [
                    const Divider(thickness: 1, height: 32),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Receta (Componentes)', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        FilledButton.tonal(onPressed: _addComponent, child: const Text('Añadir Componente')),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (_bomComponents.isEmpty)
                      const Center(child: Padding(padding: EdgeInsets.all(16.0), child: Text('Este artículo no tiene componentes.', style: TextStyle(color: Colors.grey)))),
                    ..._bomComponents.map((component) {
                      return Card(
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        child: ListTile(
                          title: Text(component.productName),
                          subtitle: Text('SKU: ${component.productSku}'),
                          trailing: SizedBox(
                            width: 150,
                            child: Row(
                              children: [
                                Expanded(
                                  child: TextFormField(
                                    initialValue: component.quantity.toString(),
                                    textAlign: TextAlign.center,
                                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                    decoration: const InputDecoration(labelText: 'Cant.', border: UnderlineInputBorder()),
                                    onChanged: (value) {
                                      component.quantity = double.tryParse(value) ?? 1.0;
                                    },
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                                  onPressed: () => setState(() => _bomComponents.remove(component)),
                                )
                              ],
                            ),
                          ),
                        ),
                      );
                    }),
                  ],
                ),
              ),
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: _isLoading ? null : _saveItem,
              style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
              child: _isLoading ? const CircularProgressIndicator(color: Colors.white) : const Text('Guardar Cambios'),
            ),
          ],
        ),
      ),
    );
  }
}

