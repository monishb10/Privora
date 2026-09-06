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

  List<VaultCategory>? _cachedCategories;

  CategoryRepository({required this.databaseService, Uuid? uuid})
      : uuid = uuid ?? const Uuid();

  List<VaultCategory>? get cachedCategories => _cachedCategories;

  Future<List<VaultCategory>> getCategories(
    String userId, {
    bool forceRefresh = false,
  }) async {
    if (_cachedCategories != null && !forceRefresh) {
      return _cachedCategories!;
    }
    final categories = await databaseService.getCategories(userId);
    _cachedCategories = categories;
    return categories;
  }

  void addCategoryLocally(VaultCategory category) {
    final current = _cachedCategories ?? [];
    if (!current.any((c) => c.id == category.id)) {
      _cachedCategories = [category, ...current];
    }
  }

  void updateCategoryLocally(VaultCategory category) {
    if (_cachedCategories == null) return;
    _cachedCategories = _cachedCategories!
        .map((c) => c.id == category.id ? category : c)
        .toList();
  }

  void removeCategoryLocally(String categoryId) {
    if (_cachedCategories == null) return;
    _cachedCategories =
        _cachedCategories!.where((c) => c.id != categoryId).toList();
  }

  void clearCache() {
    _cachedCategories = null;
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
