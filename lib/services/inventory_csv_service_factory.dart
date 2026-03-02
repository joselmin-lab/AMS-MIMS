import 'inventory_csv_service.dart';
import 'inventory_csv_service_factory_stub.dart'
    if (dart.library.html) 'inventory_csv_service_factory_web.dart'
    if (dart.library.io) 'inventory_csv_service_factory_mobile.dart';

InventoryCsvService createInventoryCsvService() => createInventoryCsvServiceImpl();