import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:photo_view/photo_view.dart';
import 'package:share_plus/share_plus.dart';
import '../../app/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/confirmation_dialog.dart';
import '../../data/models/vault_photo.dart';
import 'move_photo_sheet.dart';
import 'photo_details_sheet.dart';

/// Full-screen photo viewer supporting pinch-to-zoom, swiping, export, share, move, and deletion.
/// Decrypts image bytes strictly in RAM.
class PhotoViewerScreen extends ConsumerStatefulWidget {
  final List<VaultPhoto> photos;
  final int initialIndex;
  final String categoryId;

  const PhotoViewerScreen({
    super.key,
    required this.photos,
    required this.initialIndex,
    required this.categoryId,
  });

  @override
  ConsumerState<PhotoViewerScreen> createState() => _PhotoViewerScreenState();
}

class _PhotoViewerScreenState extends ConsumerState<PhotoViewerScreen> {
  late PageController _pageController;
  late int _currentIndex;
  late List<VaultPhoto> _photos;
  bool _showUi = true;

  @override
  void initState() {
    super.initState();
    _photos = List.from(widget.photos);
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  VaultPhoto get _currentPhoto => _photos[_currentIndex];

  Future<void> _handleShare() async {
    final confirmed = await ConfirmationDialog.show(
      context: context,
      title: 'Share Encrypted Photo',
      message:
          'This photo will temporarily leave Privora in decrypted form for the system share dialog. The decrypted temporary file is deleted immediately after use.',
      confirmText: 'Share Photo',
      icon: Icons.share_rounded,
    );

    if (confirmed == true && mounted) {
      final masterKey = ref.read(vaultRepositoryProvider).activeMasterKey;
      if (masterKey == null) return;

      final photoRepo = ref.read(photoRepositoryProvider);
      final cleaner = ref.read(temporaryFileCleanerProvider);

      try {
        final tempFile = await photoRepo.preparePhotoForExportOrShare(
          photo: _currentPhoto,
          masterKey: masterKey,
        );

        // ignore: deprecated_member_use
        await Share.shareXFiles([
          XFile(
            tempFile.path,
            mimeType: _currentPhoto.mimeType,
            name: _currentPhoto.displayName,
          ),
        ], text: 'Shared from Privora');

        // Delete temporary file immediately
        await cleaner.deleteSingleFile(tempFile.path);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to prepare photo: $e')),
          );
        }
      }
    }
  }

  Future<void> _handleDelete() async {
    final confirmed = await ConfirmationDialog.show(
      context: context,
      title: 'Move to Recently Deleted?',
      message:
          'This photo will be moved to Recently Deleted and kept for 30 days before permanent removal.',
      confirmText: 'Move to Trash',
      isDestructive: true,
      icon: Icons.delete_outline_rounded,
    );

    if (confirmed == true && mounted) {
      final user = ref.read(currentUserProvider);
      if (user == null) return;

      final photoId = _currentPhoto.id;
      await ref.read(photoRepositoryProvider).softDeletePhoto(photoId, user.id);
      ref.invalidate(recentlyDeletedPhotosProvider);

      setState(() {
        _photos.removeAt(_currentIndex);
        if (_photos.isEmpty) {
          Navigator.of(context).pop(true);
        } else {
          if (_currentIndex >= _photos.length) {
            _currentIndex = _photos.length - 1;
          }
        }
      });
    }
  }

  Future<void> _handleRename() async {
    final controller = TextEditingController(text: _currentPhoto.displayName);
    final newName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Rename Photo', style: AppTypography.titleLarge),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: AppTypography.bodyLarge,
          decoration: const InputDecoration(labelText: 'File Name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (newName != null && newName.isNotEmpty && mounted) {
      await ref
          .read(photoRepositoryProvider)
          .renamePhoto(_currentPhoto, newName);
      setState(() {
        _photos[_currentIndex] = _currentPhoto.copyWith(displayName: newName);
      });
    }
  }

  Future<void> _handleSetAsCover() async {
    final user = ref.read(currentUserProvider);
    if (user == null) return;

    await ref
        .read(categoryRepositoryProvider)
        .setCoverPhoto(widget.categoryId, user.id, _currentPhoto.id);

    ref.invalidate(categoriesProvider);

    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Category cover updated.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final masterKey = ref.watch(vaultRepositoryProvider).activeMasterKey;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Photo PageView with Pinch-to-Zoom
          GestureDetector(
            onTap: () => setState(() => _showUi = !_showUi),
            child: PageView.builder(
              controller: _pageController,
              itemCount: _photos.length,
              onPageChanged: (index) => setState(() => _currentIndex = index),
              itemBuilder: (context, index) {
                final photo = _photos[index];
                if (masterKey == null) {
                  return const Center(
                    child: Text(
                      'Session locked.',
                      style: TextStyle(color: Colors.white),
                    ),
                  );
                }

                return FutureBuilder<Uint8List>(
                  future: ref
                      .read(photoRepositoryProvider)
                      .loadFullPhoto(photo: photo, masterKey: masterKey),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(
                        child: CircularProgressIndicator(
                          valueColor: AlwaysStoppedAnimation<Color>(
                            AppColors.primaryAccent,
                          ),
                        ),
                      );
                    }

                    if (snapshot.hasError || !snapshot.hasData) {
                      return Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.broken_image_rounded,
                              size: 48,
                              color: AppColors.danger,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'Failed to decrypt photo',
                              style: AppTypography.bodySmall.copyWith(
                                color: AppColors.secondaryText,
                              ),
                            ),
                          ],
                        ),
                      );
                    }

                    return PhotoView(
                      imageProvider: MemoryImage(snapshot.data!),
                      minScale: PhotoViewComputedScale.contained,
                      maxScale: PhotoViewComputedScale.covered * 3.0,
                      backgroundDecoration: const BoxDecoration(
                        color: Colors.black,
                      ),
                    );
                  },
                );
              },
            ),
          ),

          // Top Navigation Bar
          if (_showUi)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: EdgeInsets.only(
                  top: MediaQuery.of(context).padding.top + 8,
                  left: 8,
                  right: 8,
                  bottom: 12,
                ),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.black87, Colors.transparent],
                  ),
                ),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(
                        Icons.arrow_back_ios_new_rounded,
                        color: Colors.white,
                        size: 20,
                      ),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _currentPhoto.displayName,
                            style: AppTypography.titleMedium.copyWith(
                              color: Colors.white,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            '${_currentIndex + 1} of ${_photos.length}',
                            style: AppTypography.labelSmall.copyWith(
                              color: AppColors.secondaryText,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(
                        Icons.info_outline_rounded,
                        color: Colors.white,
                      ),
                      onPressed: () => PhotoDetailsSheet.show(
                        context: context,
                        photo: _currentPhoto,
                        onRenameRequested: _handleRename,
                        onSetCoverRequested: _handleSetAsCover,
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // Bottom Action Bar
          if (_showUi)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: EdgeInsets.only(
                  bottom: MediaQuery.of(context).padding.bottom + 12,
                  top: 16,
                  left: 24,
                  right: 24,
                ),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [Colors.black87, Colors.transparent],
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    IconButton(
                      icon: const Icon(
                        Icons.share_outlined,
                        color: Colors.white,
                      ),
                      tooltip: 'Share',
                      onPressed: _handleShare,
                    ),
                    IconButton(
                      icon: const Icon(
                        Icons.drive_file_move_outlined,
                        color: Colors.white,
                      ),
                      tooltip: 'Move Category',
                      onPressed: () async {
                        final nav = Navigator.of(context);
                        final moved = await MovePhotoSheet.show(
                          context: context,
                          currentCategoryId: widget.categoryId,
                          photoIds: [_currentPhoto.id],
                        );
                        if (moved == true && mounted) {
                          nav.pop(true);
                        }
                      },
                    ),
                    IconButton(
                      icon: const Icon(
                        Icons.delete_outline_rounded,
                        color: AppColors.danger,
                      ),
                      tooltip: 'Move to Trash',
                      onPressed: _handleDelete,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
