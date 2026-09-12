import 'dart:async';
import 'package:uuid/uuid.dart';
import '../../core/config/supabase_config.dart';
import '../models/vault_category.dart';
import '../services/supabase_database_service.dart';

/// Repository for managing user-created categories.
/// Strict rule: No default categories. Every category is user-created.
class CategoryRepository {
  final SupabaseDatabaseService databaseService;
  final Uuid uuid;

  String? _cachedUserId;
  List<VaultCategory>? _cachedCategories;

  CategoryRepository({required this.databaseService, Uuid? uuid})
    : uuid = uuid ?? const Uuid();

  List<VaultCategory>? get cachedCategories => _cachedCategories;

  Future<List<VaultCategory>> getCategories(
    String userId, {
    bool forceRefresh = false,
  }) async {
    final effectiveUserId =
        SupabaseConfig.client?.auth.currentUser?.id ?? userId;
    if (_cachedUserId == effectiveUserId &&
        _cachedCategories != null &&
        !forceRefresh) {
      return _cachedCategories!;
    }
    final categories = await databaseService
        .getCategories(effectiveUserId)
        .timeout(const Duration(seconds: 10));
    _cachedUserId = effectiveUserId;
    _cachedCategories = categories;
    return categories;
  }

  void addCategoryLocally(VaultCategory category) {
    if (_cachedUserId != null && _cachedUserId != category.userId) return;
    _cachedUserId = category.userId;
    final current = _cachedCategories ?? [];
    if (!current.any((c) => c.id == category.id)) {
      _cachedCategories = [category, ...current];
    }
  }

  void updateCategoryLocally(VaultCategory category) {
    if (_cachedCategories == null) return;
    if (_cachedUserId != null && _cachedUserId != category.userId) return;
    _cachedCategories = _cachedCategories!
        .map((c) => c.id == category.id ? category : c)
        .toList();
  }

  void removeCategoryLocally(String categoryId) {
    if (_cachedCategories == null) return;
    _cachedCategories = _cachedCategories!
        .where((c) => c.id != categoryId)
        .toList();
  }

  void updatePhotoCountLocally(String categoryId, int delta) {
    if (_cachedCategories == null) return;
    _cachedCategories = _cachedCategories!.map((c) {
      if (c.id == categoryId) {
        final newCount = (c.photoCount + delta).clamp(0, 999999);
        return c.copyWith(photoCount: newCount);
      }
      return c;
    }).toList();
  }

  void setPhotoCountLocally(String categoryId, int count) {
    if (_cachedCategories == null) return;
    _cachedCategories = _cachedCategories!.map((c) {
      if (c.id == categoryId) {
        return c.copyWith(photoCount: count.clamp(0, 999999));
      }
      return c;
    }).toList();
  }

  void clearCache([String? userId]) {
    if (userId == null || _cachedUserId == userId) {
      _cachedUserId = null;
      _cachedCategories = null;
    }
  }

  Future<VaultCategory> createCategory({
    required String userId,
    required String name,
    required int colorValue,
    String? categoryId,
  }) async {
    final effectiveUserId =
        SupabaseConfig.client?.auth.currentUser?.id ?? userId;
    final id = categoryId ?? uuid.v4();
    final now = DateTime.now();
    final category = VaultCategory(
      id: id,
      userId: effectiveUserId,
      name: name.trim(),
      colorValue: colorValue,
      createdAt: now,
      updatedAt: now,
    );

    final created = await databaseService
        .createCategory(category)
        .timeout(const Duration(seconds: 10));

    addCategoryLocally(created);
    return created;
  }

  Future<void> updateCategory(VaultCategory category) async {
    updateCategoryLocally(category);
    await databaseService.updateCategory(category);
  }

  Future<void> deleteCategory(String categoryId, String userId) async {
    removeCategoryLocally(categoryId);
    await databaseService.deleteCategoryWithPhotos(categoryId, userId);
  }

  Future<void> setCoverPhoto(
    String categoryId,
    String userId,
    String photoId,
  ) async {
    final categories = await getCategories(userId);
    final target = categories.firstWhere((c) => c.id == categoryId);
    final updated = target.copyWith(
      coverPhotoId: photoId,
      updatedAt: DateTime.now(),
    );
    await updateCategory(updated);
  }
}
