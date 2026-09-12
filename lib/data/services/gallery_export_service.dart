import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:photo_manager/photo_manager.dart';
import '../../core/errors/app_exception.dart';
import '../models/vault_photo.dart';
import 'photo_download_service.dart';

/// Service managing the export of decrypted vault photos into
/// Android's shared gallery under Pictures/Privora.
///
/// Strict rules:
/// 1. Decrypted bytes are in-memory only and never persist unencrypted to internal app storage.
/// 2. Ciphertext envelopes (starting with 0x01) are strictly rejected from export.
/// 3. Vault photos, metadata records, and cloud storage assets are never deleted or moved.
/// 4. Android 10+ uses scoped storage (no broad storage or READ_MEDIA_IMAGES requested).
class GalleryExportService {
  final PhotoDownloadService downloadService;

  GalleryExportService({required this.downloadService});

  /// Saves a decrypted copy of the photo to the shared gallery under Pictures/Privora.
  /// Strictly verifies decrypted bytes are authentic image data before writing.
  /// Keeps the Privora vault copy completely intact.
  Future<AssetEntity?> savePhotoToGallery({
    required VaultPhoto photo,
    required Uint8List masterKey,
  }) async {
    // 1. Download and decrypt full photo into RAM only (never thumbnail)
    final decryptedBytes = await downloadService.getDecryptedFullPhoto(
      photo: photo,
      masterKey: masterKey,
    );

    // 2. Validate decrypted bytes are authentic image data, never raw ciphertext
    validateDecryptedImageBytes(decryptedBytes);

    // 3. Determine clean filename and extension
    final ext = detectExtension(decryptedBytes, photo.mimeType);
    var cleanName = photo.displayName.trim();
    if (cleanName.isEmpty) {
      cleanName = 'Privora_${photo.id.substring(0, 8)}';
    }

    // Strip existing extension if present to avoid double extension (e.g. photo.jpg.jpg)
    final lastDot = cleanName.lastIndexOf('.');
    if (lastDot > 0 && lastDot > cleanName.length - 6) {
      cleanName = cleanName.substring(0, lastDot);
    }

    cleanName = cleanName.replaceAll(RegExp(r'[^\w\.-]'), '_');
    if (cleanName.isEmpty) {
      cleanName = 'Privora_${photo.id.substring(0, 8)}';
    }
    final fullFilename = '$cleanName$ext';

    // 4. Save to Android MediaStore under Pictures/Privora using Scoped Storage
    try {
      final assetEntity = await PhotoManager.editor.saveImage(
        decryptedBytes,
        title: cleanName,
        filename: fullFilename,
        relativePath: 'Pictures/Privora',
      );
      return assetEntity;
    } on PlatformException catch (e) {
      // Legacy fallback for Android 9 and older where WRITE_EXTERNAL_STORAGE is required
      if (Platform.isAndroid &&
          (e.code.toLowerCase().contains('permission') ||
              e.message?.toLowerCase().contains('permission') == true)) {
        final status = await Permission.storage.request();
        if (status.isGranted) {
          final assetEntity = await PhotoManager.editor.saveImage(
            decryptedBytes,
            title: cleanName,
            filename: fullFilename,
            relativePath: 'Pictures/Privora',
          );
          return assetEntity;
        }
        throw const PermissionException(
          'Storage permission denied. Please grant permission in device settings.',
        );
      }
      debugPrint('savePhotoToGallery PlatformException: $e');
      throw StorageException('Failed to save photo to Gallery: ${e.message}');
    } catch (e) {
      debugPrint('savePhotoToGallery error: $e');
      if (e is AppException) rethrow;
      throw StorageException('Failed to save photo to Gallery: $e');
    }
  }

  /// Verifies image bytes start with valid image magic bytes.
  /// Prevents saving raw or corrupted ciphertext to the gallery.
  static void validateDecryptedImageBytes(Uint8List bytes) {
    if (bytes.length < 12) {
      throw const ImageDecodeException('Decrypted image data is too short.');
    }

    // Reject Privora ciphertext envelope header (version byte 0x01 + 12-byte nonce + 16-byte tag)
    if (bytes[0] == 0x01 && bytes.length >= 29) {
      throw const CryptoException(
        'Cannot export ciphertext to Gallery. Decryption failed.',
      );
    }

    // Detect valid image formats:
    // JPEG: FF D8 FF
    final isJpeg = bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF;
    // PNG: 89 50 4E 47 0D 0A 1A 0A
    final isPng =
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47;
    // WebP / RIFF: 52 49 46 46 ... 57 45 42 50
    final isWebp =
        bytes[0] == 0x52 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x46 &&
        bytes.length >= 12 &&
        bytes[8] == 0x57 &&
        bytes[9] == 0x45 &&
        bytes[10] == 0x42 &&
        bytes[11] == 0x50;
    // GIF: 47 49 46 38
    final isGif =
        bytes[0] == 0x47 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x38;
    // HEIF / HEIC: ftyp box
    final isHeif =
        bytes.length >= 12 &&
        bytes[4] == 0x66 &&
        bytes[5] == 0x74 &&
        bytes[6] == 0x79 &&
        bytes[7] == 0x70;
    // BMP: 42 4D
    final isBmp = bytes[0] == 0x42 && bytes[1] == 0x4D;

    if (!isJpeg && !isPng && !isWebp && !isGif && !isHeif && !isBmp) {
      throw const ImageDecodeException(
        'Decrypted data is not a recognized image format.',
      );
    }
  }

  /// Detects the file extension from image magic bytes with MIME fallback.
  static String detectExtension(Uint8List bytes, String mimeType) {
    if (bytes.length >= 3 &&
        bytes[0] == 0xFF &&
        bytes[1] == 0xD8 &&
        bytes[2] == 0xFF) {
      return '.jpg';
    }
    if (bytes.length >= 4 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47) {
      return '.png';
    }
    if (bytes.length >= 12 &&
        bytes[0] == 0x52 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x46 &&
        bytes[8] == 0x57 &&
        bytes[9] == 0x45 &&
        bytes[10] == 0x42 &&
        bytes[11] == 0x50) {
      return '.webp';
    }
    if (bytes.length >= 4 &&
        bytes[0] == 0x47 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x38) {
      return '.gif';
    }
    if (bytes.length >= 12 &&
        bytes[4] == 0x66 &&
        bytes[5] == 0x74 &&
        bytes[6] == 0x79 &&
        bytes[7] == 0x70) {
      return '.heic';
    }
    if (bytes.length >= 2 && bytes[0] == 0x42 && bytes[1] == 0x4D) {
      return '.bmp';
    }
    if (mimeType.contains('png')) return '.png';
    if (mimeType.contains('webp')) return '.webp';
    if (mimeType.contains('gif')) return '.gif';
    if (mimeType.contains('heic') || mimeType.contains('heif')) return '.heic';
    if (mimeType.contains('bmp')) return '.bmp';
    return '.jpg';
  }
}
