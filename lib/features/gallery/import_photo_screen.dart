import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/providers.dart';
import '../../core/errors/app_exception.dart';
import '../../core/models/pending_import_context.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/utils/import_pipeline_logger.dart';
import '../../core/widgets/privora_button.dart';
import '../../data/models/upload_state.dart';

/// Screen managing multi-photo selection, Android lifecycle preservation,
/// stage-specific diagnostics, and resilient batch ingestion from the phone gallery.
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
  List<File> _selectedFiles = [];
  List<File> _failedFiles = [];
  PendingImportContext? _importContext;
  bool _isUploading = false;
  bool _isComplete = false;
  bool _isClosing = false;
  int _successCount = 0;
  int _currentUploadIndex = 0;
  int _totalBatchCount = 0;
  UploadState _uploadState = const UploadState();
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final user = ref.read(currentUserProvider);
      if (user == null) return;

      final importService = ref.read(galleryImportServiceProvider);
      // Check for lost data recovered across Android activity destruction/restart
      final recovered = await importService.checkAndRecoverLostData(
        currentUserId: user.id,
      );

      if (recovered != null &&
          recovered.files.isNotEmpty &&
          recovered.context.categoryId == widget.categoryId) {
        if (mounted) {
          ImportPipelineLogger.logStage(
            ImportStage.filesSelected,
            requestId: recovered.context.requestId,
            details:
                'Recovered ${recovered.files.length} photo(s) across activity restart',
          );
          setState(() {
            _selectedFiles = recovered.files;
            _importContext = recovered.context;
            _failedFiles = [];
            _successCount = 0;
            _isComplete = false;
            _errorMessage = null;
          });
        }
      } else if (mounted && _selectedFiles.isEmpty) {
        _pickGalleryPhotos();
      }
    });
  }

  Future<void> _pickGalleryPhotos() async {
    if (_isUploading) return;

    final user = ref.read(currentUserProvider);
    if (user == null) {
      setState(
        () => _errorMessage = 'User session is not active. Please sign in.',
      );
      return;
    }

    final importService = ref.read(galleryImportServiceProvider);
    final sessionLockNotifier = ref.read(sessionLockServiceProvider.notifier);

    try {
      sessionLockNotifier.markExternalActivityActive(true);
      final result = await importService.launchPicker(
        userId: user.id,
        categoryId: widget.categoryId,
        categoryName: widget.categoryName,
        onExternalActivityChanged: (active) {
          sessionLockNotifier.markExternalActivityActive(active);
        },
      );

      sessionLockNotifier.setPendingImportContext(result.context);

      // User cancellation: clear context quietly without error banner
      if (result.isCancelled || result.files.isEmpty) {
        sessionLockNotifier.clearPendingImportContext();
        return;
      }

      setState(() {
        _selectedFiles = result.files;
        _importContext = result.context;
        _failedFiles = [];
        _successCount = 0;
        _isComplete = false;
        _errorMessage = null;
      });
    } catch (e) {
      debugPrint('[ImportPhotoScreen] Error opening photo picker: $e');
      if (mounted) {
        setState(() {
          _errorMessage = ImportPipelineLogger.getUserFriendlyErrorMessage(
            ImportStage.pickerLaunched,
            e,
          );
        });
      }
    } finally {
      sessionLockNotifier.markExternalActivityActive(false);
    }
  }

  Future<void> _startImport({bool retryOnlyFailed = false}) async {
    if (_isUploading) return;

    final filesToUpload = retryOnlyFailed
        ? List<File>.from(_failedFiles)
        : List<File>.from(_selectedFiles);
    if (filesToUpload.isEmpty) return;

    final user = ref.read(currentUserProvider);
    final masterKey = ref.read(vaultRepositoryProvider).activeMasterKey;

    if (user == null || masterKey == null) {
      setState(
        () => _errorMessage =
            'Session locked or vault not unlocked. Please unlock your vault before encrypting photos.',
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
    final importService = ref.read(galleryImportServiceProvider);
    final sessionLockNotifier = ref.read(sessionLockServiceProvider.notifier);

    final newlyFailed = <File>[];
    int newlySucceeded = 0;
    String? lastFailureMessage;

    // Process sequentially (1 at a time) for memory stability and bounded resource usage
    for (int i = 0; i < filesToUpload.length; i++) {
      if (!mounted) break;
      final file = filesToUpload[i];

      setState(() {
        _currentUploadIndex = i + 1;
      });

      try {
        await uploadService.uploadPhoto(
          sourceFile: file,
          userId: user.id,
          categoryId: widget.categoryId,
          masterKey: masterKey,
          deleteSourceFile: true, // Delete app-private temp file upon success
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
        debugPrint('[ImportPhotoScreen] Upload error for ${file.path}: $e');
        newlyFailed.add(file);
        lastFailureMessage = e is AppException ? e.message : e.toString();
      }
    }

    // Refresh categories and gallery immediately with optimistic count
    if (newlySucceeded > 0) {
      ref
          .read(categoryRepositoryProvider)
          .updatePhotoCountLocally(widget.categoryId, newlySucceeded);
    }
    ref.invalidate(categoriesProvider);
    unawaited(() async {
      try {
        final u = ref.read(currentUserProvider);
        if (u != null) {
          await ref
              .read(categoryRepositoryProvider)
              .getCategories(u.id, forceRefresh: true);
          ref.invalidate(categoriesProvider);
        }
      } catch (_) {}
    }());
    ImportPipelineLogger.logStage(
      ImportStage.categoryRefreshed,
      requestId: _importContext?.requestId,
      details: 'category ${widget.categoryId} refreshed',
    );

    if (_importContext != null && newlyFailed.isEmpty) {
      await importService.cleanupRequest(_importContext!.requestId);
      sessionLockNotifier.clearPendingImportContext();
      ImportPipelineLogger.logStage(
        ImportStage.tempFilesCleaned,
        requestId: _importContext?.requestId,
      );
    }

    if (!mounted) return;

    setState(() {
      _isUploading = false;
      _isComplete = true;
      _successCount += newlySucceeded;
      _failedFiles = newlyFailed;
      if (newlyFailed.isNotEmpty && lastFailureMessage != null) {
        _errorMessage = lastFailureMessage;
      }
    });
  }

  Future<void> _closeImport() async {
    if (_isUploading || _isClosing) return;
    _isClosing = true;

    final requestId = _importContext?.requestId;
    if (requestId != null) {
      await ref.read(galleryImportServiceProvider).cleanupRequest(requestId);
      ref.read(sessionLockServiceProvider.notifier).clearPendingImportContext();
    }

    if (mounted) {
      Navigator.of(context).pop(_successCount > 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (_isUploading) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Upload in progress. Please wait for completion.'),
            ),
          );
        } else {
          unawaited(_closeImport());
        }
      },
      child: Scaffold(
        backgroundColor: AppColors.mainBackground,
        appBar: AppBar(
          title: Text('Import to ${widget.categoryName}'),
          leading: SizedBox(
            width: 48,
            height: 48,
            child: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
              tooltip: 'Back',
              onPressed: _isUploading ? null : () => unawaited(_closeImport()),
            ),
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
                  if (_errorMessage != null) ...[
                    const SizedBox(height: 16),
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Text(
                          _errorMessage!,
                          style: const TextStyle(
                            color: AppColors.errorDestructive,
                            fontSize: 13,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                  ],
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
                              child: Image.file(file, fit: BoxFit.cover),
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

                  // Stage-specific Error Message
                  if (_errorMessage != null) ...[
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.symmetric(vertical: 8),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.errorDestructive.withValues(
                          alpha: 0.1,
                        ),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: AppColors.errorDestructive.withValues(
                            alpha: 0.4,
                          ),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.error_outline,
                            color: AppColors.errorDestructive,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _errorMessage!,
                              style: const TextStyle(
                                color: AppColors.errorDestructive,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  // Progress Bar and Format: "Uploading X of Y"
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
                            ? AppColors.primaryActionBlue.withValues(
                                alpha: 0.08,
                              )
                            : AppColors.errorDestructive.withValues(
                                alpha: 0.08,
                              ),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _failedFiles.isEmpty
                              ? AppColors.primaryActionBlue.withValues(
                                  alpha: 0.3,
                                )
                              : AppColors.errorDestructive.withValues(
                                  alpha: 0.3,
                                ),
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
                            onPressed: () => unawaited(_closeImport()),
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
                            onPressed: () => unawaited(_closeImport()),
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
      ),
    );
  }
}
