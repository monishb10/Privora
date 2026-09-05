import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:uuid/uuid.dart';
import '../../core/constants/app_constants.dart';
import '../../core/constants/storage_constants.dart';
import '../../core/security/temporary_file_cleaner.dart';
import '../../core/security/vault_crypto_service.dart';
import '../../core/utils/file_utils.dart';
import '../models/upload_state.dart';
import '../models/vault_photo.dart';
import 'supabase_database_service.dart';
import 'supabase_storage_service.dart';

/// Service orchestrating the complete private photo encryption, thumbnail generation,
/// cloud upload, and rollback protocol.
class PhotoUploadService {
  final VaultCryptoService cryptoService;
  final SupabaseStorageService storageService;
  final SupabaseDatabaseService databaseService;
  final TemporaryFileCleaner cleaner;
  final Uuid uuid;

  PhotoUploadService({
    required this.cryptoService,
    required this.storageService,
    required this.databaseService,
    required this.cleaner,
    Uuid? uuid,
  }) : uuid = uuid ?? const Uuid();

  /// Processes, encrypts, and uploads a photo file.
  /// Notifies the [onStateChanged] callback of progress.
  Future<VaultPhoto> uploadPhoto({
    required File sourceFile,
    required String userId,
    required String categoryId,
    required Uint8List masterKey,
    String? customDisplayName,
    void Function(UploadState state)? onStateChanged,
  }) async {
    final photoId = uuid.v4();
    final originalFileName =
        customDisplayName ?? sourceFile.uri.pathSegments.last;
    final photoStoragePath = StorageConstants.photoPath(userId, photoId);
    final thumbnailStoragePath = StorageConstants.thumbnailPath(
      userId,
      photoId,
    );

    bool photoUploaded = false;
    bool thumbUploaded = false;

    void update(UploadStatus status, double progress, [String? error]) {
      onStateChanged?.call(
        UploadState(
          status: status,
          progress: progress,
          currentFileName: originalFileName,
          errorMessage: error,
        ),
      );
    }

    try {
      // 1. Validate source file
      update(UploadStatus.reading, 0.1);
      FileUtils.validatePhotoFile(sourceFile);
      final rawBytes = await sourceFile.readAsBytes();
      final mimeType = FileUtils.getMimeType(sourceFile.path);

      // Extract image dimensions
      final dimensions = await FileUtils.getImageDimensions(rawBytes);

      // 2. Generate thumbnail bytes
      update(UploadStatus.generatingThumbnail, 0.25);
      final thumbnailBytes = await _createThumbnail(rawBytes);

      // 3. Encrypt both thumbnail and full photo with Master Vault Key
      update(UploadStatus.encrypting, 0.4);
      final encryptedThumb = await cryptoService.encryptPhotoBytes(
        thumbnailBytes,
        masterKey,
      );
      final encryptedFull = await cryptoService.encryptPhotoBytes(
        rawBytes,
        masterKey,
      );

      // 4. Upload encrypted thumbnail
      update(UploadStatus.uploadingThumbnail, 0.6);
      await storageService.uploadEncryptedBytes(
        path: thumbnailStoragePath,
        bytes: encryptedThumb,
      );
      thumbUploaded = true;

      // 5. Upload encrypted full photo
      update(UploadStatus.uploadingFullPhoto, 0.8);
      await storageService.uploadEncryptedBytes(
        path: photoStoragePath,
        bytes: encryptedFull,
      );
      photoUploaded = true;

      // 6. Insert metadata record into Supabase PostgreSQL
      update(UploadStatus.savingMetadata, 0.9);
      final now = DateTime.now();
      final photo = VaultPhoto(
        id: photoId,
        userId: userId,
        categoryId: categoryId,
        storagePath: photoStoragePath,
        thumbnailPath: thumbnailStoragePath,
        displayName: originalFileName,
        mimeType: mimeType,
        encryptedSize: encryptedFull.length,
        width: dimensions.width > 0 ? dimensions.width : null,
        height: dimensions.height > 0 ? dimensions.height : null,
        createdAt: now,
        updatedAt: now,
      );

      final insertedPhoto = await databaseService.insertPhoto(photo);

      // 7. Success: clean up temporary file artifacts
      await cleaner.deleteSingleFile(sourceFile.path);

      update(UploadStatus.completed, 1.0);
      return insertedPhoto;
    } catch (e) {
      debugPrint('Upload failure: $e');

      // CRITICAL ROLLBACK: Remove uploaded storage objects if database insert or post-processing fails
      if (photoUploaded || thumbUploaded) {
        debugPrint('Rollback: Cleaning orphaned cloud storage objects...');
        final toDelete = <String>[];
        if (photoUploaded) toDelete.add(photoStoragePath);
        if (thumbUploaded) toDelete.add(thumbnailStoragePath);
        try {
          await storageService.deleteFiles(toDelete);
        } catch (rollbackErr) {
          debugPrint('Rollback deletion warning: $rollbackErr');
        }
      }

      // Also clean any temporary files
      await cleaner.deleteSingleFile(sourceFile.path);

      update(UploadStatus.error, 0.0, e.toString());
      rethrow;
    }
  }

  /// Compresses raw image bytes to create a compact thumbnail (~400px)
  Future<Uint8List> _createThumbnail(Uint8List rawBytes) async {
    try {
      final compressed = await FlutterImageCompress.compressWithList(
        rawBytes,
        minWidth: AppConstants.thumbnailSizePixels,
        minHeight: AppConstants.thumbnailSizePixels,
        quality: AppConstants.thumbnailQuality,
        format: CompressFormat.jpeg,
      );

      if (compressed.isNotEmpty) {
        return Uint8List.fromList(compressed);
      }
    } catch (e) {
      debugPrint('Thumbnail compression fallback: $e');
    }
    // Fallback if compression plugin cannot run
    return rawBytes;
  }
}
