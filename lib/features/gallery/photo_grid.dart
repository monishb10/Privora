import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_motion.dart';
import '../../data/models/vault_photo.dart';
import 'photo_viewer_screen.dart';

/// Clean photo grid component with consistent crops, restrained rounding,
/// clear selection indicators, and thumbnail fade-in transitions.
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
      padding: const EdgeInsets.all(8),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 6,
        mainAxisSpacing: 6,
      ),
      itemCount: photos.length,
      itemBuilder: (context, index) {
        final photo = photos[index];
        final isSelected = selectedPhotoIds.contains(photo.id);

        return ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: GestureDetector(
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
                // Decrypted thumbnail tile
                Container(
                  color: AppColors.softBlueSurface,
                  child: masterKey == null
                      ? const SizedBox()
                      : _EncryptedThumbnailTile(
                          photo: photo,
                          masterKey: masterKey,
                        ),
                ),

                // Clear selection overlay & checkmark
                if (isSelectionMode)
                  AnimatedContainer(
                    duration: AppMotion.pressDuration,
                    color: isSelected
                        ? AppColors.primaryActionBlue.withValues(alpha: 0.28)
                        : Colors.black.withValues(alpha: 0.15),
                    padding: const EdgeInsets.all(6),
                    alignment: Alignment.topRight,
                    child: AnimatedContainer(
                      duration: AppMotion.pinIndicatorDuration,
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isSelected
                            ? AppColors.primaryActionBlue
                            : Colors.black.withValues(alpha: 0.35),
                        border: Border.all(
                          color: isSelected
                              ? AppColors.cardSurface
                              : Colors.white.withValues(alpha: 0.8),
                          width: 1.8,
                        ),
                        boxShadow: isSelected
                            ? [
                                BoxShadow(
                                  color: AppColors.primaryActionBlue.withValues(
                                    alpha: 0.35,
                                  ),
                                  blurRadius: 6,
                                  offset: const Offset(0, 1),
                                ),
                              ]
                            : null,
                      ),
                      child: isSelected
                          ? const Icon(
                              Icons.check_rounded,
                              size: 15,
                              color: Colors.white,
                            )
                          : null,
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _EncryptedThumbnailTile extends ConsumerWidget {
  final VaultPhoto photo;
  final Uint8List masterKey;

  const _EncryptedThumbnailTile({required this.photo, required this.masterKey});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FutureBuilder<Uint8List>(
      future: ref
          .read(photoRepositoryProvider)
          .loadThumbnail(photo: photo, masterKey: masterKey),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(
                  AppColors.primaryActionBlue,
                ),
              ),
            ),
          );
        }

        if (snapshot.hasError || !snapshot.hasData) {
          return const Center(
            child: Icon(
              Icons.broken_image_outlined,
              size: 24,
              color: AppColors.secondaryTextColor,
            ),
          );
        }

        // Thumbnail fade-in over 140ms
        return TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: 0.0, end: 1.0),
          duration: AppMotion.thumbnailFadeDuration,
          curve: AppMotion.standardCurve,
          builder: (context, opacity, child) {
            return Opacity(
              opacity: opacity,
              child: Image.memory(snapshot.data!, fit: BoxFit.cover),
            );
          },
        );
      },
    );
  }
}
