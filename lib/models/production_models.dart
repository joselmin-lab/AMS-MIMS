// lib/models/production_models.dart

class ProductionLineItem {
  final String productId;
  final String productName;
  final String productSku;
  double quantity;

  ProductionLineItem({
    required this.productId,
    required this.productName,
    required this.productSku,
    this.quantity = 1.0,
  });
}

class BomComponent {
  final String productId;
  final String productName;
  final String productSku;
  double quantity; // cantidad necesaria para hacer 1 unidad del padre

  BomComponent({
    required this.productId,
    required this.productName,
    required this.productSku,
    this.quantity = 1.0,
  });
}