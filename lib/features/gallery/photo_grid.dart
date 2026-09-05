import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../data/models/vault_photo.dart';
import 'photo_viewer_screen.dart';

/// Photo grid component supporting multi-select, memory decryption, and responsive thumbnail display.
class PhotoGrid extends ConsumerWidget {
  final List<VaultPhoto> photos;
  final String categoryId;
  final bool isSelectionMode;
  final Set<String> selectedPhotoIds;
  final ValueChanged<String> onToggleSelect;
  final VoidCallback onPhotoDeletedOrMoved;

  const PhotoGrid({
    super.key,
    required this.photos,
    required this.categoryId,
    this.isSelectionMode = false,
    required this.selectedPhotoIds,
    required this.onToggleSelect,
    required this.onPhotoDeletedOrMoved,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final masterKey = ref.watch(vaultRepositoryProvider).activeMasterKey;

    return GridView.builder(
      padding: const EdgeInsets.all(4),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 4,
        mainAxisSpacing: 4,
      ),
      itemCount: photos.length,
      itemBuilder: (context, index) {
        final photo = photos[index];
        final isSelected = selectedPhotoIds.contains(photo.id);

        return GestureDetector(
          onTap: () {
            if (isSelectionMode) {
              onToggleSelect(photo.id);
            } else {
              Navigator.of(context)
                  .push(
                    MaterialPageRoute(
                      builder: (context) => PhotoViewerScreen(
                        photos: photos,
                        initialIndex: index,
                        categoryId: categoryId,
                      ),
                    ),
                  )
                  .then((result) {
                    if (result == true) {
                      onPhotoDeletedOrMoved();
                    }
                  });
            }
          },
          onLongPress: () {
            if (!isSelectionMode) {
              onToggleSelect(photo.id);
            }
          },
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Memory decrypted thumbnail
              Container(
                color: AppColors.elevatedSurface,
                child: masterKey == null
                    ? const SizedBox()
                    : _EncryptedThumbnailTile(
                        thumbnailPath: photo.thumbnailPath,
                        masterKey: masterKey,
                      ),
              ),

              // Selection overlay
              if (isSelectionMode)
                Container(
                  color: isSelected
                      ? AppColors.primaryAccent.withValues(alpha: 0.3)
                      : Colors.black26,
                  padding: const EdgeInsets.all(6),
                  alignment: Alignment.topRight,
                  child: Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isSelected
                          ? AppColors.primaryAccent
                          : Colors.black45,
                      border: Border.all(
                        color: isSelected
                            ? AppColors.primaryAccent
                            : Colors.white,
                        width: 2,
                      ),
                    ),
                    child: isSelected
                        ? const Icon(
                            Icons.check,
                            size: 16,
                            color: AppColors.background,
                          )
                        : null,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _EncryptedThumbnailTile extends ConsumerWidget {
  final String thumbnailPath;
  final Uint8List masterKey;

  const _EncryptedThumbnailTile({
    required this.thumbnailPath,
    required this.masterKey,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FutureBuilder<Uint8List>(
      future: ref
          .read(photoRepositoryProvider)
          .loadThumbnail(thumbnailPath: thumbnailPath, masterKey: masterKey),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(
                  AppColors.primaryAccent,
                ),
              ),
            ),
          );
        }

        if (snapshot.hasError || !snapshot.hasData) {
          return const Center(
            child: Icon(
              Icons.broken_image_rounded,
              size: 24,
              color: AppColors.secondaryText,
            ),
          );
        }

        return Image.memory(snapshot.data!, fit: BoxFit.cover);
      },
    );
  }
}
