// lib/services/cloudinary_service.dart

import 'dart:io';
import 'dart:typed_data';
import 'package:dio/dio.dart'; // Solo dependemos de Dio

class CloudinaryService {
  // --- Configuración para la llamada directa a la API ---
  final String _cloudName = 'dxm6mzrkt'; // Tu Cloud Name
  final String _uploadPreset = 'ams_mims_unsigned'; // Tu Upload Preset
  final Dio _dio = Dio();

  /// Sube un archivo a Cloudinary usando una petición HTTP directa con Dio.
  Future<String> uploadFile(File file, String folder) async {
    // 1. La URL del API de Cloudinary para subidas de cualquier tipo de archivo
    final url = 'https://api.cloudinary.com/v1_1/$_cloudName/auto/upload';

    try {
      // 2. Leemos los bytes del archivo y preparamos el cuerpo de la petición
      String fileName = file.path.split('/').last;
      FormData formData = FormData.fromMap({
        // El archivo se adjunta como un 'MultipartFile'
        "file": await MultipartFile.fromFile(file.path, filename: fileName),
        // Los parámetros de la subida se pasan aquí, en el FormData
        "upload_preset": _uploadPreset,
        "folder": folder,
      });

      Response response = await _dio.post(url, data: formData);

      if (response.statusCode == 200) {
        final responseData = response.data;
        return responseData['secure_url'];
      } else {
        return '';
      }
    } on DioException {
      return '';
    } catch (_) {
      return '';
    }
  }

  /// Sube bytes (por ejemplo un PDF generado en memoria). Ideal para Web.
  Future<String> uploadBytes(
    Uint8List bytes, {
    required String fileName,
    required String folder,
  }) async {
    final url = 'https://api.cloudinary.com/v1_1/$_cloudName/auto/upload';

    try {
      final formData = FormData.fromMap({
        "file": MultipartFile.fromBytes(bytes, filename: fileName),
        "upload_preset": _uploadPreset,
        "folder": folder,
      });

      final response = await _dio.post(url, data: formData);

      if (response.statusCode == 200) {
        final responseData = response.data;
        return responseData['secure_url'];
      }
      return '';
    } on DioException {
      return '';
    } catch (_) {
      return '';
    }
  }
}