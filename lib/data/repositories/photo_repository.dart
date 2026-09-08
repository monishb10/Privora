import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import '../models/upload_state.dart';
import '../models/vault_photo.dart';
import '../services/cloudinary_media_service.dart';
import '../services/photo_download_service.dart';
import '../services/photo_upload_service.dart';
import '../services/supabase_database_service.dart';
import '../services/supabase_storage_service.dart';

/// Repository coordinating encrypted photo storage, retrieval, deletion, and trash cleanup.
class PhotoRepository {
  final SupabaseDatabaseService databaseService;
  final SupabaseStorageService storageService;
  final PhotoUploadService uploadService;
  final PhotoDownloadService downloadService;
  final CloudinaryMediaService? cloudinaryService;

  PhotoRepository({
    required this.databaseService,
    required this.storageService,
    required this.uploadService,
    required this.downloadService,
    this.cloudinaryService,
  });

  Future<List<VaultPhoto>> getPhotosByCategory(
    String userId,
    String categoryId, {
    int limit = 50,
    int offset = 0,
    bool ascending = false,
  }) {
    return databaseService.getPhotosByCategory(
      userId,
      categoryId,
      limit: limit,
      offset: offset,
      ascending: ascending,
    );
  }

  Future<VaultPhoto> uploadPhoto({
    required File sourceFile,
    required String userId,
    required String categoryId,
    required Uint8List masterKey,
    String? customDisplayName,
    void Function(UploadState state)? onStateChanged,
  }) {
    return uploadService.uploadPhoto(
      sourceFile: sourceFile,
      userId: userId,
      categoryId: categoryId,
      masterKey: masterKey,
      customDisplayName: customDisplayName,
      onStateChanged: onStateChanged,
    );
  }

  Future<Uint8List> loadThumbnail({
    String? thumbnailPath,
    VaultPhoto? photo,
    required Uint8List masterKey,
  }) {
    if (photo != null) {
      return downloadService.getDecryptedThumbnail(
        photo: photo,
        masterKey: masterKey,
      );
    }
    if (thumbnailPath != null) {
      return downloadService.getDecryptedThumbnailByPath(
        thumbnailPath: thumbnailPath,
        masterKey: masterKey,
      );
    }
    throw ArgumentError('Either photo or thumbnailPath must be provided');
  }

  Future<Uint8List> loadFullPhoto({
    String? photoPath,
    VaultPhoto? photo,
    required Uint8List masterKey,
  }) {
    if (photo != null) {
      return downloadService.getDecryptedFullPhoto(
        photo: photo,
        masterKey: masterKey,
      );
    }
    if (photoPath != null) {
      return downloadService.getDecryptedFullPhotoByPath(
        photoPath: photoPath,
        masterKey: masterKey,
      );
    }
    throw ArgumentError('Either photo or photoPath must be provided');
  }

  Future<void> softDeletePhoto(String photoId, String userId) {
    return databaseService.softDeletePhoto(photoId, userId);
  }

  Future<void> restorePhoto(String photoId, String userId) {
    return databaseService.restorePhoto(photoId, userId);
  }

  Future<List<VaultPhoto>> getRecentlyDeleted(String userId) {
    return databaseService.getRecentlyDeletedPhotos(userId);
  }

  /// Permanently deletes a photo: Cloud Storage first, then Database record.
  Future<void> permanentlyDeletePhoto(VaultPhoto photo, String userId) async {
    if (photo.isCloudinary) {
      if (cloudinaryService != null) {
        await cloudinaryService!.permanentlyDelete(photoId: photo.id);
      } else {
        await databaseService.permanentDeletePhotoMetadata(photo.id, userId);
      }
    } else {
      // 1. Delete encrypted objects from Supabase Storage
      await storageService.deleteFiles([
        photo.storagePath,
        photo.thumbnailPath,
      ]);

      // 2. Delete database record
      await databaseService.permanentDeletePhotoMetadata(photo.id, userId);
    }
  }

