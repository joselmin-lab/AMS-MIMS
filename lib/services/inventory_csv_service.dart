abstract class InventoryCsvService {
  Future<void> exportInventoryCsv();
  Future<InventoryCsvImportResult> importInventoryCsvAsAdjustment({required String note});
}

class InventoryCsvImportResult {
  final int changedCount;
  final List<String> missingSkus;

  InventoryCsvImportResult({
    required this.changedCount,
    required this.missingSkus,
  });
}