import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sp;
import '../../core/config/supabase_config.dart';
import '../../core/constants/storage_constants.dart';
import '../../core/errors/app_exception.dart';
import '../../core/errors/error_mapper.dart';
import '../models/user_profile.dart';
import '../models/vault_category.dart';
import '../models/vault_photo.dart';

/// Database service interacting with Supabase PostgreSQL under strict Row Level Security.
class SupabaseDatabaseService {
  sp.SupabaseClient get _client {
    final client = SupabaseConfig.client;
    if (client == null) {
      throw const StorageException('Supabase is not configured.');
    }
    return client;
  }

  // -------------------------------------------------------------
  // PROFILES
  // -------------------------------------------------------------

  Future<UserProfile?> getProfile(String userId) async {
    try {
      final data = await _client
          .from(StorageConstants.tableProfiles)
          .select()
          .eq('id', userId)
          .maybeSingle();

      if (data == null) return null;
      final userEmail = _client.auth.currentUser?.email;
      return UserProfile.fromJson(data, userEmail);
    } catch (e) {
      debugPrint('getProfile error: $e');
      throw StorageException(ErrorMapper.mapToUserMessage(e));
    }
  }

  Future<void> updateDisplayName(String userId, String displayName) async {
    try {
      await _client
          .from(StorageConstants.tableProfiles)
          .update({'display_name': displayName})
          .eq('id', userId);
    } catch (e) {
      debugPrint('updateDisplayName error: $e');
      throw StorageException(ErrorMapper.mapToUserMessage(e));
    }
  }

  // -------------------------------------------------------------
  // VAULT KEYS
  // -------------------------------------------------------------

  Future<void> saveVaultKeys({
    required String userId,
    required String recoveryWrappedKey,
    required String recoverySalt,
    required String recoveryNonce,
    int cryptoVersion = 1,
  }) async {
    try {
      await _client.from(StorageConstants.tableVaultKeys).upsert({
        'user_id': userId,
        'recovery_wrapped_key': recoveryWrappedKey,
        'recovery_salt': recoverySalt,
        'recovery_nonce': recoveryNonce,
        'crypto_version': cryptoVersion,
      });
    } catch (e) {
      debugPrint('saveVaultKeys error: $e');
      throw CryptoException(ErrorMapper.mapToUserMessage(e));
    }
  }

  Future<Map<String, dynamic>?> getVaultKeys(String userId) async {
    try {
      final data = await _client
          .from(StorageConstants.tableVaultKeys)
          .select()
          .eq('user_id', userId)
          .maybeSingle();
      return data;
    } catch (e) {
      debugPrint('getVaultKeys error: $e');
      throw CryptoException(ErrorMapper.mapToUserMessage(e));
    }
  }

  // -------------------------------------------------------------
  // CATEGORIES
  // -------------------------------------------------------------

  Future<List<VaultCategory>> getCategories(String userId) async {
    try {
      // Fetch categories with photo counts and latest upload date
      final data = await _client
          .from(StorageConstants.tableCategories)
          .select('*, photos:photos(id, created_at, deleted_at)')
          .eq('user_id', userId)
          .order('created_at', ascending: false);

      final List<VaultCategory> categories = [];
      for (final item in data) {
        final photosList = (item['photos'] as List<dynamic>?) ?? [];
        // Filter out soft-deleted photos
        final activePhotos = photosList
            .where((p) => p['deleted_at'] == null)
            .toList();
        final count = activePhotos.length;

        DateTime? latestDate;
        if (activePhotos.isNotEmpty) {
          activePhotos.sort(
            (a, b) => (b['created_at'] as String).compareTo(
              a['created_at'] as String,
            ),
          );
          latestDate = DateTime.parse(
            activePhotos.first['created_at'] as String,
          );
        }

        categories.add(
          VaultCategory.fromJson(
            item,
            photoCount: count,
            latestPhotoDate: latestDate,
          ),
        );
      }

      return categories;
    } catch (e) {
      debugPrint('getCategories error: $e');
      throw StorageException(ErrorMapper.mapToUserMessage(e));
    }
  }

