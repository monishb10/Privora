import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Cleans temporary files created for camera captures, photo sharing, and encryption.
/// Enforces Privora's rule that no unencrypted media ever remains on the device.
class TemporaryFileCleaner {
  TemporaryFileCleaner();

  /// Scans temporary and cache directories and safely removes all leftover temp files.
  Future<void> cleanTemporaryFiles() async {
    try {
      final tempDir = await getTemporaryDirectory();
      await _deleteFilesRecursively(tempDir);

      try {
        final cacheDir = await getApplicationCacheDirectory();
        await _deleteFilesRecursively(cacheDir);
      } catch (_) {
        // Cache directory may not exist on all test platforms
      }
    } catch (e) {
      debugPrint('TemporaryFileCleaner warning: $e');
    }
  }

  /// Safely deletes a specific temporary file immediately after use.
  Future<void> deleteSingleFile(String? filePath) async {
    if (filePath == null || filePath.isEmpty) return;
    try {
      final file = File(filePath);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (e) {
      debugPrint('Failed to delete temporary file $filePath: $e');
    }
  }

  Future<void> _deleteFilesRecursively(Directory dir) async {
    if (!await dir.exists()) return;

    final entities = dir.listSync(recursive: true, followLinks: false);
    for (final entity in entities) {
      try {
        if (entity is File) {
          // Delete temp photos, share files, enc files, and camera artifacts
          final name = entity.path.toLowerCase();
          if (name.endsWith('.jpg') ||
              name.endsWith('.jpeg') ||
              name.endsWith('.png') ||
              name.endsWith('.webp') ||
              name.endsWith('.enc') ||
              name.endsWith('.tmp') ||
              name.contains('privora_') ||
              name.contains('camera')) {
            await entity.delete();
          }
        }
      } catch (_) {
        // File may be locked by another process, ignore and continue
      }
    }
  }
}
