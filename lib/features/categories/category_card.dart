import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_motion.dart';
import '../../core/theme/app_typography.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/vault_category.dart';

/// Refined category card displayed in the responsive category grid.
/// Conforms to the design specification:
/// - 20px card radius with subtle decorative border #DCE5F2
/// - Refined folder symbol in a pale category-colour container
/// - Subtle press scale (0.985) via PrivoraPressable
/// - Readable category name, actual photo count, accessible overflow menu
class CategoryCard extends ConsumerStatefulWidget {
  final VaultCategory category;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const CategoryCard({
    super.key,
    required this.category,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  ConsumerState<CategoryCard> createState() => _CategoryCardState();
}

class _CategoryCardState extends ConsumerState<CategoryCard> {
  Uint8List? _coverBytes;
  bool _isLoadingCover = false;

  @override
  void initState() {
    super.initState();
    _loadCoverImage();
  }

  @override
  void didUpdateWidget(CategoryCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.category.coverPhotoId != widget.category.coverPhotoId) {
      _loadCoverImage();
    }
  }

  Future<void> _loadCoverImage() async {
    final coverId = widget.category.coverPhotoId;
    if (coverId == null) return;

    final masterKey = ref.read(vaultRepositoryProvider).activeMasterKey;
    if (masterKey == null) return;

    setState(() => _isLoadingCover = true);

    try {
      final user = ref.read(currentUserProvider);
      if (user == null) return;

      final photo = await ref
          .read(supabaseDatabaseServiceProvider)
          .getPhotoById(coverId, user.id);

      Uint8List bytes;
      if (photo != null) {
        bytes = await ref
            .read(photoRepositoryProvider)
            .loadThumbnail(photo: photo, masterKey: masterKey);
      } else {
        final thumbPath = '${user.id}/thumbnails/$coverId.enc';
        bytes = await ref
            .read(photoRepositoryProvider)
            .loadThumbnail(thumbnailPath: thumbPath, masterKey: masterKey);
      }

      if (mounted) {
        setState(() {
          _coverBytes = bytes;
          _isLoadingCover = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isLoadingCover = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final catColor = widget.category.color;
    final photoCount = widget.category.photoCount;
    final photoCountText =
        '$photoCount ${photoCount == 1 ? 'photo' : 'photos'}';

    return PrivoraPressable(
      onTap: widget.onTap,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.cardSurface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: _coverBytes != null
                ? catColor.withValues(alpha: 0.35)
                : AppColors.borderDivider,
            width: 1.0,
          ),
          boxShadow: [
            BoxShadow(
              color: AppColors.cardShadow,
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Pale category-color accent wash
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    catColor.withValues(alpha: 0.08),
                    AppColors.cardSurface,
                  ],
                ),
              ),
            ),

            // Decrypted cover photo thumbnail with fade-in
            if (_coverBytes != null)
              Positioned.fill(
                child: TweenAnimationBuilder<double>(
                  tween: Tween<double>(begin: 0.0, end: 1.0),
                  duration: AppMotion.thumbnailFadeDuration,
                  curve: AppMotion.standardCurve,
                  builder: (context, opacity, child) {
                    return Opacity(
                      opacity: opacity,
                      child: Image.memory(_coverBytes!, fit: BoxFit.cover),
                    );
                  },
                ),
              )
            else if (_isLoadingCover)
              const Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      AppColors.primaryActionBlue,
                    ),
                  ),
                ),
              )
            else
              // Refined folder symbol in a pale category-colored container
              Center(
                child: Container(
                  width: 54,
                  height: 54,
                  decoration: BoxDecoration(
                    color: catColor.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: catColor.withValues(alpha: 0.25),
                      width: 1.0,
                    ),
                  ),
                  child: Center(
                    child: Icon(
                      Icons.folder_rounded,
                      size: 28,
                      color: catColor,
                    ),
                  ),
                ),
              ),

            // Subtle darkener only over cover photo to protect text contrast
            if (_coverBytes != null)
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.15),
                        Colors.black.withValues(alpha: 0.80),
                      ],
                      stops: const [0.3, 1.0],
                    ),
                  ),
                ),
              ),

            // Category color top accent line
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: 3.5,
              child: Container(color: catColor),
            ),

            // Accessible 3-dots overflow menu
            Positioned(
              top: 6,
              right: 4,
              child: Semantics(
                button: true,
                label: 'Category options for ${widget.category.name}',
                child: SizedBox(
                  width: 44,
                  height: 44,
                  child: PopupMenuButton<String>(
                    tooltip: 'Category options',
                    padding: EdgeInsets.zero,
                    icon: Icon(
                      Icons.more_vert_rounded,
                      size: 20,
                      color: _coverBytes != null
                          ? Colors.white
                          : AppColors.secondaryTextColor,
                    ),
                    color: AppColors.cardSurface,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: const BorderSide(color: AppColors.borderDivider),
                    ),
                    elevation: 4,
                    onSelected: (val) {
                      if (val == 'edit') widget.onEdit();
                      if (val == 'delete') widget.onDelete();
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem(
                        value: 'edit',
                        child: Row(
                          children: [
                            Icon(
                              Icons.edit_outlined,
                              size: 18,
                              color: AppColors.primaryText,
                            ),
                            SizedBox(width: 10),
                            Text(
                              'Edit Category',
                              style: AppTypography.bodyMedium,
                            ),
                          ],
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'delete',
                        child: Row(
                          children: [
                            Icon(
                              Icons.delete_outline_rounded,
                              size: 18,
                              color: AppColors.errorDestructive,
                            ),
                            SizedBox(width: 10),
                            Text(
                              'Delete Category',
                              style: TextStyle(
                                color: AppColors.errorDestructive,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // Bottom metadata container: Name & actual photo count
            Positioned(
              left: 14,
              right: 14,
              bottom: 12,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.category.name,
                    style: AppTypography.categoryName.copyWith(
                      color: _coverBytes != null
                          ? Colors.white
                          : AppColors.primaryText,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Text(
                        photoCountText,
                        style: AppTypography.photoCount.copyWith(
                          color: _coverBytes != null
                              ? Colors.white.withValues(alpha: 0.85)
                              : AppColors.secondaryTextColor,
                        ),
                      ),
                      if (widget.category.latestPhotoDate != null) ...[
                        const SizedBox(width: 6),
                        Text(
                          '•',
                          style: TextStyle(
                            color: _coverBytes != null
                                ? Colors.white70
                                : AppColors.secondaryTextColor,
                            fontSize: 10,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            Formatters.formatDate(
                              widget.category.latestPhotoDate!,
                            ),
                            style: AppTypography.bodySmall.copyWith(
                              color: _coverBytes != null
                                  ? Colors.white70
                                  : AppColors.secondaryTextColor,
                              fontSize: 11,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