  Future<VaultCategory> createCategory(VaultCategory category) async {
    try {
      final authUser = _client.auth.currentUser;
      final currentUserId = authUser?.id ?? category.userId;
      if (authUser == null && currentUserId.isEmpty) {
        throw const StorageException('Session expired. Please sign in again.');
      }

      final insertData = <String, dynamic>{
        if (category.id.isNotEmpty) 'id': category.id,
        'user_id': currentUserId,
        'name': category.name,
        'color_value': category.colorValue,
        if (category.coverPhotoId != null && category.coverPhotoId!.isNotEmpty)
          'cover_photo_id': category.coverPhotoId,
      };

      final inserted = await _client
          .from(StorageConstants.tableCategories)
          .insert(insertData)
          .select()
          .single()
          .timeout(const Duration(seconds: 10));

      return VaultCategory.fromJson(inserted);
    } on TimeoutException catch (e) {
      debugPrint('createCategory timeout: $e');
      throw const StorageException(
        'Request timed out. Please check your network connection.',
      );
    } on sp.PostgrestException catch (e) {
      debugPrint(
        'createCategory PostgrestException: code=${e.code}, message=${e.message}, details=${e.details}, hint=${e.hint}',
      );
      throw StorageException(ErrorMapper.mapToUserMessage(e));
    } catch (e) {
      debugPrint('createCategory error: $e');
      if (e is AppException) rethrow;
      throw StorageException(ErrorMapper.mapToUserMessage(e));
    }
  }

  Future<void> updateCategory(VaultCategory category) async {
    try {
      final currentUserId = sp.Supabase.instance.client.auth.currentUser!.id;
      final updateData = <String, dynamic>{
        'name': category.name,
        'color_value': category.colorValue,
        'cover_photo_id': category.coverPhotoId,
        'updated_at': DateTime.now().toIso8601String(),
      };

      await _client
          .from(StorageConstants.tableCategories)
          .update(updateData)
          .eq('id', category.id)
          .eq('user_id', currentUserId);
    } on sp.PostgrestException catch (e) {
      debugPrint(
        'updateCategory PostgrestException: code=${e.code}, message=${e.message}, details=${e.details}, hint=${e.hint}',
      );
      throw StorageException(ErrorMapper.mapToUserMessage(e));
    } catch (e) {
      debugPrint('updateCategory error: $e');
      throw StorageException(ErrorMapper.mapToUserMessage(e));
    }
  }

  /// Deletes a category. As per specification, any photos in it are moved to Recently Deleted first!
  Future<void> deleteCategoryWithPhotos(
    String categoryId,
    String userId,
  ) async {
    try {
      final now = DateTime.now();
      final deleteAfter = now.add(const Duration(days: 30));

      // 1. Soft-delete active photos into Recently Deleted
      await _client
          .from(StorageConstants.tablePhotos)
          .update({
            'deleted_at': now.toIso8601String(),
            'delete_after': deleteAfter.toIso8601String(),
          })
          .eq('category_id', categoryId)
          .eq('user_id', userId)
          .isFilter('deleted_at', null);

      // 2. Delete the category itself
      await _client
          .from(StorageConstants.tableCategories)
          .delete()
          .eq('id', categoryId)
          .eq('user_id', userId);
    } catch (e) {
      debugPrint('deleteCategoryWithPhotos error: $e');
      throw StorageException(ErrorMapper.mapToUserMessage(e));
    }
  }

  // -------------------------------------------------------------
  // PHOTOS
  // -------------------------------------------------------------

