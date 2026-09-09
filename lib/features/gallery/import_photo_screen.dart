import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../../app/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/privora_button.dart';
import '../../data/models/upload_state.dart';

/// Screen managing multi-photo selection and resilient batch ingestion from the phone gallery.
/// Implements sequential encryption and upload, progress reporting ("Uploading X of Y"),
/// partial-failure resilience with failed-only retry, and zero modification of original gallery files.
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
  List<XFile> _failedFiles = [];
  bool _isUploading = false;
  bool _isComplete = false;
  int _successCount = 0;
  int _currentUploadIndex = 0;
  int _totalBatchCount = 0;
  UploadState _uploadState = const UploadState();
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    // Open the system photo picker shortly after screen mount
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _selectedFiles.isEmpty) {
        _pickGalleryPhotos();
      }
    });
  }

  Future<void> _pickGalleryPhotos() async {
    if (_isUploading) return;

    try {
      // Pick multiple photos using Android system photo picker
      final picked = await _picker.pickMultiImage();

      // If user closed or cancelled picker without selecting photos, close quietly without error
      if (picked.isEmpty) {
        return;
      }

      setState(() {
        _selectedFiles = picked;
        _failedFiles = [];
        _successCount = 0;
        _isComplete = false;
        _errorMessage = null;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Failed to open photo picker: $e';
        });
      }
    }
  }

  Future<void> _startImport({bool retryOnlyFailed = false}) async {
    // Prevent duplicate taps from starting concurrent batch uploads
    if (_isUploading) return;

    final filesToUpload = retryOnlyFailed
        ? List<XFile>.from(_failedFiles)
        : List<XFile>.from(_selectedFiles);
    if (filesToUpload.isEmpty) return;

    final user = ref.read(currentUserProvider);
    final masterKey = ref.read(vaultRepositoryProvider).activeMasterKey;

    if (user == null || masterKey == null) {
      setState(
        () => _errorMessage =
            'Session locked or expired. Please unlock your vault.',
      );
      return;
    }

    setState(() {
      _isUploading = true;
      _isComplete = false;
      _errorMessage = null;
      _totalBatchCount = filesToUpload.length;
      _currentUploadIndex = 0;
      if (!retryOnlyFailed) {
        _successCount = 0;
        _failedFiles = [];
      }
    });

    final uploadService = ref.read(photoUploadServiceProvider);
    final cleaner = ref.read(temporaryFileCleanerProvider);
    final newlyFailed = <XFile>[];
    int newlySucceeded = 0;

    // Process sequentially (one at a time) to prevent memory crashes with high-res photos
    for (int i = 0; i < filesToUpload.length; i++) {
      if (!mounted) break;
      final file = filesToUpload[i];

      setState(() {
        _currentUploadIndex = i + 1;
      });

      try {
        await uploadService.uploadPhoto(
          sourceFile: File(file.path),
          userId: user.id,
          categoryId: widget.categoryId,
          masterKey: masterKey,
          deleteSourceFile: false,
          onStateChanged: (state) {
            if (mounted) {
              setState(() {
                _uploadState = state;
              });
            }
          },
        );

        newlySucceeded++;
      } catch (e) {
        debugPrint('Upload error for ${file.name}: $e');
        newlyFailed.add(file);
      } finally {
        // Clean up temporary encrypted/decrypted chunks after each photo
        await cleaner.cleanTemporaryFiles();
      }
    }

    // Refresh categories and gallery once at the end of the batch
    ref.invalidate(categoriesProvider);

    if (!mounted) return;

    setState(() {
      _isUploading = false;
      _isComplete = true;
      _successCount += newlySucceeded;
      _failedFiles = newlyFailed;
    });

    // Final disk hygiene pass
    await cleaner.cleanTemporaryFiles();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.mainBackground,
      appBar: AppBar(
        title: Text('Import to ${widget.categoryName}'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: _isUploading ? null : () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // No files selected view
              if (_selectedFiles.isEmpty) ...[
                const Spacer(flex: 1),
                Center(
                  child: Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      color: AppColors.softBlueSurface,
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.borderDivider),
                    ),
                    child: const Icon(
                      Icons.photo_library_outlined,
                      size: 38,
                      color: AppColors.primaryActionBlue,
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
                      'Photos will be encrypted with client-side AES-256-GCM before uploading to your private cloud.',
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.secondaryTextColor,
                      ),
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
                // Header with photo count
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '${_selectedFiles.length} ${_selectedFiles.length == 1 ? 'photo' : 'photos'} selected',
                      style: AppTypography.titleMedium,
                    ),
                    if (!_isUploading && !_isComplete)
                      TextButton(
                        onPressed: _pickGalleryPhotos,
                        child: const Text('Change'),
                      ),
                  ],
                ),
                const SizedBox(height: 12),

                // Selected photos preview grid
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
                      final file = _selectedFiles[index];
                      final isFailed = _failedFiles.contains(file);

                      return Stack(
                        fit: StackFit.expand,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: Image.file(
                              File(file.path),
                              fit: BoxFit.cover,
                            ),
                          ),
                          if (isFailed)
                            Container(
                              decoration: BoxDecoration(
                                color: Colors.black54,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Center(
                                child: Icon(
                                  Icons.error_outline_rounded,
                                  color: AppColors.errorDestructive,
                                  size: 28,
                                ),
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                ),

                // Error Message
                if (_errorMessage != null) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      _errorMessage!,
                      style: const TextStyle(color: AppColors.errorDestructive),
                    ),
                  ),
                ],

                // Progress Bar and Exact Requirement Format: "Uploading 3 of 8"
                if (_isUploading) ...[
                  LinearProgressIndicator(
                    value: _totalBatchCount > 0
                        ? _currentUploadIndex / _totalBatchCount
                        : 0.0,
                    color: AppColors.primaryActionBlue,
                    backgroundColor: AppColors.softBlueSurface,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Uploading $_currentUploadIndex of $_totalBatchCount',
                    style: AppTypography.labelMedium.copyWith(
                      color: AppColors.primaryActionBlue,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (_uploadState.statusMessage.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      _uploadState.statusMessage,
                      style: AppTypography.labelSmall.copyWith(
                        color: AppColors.secondaryTextColor,
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                ],

                // Completion status summary
                if (_isComplete) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: _failedFiles.isEmpty
                          ? AppColors.primaryActionBlue.withValues(alpha: 0.08)
                          : AppColors.errorDestructive.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _failedFiles.isEmpty
                            ? AppColors.primaryActionBlue.withValues(alpha: 0.3)
                            : AppColors.errorDestructive.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '$_successCount ${_successCount == 1 ? 'photo' : 'photos'} uploaded',
                          style: AppTypography.bodyMedium.copyWith(
                            color: AppColors.primaryText,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (_failedFiles.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              '${_failedFiles.length} ${_failedFiles.length == 1 ? 'photo' : 'photos'} failed',
                              style: AppTypography.bodySmall.copyWith(
                                color: AppColors.errorDestructive,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                // Action Buttons
                if (!_isUploading && !_isComplete) ...[
                  Row(
                    children: [
                      Expanded(
                        child: PrivoraButton(
                          text: 'Cancel',
                          variant: PrivoraButtonVariant.secondary,
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: PrivoraButton(
                          text: 'Encrypt & Upload',
                          variant: PrivoraButtonVariant.primary,
                          onPressed: () => _startImport(),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                ] else if (_isComplete) ...[
                  Row(
                    children: [
                      if (_failedFiles.isNotEmpty) ...[
                        Expanded(
                          child: PrivoraButton(
                            text: 'Retry Failed (${_failedFiles.length})',
                            variant: PrivoraButtonVariant.secondary,
                            onPressed: () =>
                                _startImport(retryOnlyFailed: true),
                          ),
                        ),
                        const SizedBox(width: 12),
                      ],
                      Expanded(
                        child: PrivoraButton(
                          text: 'Done',
                          variant: PrivoraButtonVariant.primary,
                          onPressed: () => Navigator.of(context).pop(true),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}
