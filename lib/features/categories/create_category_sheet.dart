import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../app/providers.dart';
import '../../core/config/supabase_config.dart';
import '../../core/errors/app_exception.dart';
import '../../core/errors/error_mapper.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/utils/validators.dart';
import '../../core/widgets/privora_button.dart';

/// Modal bottom sheet for creating a new custom category.
class CreateCategorySheet extends ConsumerStatefulWidget {
  const CreateCategorySheet({super.key});

  static Future<bool?> show(BuildContext context) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
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
    final authUser = ref.read(currentUserProvider) ??
        (SupabaseConfig.isInitialized
            ? Supabase.instance.client.auth.currentUser
            : null);

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

    try {
      final categoryRepo = ref.read(categoryRepositoryProvider);
      await categoryRepo.createCategory(
        userId: authUser.id,
        name: _nameController.text.trim(),
        colorValue: _selectedColor.toARGB32(),
      );

      // Local state is already updated in categoryRepo.
      // Refresh local provider immediately so UI reflects the newly added category.
      ref.invalidate(categoriesProvider);

      if (!mounted) return;

      final messenger = ScaffoldMessenger.of(context);
      Navigator.of(context).pop(true);
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Category created'),
          duration: Duration(seconds: 2),
        ),
      );

      // Refresh categories silently in the background afterward
      unawaited(
        categoryRepo.getCategories(authUser.id, forceRefresh: true).then((_) {
          ref.invalidate(categoriesProvider);
        }).catchError((err) {
          debugPrint('Background category refresh error: $err');
        }),
      );
    } on TimeoutException catch (e) {
      debugPrint('createCategory TimeoutException: $e');
      if (mounted) {
        setState(() {
          _errorMessage =
              'Request timed out. Please check your network connection.';
        });
      }
    } on PostgrestException catch (e) {
      debugPrint(
        'createCategory PostgrestException: code=${e.code}, message=${e.message}, details=${e.details}, hint=${e.hint}',
      );
      if (mounted) {
        setState(() {
          _errorMessage = ErrorMapper.mapToUserMessage(e);
        });
      }
    } on AppException catch (e) {
      debugPrint('createCategory AppException: ${e.message}');
      if (mounted) {
        setState(() {
          _errorMessage = e.message;
        });
      }
    } catch (e) {
      debugPrint('createCategory error: $e');
      if (mounted) {
        setState(() {
          _errorMessage = ErrorMapper.mapToUserMessage(e);
        });
      }
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

    return Padding(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 20,
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
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            const Text('New Category', style: AppTypography.titleLarge),
            const SizedBox(height: 6),
            const Text(
              'Create a private collection to organize your encrypted moments.',
              style: AppTypography.bodySmall,
            ),
            const SizedBox(height: 20),

            if (_errorMessage != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.danger.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: AppColors.danger.withValues(alpha: 0.4),
                  ),
                ),
                child: Text(
                  _errorMessage!,
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.danger,
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
                  color: AppColors.secondaryText,
                ),
              ),
              validator: Validators.validateCategoryName,
            ),
            const SizedBox(height: 20),

            const Text('Category Color', style: AppTypography.labelMedium),
            const SizedBox(height: 12),
            SizedBox(
              height: 44,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: AppColors.categoryPalette.length,
                separatorBuilder: (context, index) => const SizedBox(width: 12),
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
                              ? AppColors.mainText
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

            PrivoraButton(
              text: 'Create Category',
              isLoading: _isLoading,
              onPressed: _handleCreate,
            ),
          ],
        ),
      ),
    );
  }
}
