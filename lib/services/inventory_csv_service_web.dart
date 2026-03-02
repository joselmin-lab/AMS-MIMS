// Web implementation
// ignore_for_file: avoid_web_libraries_in_flutter

import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;

import 'package:ams_mims/services/inventory_csv_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class InventoryCsvServiceWeb implements InventoryCsvService {
  final FirebaseFirestore db;

  InventoryCsvServiceWeb({FirebaseFirestore? firestore})
      : db = firestore ?? FirebaseFirestore.instance;

  String _escape(String s) {
    final needsQuotes =
        s.contains(',') || s.contains('"') || s.contains('\n') || s.contains('\r');
    if (!needsQuotes) return s;
    return '"${s.replaceAll('"', '""')}"';
  }
Future<int> deleteAllInventoryItems() async {
  final allDocsSnap = await db.collection('inventory').get();
  if (allDocsSnap.docs.isEmpty) {
    return 0; // No hay nada que borrar
  }

  var batch = db.batch();
  int deleteCount = 0;
  int operationCount = 0;

  for (final doc in allDocsSnap.docs) {
    batch.delete(doc.reference);
    operationCount++;
    deleteCount++;

    // Ejecutar el batch si nos acercamos al límite de 500 operaciones
    if (operationCount >= 498) {
      await batch.commit();
      batch = db.batch();
      operationCount = 0;
    }
  }

  // Ejecutar el último batch si queda alguna operación pendiente
  if (operationCount > 0) {
    await batch.commit();
  }

  return deleteCount;
}
  // --- FUNCIÓN DE EXPORTACIÓN (CON 'unit') ---
  @override
  Future<void> exportInventoryCsv() async {
    final snap = await db.collection('inventory').orderBy('sku').get();

    final headers = [
      'sku', 'name', 'category', 'stock', 'minStock', 'location', 
      'supplier', 'unit', 'origin', 'description', 'photoUrl', 'documentUrl'
    ];
    final lines = <String>[headers.join(',')];

    for (final doc in snap.docs) {
      final d = doc.data();
      final line = [
        _escape((d['sku'] ?? '').toString()),
        _escape((d['name'] ?? '').toString()),
        _escape((d['category'] ?? '').toString()),
        (d['stock'] as num? ?? 0).toString(),
        (d['minStock'] as num? ?? 0).toString(),
        _escape((d['location'] ?? '').toString()),
        _escape((d['supplier'] ?? '').toString()),
        _escape((d['unit'] ?? '').toString()), // <-- AÑADIDO AQUÍ
        _escape((d['origin'] ?? '').toString()),
        _escape((d['description'] ?? '').toString()),
        _escape((d['photoUrl'] ?? '').toString()),
        _escape((d['documentUrl'] ?? '').toString()),
      ].join(',');
      lines.add(line);
    }

    final csv = lines.join('\n');
    final bytes = utf8.encode(csv);
    final blob = html.Blob([bytes], 'text/csv;charset=utf-8;');
    final url = html.Url.createObjectUrlFromBlob(blob);
    final now = DateTime.now();
    final filename =
        'inventario_completo_${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}.csv';
    final anchor = html.AnchorElement(href: url)
      ..download = filename
      ..style.display = 'none';
    html.document.body!.children.add(anchor);
    anchor.click();
    anchor.remove();
    html.Url.revokeObjectUrl(url);
  }

  // --- FUNCIÓN DE IMPORTACIÓN (CON 'unit') ---
  @override
 // Reemplaza la función de importación con esta versión corregida
