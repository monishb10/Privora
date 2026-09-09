import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:uuid/uuid.dart';
import '../../core/constants/app_constants.dart';
import '../../core/constants/storage_constants.dart';
import '../../core/errors/app_exception.dart';
import '../../core/security/temporary_file_cleaner.dart';
import '../../core/security/vault_crypto_service.dart';
import '../../core/utils/file_utils.dart';
import '../models/upload_state.dart';
import '../models/vault_photo.dart';
import 'cloudinary_media_service.dart';
import 'supabase_database_service.dart';
import 'supabase_storage_service.dart';

/// Service orchestrating the complete private photo encryption, thumbnail generation,
/// cloud upload to Cloudinary (or Supabase fallback), and rollback protocol.
class PhotoUploadService {
  final VaultCryptoService cryptoService;
  final SupabaseStorageService? storageService;
  final CloudinaryMediaService? cloudinaryService;
  final SupabaseDatabaseService databaseService;
  final TemporaryFileCleaner cleaner;
  final Uuid uuid;

  PhotoUploadService({
    required this.cryptoService,
    this.storageService,
    this.cloudinaryService,
    required this.databaseService,
    required this.cleaner,
    Uuid? uuid,
  }) : uuid = uuid ?? const Uuid();

  /// Processes, encrypts, and uploads a photo file.
  /// All new uploads target Cloudinary raw authenticated assets via signed Edge Function.
  Future<VaultPhoto> uploadPhoto({
    required File sourceFile,
    required String userId,
    required String categoryId,
    required Uint8List masterKey,
    String? customDisplayName,
    bool deleteSourceFile = true,
    void Function(UploadState state)? onStateChanged,
  }) async {
    final photoId = uuid.v4();
    final originalFileName =
        customDisplayName ?? sourceFile.uri.pathSegments.last;

    String? fullPublicId;
    String? thumbPublicId;
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

      // 2. Generate thumbnail bytes locally before encryption
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

      final cService = cloudinaryService;
      if (cService != null) {
        // --- CLOUDINARY UPLOAD FLOW ---
        // 4. Request signed upload parameters from Edge Function
        update(UploadStatus.uploadingThumbnail, 0.5);
        final params = await cService.createUploadSignature(
          categoryId: categoryId,
          photoId: photoId,
        );

        fullPublicId = params.fullPublicId;
        thumbPublicId = params.thumbnailPublicId;

        // 5. Upload encrypted thumbnail as raw authenticated asset
        update(UploadStatus.uploadingThumbnail, 0.65);
        await cService.uploadEncryptedBytes(
          cloudName: params.cloudName,
          apiKey: params.apiKey,
          timestamp: params.timestamp,
          uploadPreset: params.uploadPreset,
          publicId: params.thumbnailPublicId,
          signature: params.thumbnailSignature,
          bytes: encryptedThumb,
          filename: '${photoId}_thumb.enc',
        );
        thumbUploaded = true;

        // 6. Upload encrypted full photo as raw authenticated asset
        update(UploadStatus.uploadingFullPhoto, 0.8);
        final fullResult = await cService.uploadEncryptedBytes(
          cloudName: params.cloudName,
          apiKey: params.apiKey,
          timestamp: params.timestamp,
          uploadPreset: params.uploadPreset,
          publicId: params.fullPublicId,
          signature: params.fullSignature,
          bytes: encryptedFull,
          filename: '$photoId.enc',
        );
        photoUploaded = true;

        // 7. Insert metadata record into Supabase PostgreSQL
        update(UploadStatus.savingMetadata, 0.9);
        final now = DateTime.now();
        final photo = VaultPhoto(
          id: photoId,
          userId: userId,
          categoryId: categoryId,
          storagePath: params.fullPublicId,
          thumbnailPath: params.thumbnailPublicId,
          displayName: originalFileName,
          mimeType: mimeType,
          encryptedSize: encryptedFull.length,
          width: dimensions.width > 0 ? dimensions.width : null,
          height: dimensions.height > 0 ? dimensions.height : null,
          createdAt: now,
          updatedAt: now,
          storageProvider: 'cloudinary',
          cloudinaryPublicId: params.fullPublicId,
          cloudinaryThumbnailPublicId: params.thumbnailPublicId,
          cloudinaryAssetId: fullResult.assetId,
          cloudinaryVersion: fullResult.version,
          encryptedBytes: fullResult.bytes,
          originalFilename: originalFileName,
        );

        final insertedPhoto = await databaseService.insertPhoto(photo);

        // 8. Clean up local source file if requested (e.g. temporary camera captures)
        if (deleteSourceFile) {
          await cleaner.deleteSingleFile(sourceFile.path);
        }

        update(UploadStatus.completed, 1.0);
        return insertedPhoto;
      } else {
        // --- LEGACY SUPABASE STORAGE FALLBACK ---
        final sService = storageService;
        if (sService == null) {
          throw const StorageException('No storage service configured.');
        }

        final photoStoragePath = StorageConstants.photoPath(userId, photoId);
        final thumbnailStoragePath = StorageConstants.thumbnailPath(
          userId,
          photoId,
        );

        update(UploadStatus.uploadingThumbnail, 0.6);
        await sService.uploadEncryptedBytes(
          path: thumbnailStoragePath,
          bytes: encryptedThumb,
        );
        thumbUploaded = true;

        update(UploadStatus.uploadingFullPhoto, 0.8);
        await sService.uploadEncryptedBytes(
          path: photoStoragePath,
          bytes: encryptedFull,
        );
        photoUploaded = true;

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
          storageProvider: 'supabase',
        );

        final insertedPhoto = await databaseService.insertPhoto(photo);
        if (deleteSourceFile) {
          await cleaner.deleteSingleFile(sourceFile.path);
        }

        update(UploadStatus.completed, 1.0);
        return insertedPhoto;
      }
    } catch (e) {
      debugPrint('Upload failure: $e');

      // CRITICAL ROLLBACK: Clean up orphaned cloud storage objects on failure
      if (photoUploaded || thumbUploaded) {
        debugPrint('Rollback: Cleaning orphaned cloud storage objects...');
        if (cloudinaryService != null) {
          try {
            await cloudinaryService!.cleanupFailedUpload(
              photoId: photoId,
              fullPublicId: photoUploaded ? fullPublicId : null,
              thumbnailPublicId: thumbUploaded ? thumbPublicId : null,
            );
          } catch (cleanupErr) {
            debugPrint('Cloudinary rollback warning: $cleanupErr');
          }
        } else if (storageService != null) {
          final toDelete = <String>[];
          final photoStoragePath = StorageConstants.photoPath(userId, photoId);
          final thumbnailStoragePath = StorageConstants.thumbnailPath(
            userId,
            photoId,
          );
          if (photoUploaded) toDelete.add(photoStoragePath);
          if (thumbUploaded) toDelete.add(thumbnailStoragePath);
          try {
            await storageService!.deleteFiles(toDelete);
          } catch (rollbackErr) {
            debugPrint('Supabase rollback warning: $rollbackErr');
          }
        }
      }

      // Clean local temporary files only if requested
      if (deleteSourceFile) {
        await cleaner.deleteSingleFile(sourceFile.path);
      }

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
