import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../app/providers.dart';
import '../../core/config/supabase_config.dart';
import '../../core/errors/error_mapper.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_motion.dart';
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
/// Strict rule: Zero demo categories allowed. Shows deliberate empty state for new accounts.
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

  bool _isOpeningCreateSheet = false;

  Future<void> _openCreateCategorySheet() async {
    if (_isOpeningCreateSheet) return;
    _isOpeningCreateSheet = true;
    try {
      final created = await CreateCategorySheet.show(context);
      if (created == true && mounted) {
        ref.invalidate(categoriesProvider);
      }
    } finally {
      if (mounted) {
        _isOpeningCreateSheet = false;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final categoriesAsync = ref.watch(categoriesProvider);

    return PopScope(
      canPop: !_isSearching,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (_isSearching) {
          setState(() {
            _isSearching = false;
            _searchController.clear();
            _searchQuery = '';
          });
        }
      },
      child: Scaffold(
        backgroundColor: AppColors.mainBackground,
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
                  // Deliberate empty state for a new account:
                  // Exactly one centered empty-state button labelled “Create your first category.”
                  // Zero other create buttons or FABs exist while empty.
                  if (categories.isEmpty) {
                    return EmptyState(
                      icon: Icons.folder_open_rounded,
                      title: 'Your private space starts here',
                      subtitle:
                          'Create your first category to begin organizing and encrypting your private photos.',
                      actionText: 'Create your first category',
                      onAction: _openCreateCategorySheet,
                    );
                  }

                  final filtered = _searchQuery.isEmpty
                      ? categories
                      : categories
                            .where(
                              (c) =>
                                  c.name.toLowerCase().contains(_searchQuery),
                            )
                            .toList();

                  if (filtered.isEmpty && _searchQuery.isNotEmpty) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24.0),
                        child: Text(
                          'No categories found matching "$_searchQuery"',
                          style: AppTypography.bodyMedium.copyWith(
                            color: AppColors.secondaryTextColor,
                          ),
                        ),
                      ),
                    );
                  }

                  return LayoutBuilder(
                    builder: (context, constraints) {
                      final width = constraints.maxWidth;
                      final textScaler = MediaQuery.textScalerOf(context);
                      final isLargeText = textScaler.scale(16) > 22;

                      // Responsive column adaptation:
                      // 2 columns on normal portrait phones
                      // 3 columns on wide screens / tablets (> 620px)
                      // 1 column on narrow width or very large text accessibility mode
                      final int crossAxisCount = (width > 620)
                          ? 3
                          : (width < 320 || isLargeText ? 1 : 2);

                      return RefreshIndicator(
                        color: AppColors.primaryActionBlue,
                        backgroundColor: AppColors.cardSurface,
                        onRefresh: _handleRetry,
                        child: CustomScrollView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          slivers: [
                            // Tidy section heading with exactly one New Category action
                            SliverToBoxAdapter(
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  20,
                                  16,
                                  20,
                                  12,
                                ),
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        const Text(
                                          'Categories',
                                          style: AppTypography.sectionTitle,
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          '${categories.length} ${categories.length == 1 ? 'collection' : 'collections'}',
                                          style: AppTypography.photoCount,
                                        ),
                                      ],
                                    ),
                                    TextButton.icon(
                                      onPressed: _openCreateCategorySheet,
                                      icon: const Icon(
                                        Icons.add_circle_outline_rounded,
                                        size: 18,
                                        color: AppColors.primaryActionBlue,
                                      ),
                                      label: Text(
                                        'New category',
                                        style: AppTypography.labelLarge
                                            .copyWith(
                                              color:
                                                  AppColors.primaryActionBlue,
                                              fontWeight: FontWeight.w600,
                                            ),
                                      ),
                                      style: TextButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 8,
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),

                            // Responsive grid
                            SliverPadding(
                              padding: EdgeInsets.only(
                                left: 20,
                                right: 20,
                                top: 4,
                                // Safe bottom margin ensures floating nav capsule never obscures content
                                bottom:
                                    120 + MediaQuery.paddingOf(context).bottom,
                              ),
                              sliver: SliverGrid(
                                gridDelegate:
                                    SliverGridDelegateWithFixedCrossAxisCount(
                                      crossAxisCount: crossAxisCount,
                                      crossAxisSpacing: 14,
                                      mainAxisSpacing: 14,
                                      childAspectRatio: isLargeText
                                          ? 1.4
                                          : 0.95,
                                    ),
                                delegate: SliverChildBuilderDelegate((
                                  context,
                                  index,
                                ) {
                                  final category = filtered[index];
                                  return PrivoraFadeIn(
                                    delay: Duration(
                                      milliseconds: (index.clamp(0, 8)) * 30,
                                    ),
                                    child: CategoryCard(
                                      category: category,
                                      onTap: () => context.push(
                                        '/category/${category.id}',
                                        extra: category,
                                      ),
                                      onEdit: () => EditCategorySheet.show(
                                        context,
                                        category,
                                      ),
                                      onDelete: () =>
                                          _handleDeleteCategory(category),
                                    ),
                                  );
                                }, childCount: filtered.length),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
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
      ),
    );
  }
}
