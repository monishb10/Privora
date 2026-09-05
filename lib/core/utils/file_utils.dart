import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:mime/mime.dart';
import '../constants/app_constants.dart';
import '../errors/app_exception.dart';

/// Utilities for validating and inspecting media files before encryption.
class FileUtils {
  FileUtils._();

  /// Validates file size and MIME type
  static void validatePhotoFile(File file) {
    if (!file.existsSync()) {
      throw const ValidationException('Selected file does not exist.');
    }

    final size = file.lengthSync();
    if (size == 0) {
      throw const ValidationException('Selected file is empty.');
    }

    if (size > AppConstants.maxPhotoSizeBytes) {
      throw const ValidationException(
        'Photo exceeds maximum allowed size of 50MB.',
      );
    }

    final mimeType = lookupMimeType(file.path) ?? 'application/octet-stream';
    if (!AppConstants.allowedMimeTypes.contains(mimeType.toLowerCase())) {
      throw ValidationException(
        'Unsupported image format ($mimeType). Only JPG, PNG, WEBP, and HEIC are supported.',
      );
    }
  }

  /// Detects MIME type for a file
  static String getMimeType(String path) {
    return lookupMimeType(path) ?? 'image/jpeg';
  }

  /// Extracts image dimensions (width, height) in-memory without third-party native tools
  static Future<({int width, int height})> getImageDimensions(
    Uint8List bytes,
  ) async {
    try {
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final width = frame.image.width;
      final height = frame.image.height;
      frame.image.dispose();
      return (width: width, height: height);
    } catch (_) {
      return (width: 0, height: 0);
    }
  }
}
