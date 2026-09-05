import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';

/// Modal bottom sheet allowing users to move photo(s) to another category.
class MovePhotoSheet extends ConsumerWidget {
  final String currentCategoryId;
  final List<String> photoIds;

  const MovePhotoSheet({
    super.key,
    required this.currentCategoryId,
    required this.photoIds,
  });

  static Future<bool?> show({
    required BuildContext context,
    required String currentCategoryId,
    required List<String> photoIds,
  }) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      builder: (context) => MovePhotoSheet(
        currentCategoryId: currentCategoryId,
        photoIds: photoIds,
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categoriesAsync = ref.watch(categoriesProvider);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
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
          Text(
            photoIds.length == 1
                ? 'Move Photo'
                : 'Move ${photoIds.length} Photos',
            style: AppTypography.titleLarge,
          ),
          const SizedBox(height: 6),
          const Text(
            'Select the destination category.',
            style: AppTypography.bodySmall,
          ),
          const SizedBox(height: 16),
          categoriesAsync.when(
            data: (categories) {
              final destinationCategories = categories
                  .where((c) => c.id != currentCategoryId)
                  .toList();

              if (destinationCategories.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: Text(
                      'No other categories available. Create another category first.',
                      style: AppTypography.bodyMedium,
                      textAlign: TextAlign.center,
                    ),
                  ),
                );
              }

              return ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: destinationCategories.length,
                separatorBuilder: (context, index) => const Divider(),
                itemBuilder: (context, index) {
                  final cat = destinationCategories[index];
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: cat.color.withValues(alpha: 0.2),
                        shape: BoxShape.circle,
                        border: Border.all(color: cat.color),
                      ),
                      child: Icon(
                        Icons.folder_outlined,
                        color: cat.color,
                        size: 20,
                      ),
                    ),
                    title: Text(cat.name, style: AppTypography.bodyLarge),
                    trailing: const Icon(
                      Icons.arrow_forward_ios_rounded,
                      size: 14,
                      color: AppColors.secondaryText,
                    ),
                    onTap: () async {
                      final user = ref.read(currentUserProvider);
                      if (user == null) return;

                      final photoRepo = ref.read(photoRepositoryProvider);
                      for (final id in photoIds) {
                        await photoRepo.movePhoto(id, user.id, cat.id);
                      }

                      ref.invalidate(categoriesProvider);

                      if (context.mounted) {
                        Navigator.of(context).pop(true);
                      }
                    },
                  );
                },
              );
            },
            loading: () => const Center(
              child: Padding(
                padding: EdgeInsets.all(24.0),
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(
                    AppColors.primaryAccent,
                  ),
                ),
              ),
            ),
            error: (err, _) => Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text(
                err.toString(),
                style: const TextStyle(color: AppColors.danger),
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}
