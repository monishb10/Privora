import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../app/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/confirmation_dialog.dart';
import '../../core/widgets/privora_button.dart';
import '../../data/models/upload_state.dart';

/// Screen managing importing photos from the phone gallery into a category.
class ImportPhotoScreen extends ConsumerStatefulWidget {
  final String categoryId;
  final String categoryName;

  const ImportPhotoScreen({
    super.key,
    required this.categoryId,
    required this.categoryName,
  });

  @override
  ConsumerState<ImportPhotoScreen> createState() => _ImportPhotoScreenState();
}

class _ImportPhotoScreenState extends ConsumerState<ImportPhotoScreen> {
  final ImagePicker _picker = ImagePicker();
  List<XFile> _selectedFiles = [];
  bool _isUploading = false;
  UploadState _uploadState = const UploadState();
  String? _errorMessage;

  Future<void> _pickGalleryPhotos() async {
    try {
      // Permission handling for Android:
      // On Android 13+ (API 33+), photo picker does not require runtime storage permission.
      // On older versions, check photos / storage permission.
      if (Platform.isAndroid) {
        final status = await Permission.photos.status;
        if (!status.isGranted) {
          final req = await Permission.photos.request();
          if (!req.isGranted) {
            await Permission.storage.request();
          }
        }
      }

      final picked = await _picker.pickMultiImage();
      if (picked.isNotEmpty) {
        setState(() {
          _selectedFiles = picked;
          _errorMessage = null;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to open photo picker: $e';
      });
    }
  }

  Future<void> _startImport() async {
    if (_selectedFiles.isEmpty) return;

    final user = ref.read(currentUserProvider);
    final masterKey = ref.read(vaultRepositoryProvider).activeMasterKey;

    if (user == null || masterKey == null) {
      setState(() => _errorMessage = 'Session locked or expired.');
      return;
    }

    setState(() {
      _isUploading = true;
      _errorMessage = null;
    });

    final uploadService = ref.read(photoUploadServiceProvider);
    int successCount = 0;
    final List<String> successfullyUploadedOriginalPaths = [];

    for (int i = 0; i < _selectedFiles.length; i++) {
      final file = _selectedFiles[i];
      try {
        await uploadService.uploadPhoto(
          sourceFile: File(file.path),
          userId: user.id,
          categoryId: widget.categoryId,
          masterKey: masterKey,
          onStateChanged: (state) {
            if (mounted) {
              setState(() {
                _uploadState = state.copyWith(
                  totalCount: _selectedFiles.length,
                  currentIndex: i + 1,
                );
              });
            }
          },
        );

        successCount++;
        successfullyUploadedOriginalPaths.add(file.path);
      } catch (e) {
        // Continue uploading remaining photos if one fails
      }
    }

    ref.invalidate(categoriesProvider);

    if (!mounted) return;

    // Offer to remove original gallery photos only after verified upload
    if (successCount > 0) {
      _showDeleteOriginalDialog(
        successCount,
        successfullyUploadedOriginalPaths,
      );
    } else {
      setState(() {
        _isUploading = false;
        _errorMessage = 'Import failed. Please check network connection.';
      });
    }
  }

  Future<void> _showDeleteOriginalDialog(
    int count,
    List<String> filePaths,
  ) async {
    final confirmed = await ConfirmationDialog.show(
      context: context,
      title: 'Remove from Phone Gallery?',
      message:
          'Successfully encrypted and uploaded $count ${count == 1 ? 'photo' : 'photos'} to Privora.\n\nWould you like to delete the unencrypted original from your phone\'s normal gallery?',
      confirmText: 'Delete from Gallery',
      cancelText: 'Keep on Phone',
      icon: Icons.delete_outline_rounded,
    );

    if (confirmed == true && mounted) {
      // Safely delete original files after explicit user confirmation
      for (final path in filePaths) {
        try {
          final f = File(path);
          if (await f.exists()) {
            await f.delete();
          }
        } catch (_) {}
      }
    }

    if (mounted) {
      Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: Text('Import to ${widget.categoryName}')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_selectedFiles.isEmpty) ...[
                const Spacer(flex: 1),
                Center(
                  child: Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      color: AppColors.elevatedSurface,
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.border),
                    ),
                    child: const Icon(
                      Icons.photo_library_outlined,
                      size: 38,
                      color: AppColors.primaryAccent,
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                const Center(
                  child: Text(
                    'Select Photos from Gallery',
                    style: AppTypography.titleLarge,
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 8),
                Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Text(
                      'Photos will be encrypted with AES-256-GCM locally before being stored in your private cloud.',
                      style: AppTypography.bodySmall,
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
                const Spacer(flex: 2),
                PrivoraButton(
                  text: 'Open Gallery',
                  leadingIcon: Icons.photo_library_rounded,
                  onPressed: _pickGalleryPhotos,
                ),
                const SizedBox(height: 20),
              ] else ...[
                Text(
                  '${_selectedFiles.length} ${_selectedFiles.length == 1 ? 'photo' : 'photos'} selected',
                  style: AppTypography.titleMedium,
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: GridView.builder(
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          crossAxisSpacing: 8,
                          mainAxisSpacing: 8,
                        ),
                    itemCount: _selectedFiles.length,
                    itemBuilder: (context, index) {
                      return ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Image.file(
                          File(_selectedFiles[index].path),
                          fit: BoxFit.cover,
                        ),
                      );
                    },
                  ),
                ),
                if (_errorMessage != null) ...[
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      _errorMessage!,
                      style: const TextStyle(color: AppColors.danger),
                    ),
                  ),
                ],
                if (_isUploading) ...[
                  LinearProgressIndicator(
                    value: _uploadState.progress,
                    color: AppColors.primaryAccent,
                    backgroundColor: AppColors.elevatedSurface,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${_uploadState.currentIndex}/${_uploadState.totalCount}: ${_uploadState.statusMessage}',
                    style: AppTypography.labelSmall,
                  ),
                  const SizedBox(height: 16),
                ],
                Row(
                  children: [
                    Expanded(
                      child: PrivoraButton(
                        text: 'Change Selection',
                        variant: PrivoraButtonVariant.secondary,
                        onPressed: _isUploading ? null : _pickGalleryPhotos,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: PrivoraButton(
                        text: 'Encrypt & Upload',
                        isLoading: _isUploading,
                        onPressed: _isUploading ? null : _startImport,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
