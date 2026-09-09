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
/// Conforms to design specification:
/// - 28px top corners on crisp white surface
/// - Subtle drag handle, descriptive labels, properly spaced name field
/// - Accessible color swatches with both check and outline indicators
/// - Fully reachable with keyboard open; useRootNavigator: true to disable background navigation
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
    if (_isLoading) return;
    if (!_formKey.currentState!.validate()) return;

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

      final createdCategory = await categoryRepo
          .createCategory(
            name: newCategoryName,
            userId: authUser.id,
            colorValue: newColor.toARGB32(),
          )
          .timeout(const Duration(seconds: 10));

      ref.read(categoryRepositoryProvider).addCategoryLocally(createdCategory);
      ref.invalidate(categoriesProvider);

      if (!mounted) return;
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
      decoration: const BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 14,
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
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.borderDivider,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                const Text('New Category', style: AppTypography.sectionTitle),
                const SizedBox(height: 4),
                Text(
                  'Create a private collection to organize your encrypted moments.',
                  style: AppTypography.bodySmall,
                ),
                const SizedBox(height: 20),

                if (_errorMessage != null) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.errorDestructive.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: AppColors.errorDestructive.withValues(
                          alpha: 0.3,
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
                    hintText: 'e.g. Personal, Trips, Documents',
                    prefixIcon: Icon(
                      Icons.folder_outlined,
                      color: AppColors.secondaryTextColor,
                    ),
                  ),
                  validator: Validators.validateCategoryName,
                ),
                const SizedBox(height: 22),

                const Text('Category Color', style: AppTypography.labelMedium),
                const SizedBox(height: 12),
                SizedBox(
                  height: 48,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: AppColors.categoryPalette.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(width: 10),
                    itemBuilder: (context, index) {
                      final color = AppColors.categoryPalette[index];
                      final isSelected =
                          color.toARGB32() == _selectedColor.toARGB32();

                      return Semantics(
                        button: true,
                        selected: isSelected,
                        label: 'Color swatch ${index + 1}',
                        child: GestureDetector(
                          onTap: () => setState(() => _selectedColor = color),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: color,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: isSelected
                                    ? AppColors.primaryText
                                    : AppColors.borderDivider,
                                width: isSelected ? 2.5 : 1.0,
                              ),
                              boxShadow: isSelected
                                  ? [
                                      BoxShadow(
                                        color: color.withValues(alpha: 0.45),
                                        blurRadius: 8,
                                        offset: const Offset(0, 2),
                                      ),
                                    ]
                                  : null,
                            ),
                            child: isSelected
                                ? const Center(
                                    child: Icon(
                                      Icons.check_rounded,
                                      color: Colors.white,
                                      size: 22,
                                    ),
                                  )
                                : null,
                          ),
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
