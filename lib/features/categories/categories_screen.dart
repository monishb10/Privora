import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../app/providers.dart';
import '../../core/config/supabase_config.dart';
import '../../core/errors/error_mapper.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/confirmation_dialog.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/error_view.dart';
import '../../core/widgets/privora_brand_app_bar.dart';
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

  bool _isRetrying = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _handleRetry() async {
    if (_isRetrying) return;
    setState(() => _isRetrying = true);

    try {
      final user =
          ref.read(currentUserProvider) ??
          SupabaseConfig.client?.auth.currentUser;
      if (user != null) {
        await ref
            .read(categoryRepositoryProvider)
            .getCategories(user.id, forceRefresh: true)
            .timeout(const Duration(seconds: 10));
      }
      ref.invalidate(categoriesProvider);
    } catch (_) {
      ref.invalidate(categoriesProvider);
    } finally {
      if (mounted) {
        setState(() => _isRetrying = false);
      }
    }
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
      appBar: PrivoraBrandAppBar(
        isSearching: _isSearching,
        searchController: _searchController,
        onSearchChanged: (val) =>
            setState(() => _searchQuery = val.trim().toLowerCase()),
        onToggleSearch: () {
          setState(() {
            if (_isSearching) {
              _searchController.clear();
              _searchQuery = '';
            }
            _isSearching = !_isSearching;
          });
        },
        onLock: () {
          ref.read(sessionLockServiceProvider.notifier).lock();
          context.go('/unlock');
        },
      ),
      body: _isRetrying
          ? const Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(
                  AppColors.primaryActionBlue,
                ),
              ),
            )
          : categoriesAsync.when(
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
                          .where(
                            (c) => c.name.toLowerCase().contains(_searchQuery),
                          )
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
                  color: AppColors.primaryActionBlue,
                  backgroundColor: AppColors.cardSurface,
                  onRefresh: _handleRetry,
                  child: GridView.builder(
                    padding: EdgeInsets.only(
                      left: 16,
                      right: 16,
                      top: 16,
                      bottom: 170 + MediaQuery.paddingOf(context).bottom,
                    ),
                    physics: const AlwaysScrollableScrollPhysics(),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
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
                        onTap: () => context.push(
                          '/category/${category.id}',
                          extra: category,
                        ),
                        onEdit: () => EditCategorySheet.show(context, category),
                        onDelete: () => _handleDeleteCategory(category),
                      );
                    },
                  ),
                );
              },
              loading: () => const Center(
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(
                    AppColors.primaryActionBlue,
                  ),
                ),
              ),
              error: (err, _) => ErrorView(
                message: ErrorMapper.mapToUserMessage(err),
                onRetry: _isRetrying ? null : _handleRetry,
              ),
            ),
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 82),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: AppColors.primaryActionBlue.withValues(alpha: 0.30),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: FloatingActionButton.extended(
            elevation: 0,
            highlightElevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            backgroundColor: AppColors.primaryActionBlue,
            foregroundColor: Colors.white,
            icon: const Icon(Icons.add_rounded, size: 22),
            label: const Text('New Category', style: AppTypography.buttonText),
            onPressed: () => CreateCategorySheet.show(context),
          ),
        ),
      ),
    );
  }
}
