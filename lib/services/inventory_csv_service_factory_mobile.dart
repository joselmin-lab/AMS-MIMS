import 'inventory_csv_service.dart';
import 'inventory_csv_service_mobile.dart';

InventoryCsvService createInventoryCsvServiceImpl() {
  return InventoryCsvServiceMobile();
}