import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/providers.dart';
import '../../core/config/supabase_config.dart';
import '../../core/errors/error_mapper.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/utils/validators.dart';
import '../../core/widgets/privora_button.dart';

/// Modal bottom sheet for creating a new custom photo category.
/// Uses useRootNavigator: true to render above the application shell and floating navigation.
class CreateCategorySheet extends ConsumerStatefulWidget {
  const CreateCategorySheet({super.key});

  static Future<bool?> show(BuildContext context) {
    return showModalBottomSheet<bool>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      barrierColor: Colors.black54,
      backgroundColor: Colors.transparent,
      builder: (context) => const CreateCategorySheet(),
    );
  }

  @override
  ConsumerState<CreateCategorySheet> createState() =>
      _CreateCategorySheetState();
}

class _CreateCategorySheetState extends ConsumerState<CreateCategorySheet> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  Color _selectedColor = AppColors.categoryPalette.first;
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _handleCreate() async {
    // Prevent multiple insert requests when button is tapped repeatedly
    if (_isLoading) return;

    if (!_formKey.currentState!.validate()) return;

    // Verify valid Supabase authenticated user before starting request
    final authUser =
        ref.read(currentUserProvider) ??
        SupabaseConfig.client?.auth.currentUser;

    if (authUser == null || authUser.id.isEmpty) {
      setState(() {
        _errorMessage = 'Session expired. Please sign in again.';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final newCategoryName = _nameController.text.trim();
    final newColor = _selectedColor;

    try {
      final categoryRepo = ref.read(categoryRepositoryProvider);

      // Create new category in remote database (times out after 10s if network hangs)
      final createdCategory = await categoryRepo
          .createCategory(
            name: newCategoryName,
            userId: authUser.id,
            colorValue: newColor.toARGB32(),
          )
          .timeout(const Duration(seconds: 10));

      // Synchronously insert new category into local cache
      ref.read(categoryRepositoryProvider).addCategoryLocally(createdCategory);

      // Invalidate category provider to trigger UI updates
      ref.invalidate(categoriesProvider);

      if (!mounted) return;

      // Close modal sheet and return success
      Navigator.of(context).pop(true);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Category created'),
          duration: Duration(seconds: 3),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = ErrorMapper.mapToUserMessage(e);
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: EdgeInsets.only(
            left: 24,
            right: 24,
            top: 16,
            bottom: 24 + bottomInset,
          ),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 38,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.borderDivider,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                const Text('New Category', style: AppTypography.titleLarge),
                const SizedBox(height: 6),
                Text(
                  'Create a private collection to organize your encrypted moments.',
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.secondaryTextColor,
                  ),
                ),
                const SizedBox(height: 20),

                if (_errorMessage != null) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.errorDestructive.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: AppColors.errorDestructive.withValues(
                          alpha: 0.4,
                        ),
                      ),
                    ),
                    child: Text(
                      _errorMessage!,
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.errorDestructive,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                TextFormField(
                  controller: _nameController,
                  autofocus: true,
                  textCapitalization: TextCapitalization.words,
                  style: AppTypography.bodyLarge,
                  decoration: const InputDecoration(
                    labelText: 'Category Name',
                    hintText: 'e.g. Travel, Personal, Documents',
                    prefixIcon: Icon(
                      Icons.folder_outlined,
                      color: AppColors.secondaryTextColor,
                    ),
                  ),
                  validator: Validators.validateCategoryName,
                ),
                const SizedBox(height: 20),

                const Text('Category Color', style: AppTypography.labelMedium),
                const SizedBox(height: 12),
                SizedBox(
                  height: 46,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: AppColors.categoryPalette.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(width: 12),
                    itemBuilder: (context, index) {
                      final color = AppColors.categoryPalette[index];
                      final isSelected =
                          color.toARGB32() == _selectedColor.toARGB32();

                      return GestureDetector(
                        onTap: () => setState(() => _selectedColor = color),
                        child: Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: color,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: isSelected
                                  ? AppColors.primaryTextColor
                                  : Colors.transparent,
                              width: 3,
                            ),
                            boxShadow: isSelected
                                ? [
                                    BoxShadow(
                                      color: color.withValues(alpha: 0.5),
                                      blurRadius: 8,
                                      spreadRadius: 2,
                                    ),
                                  ]
                                : null,
                          ),
                          child: isSelected
                              ? const Icon(
                                  Icons.check_rounded,
                                  color: Colors.black87,
                                  size: 22,
                                )
                              : null,
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 28),

                Row(
                  children: [
                    Expanded(
                      child: PrivoraButton(
                        text: 'Cancel',
                        variant: PrivoraButtonVariant.secondary,
                        onPressed: _isLoading
                            ? null
                            : () => Navigator.of(context).pop(false),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: PrivoraButton(
                        text: 'Create Category',
                        variant: PrivoraButtonVariant.primary,
                        isLoading: _isLoading,
                        onPressed: _isLoading ? null : _handleCreate,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
