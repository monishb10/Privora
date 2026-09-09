import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/privora_button.dart';
import '../../data/models/upload_state.dart';

/// Screen previewing a photo captured via Privora's private in-app camera.
/// Never saves to Android MediaStore. Removes temp capture file after verified upload.
class CapturedPhotoPreviewScreen extends ConsumerStatefulWidget {
  final String imagePath;
  final String categoryId;
  final String categoryName;

  const CapturedPhotoPreviewScreen({
    super.key,
    required this.imagePath,
    required this.categoryId,
    required this.categoryName,
  });

  @override
  ConsumerState<CapturedPhotoPreviewScreen> createState() =>
      _CapturedPhotoPreviewScreenState();
}

class _CapturedPhotoPreviewScreenState
    extends ConsumerState<CapturedPhotoPreviewScreen> {
  bool _isUploading = false;
  UploadState _uploadState = const UploadState();
  String? _errorMessage;

  Future<void> _handleRetake() async {
    // Delete temp file immediately
    await ref
        .read(temporaryFileCleanerProvider)
        .deleteSingleFile(widget.imagePath);
    if (mounted) {
      Navigator.of(context).pop(false);
    }
  }

  Future<void> _handleConfirmUpload() async {
    final user = ref.read(currentUserProvider);
    final masterKey = ref.read(vaultRepositoryProvider).activeMasterKey;

    if (user == null || masterKey == null) {
      setState(() => _errorMessage = 'Session locked. Please unlock first.');
      return;
    }

    setState(() {
      _isUploading = true;
      _errorMessage = null;
    });

    try {
      final uploadService = ref.read(photoUploadServiceProvider);
      final file = File(widget.imagePath);

      await uploadService.uploadPhoto(
        sourceFile: file,
        userId: user.id,
        categoryId: widget.categoryId,
        masterKey: masterKey,
        deleteSourceFile: true,
        customDisplayName:
            'Camera_${DateTime.now().millisecondsSinceEpoch}.jpg',
        onStateChanged: (state) {
          if (mounted) {
            setState(() => _uploadState = state);
          }
        },
      );

      ref.invalidate(categoriesProvider);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Private photo securely saved to ${widget.categoryName}.',
          ),
        ),
      );

      // Return true to pop camera screen as well
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isUploading = false;
        _errorMessage = 'Upload failed: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Preview of captured image from private cache
          Image.file(File(widget.imagePath), fit: BoxFit.contain),

          // Top Header
          Positioned(
            top: MediaQuery.of(context).padding.top + 10,
            left: 16,
            right: 16,
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: AppColors.primaryAccent.withValues(alpha: 0.5),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.shield_outlined,
                        size: 16,
                        color: AppColors.primaryAccent,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Destination: ${widget.categoryName}',
                        style: AppTypography.labelSmall.copyWith(
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Bottom Action Bar
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: EdgeInsets.only(
                left: 24,
                right: 24,
                top: 24,
                bottom: MediaQuery.of(context).padding.bottom + 20,
              ),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [Colors.black87, Colors.transparent],
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_errorMessage != null) ...[
                    Text(
                      _errorMessage!,
                      style: const TextStyle(color: AppColors.danger),
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (_isUploading) ...[
                    LinearProgressIndicator(
                      value: _uploadState.progress,
                      color: AppColors.primaryAccent,
                      backgroundColor: AppColors.border,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _uploadState.statusMessage,
                      style: AppTypography.labelSmall.copyWith(
                        color: AppColors.secondaryText,
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  Row(
                    children: [
                      Expanded(
                        child: PrivoraButton(
                          text: 'Retake',
                          variant: PrivoraButtonVariant.secondary,
                          leadingIcon: Icons.refresh_rounded,
                          onPressed: _isUploading ? null : _handleRetake,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: PrivoraButton(
                          text: 'Encrypt & Save',
                          variant: PrivoraButtonVariant.primary,
                          leadingIcon: Icons.lock_outline_rounded,
                          isLoading: _isUploading,
                          onPressed: _isUploading ? null : _handleConfirmUpload,
                        ),
                      ),
                    ],
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
