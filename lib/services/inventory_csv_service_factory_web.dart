import 'inventory_csv_service.dart';
import 'inventory_csv_service_web.dart';

InventoryCsvService createInventoryCsvServiceImpl() {
  return InventoryCsvServiceWeb();
}