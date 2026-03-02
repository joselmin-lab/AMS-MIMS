import 'package:ams_mims/services/inventory_csv_service.dart';

class InventoryCsvServiceMobile implements InventoryCsvService {
  @override
  Future<void> exportInventoryCsv() async {
    throw UnimplementedError('Export CSV solo está habilitado en Web por ahora.');
  }

  @override
  Future<InventoryCsvImportResult> importInventoryCsvAsAdjustment({required String note}) async {
    throw UnimplementedError('Import CSV solo está habilitado en Web por ahora.');
  }
}