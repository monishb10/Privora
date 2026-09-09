import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/utils/validators.dart';
import '../../core/widgets/confirmation_dialog.dart';
import '../../core/widgets/privora_button.dart';
import '../../data/models/vault_category.dart';

/// Modal bottom sheet for updating an existing category name and color.
/// Conforms to design specification:
/// - 28px top corners on crisp white surface
/// - Subtle drag handle, descriptive labels, properly spaced name field
/// - Accessible color swatches with both check and outline indicators
/// - Fully reachable with keyboard open; useRootNavigator: true to disable background navigation
class EditCategorySheet extends ConsumerStatefulWidget {
  final VaultCategory category;

  const EditCategorySheet({super.key, required this.category});

  static Future<bool?> show(BuildContext context, VaultCategory category) {
    return showModalBottomSheet<bool>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      barrierColor: Colors.black54,
      backgroundColor: Colors.transparent,
      builder: (context) => EditCategorySheet(category: category),
    );
  }

  @override
  ConsumerState<EditCategorySheet> createState() => _EditCategorySheetState();
}

class _EditCategorySheetState extends ConsumerState<EditCategorySheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late Color _selectedColor;
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.category.name);
    _selectedColor = widget.category.color;
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _handleSave() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final updated = widget.category.copyWith(
        name: _nameController.text.trim(),
        colorValue: _selectedColor.toARGB32(),
        updatedAt: DateTime.now(),
      );

      final categoryRepo = ref.read(categoryRepositoryProvider);
      await categoryRepo.updateCategory(updated);

      // Invalidate categories list
      ref.invalidate(categoriesProvider);

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.toString().replaceFirst('Exception: ', '');
        _isLoading = false;
      });
    }
  }

  bool get _isDirty =>
      _nameController.text.trim() != widget.category.name ||
      _selectedColor.toARGB32() != widget.category.color.toARGB32();

  Future<void> _handleCancel() async {
    if (_isLoading) return;
    if (_isDirty) {
      final confirmed = await ConfirmationDialog.show(
        context: context,
        title: 'Discard Changes?',
        message:
            'You have unsaved changes. Are you sure you want to discard them?',
        confirmText: 'Discard',
        cancelText: 'Keep Editing',
        isDestructive: true,
      );
      if (confirmed == true && mounted) {
        Navigator.of(context).pop(false);
      }
    } else {
      Navigator.of(context).pop(false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return PopScope(
      canPop: !_isDirty && !_isLoading,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        await _handleCancel();
      },
      child: Container(
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
                  // Subtle handle
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
                  const Text(
                    'Edit Category',
                    style: AppTypography.sectionTitle,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Update the collection name and accent color.',
                    style: AppTypography.bodySmall,
                  ),
                  const SizedBox(height: 20),

                  if (_errorMessage != null) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.errorDestructive.withValues(
                          alpha: 0.08,
                        ),
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

                  // Properly spaced category name field
                  TextFormField(
                    controller: _nameController,
                    textCapitalization: TextCapitalization.words,
                    style: AppTypography.bodyLarge,
                    decoration: const InputDecoration(
                      labelText: 'Category Name',
                      hintText: 'Enter category name',
                      prefixIcon: Icon(
                        Icons.folder_outlined,
                        color: AppColors.secondaryTextColor,
                      ),
                    ),
                    validator: Validators.validateCategoryName,
                  ),
                  const SizedBox(height: 22),

                  const Text(
                    'Category Color',
                    style: AppTypography.labelMedium,
                  ),
                  const SizedBox(height: 12),
                  // Accessible color swatches with both check AND outline indicators
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

                  // Reachable action buttons with consistent hierarchy
                  Row(
                    children: [
                      Expanded(
                        child: PrivoraButton(
                          text: 'Cancel',
                          variant: PrivoraButtonVariant.secondary,
                          onPressed: _isLoading ? null : _handleCancel,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: PrivoraButton(
                          text: 'Save Changes',
                          variant: PrivoraButtonVariant.primary,
                          isLoading: _isLoading,
                          onPressed: _isLoading ? null : _handleSave,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
