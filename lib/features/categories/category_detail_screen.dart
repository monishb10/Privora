import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/confirmation_dialog.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/error_view.dart';
import '../../data/models/vault_category.dart';
import '../../data/models/vault_photo.dart';
import '../camera/private_camera_screen.dart';
import '../gallery/import_photo_screen.dart';
import '../gallery/move_photo_sheet.dart';
import '../gallery/photo_grid.dart';

/// Screen displaying all photos within a specific user category.
class CategoryDetailScreen extends ConsumerStatefulWidget {
  final VaultCategory category;

  const CategoryDetailScreen({super.key, required this.category});

  @override
  ConsumerState<CategoryDetailScreen> createState() =>
      _CategoryDetailScreenState();
}

class _CategoryDetailScreenState extends ConsumerState<CategoryDetailScreen> {
  bool _ascending = false;
  bool _isSelectionMode = false;
  final Set<String> _selectedPhotoIds = {};

  Future<List<VaultPhoto>> _fetchPhotos() async {
    final user = ref.read(currentUserProvider);
    if (user == null) return [];

    return ref
        .read(photoRepositoryProvider)
        .getPhotosByCategory(
          user.id,
          widget.category.id,
          ascending: _ascending,
        );
  }

  void _toggleSelect(String photoId) {
    setState(() {
      if (_selectedPhotoIds.contains(photoId)) {
        _selectedPhotoIds.remove(photoId);
        if (_selectedPhotoIds.isEmpty) {
          _isSelectionMode = false;
        }
      } else {
        _selectedPhotoIds.add(photoId);
        _isSelectionMode = true;
      }
    });
  }

  void _selectAll(List<VaultPhoto> photos) {
    setState(() {
      if (_selectedPhotoIds.length == photos.length) {
        _selectedPhotoIds.clear();
        _isSelectionMode = false;
      } else {
        _selectedPhotoIds.addAll(photos.map((p) => p.id));
        _isSelectionMode = true;
      }
    });
  }

  Future<void> _deleteSelected() async {
    final count = _selectedPhotoIds.length;
    final confirmed = await ConfirmationDialog.show(
      context: context,
      title: 'Move $count ${count == 1 ? 'Photo' : 'Photos'} to Trash?',
      message:
          'Selected photos will be moved to Recently Deleted and kept for 30 days.',
      confirmText: 'Move to Trash',
      isDestructive: true,
      icon: Icons.delete_outline_rounded,
    );

    if (confirmed == true && mounted) {
      final user = ref.read(currentUserProvider);
      if (user == null) return;

      final photoRepo = ref.read(photoRepositoryProvider);
      for (final id in _selectedPhotoIds) {
        await photoRepo.softDeletePhoto(id, user.id);
      }

      ref.invalidate(categoriesProvider);
      ref.invalidate(recentlyDeletedPhotosProvider);

      setState(() {
        _selectedPhotoIds.clear();
        _isSelectionMode = false;
      });
    }
  }

  Future<void> _moveSelected() async {
    final moved = await MovePhotoSheet.show(
      context: context,
      currentCategoryId: widget.category.id,
      photoIds: _selectedPhotoIds.toList(),
    );

    if (moved == true && mounted) {
      setState(() {
        _selectedPhotoIds.clear();
        _isSelectionMode = false;
      });
    }
  }

