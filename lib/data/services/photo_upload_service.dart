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
import '../../core/utils/import_pipeline_logger.dart';
import '../models/upload_state.dart';
import '../models/vault_photo.dart';
import 'cloudinary_media_service.dart';
import 'supabase_database_service.dart';
import 'supabase_storage_service.dart';

/// Service orchestrating private photo encryption, thumbnail generation,
/// cloud upload to Cloudinary (or Supabase if explicitly configured), and rollback protocol.
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
  /// New photos do NOT silently fall back to Supabase Storage.
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
    ImportStage currentStage = ImportStage.sourceOpened;

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
      // 1. Stage 4: Source opened & validated
      currentStage = ImportStage.sourceOpened;
      update(UploadStatus.reading, 0.1);
      FileUtils.validatePhotoFile(sourceFile);
      final rawBytes = await sourceFile.readAsBytes();
      final mimeType = FileUtils.getMimeType(sourceFile.path);
      ImportPipelineLogger.logStage(
        ImportStage.sourceOpened,
        details: '$originalFileName (${rawBytes.length} bytes)',
      );

      // Extract image dimensions
      final dimensions = await FileUtils.getImageDimensions(rawBytes);

      // 2. Stage 6: Generate thumbnail bytes locally before encryption
      currentStage = ImportStage.thumbnailCreated;
      update(UploadStatus.generatingThumbnail, 0.25);
      final thumbnailBytes = await _createThumbnail(rawBytes);
      ImportPipelineLogger.logStage(
        ImportStage.thumbnailCreated,
        details: 'thumbnail created (${thumbnailBytes.length} bytes)',
      );

      // 3. Stage 7 & 8: Encrypt full photo and thumbnail with Master Vault Key
      currentStage = ImportStage.thumbnailEncrypted;
      update(UploadStatus.encrypting, 0.35);
      final encryptedThumb = await cryptoService.encryptPhotoBytes(
        thumbnailBytes,
        masterKey,
      );
      ImportPipelineLogger.logStage(
        ImportStage.thumbnailEncrypted,
        details: 'encrypted thumbnail (${encryptedThumb.length} bytes)',
      );

      currentStage = ImportStage.fullImageEncrypted;
      update(UploadStatus.encrypting, 0.45);
      final encryptedFull = await cryptoService.encryptPhotoBytes(
        rawBytes,
        masterKey,
      );
      ImportPipelineLogger.logStage(
        ImportStage.fullImageEncrypted,
        details: 'encrypted full photo (${encryptedFull.length} bytes)',
      );

      final cService = cloudinaryService;

      if (cService != null) {
        // --- CLOUDINARY UPLOAD FLOW ---
        // 4. Stage 9: Cloudinary upload signature received
        currentStage = ImportStage.uploadSignatureReceived;
        update(UploadStatus.uploadingThumbnail, 0.55);
        final CloudinaryUploadParams params = await cService
            .createUploadSignature(categoryId: categoryId, photoId: photoId);
        ImportPipelineLogger.logStage(
          ImportStage.uploadSignatureReceived,
          details: 'signature acquired for photo $photoId',
        );

        fullPublicId = params.fullPublicId;
        thumbPublicId = params.thumbnailPublicId;

        // 5. Stage 11: Upload encrypted thumbnail as raw authenticated asset
        currentStage = ImportStage.thumbnailUploaded;
        update(UploadStatus.uploadingThumbnail, 0.65);
        final thumbSignedParams = params.thumbnailSignedParams.isNotEmpty
            ? params.thumbnailSignedParams
            : {
                'public_id': params.thumbnailPublicId,
                'timestamp': params.timestamp.toString(),
                if (params.uploadPreset != null &&
                    params.uploadPreset!.isNotEmpty)
                  'upload_preset': params.uploadPreset!,
              };

        await cService.uploadEncryptedBytes(
          cloudName: params.cloudName,
          apiKey: params.apiKey,
          timestamp: params.timestamp,
          uploadPreset: params.uploadPreset,
          publicId: params.thumbnailPublicId,
          signature: params.thumbnailSignature,
          signedParams: thumbSignedParams,
          bytes: encryptedThumb,
          filename: '${photoId}_thumb.enc',
          stage: 'thumbnail',
        );
        thumbUploaded = true;
        ImportPipelineLogger.logStage(
          ImportStage.thumbnailUploaded,
          details: 'thumbnail uploaded to Cloudinary',
        );

        // 6. Stage 10: Upload encrypted full photo as raw authenticated asset
        currentStage = ImportStage.fullAssetUploaded;
        update(UploadStatus.uploadingFullPhoto, 0.8);
        final fullSignedParams = params.fullSignedParams.isNotEmpty
            ? params.fullSignedParams
            : {
                'public_id': params.fullPublicId,
                'timestamp': params.timestamp.toString(),
                if (params.uploadPreset != null &&
                    params.uploadPreset!.isNotEmpty)
                  'upload_preset': params.uploadPreset!,
              };

        final fullResult = await cService.uploadEncryptedBytes(
          cloudName: params.cloudName,
          apiKey: params.apiKey,
          timestamp: params.timestamp,
          uploadPreset: params.uploadPreset,
          publicId: params.fullPublicId,
          signature: params.fullSignature,
          signedParams: fullSignedParams,
          bytes: encryptedFull,
          filename: '$photoId.enc',
          stage: 'full_photo',
        );
        photoUploaded = true;
        ImportPipelineLogger.logStage(
          ImportStage.fullAssetUploaded,
          details: 'full encrypted asset uploaded to Cloudinary',
        );

        // 7. Stage 12: Insert metadata record into Supabase PostgreSQL
        currentStage = ImportStage.metadataCommitted;
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
        ImportPipelineLogger.logStage(
          ImportStage.metadataCommitted,
          details: 'metadata record committed for photo $photoId',
        );

        // Stage 14: Clean up local source file if requested
        if (deleteSourceFile) {
          await cleaner.deleteSingleFile(sourceFile.path);
          ImportPipelineLogger.logStage(
            ImportStage.tempFilesCleaned,
            details: 'source file deleted',
          );
        }

        update(UploadStatus.completed, 1.0);
        return insertedPhoto;
      } else {
        // --- SUPABASE STORAGE FLOW (Only when Cloudinary is not configured) ---
        final sService = storageService;
        if (sService == null) {
          throw const StorageException('No storage service configured.');
        }

        final photoStoragePath = StorageConstants.photoPath(userId, photoId);
        final thumbnailStoragePath = StorageConstants.thumbnailPath(
          userId,
          photoId,
        );

        currentStage = ImportStage.thumbnailUploaded;
        update(UploadStatus.uploadingThumbnail, 0.6);
        await sService.uploadEncryptedBytes(
          path: thumbnailStoragePath,
          bytes: encryptedThumb,
        );
        thumbUploaded = true;
        ImportPipelineLogger.logStage(
          ImportStage.thumbnailUploaded,
          details: 'thumbnail uploaded to Supabase Storage',
        );

        currentStage = ImportStage.fullAssetUploaded;
        update(UploadStatus.uploadingFullPhoto, 0.8);
        await sService.uploadEncryptedBytes(
          path: photoStoragePath,
          bytes: encryptedFull,
        );
        photoUploaded = true;
        ImportPipelineLogger.logStage(
          ImportStage.fullAssetUploaded,
          details: 'full encrypted asset uploaded to Supabase Storage',
        );

        currentStage = ImportStage.metadataCommitted;
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
        ImportPipelineLogger.logStage(
          ImportStage.metadataCommitted,
          details: 'metadata record committed for photo $photoId',
        );

        if (deleteSourceFile) {
          await cleaner.deleteSingleFile(sourceFile.path);
          ImportPipelineLogger.logStage(
            ImportStage.tempFilesCleaned,
            details: 'source file deleted',
          );
        }

        update(UploadStatus.completed, 1.0);
        return insertedPhoto;
      }
    } catch (e, st) {
      ImportPipelineLogger.logFailure(currentStage, e, st);

      // CRITICAL ROLLBACK: Clean up orphaned cloud storage objects on failure
      if (photoUploaded || thumbUploaded) {
        debugPrint(
          '[PhotoUploadService] Rollback: Cleaning orphaned cloud storage objects...',
        );
        if (fullPublicId != null && cloudinaryService != null) {
          try {
            await cloudinaryService!.cleanupFailedUpload(
              photoId: photoId,
              fullPublicId: photoUploaded ? fullPublicId : null,
              thumbnailPublicId: thumbUploaded ? thumbPublicId : null,
            );
          } catch (cleanupErr) {
            debugPrint(
              '[PhotoUploadService] Cloudinary rollback warning: $cleanupErr',
            );
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
            debugPrint(
              '[PhotoUploadService] Supabase rollback warning: $rollbackErr',
            );
          }
        }
      }

      // Clean local temporary files only if requested
      if (deleteSourceFile) {
        await cleaner.deleteSingleFile(sourceFile.path);
      }

      final friendlyMsg = ImportPipelineLogger.getUserFriendlyErrorMessage(
        currentStage,
        e,
      );
      update(UploadStatus.error, 0.0, friendlyMsg);

      if (e is AppException) {
        throw StorageException(friendlyMsg, code: e.code);
      }
      throw StorageException(friendlyMsg);
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
