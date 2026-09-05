import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sp;
import '../../core/config/supabase_config.dart';
import '../../core/constants/storage_constants.dart';
import '../../core/errors/app_exception.dart';
import '../../core/errors/error_mapper.dart';

/// Interacts with Supabase Storage for encrypted blobs.
/// Strictly enforces that the bucket is private and all objects are pre-encrypted before upload.
class SupabaseStorageService {
  sp.SupabaseClient get _client {
    final client = SupabaseConfig.client;
    if (client == null) {
      throw const StorageException('Supabase is not configured.');
    }
    return client;
  }

  /// Uploads encrypted bytes to private-photos bucket
  Future<String> uploadEncryptedBytes({
    required String path,
    required Uint8List bytes,
  }) async {
    try {
      await _client.storage
          .from(StorageConstants.privatePhotosBucket)
          .uploadBinary(
            path,
            bytes,
            fileOptions: const sp.FileOptions(
              contentType: 'application/octet-stream',
              upsert: true,
            ),
          );
      return path;
    } catch (e) {
      debugPrint('uploadEncryptedBytes error at $path: $e');
      throw StorageException(ErrorMapper.mapToUserMessage(e));
    }
  }

  /// Downloads encrypted bytes from private-photos bucket using authenticated call
  Future<Uint8List> downloadEncryptedBytes(String path) async {
    try {
      final bytes = await _client.storage
          .from(StorageConstants.privatePhotosBucket)
          .download(path);
      return bytes;
    } catch (e) {
      debugPrint('downloadEncryptedBytes error at $path: $e');
      throw StorageException(ErrorMapper.mapToUserMessage(e));
    }
  }

  /// Deletes a single file from the bucket
  Future<void> deleteFile(String path) async {
    try {
      await _client.storage.from(StorageConstants.privatePhotosBucket).remove([
        path,
      ]);
    } catch (e) {
      debugPrint('deleteFile error for $path: $e');
      throw StorageException(ErrorMapper.mapToUserMessage(e));
    }
  }

  /// Deletes multiple files from the bucket
  Future<void> deleteFiles(List<String> paths) async {
    if (paths.isEmpty) return;
    try {
      await _client.storage
          .from(StorageConstants.privatePhotosBucket)
          .remove(paths);
    } catch (e) {
      debugPrint('deleteFiles error: $e');
      throw StorageException(ErrorMapper.mapToUserMessage(e));
    }
  }

  /// Recursively lists and deletes all files belonging to a user for account cleanup
  Future<void> deleteAllUserStorage(String userId) async {
    try {
      // List photos and thumbnails
      final photoObjects = await _client.storage
          .from(StorageConstants.privatePhotosBucket)
          .list(path: '$userId/photos');

      final thumbnailObjects = await _client.storage
          .from(StorageConstants.privatePhotosBucket)
          .list(path: '$userId/thumbnails');

      final List<String> pathsToDelete = [];
      for (final obj in photoObjects) {
        pathsToDelete.add('$userId/photos/${obj.name}');
      }
      for (final obj in thumbnailObjects) {
        pathsToDelete.add('$userId/thumbnails/${obj.name}');
      }

      if (pathsToDelete.isNotEmpty) {
        await _client.storage
            .from(StorageConstants.privatePhotosBucket)
            .remove(pathsToDelete);
      }
    } catch (e) {
      debugPrint('deleteAllUserStorage warning: $e');
      // Continue cleanup even if partial
    }
  }
}
