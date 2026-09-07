import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/vault_category.dart';

/// Polished category card displayed in the 2-column grid.
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

      // Thumbnail path: {userId}/thumbnails/{coverId}.enc
      final thumbPath = '${user.id}/thumbnails/$coverId.enc';
      final bytes = await ref
          .read(photoRepositoryProvider)
          .loadThumbnail(thumbnailPath: thumbPath, masterKey: masterKey);

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

    return Card(
      clipBehavior: Clip.antiAlias,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          color: _coverBytes != null
              ? catColor.withValues(alpha: 0.35)
              : AppColors.borderDivider,
          width: 1.2,
        ),
      ),
      child: InkWell(
        onTap: widget.onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.cardSurface,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [catColor.withValues(alpha: 0.12), AppColors.cardSurface],
            ),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Cover image if decrypted
              if (_coverBytes != null)
                Positioned.fill(
                  child: Image.memory(_coverBytes!, fit: BoxFit.cover),
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
                Center(
                  child: Icon(
                    Icons.folder_rounded,
                    size: 46,
                    color: catColor.withValues(alpha: 0.75),
                  ),
                ),

              // Gradient darkener only over cover image so text is readable
              if (_coverBytes != null)
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withValues(alpha: 0.25),
                          Colors.black.withValues(alpha: 0.85),
                        ],
                      ),
                    ),
                  ),
                ),

              // Category color indicator bar at top
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: 4,
                child: Container(color: catColor),
              ),

              // 3-dots popup menu at top right
              Positioned(
                top: 6,
                right: 4,
                child: PopupMenuButton<String>(
                  icon: Icon(
                    Icons.more_vert_rounded,
                    size: 20,
                    color: _coverBytes != null
                        ? Colors.white
                        : AppColors.primaryText,
                  ),
                  color: AppColors.cardSurface,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                    side: const BorderSide(color: AppColors.borderDivider),
                  ),
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
                            color: AppColors.mainText,
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
                            color: AppColors.danger,
                          ),
                          SizedBox(width: 10),
                          Text(
                            'Delete Category',
                            style: TextStyle(color: AppColors.danger),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // Content at bottom: Name, photo count, date
              Positioned(
                left: 14,
                right: 14,
                bottom: 14,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.category.name,
                      style: AppTypography.titleMedium.copyWith(
                        color: _coverBytes != null
                            ? Colors.white
                            : AppColors.primaryText,
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Text(
                          '${widget.category.photoCount} ${widget.category.photoCount == 1 ? 'photo' : 'photos'}',
                          style: AppTypography.bodySmall.copyWith(
                            color: _coverBytes != null
                                ? Colors.white70
                                : AppColors.secondaryTextColor,
                            fontWeight: FontWeight.w500,
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
      ),
    );
  }
}