  Future<List<VaultPhoto>> getPhotosByCategory(
    String userId,
    String categoryId, {
    int limit = 50,
    int offset = 0,
    bool ascending = false,
  }) async {
    try {
      final data = await _client
          .from(StorageConstants.tablePhotos)
          .select()
          .eq('user_id', userId)
          .eq('category_id', categoryId)
          .isFilter('deleted_at', null)
          .order('created_at', ascending: ascending)
          .range(offset, offset + limit - 1);

      return (data as List<dynamic>)
          .map((item) => VaultPhoto.fromJson(item as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('getPhotosByCategory error: $e');
      throw StorageException(ErrorMapper.mapToUserMessage(e));
    }
  }

  Future<List<VaultPhoto>> getRecentlyDeletedPhotos(String userId) async {
    try {
      final data = await _client
          .from(StorageConstants.tablePhotos)
          .select()
          .eq('user_id', userId)
          .not('deleted_at', 'is', null)
          .order('deleted_at', ascending: false);

      return (data as List<dynamic>)
          .map((item) => VaultPhoto.fromJson(item as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('getRecentlyDeletedPhotos error: $e');
      throw StorageException(ErrorMapper.mapToUserMessage(e));
    }
  }

  Future<VaultPhoto> insertPhoto(VaultPhoto photo) async {
    try {
      final data = await _client
          .from(StorageConstants.tablePhotos)
          .insert(photo.toJson())
          .select()
          .single();

      return VaultPhoto.fromJson(data);
    } catch (e) {
      debugPrint('insertPhoto error: $e');
      throw StorageException(ErrorMapper.mapToUserMessage(e));
    }
  }

  Future<void> updatePhoto(VaultPhoto photo) async {
    try {
      await _client
          .from(StorageConstants.tablePhotos)
          .update(photo.toJson())
          .eq('id', photo.id)
          .eq('user_id', photo.userId);
    } catch (e) {
      debugPrint('updatePhoto error: $e');
      throw StorageException(ErrorMapper.mapToUserMessage(e));
    }
  }

  Future<void> softDeletePhoto(String photoId, String userId) async {
    try {
      final now = DateTime.now();
      final deleteAfter = now.add(const Duration(days: 30));

      await _client
          .from(StorageConstants.tablePhotos)
          .update({
            'deleted_at': now.toIso8601String(),
            'delete_after': deleteAfter.toIso8601String(),
          })
          .eq('id', photoId)
          .eq('user_id', userId);
    } catch (e) {
      debugPrint('softDeletePhoto error: $e');
      throw StorageException(ErrorMapper.mapToUserMessage(e));
    }
  }

  Future<void> restorePhoto(String photoId, String userId) async {
    try {
      await _client
          .from(StorageConstants.tablePhotos)
          .update({'deleted_at': null, 'delete_after': null})
          .eq('id', photoId)
          .eq('user_id', userId);
    } catch (e) {
      debugPrint('restorePhoto error: $e');
      throw StorageException(ErrorMapper.mapToUserMessage(e));
    }
  }

  Future<void> movePhotoCategory(
    String photoId,
    String userId,
    String newCategoryId,
  ) async {
    try {
      await _client
          .from(StorageConstants.tablePhotos)
          .update({'category_id': newCategoryId})
          .eq('id', photoId)
          .eq('user_id', userId);
    } catch (e) {
      debugPrint('movePhotoCategory error: $e');
      throw StorageException(ErrorMapper.mapToUserMessage(e));
    }
  }

  Future<void> permanentDeletePhotoMetadata(
    String photoId,
    String userId,
  ) async {
    try {
      await _client
          .from(StorageConstants.tablePhotos)
          .delete()
          .eq('id', photoId)
          .eq('user_id', userId);
    } catch (e) {
      debugPrint('permanentDeletePhotoMetadata error: $e');
      throw StorageException(ErrorMapper.mapToUserMessage(e));
    }
  }

  /// Finds photos where delete_after is past now()
  Future<List<VaultPhoto>> getExpiredPhotos(String userId) async {
    try {
      final now = DateTime.now().toIso8601String();
      final data = await _client
          .from(StorageConstants.tablePhotos)
          .select()
          .eq('user_id', userId)
          .not('delete_after', 'is', null)
          .lte('delete_after', now);

      return (data as List<dynamic>)
          .map((item) => VaultPhoto.fromJson(item as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('getExpiredPhotos error: $e');
      return [];
    }
  }

  /// Calculates total cloud storage bytes used by the user's photos
  Future<int> getTotalStorageBytes(String userId) async {
    try {
      final data = await _client
          .from(StorageConstants.tablePhotos)
          .select('encrypted_size')
          .eq('user_id', userId);

      int total = 0;
      for (final item in data) {
        final size = item['encrypted_size'];
        if (size is int) {
          total += size;
        } else if (size != null) {
          total += int.tryParse(size.toString()) ?? 0;
        }
      }
      return total;
    } catch (e) {
      debugPrint('getTotalStorageBytes error: $e');
      return 0;
    }
  }

  /// Deletes all database records for account deletion
  Future<void> deleteUserDatabaseRecords(String userId) async {
    try {
      await _client
          .from(StorageConstants.tablePhotos)
          .delete()
          .eq('user_id', userId);
      await _client
          .from(StorageConstants.tableCategories)
          .delete()
          .eq('user_id', userId);
      await _client
          .from(StorageConstants.tableVaultKeys)
          .delete()
          .eq('user_id', userId);
      await _client
          .from(StorageConstants.tableProfiles)
          .delete()
          .eq('id', userId);
    } catch (e) {
      debugPrint('deleteUserDatabaseRecords error: $e');
      throw StorageException(ErrorMapper.mapToUserMessage(e));
    }
  }
}
