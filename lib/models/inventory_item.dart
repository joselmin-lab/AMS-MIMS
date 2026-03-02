// lib/models/inventory_item.dart

class InventoryItem {
  final String id;
  final String name;
  final String sku;
  final int stock;
  final String origin;
  final String category;
  final String photoUrl;
  final String documentUrl;
 
  
  // --- CAMPOS AÑADIDOS ---
  final String location;      // Ubicación (ej: Estante A-3)
  final String supplier;      // Proveedor (ej: ACME Corp)
  final String unit;          // Unidad (ej: pz, kg, m)
  final int minStock;       // Stock Mínimo para alertas

  InventoryItem({
    required this.id,
    required this.name,
    required this.sku,
    required this.stock,
    required this.origin,
    required this.category,
    this.photoUrl = '',
    this.documentUrl = '',
    // --- INICIALIZADORES AÑADIDOS ---
    this.location = '',
    this.supplier = '',
    this.unit = 'pz', // Asignamos 'pz' (pieza) como valor por defecto
    this.minStock = 0,
  });

  factory InventoryItem.fromFirestore(Map<String, dynamic> data, String documentId) {
    return InventoryItem(
      id: documentId,
      name: data['name'] ?? 'Sin Nombre',
      sku: data['sku'] ?? 'Sin SKU',
      stock: data['stock'] ?? 0,
      origin: data['origin'] ?? 'buy',
      category: data['category'] ?? 'part', // Asignamos 'part' por defecto si no existe
      photoUrl: data['photoUrl'] ?? '',
      documentUrl: data['documentUrl'] ?? '',
      // --- LECTURA DESDE FIRESTORE AÑADIDA ---
      location: data['location'] ?? '',
      supplier: data['supplier'] ?? '',
      unit: data['unit'] ?? 'pz',
      minStock: data['minStock'] ?? 0,
    );
  }
}
