// lib/widgets/pdf_viewer_screen.dart

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_pdfview/flutter_pdfview.dart';
import 'package:path_provider/path_provider.dart';
import 'package:dio/dio.dart';

class PdfViewerScreen extends StatefulWidget {
  final String pdfUrl;
  final String title;

  const PdfViewerScreen({super.key, required this.pdfUrl, required this.title});

  @override
  State<PdfViewerScreen> createState() => _PdfViewerScreenState();
}

class _PdfViewerScreenState extends State<PdfViewerScreen> {
  // En lugar de una variable de estado booleana, usaremos un Future
  // Esto se integra mucho mejor con la lógica de construcción de Flutter.
  late Future<String> _localPdfPathFuture;

  @override
  void initState() {
    super.initState();
    // En lugar de llamar a una función que usa setState,
    // asignamos directamente el Future a nuestra variable.
    _localPdfPathFuture = _loadAndGetPath();
  }

  // Esta función ahora solo se encarga de descargar y DEVOLVER la ruta del archivo.
  Future<String> _loadAndGetPath() async {
  try {
    final dir = await getApplicationDocumentsDirectory();
    final safeTitle = widget.title.replaceAll(RegExp(r'[^\w\-]+'), '_');
    final fileName = '${safeTitle}_${DateTime.now().millisecondsSinceEpoch}.pdf';
    final file = File('${dir.path}/$fileName');

    // Descarga como bytes (más confiable que download() en algunos casos)
    final dio = Dio();
    final response = await dio.get<List<int>>(
      widget.pdfUrl,
      options: Options(
        responseType: ResponseType.bytes,
        followRedirects: true,
        receiveTimeout: const Duration(seconds: 30),
        sendTimeout: const Duration(seconds: 30),
      ),
    );

    final bytes = response.data;
    if (bytes == null || bytes.isEmpty) {
      throw Exception('Descarga vacía (0 bytes).');
    }

    // Validación ligera: un PDF normalmente empieza con "%PDF"
    // (no siempre es estrictamente necesario, pero ayuda a diagnosticar)
    final header = String.fromCharCodes(bytes.take(4));
    if (header != '%PDF') {
      // No lo bloqueamos, pero lo avisamos para debug
      debugPrint('Advertencia: el archivo no inicia con %PDF. Header="$header"');
    }

    await file.writeAsBytes(bytes, flush: true);

    debugPrint('PDF guardado en: ${file.path} (${bytes.length} bytes)');
    debugPrint('content-type: ${response.headers.value('content-type')}');

    return file.path;
  } catch (e) {
    debugPrint("Error al cargar PDF: $e");
    throw Exception('Error al cargar el PDF: $e');
  }
}
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
      ),
      // --- LÓGICA DE CONSTRUCCIÓN REFORZADA CON FutureBuilder ---
      body: FutureBuilder<String>(
        future: _localPdfPathFuture, // Le decimos que "escuche" a nuestro Future
        builder: (context, snapshot) {
          // Mientras el Future se está ejecutando (descargando)
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          
          // Si el Future terminó con un error
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text('Error: ${snapshot.error}', style: const TextStyle(color: Colors.red)),
              ),
            );
          }

          // Si el Future terminó con éxito y tenemos la ruta del archivo
          if (snapshot.hasData) {
            return PDFView(
              filePath: snapshot.data!, // Usamos el resultado del Future
              // Opciones para mejorar la experiencia de usuario
              enableSwipe: true,
              swipeHorizontal: false,
              autoSpacing: false,
              pageFling: true,
            );
          }
          
          // Un estado por defecto por si algo muy raro pasa
          return const Center(child: Text('Preparando visor de PDF...'));
        },
      ),
    );
  }
}
