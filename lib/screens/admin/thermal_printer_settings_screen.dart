import 'package:ams_mims/services/thermal_printer_service.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';

class ThermalPrinterSettingsScreen extends StatefulWidget {
  const ThermalPrinterSettingsScreen({super.key});

  @override
  State<ThermalPrinterSettingsScreen> createState() => _ThermalPrinterSettingsScreenState();
}

class _ThermalPrinterSettingsScreenState extends State<ThermalPrinterSettingsScreen> {
  bool _loading = false;
  String _currentMac = '';
  List<BluetoothInfo> _paired = const [];

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _ensurePermissions() async {
    // En Android 12+ lo importante es CONNECT (y SCAN si vas a escanear).
    // Para listar emparejados, CONNECT suele ser suficiente.
    final connect = await Permission.bluetoothConnect.request();
    if (!connect.isGranted) {
      // Si está permanentemente denegado, hay que ir a Settings
      if (connect.isPermanentlyDenied) {
        await openAppSettings();
      }
      throw Exception('Permiso BLUETOOTH_CONNECT no otorgado.');
    }

    // SCAN: algunas libs lo requieren igual.
    final scan = await Permission.bluetoothScan.request();
    if (!scan.isGranted) {
      // No siempre es fatal para "paired", pero mejor avisar.
      // Intentamos continuar si CONNECT está granted.
      // Si quieres hacerlo estricto, cambia a throw.
    }

    // Location: NO lo exigimos para Android 12+ (solo para <12).
    // Igual si tu Android es viejo, podrías pedirlo opcionalmente:
    // final loc = await Permission.locationWhenInUse.request();
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    try {
      await _ensurePermissions();
      final svc = ThermalPrinterService();
      final mac = await svc.getDefaultPrinterMac();
      final paired = await svc.getPairedDevices();

      if (!mounted) return;
      setState(() {
        _currentMac = mac;
        _paired = paired;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error cargando impresoras: $e')),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _setDefault(BluetoothInfo info) async {
    setState(() => _loading = true);
    try {
      final svc = ThermalPrinterService();
      await svc.setDefaultPrinterMac(info.macAdress);

      if (!mounted) return;
      setState(() => _currentMac = info.macAdress);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Impresora configurada: ${info.name} (${info.macAdress})')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error guardando impresora: $e')),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Impresora térmica (Android)'),
        actions: [
          IconButton(
            onPressed: _loading ? null : _refresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(12),
              children: [
                Card(
                  child: ListTile(
                    title: const Text('Impresora por defecto (MAC)'),
                    subtitle: Text(_currentMac.isEmpty ? '(No configurada)' : _currentMac),
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Dispositivos emparejados',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                if (_paired.isEmpty)
                  const Card(
                    child: ListTile(
                      title: Text('No hay dispositivos emparejados.'),
                      subtitle: Text('Empareja la impresora en Ajustes Bluetooth del teléfono primero.'),
                    ),
                  ),
                ..._paired.map((p) {
                  final selected = p.macAdress == _currentMac;
                  return Card(
                    child: ListTile(
                      leading: Icon(selected ? Icons.check_circle : Icons.print),
                      title: Text(p.name),
                      subtitle: Text(p.macAdress),
                      trailing: FilledButton.tonal(
                        onPressed: () => _setDefault(p),
                        child: Text(selected ? 'Seleccionada' : 'Usar'),
                      ),
                    ),
                  );
                }),
              ],
            ),
    );
  }
}