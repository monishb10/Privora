import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../app/providers.dart';
import '../../core/constants/app_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/confirmation_dialog.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/error_view.dart';
import '../../data/models/vault_category.dart';
import 'category_card.dart';
import 'create_category_sheet.dart';
import 'edit_category_sheet.dart';

/// Main screen after PIN unlock displaying the user's private categories.
/// Strict rule: Zero default categories allowed. Displays empty state for new users.
class CategoriesScreen extends ConsumerStatefulWidget {
  const CategoriesScreen({super.key});

  @override
  ConsumerState<CategoriesScreen> createState() => _CategoriesScreenState();
}

class _CategoriesScreenState extends ConsumerState<CategoriesScreen> {
  bool _isSearching = false;
  final _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _handleDeleteCategory(VaultCategory category) async {
    final confirmed = await ConfirmationDialog.show(
      context: context,
      title: 'Delete "${category.name}"?',
      message: category.photoCount > 0
          ? 'This category contains ${category.photoCount} photos. All photos will be moved to Recently Deleted before the category is deleted.'
          : 'Are you sure you want to delete this category?',
      confirmText: 'Delete Category',
      isDestructive: true,
      icon: Icons.delete_sweep_outlined,
    );

    if (confirmed == true && mounted) {
      try {
        final user = ref.read(currentUserProvider);
        if (user == null) return;

        await ref
            .read(categoryRepositoryProvider)
            .deleteCategory(category.id, user.id);
        ref.invalidate(categoriesProvider);
        ref.invalidate(recentlyDeletedPhotosProvider);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Category "${category.name}" deleted.')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to delete category: $e')),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final categoriesAsync = ref.watch(categoriesProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: _isSearching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                style: AppTypography.bodyLarge,
                decoration: const InputDecoration(
                  hintText: 'Search categories...',
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  fillColor: Colors.transparent,
                  contentPadding: EdgeInsets.zero,
                ),
                onChanged: (val) =>
                    setState(() => _searchQuery = val.trim().toLowerCase()),
              )
            : Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: AppColors.elevatedSurface,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: const Icon(
                      Icons.shield_outlined,
                      size: 18,
                      color: AppColors.primaryAccent,
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Text(
                    AppConstants.appName,
                    style: AppTypography.titleLarge,
                  ),
                ],
              ),
        actions: [
          IconButton(
            icon: Icon(
              _isSearching ? Icons.close_rounded : Icons.search_rounded,
            ),
            tooltip: _isSearching ? 'Close Search' : 'Search Categories',
            onPressed: () {
              setState(() {
                if (_isSearching) {
                  _searchController.clear();
                  _searchQuery = '';
                }
                _isSearching = !_isSearching;
              });
            },
          ),
          IconButton(
            icon: const Icon(Icons.lock_outline_rounded),
            tooltip: 'Lock Privora',
            onPressed: () {
              ref.read(sessionLockServiceProvider.notifier).lock();
              context.go('/unlock');
            },
          ),
        ],
      ),
      body: categoriesAsync.when(
        data: (categories) {
          // Zero-demo check: If no categories exist, display the required empty state
          if (categories.isEmpty) {
            return EmptyState(
              icon: Icons.create_new_folder_outlined,
              title: 'No categories yet',
              subtitle: 'Create your first private collection.',
              actionText: 'Create Category',
              onAction: () => CreateCategorySheet.show(context),
            );
          }

          final filtered = _searchQuery.isEmpty
              ? categories
              : categories
                    .where((c) => c.name.toLowerCase().contains(_searchQuery))
                    .toList();

          if (filtered.isEmpty && _searchQuery.isNotEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Text(
                  'No categories found matching "$_searchQuery"',
                  style: AppTypography.bodyMedium.copyWith(
                    color: AppColors.secondaryText,
                  ),
                ),
              ),
            );
          }

          return RefreshIndicator(
            color: AppColors.primaryAccent,
            backgroundColor: AppColors.surface,
            onRefresh: () async {
              ref.invalidate(categoriesProvider);
            },
            child: GridView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              physics: const AlwaysScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 14,
                mainAxisSpacing: 14,
                childAspectRatio: 0.95,
              ),
              itemCount: filtered.length,
              itemBuilder: (context, index) {
                final category = filtered[index];
                return CategoryCard(
                  category: category,
                  onTap: () =>
                      context.push('/category/${category.id}', extra: category),
                  onEdit: () => EditCategorySheet.show(context, category),
                  onDelete: () => _handleDeleteCategory(category),
                );
              },
            ),
          );
        },
        loading: () => const Center(
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(AppColors.primaryAccent),
          ),
        ),
        error: (err, _) => ErrorView(
          message: err.toString(),
          onRetry: () => ref.invalidate(categoriesProvider),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.primaryAccent,
        foregroundColor: AppColors.background,
        elevation: 4,
        icon: const Icon(Icons.add_rounded, size: 22),
        label: Text(
          'New Category',
          style: AppTypography.labelLarge.copyWith(
            color: AppColors.background,
            fontWeight: FontWeight.w700,
          ),
        ),
        onPressed: () => CreateCategorySheet.show(context),
      ),
    );
  }
}
