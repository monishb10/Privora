import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import '../../core/models/pending_import_context.dart';
import '../../core/utils/import_pipeline_logger.dart';

/// Result object holding imported photos copied into private temporary storage
class GalleryImportResult {
  final PendingImportContext context;
  final List<File> files;
  final bool isCancelled;

  const GalleryImportResult({
    required this.context,
    required this.files,
    this.isCancelled = false,
  });
}

/// Service managing gallery photo selection, Android activity-death recovery,
/// and prompt isolation of raw assets into app-private temporary storage.
class GalleryImportService {
  final ImagePicker _picker;
  final Uuid _uuid;
  final Future<Directory> Function() _tempDirProvider;

  GalleryImportService({
    ImagePicker? picker,
    Uuid? uuid,
    Future<Directory> Function()? tempDirProvider,
  })  : _picker = picker ?? ImagePicker(),
        _uuid = uuid ?? const Uuid(),
        _tempDirProvider = tempDirProvider ?? _defaultTempDir;

  static Future<Directory> _defaultTempDir() async {
    try {
      return await getTemporaryDirectory();
    } catch (_) {
      return Directory.systemTemp;
    }
  }

  Future<Directory> _getTempDir() => _tempDirProvider();

  /// Launches the system photo picker, persisting pending context before opening.
  /// Selected photos are promptly streamed/copied into app-private temporary files.
  Future<GalleryImportResult> launchPicker({
    required String userId,
    required String categoryId,
    required String categoryName,
    void Function(bool isActive)? onExternalActivityChanged,
  }) async {
    final requestId = _uuid.v4();
    final context = PendingImportContext(
      requestId: requestId,
      userId: userId,
      categoryId: categoryId,
      categoryName: categoryName,
      pickerType: 'gallery_multi',
      startTime: DateTime.now(),
    );

    // 1. Stage 1: Picker launched
    ImportPipelineLogger.logStage(
      ImportStage.pickerLaunched,
      requestId: requestId,
      details: 'category: $categoryId, user: $userId',
    );

    await _savePendingContextToDisk(context);
    onExternalActivityChanged?.call(true);

    List<XFile> picked = [];
    try {
      try {
        picked = await _picker.pickMultiImage();
      } catch (multiError) {
        debugPrint(
          '[GalleryImportService] pickMultiImage failed ($multiError), falling back to pickImage',
        );
        final single = await _picker.pickImage(source: ImageSource.gallery);
        if (single != null) {
          picked = [single];
        }
      }

      // 2. Stage 2: Picker returned
      ImportPipelineLogger.logStage(
        ImportStage.pickerReturned,
        requestId: requestId,
        details: 'returned ${picked.length} item(s)',
      );

      // Empty result represents user cancellation, NOT an error
      if (picked.isEmpty) {
        await _clearPendingContextFromDisk(requestId);
        return GalleryImportResult(
          context: context,
          files: const [],
          isCancelled: true,
        );
      }

      // 3. Stage 3: Number of selected files
      ImportPipelineLogger.logStage(
        ImportStage.filesSelected,
        requestId: requestId,
        details: '${picked.length} photo(s) selected',
      );

      // 4 & 5. Copy selected content promptly into app-private temporary files
      final privateTempFiles = await _copyXFilesToPrivateStorage(
        picked,
        requestId,
      );

      final updatedContext = context.copyWith(
        tempFilePaths: privateTempFiles.map((f) => f.path).toList(),
      );
      await _savePendingContextToDisk(updatedContext);

      return GalleryImportResult(
        context: updatedContext,
        files: privateTempFiles,
        isCancelled: false,
      );
    } catch (e, st) {
      ImportPipelineLogger.logFailure(
        ImportStage.pickerLaunched,
        e,
        st,
        requestId: requestId,
      );
      await _clearPendingContextFromDisk(requestId);
      rethrow;
    } finally {
      onExternalActivityChanged?.call(false);
    }
  }

  /// Copies XFiles into an app-private cache directory isolated by requestId.
  /// Never writes decrypted copies to the public gallery, and prevents Android content URI errors.
  Future<List<File>> _copyXFilesToPrivateStorage(
    List<XFile> xFiles,
    String requestId,
  ) async {
    final tempDir = await _getTempDir();
    final importDir = Directory(
      '${tempDir.path}${Platform.pathSeparator}privora_import${Platform.pathSeparator}$requestId',
    );
    if (!await importDir.exists()) {
      await importDir.create(recursive: true);
    }

    final copiedFiles = <File>[];
    for (int i = 0; i < xFiles.length; i++) {
      final xfile = xFiles[i];
      // Stage 4: Source opened
      ImportPipelineLogger.logStage(
        ImportStage.sourceOpened,
        requestId: requestId,
        details: 'item [${i + 1}/${xFiles.length}]: ${xfile.name}',
      );

      final bytes = await xfile.readAsBytes();
      final ext = _resolveFileExtension(xfile.name, xfile.path);
      final destFile = File(
        '${importDir.path}${Platform.pathSeparator}import_${_uuid.v4()}$ext',
      );
      await destFile.writeAsBytes(bytes, flush: true);

      // Stage 5: Private temporary copy created
      ImportPipelineLogger.logStage(
        ImportStage.privateTempCopyCreated,
        requestId: requestId,
        details: 'saved to app-private cache (${bytes.length} bytes)',
      );

      copiedFiles.add(destFile);
    }

    return copiedFiles;
  }