  void _showAddPhotoOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.elevatedSurface,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.camera_alt_outlined,
                    color: AppColors.primaryAccent,
                  ),
                ),
                title: const Text(
                  'Take Private Photo',
                  style: AppTypography.titleMedium,
                ),
                subtitle: const Text(
                  'Captured photo never touches phone gallery',
                  style: AppTypography.bodySmall,
                ),
                onTap: () {
                  Navigator.of(context).pop();
                  Navigator.of(context)
                      .push(
                        MaterialPageRoute(
                          builder: (context) => PrivateCameraScreen(
                            initialCategoryId: widget.category.id,
                            initialCategoryName: widget.category.name,
                          ),
                        ),
                      )
                      .then((_) => setState(() {}));
                },
              ),
              const Divider(),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.elevatedSurface,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.photo_library_outlined,
                    color: AppColors.secondaryAccent,
                  ),
                ),
                title: const Text(
                  'Import from Gallery',
                  style: AppTypography.titleMedium,
                ),
                subtitle: const Text(
                  'Encrypt and upload existing photos',
                  style: AppTypography.bodySmall,
                ),
                onTap: () {
                  Navigator.of(context).pop();
                  Navigator.of(context)
                      .push(
                        MaterialPageRoute(
                          builder: (context) => ImportPhotoScreen(
                            categoryId: widget.category.id,
                            categoryName: widget.category.name,
                          ),
                        ),
                      )
                      .then((_) => setState(() {}));
                },
              ),
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: _isSelectionMode
            ? Text(
                '${_selectedPhotoIds.length} Selected',
                style: AppTypography.titleLarge,
              )
            : Text(widget.category.name, style: AppTypography.titleLarge),
        leading: _isSelectionMode
            ? IconButton(
                icon: const Icon(Icons.close_rounded),
                onPressed: () => setState(() {
                  _selectedPhotoIds.clear();
                  _isSelectionMode = false;
                }),
              )
            : const BackButton(),
        actions: [
          if (_isSelectionMode) ...[
            IconButton(
              icon: const Icon(Icons.drive_file_move_outlined),
              tooltip: 'Move Selected',
              onPressed: _selectedPhotoIds.isEmpty ? null : _moveSelected,
            ),
            IconButton(
              icon: const Icon(
                Icons.delete_outline_rounded,
                color: AppColors.danger,
              ),
              tooltip: 'Delete Selected',
              onPressed: _selectedPhotoIds.isEmpty ? null : _deleteSelected,
            ),
          ] else ...[
            IconButton(
              icon: Icon(
                _ascending
                    ? Icons.arrow_upward_rounded
                    : Icons.arrow_downward_rounded,
              ),
              tooltip: _ascending
                  ? 'Showing Oldest First'
                  : 'Showing Newest First',
              onPressed: () => setState(() => _ascending = !_ascending),
            ),
          ],
        ],
      ),
      body: FutureBuilder<List<VaultPhoto>>(
        future: _fetchPhotos(),
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

          if (snapshot.hasError) {
            return ErrorView(
              message: snapshot.error.toString(),
              onRetry: () => setState(() {}),
            );
          }

          final photos = snapshot.data ?? [];

          if (photos.isEmpty) {
            return EmptyState(
              icon: Icons.photo_camera_back_outlined,
              title: 'No photos in this category yet',
              subtitle:
                  'Take a private photo or import photos from your device gallery.',
              actionText: 'Add Photo',
              onAction: _showAddPhotoOptions,
            );
          }

          return Column(
            children: [
              if (_isSelectionMode)
                Container(
                  color: AppColors.elevatedSurface,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      TextButton(
                        onPressed: () => _selectAll(photos),
                        child: Text(
                          _selectedPhotoIds.length == photos.length
                              ? 'Deselect All'
                              : 'Select All',
                        ),
                      ),
                      Text(
                        '${_selectedPhotoIds.length} of ${photos.length}',
                        style: AppTypography.labelSmall,
                      ),
                    ],
                  ),
                ),
              Expanded(
                child: PhotoGrid(
                  photos: photos,
                  categoryId: widget.category.id,
                  isSelectionMode: _isSelectionMode,
                  selectedPhotoIds: _selectedPhotoIds,
                  onToggleSelect: _toggleSelect,
                  onPhotoDeletedOrMoved: () => setState(() {}),
                ),
              ),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppColors.primaryAccent,
        foregroundColor: AppColors.background,
        onPressed: _showAddPhotoOptions,
        child: const Icon(Icons.add_rounded, size: 28),
      ),
    );
  }
}