  /// Empties Recently Deleted: deletes cloud storage objects first, then database records.
  Future<void> emptyTrash(String userId) async {
    final trashPhotos = await databaseService.getRecentlyDeletedPhotos(userId);
    if (trashPhotos.isEmpty) return;

    final supabasePaths = <String>[];
    for (final photo in trashPhotos) {
      if (photo.isCloudinary) {
        if (cloudinaryService != null) {
          try {
            await cloudinaryService!.permanentlyDelete(photoId: photo.id);
          } catch (e) {
            debugPrint('Error deleting Cloudinary photo ${photo.id}: $e');
          }
        } else {
          await databaseService.permanentDeletePhotoMetadata(photo.id, userId);
        }
      } else {
        supabasePaths.add(photo.storagePath);
        supabasePaths.add(photo.thumbnailPath);
      }
    }

    // 1. Delete from Supabase Storage for legacy photos
    if (supabasePaths.isNotEmpty) {
      await storageService.deleteFiles(supabasePaths);
    }

    // 2. Delete legacy metadata records from Database
    for (final photo in trashPhotos) {
      if (!photo.isCloudinary) {
        await databaseService.permanentDeletePhotoMetadata(photo.id, userId);
      }
    }
  }

  /// Deletes photos that have passed their 30-day delete_after date.
  Future<void> cleanExpiredTrash(String userId) async {
    try {
      final expired = await databaseService.getExpiredPhotos(userId);
      if (expired.isEmpty) return;

      final supabasePaths = <String>[];
      for (final photo in expired) {
        if (photo.isCloudinary) {
          if (cloudinaryService != null) {
            try {
              await cloudinaryService!.permanentlyDelete(photoId: photo.id);
            } catch (e) {
              debugPrint(
                'cleanExpiredTrash Cloudinary error for ${photo.id}: $e',
              );
            }
          } else {
            await databaseService.permanentDeletePhotoMetadata(
              photo.id,
              userId,
            );
          }
        } else {
          supabasePaths.add(photo.storagePath);
          supabasePaths.add(photo.thumbnailPath);
        }
      }

      if (supabasePaths.isNotEmpty) {
        await storageService.deleteFiles(supabasePaths);
      }
      for (final photo in expired) {
        if (!photo.isCloudinary) {
          await databaseService.permanentDeletePhotoMetadata(photo.id, userId);
        }
      }
      debugPrint('Privora: Cleaned ${expired.length} expired trash items.');
    } catch (e) {
      debugPrint('cleanExpiredTrash warning: $e');
    }
  }

  Future<void> movePhoto(String photoId, String userId, String newCategoryId) {
    return databaseService.movePhotoCategory(photoId, userId, newCategoryId);
  }

  Future<void> renamePhoto(VaultPhoto photo, String newName) {
    final updated = photo.copyWith(
      displayName: newName.trim(),
      updatedAt: DateTime.now(),
    );
    return databaseService.updatePhoto(updated);
  }

  /// Decrypts photo into a temporary file for OS share/export dialog.
  /// Caller MUST clean up the file immediately after use.
  Future<File> preparePhotoForExportOrShare({
    required VaultPhoto photo,
    required Uint8List masterKey,
  }) async {
    final decryptedBytes = await downloadService.getDecryptedFullPhoto(
      photo: photo,
      masterKey: masterKey,
    );

    final tempDir = await getTemporaryDirectory();
    final ext = photo.mimeType.contains('png')
        ? '.png'
        : photo.mimeType.contains('webp')
        ? '.webp'
        : '.jpg';

    final tempPath =
        '${tempDir.path}/privora_share_${DateTime.now().millisecondsSinceEpoch}$ext';
    final tempFile = File(tempPath);
    await tempFile.writeAsBytes(decryptedBytes);
    return tempFile;
  }

  Future<int> getTotalStorageUsage(String userId) {
    return databaseService.getTotalStorageBytes(userId);
  }
}