  /// Checks and recovers lost data if the Android activity was destroyed while the picker was open.
  Future<GalleryImportResult?> checkAndRecoverLostData({
    required String currentUserId,
  }) async {
    if (kIsWeb || !Platform.isAndroid) {
      return null;
    }

    try {
      final lostData = await _picker.retrieveLostData();
      if (lostData.isEmpty) {
        return null;
      }

      final savedContext = await _loadPendingContextFromDisk();
      if (savedContext == null) {
        debugPrint(
          '[GalleryImportService] Lost data found, but no matching pending import context found.',
        );
        return null;
      }

      // Discard recovered items safely if account changed
      if (savedContext.userId != currentUserId) {
        debugPrint(
          '[GalleryImportService] Account changed from ${savedContext.userId} to $currentUserId. Discarding recovered photos.',
        );
        await cleanupRequest(savedContext.requestId);
        return null;
      }

      final recoveredXFiles = <XFile>[];
      if (lostData.files != null && lostData.files!.isNotEmpty) {
        recoveredXFiles.addAll(lostData.files!);
      } else if (lostData.file != null) {
        recoveredXFiles.add(lostData.file!);
      }

      if (recoveredXFiles.isEmpty) {
        return null;
      }

      debugPrint(
        '[GalleryImportService] Successfully recovered ${recoveredXFiles.length} photo(s) after activity restart.',
      );

      final copiedFiles = await _copyXFilesToPrivateStorage(
        recoveredXFiles,
        savedContext.requestId,
      );

      final updatedContext = savedContext.copyWith(
        tempFilePaths: copiedFiles.map((f) => f.path).toList(),
      );
      await _savePendingContextToDisk(updatedContext);

      return GalleryImportResult(
        context: updatedContext,
        files: copiedFiles,
        isCancelled: false,
      );
    } catch (e, st) {
      debugPrint('[GalleryImportService] Error recovering lost data: $e\n$st');
      return null;
    }
  }

  /// Cleans up temporary private files created for a specific import request
  Future<void> cleanupRequest(String requestId) async {
    try {
      final tempDir = await _getTempDir();
      final importDir = Directory(
        '${tempDir.path}${Platform.pathSeparator}privora_import${Platform.pathSeparator}$requestId',
      );
      if (await importDir.exists()) {
        await importDir.delete(recursive: true);
      }
      await _clearPendingContextFromDisk(requestId);
    } catch (e) {
      debugPrint(
        '[GalleryImportService] Error cleaning request temp files: $e',
      );
    }
  }

  String _resolveFileExtension(String name, String path) {
    if (name.contains('.')) {
      final ext = name.substring(name.lastIndexOf('.')).toLowerCase();
      if (['.jpg', '.jpeg', '.png', '.webp', '.heic'].contains(ext)) {
        return ext;
      }
    }
    if (path.contains('.')) {
      final ext = path.substring(path.lastIndexOf('.')).toLowerCase();
      if (['.jpg', '.jpeg', '.png', '.webp', '.heic'].contains(ext)) {
        return ext;
      }
    }
    return '.jpg';
  }

  Future<void> _savePendingContextToDisk(PendingImportContext context) async {
    try {
      final tempDir = await _getTempDir();
      final file = File(
        '${tempDir.path}${Platform.pathSeparator}pending_import.json',
      );
      await file.writeAsString(context.serialize(), flush: true);
    } catch (e) {
      debugPrint('[GalleryImportService] Error saving pending context: $e');
    }
  }

  Future<PendingImportContext?> _loadPendingContextFromDisk() async {
    try {
      final tempDir = await _getTempDir();
      final file = File(
        '${tempDir.path}${Platform.pathSeparator}pending_import.json',
      );
      if (!await file.exists()) return null;
      final raw = await file.readAsString();
      return PendingImportContext.deserialize(raw);
    } catch (e) {
      debugPrint('[GalleryImportService] Error loading pending context: $e');
      return null;
    }
  }

  Future<void> _clearPendingContextFromDisk(String requestId) async {
    try {
      final tempDir = await _getTempDir();
      final file = File(
        '${tempDir.path}${Platform.pathSeparator}pending_import.json',
      );
      if (await file.exists()) {
        await file.delete();
      }
    } catch (e) {
      debugPrint('[GalleryImportService] Error clearing pending context: $e');
    }
  }
}