@override
Future<InventoryCsvImportResult> importInventoryCsvAsAdjustment(
    {required String note}) async {
  // ... (todo el código de lectura del CSV se mantiene igual hasta el final del primer for) ...

  final file = await _pickCsvFile();
  if (file == null) return InventoryCsvImportResult(changedCount: 0, missingSkus: const []);

  final text = await _readFileAsText(file);
  final rows = _parseCsv(text);
  if (rows.isEmpty) throw Exception('CSV vacío.');

  var firstCell = rows.first.first;
  if (firstCell.startsWith('\uFEFF')) firstCell = firstCell.substring(1);
  rows.first[0] = firstCell;
  
  final header = rows.first.map((c) => c.trim().toLowerCase()).toList();
  final skuIdx = header.indexOf('sku');
  final nameIdx = header.indexOf('name');
  final categoryIdx = header.indexOf('category');
  final stockIdx = header.indexOf('stock');
  final minStockIdx = header.indexOf('minstock');
  final locationIdx = header.indexOf('location');
  final supplierIdx = header.indexOf('supplier');
  final unitIdx = header.indexOf('unit');
  final originIdx = header.indexOf('origin');
  final descriptionIdx = header.indexOf('description');
  final photoUrlIdx = header.indexOf('photourl');
  final documentUrlIdx = header.indexOf('documenturl');

  if (skuIdx < 0 || nameIdx < 0 || categoryIdx < 0 || stockIdx < 0) {
    throw Exception('CSV inválido. Columnas obligatorias: sku, name, category, stock');
  }

  final itemsFromCsv = <String, Map<String, dynamic>>{};
  for (int i = 1; i < rows.length; i++) {
    final row = rows[i];
    if (row.every((cell) => cell.trim().isEmpty)) continue;
    final sku = row.length > skuIdx ? row[skuIdx].trim() : '';
    if (sku.isEmpty) continue;

    final name = row.length > nameIdx ? row[nameIdx].trim() : '';
    final category = row.length > categoryIdx ? row[categoryIdx].trim() : '';
    if (name.isEmpty || category.isEmpty) continue;

    itemsFromCsv[sku] = {
      // ¡¡CORRECCIÓN!! Añadimos el SKU aquí también
      'sku': sku,
      'name': name,
      'category': category,
      'stock': int.tryParse(row.length > stockIdx ? row[stockIdx].trim() : '0') ?? 0,
      'minStock': int.tryParse(minStockIdx >= 0 && row.length > minStockIdx ? row[minStockIdx].trim() : '0') ?? 0,
      'location': locationIdx >= 0 && row.length > locationIdx ? row[locationIdx].trim() : null,
      'supplier': supplierIdx >= 0 && row.length > supplierIdx ? row[supplierIdx].trim() : null,
      'unit': unitIdx >= 0 && row.length > unitIdx ? row[unitIdx].trim() : null,
      'origin': originIdx >= 0 && row.length > originIdx ? row[originIdx].trim() : null,
      'description': descriptionIdx >= 0 && row.length > descriptionIdx ? row[descriptionIdx].trim() : null,
      'photoUrl': photoUrlIdx >= 0 && row.length > photoUrlIdx ? row[photoUrlIdx].trim() : null,
      'documentUrl': documentUrlIdx >= 0 && row.length > documentUrlIdx ? row[documentUrlIdx].trim() : null,
    };
  }

  if (itemsFromCsv.isEmpty) throw Exception('No se encontraron filas válidas.');

  final allSkus = itemsFromCsv.keys.toList();
  final docBySku = <String, QueryDocumentSnapshot<Map<String, dynamic>>>{};
  
  for (var i = 0; i < allSkus.length; i += 30) {
    final chunk = allSkus.sublist(i, i + 30 > allSkus.length ? allSkus.length : i + 30);
    final invSnap = await db.collection('inventory').where('sku', whereIn: chunk).get();
    for (final doc in invSnap.docs) {
      docBySku[(doc.data()['sku'] ?? '').toString().trim()] = doc;
    }
  }

  var batch = db.batch();
  final movementLines = <Map<String, dynamic>>[];
  int changedCount = 0;
  int operationCount = 0;

  for (final entry in itemsFromCsv.entries) {
    if (operationCount >= 498) {
      await batch.commit();
      batch = db.batch();
      operationCount = 0;
    }

    final sku = entry.key;
    final csvData = entry.value;
    final existingDoc = docBySku[sku];

    if (existingDoc != null) {
      final invData = existingDoc.data();
      final updatePayload = <String, dynamic>{};
      void updateField(String key, dynamic csvValue) {
        if (csvValue != null && csvValue != invData[key]) updatePayload[key] = csvValue;
      }
      csvData.forEach((key, value) => updateField(key, value));
      if(updatePayload.containsKey('name')) {
         final newName = csvData['name'] as String;
         updatePayload['searchKeywords'] = <String>{...newName.toLowerCase().split(' '), sku.toLowerCase()}.toList();
      }
      if (updatePayload.isNotEmpty) {
        batch.update(existingDoc.reference, updatePayload);
        operationCount++;
        changedCount++;
        final currentStock = (invData['stock'] as num? ?? 0).toInt();
        final newStock = csvData['stock'] as int;
        if (newStock != currentStock) {
          movementLines.add({'productId': existingDoc.id, 'sku': sku, 'name': csvData['name'], 'qty': newStock - currentStock});
        }
      }
    } else {
      final newDocRef = db.collection('inventory').doc();
      final name = csvData['name'] as String;
      final newDocData = {
        'createdAt': FieldValue.serverTimestamp(),
        'searchKeywords': <String>{...name.toLowerCase().split(' '), sku.toLowerCase()}.toList(),
      };
      csvData.forEach((key, value) {
        newDocData[key] = value ?? '';
      });
      batch.set(newDocRef, newDocData);
      operationCount += 2;
      movementLines.add({'productId': newDocRef.id, 'sku': sku, 'name': name, 'qty': csvData['stock']});
      changedCount++;
    }
  }

  if (changedCount > 0) {
    final movementRef = db.collection('inventory_movements').doc();
    batch.set(movementRef, {
      'type': 'adjustment', 'direction': 'adjust', 'createdAt': FieldValue.serverTimestamp(),
      'note': note.trim().isEmpty ? 'Sincronización por CSV' : note.trim(),
      'referenceType': 'csv_import', 'referenceId': movementRef.id, 'lines': movementLines,
    });
    await batch.commit();
  }

  return InventoryCsvImportResult(changedCount: changedCount, missingSkus: const []);
}

  Future<html.File?> _pickCsvFile() async {
    final input = html.FileUploadInputElement()..accept = '.csv,text/csv';
    input.click();
    await input.onChange.first;
    if (input.files == null || input.files!.isEmpty) return null;
    return input.files!.first;
  }

  Future<String> _readFileAsText(html.File file) async {
    final reader = html.FileReader();
    final completer = Completer<String>();
    reader.onLoad.listen((_) => completer.complete(reader.result as String? ?? ''));
    reader.onError.listen((_) => completer.completeError(reader.error ?? 'Error'));
    reader.readAsText(file, 'utf-8');
    return completer.future;
  }

  List<List<String>> _parseCsv(String csv) {
    final rows = <List<String>>[];
    final currentRow = <String>[];
    final buffer = StringBuffer();
    bool inQuotes = false;
    void endCell() { currentRow.add(buffer.toString()); buffer.clear(); }
    void endRow() { endCell(); rows.add(List<String>.from(currentRow)); currentRow.clear(); }
    for (int i = 0; i < csv.length; i++) {
      final ch = csv[i];
      if (ch == '"') {
        if (inQuotes && i + 1 < csv.length && csv[i + 1] == '"') { buffer.write('"'); i++; }
        else { inQuotes = !inQuotes; }
        continue;
      }
      if (!inQuotes && ch == ',') { endCell(); continue; }
      if (!inQuotes && (ch == '\n' || ch == '\r')) {
        if (ch == '\r' && i + 1 < csv.length && csv[i + 1] == '\n') i++;
        if (buffer.isNotEmpty || currentRow.isNotEmpty) endRow();
        else { buffer.clear(); currentRow.clear(); }
        continue;
      }
      buffer.write(ch);
    }
    if (buffer.isNotEmpty || currentRow.isNotEmpty) endRow();
    return rows;
  }
}
