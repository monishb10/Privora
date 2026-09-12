import 'package:flutter/foundation.dart';
import '../errors/app_exception.dart';

/// The 14 distinct stages of the gallery photo import and upload pipeline.
enum ImportStage {
  pickerLaunched(1, 'Picker launched'),
  pickerReturned(2, 'Picker returned'),
  filesSelected(3, 'Number of selected files'),
  sourceOpened(4, 'Source opened'),
  privateTempCopyCreated(5, 'Private temporary copy created'),
  thumbnailCreated(6, 'Thumbnail created'),
  fullImageEncrypted(7, 'Full image encrypted'),
  thumbnailEncrypted(8, 'Thumbnail encrypted'),
  uploadSignatureReceived(9, 'Cloudinary upload signature received'),
  fullAssetUploaded(10, 'Encrypted full asset upload'),
  thumbnailUploaded(11, 'Encrypted thumbnail upload'),
  metadataCommitted(12, 'Supabase photo metadata committed'),
  categoryRefreshed(13, 'Category refreshed'),
  tempFilesCleaned(14, 'Temporary files cleaned');

  final int stageNumber;
  final String stageName;
  const ImportStage(this.stageNumber, this.stageName);

  @override
  String toString() => 'Stage $stageNumber: $stageName';
}

/// Safe diagnostics logger for tracing gallery imports without leaking
/// photo bytes, secrets, keys, or sensitive tokens.
class ImportPipelineLogger {
  ImportPipelineLogger._();

  /// Logs a successful stage advancement
  static void logStage(
    ImportStage stage, {
    String? requestId,
    String? details,
  }) {
    final prefix = requestId != null ? '[$requestId] ' : '';
    final extra = details != null && details.isNotEmpty ? ' - $details' : '';
    debugPrint('[ImportPipeline] $prefix${stage.toString()}$extra');
  }

  /// Logs a stage failure with safe error diagnostics
  static void logFailure(
    ImportStage stage,
    Object error,
    StackTrace? stackTrace, {
    String? requestId,
    String? safeErrorCode,
  }) {
    final prefix = requestId != null ? '[$requestId] ' : '';
    final code = safeErrorCode ?? _deriveSafeErrorCode(error);
    final exceptionType = error.runtimeType.toString();

    debugPrint(
      '===============================================================\n'
      '[ImportPipeline] $prefix${stage.toString()} FAILED\n'
      '  Exception Type: $exceptionType\n'
      '  Safe Error Code: $code\n'
      '  Message: ${_sanitizeErrorMessage(error.toString())}\n'
      '===============================================================',
    );

    if (kDebugMode && stackTrace != null) {
      debugPrint('[ImportPipeline] StackTrace:\n$stackTrace');
    }
  }

  /// Derives an informative, user-facing error message pinpointing the exact failed stage.
  static String getUserFriendlyErrorMessage(ImportStage stage, Object error) {
    final rawMsg = error is AppException
        ? error.message
        : _sanitizeErrorMessage(error.toString());

    switch (stage) {
      case ImportStage.pickerLaunched:
      case ImportStage.pickerReturned:
      case ImportStage.filesSelected:
        return 'Photo selection failed (${stage.stageName}): $rawMsg';

      case ImportStage.sourceOpened:
      case ImportStage.privateTempCopyCreated:
        return 'Failed to read photo from gallery into private storage: $rawMsg';

      case ImportStage.thumbnailCreated:
        return 'Thumbnail generation failed: $rawMsg';

      case ImportStage.fullImageEncrypted:
      case ImportStage.thumbnailEncrypted:
        return 'Client-side AES-256 encryption failed: $rawMsg';

      case ImportStage.uploadSignatureReceived:
        return 'Cloud authorization failed (${stage.stageName}): $rawMsg';

      case ImportStage.fullAssetUploaded:
      case ImportStage.thumbnailUploaded:
        return 'Cloud upload failed (${stage.stageName}): $rawMsg';

      case ImportStage.metadataCommitted:
        return 'Database record creation failed: $rawMsg';

      case ImportStage.categoryRefreshed:
      case ImportStage.tempFilesCleaned:
        return 'Photo uploaded, but local finalization failed: $rawMsg';
    }
  }

  static String _deriveSafeErrorCode(Object error) {
    if (error is AppException && error.code != null) {
      return error.code!;
    }
    final str = error.toString().toLowerCase();
    if (str.contains('404') || str.contains('not found')) {
      return 'EDGE_FUNCTION_NOT_FOUND_404';
    }
    if (str.contains('timeout')) {
      return 'NETWORK_TIMEOUT';
    }
    if (str.contains('unauthorized') || str.contains('401')) {
      return 'UNAUTHORIZED_401';
    }
    if (str.contains('forbidden') || str.contains('403')) {
      return 'FORBIDDEN_403';
    }
    if (str.contains('nosuchbucket')) {
      return 'NO_SUCH_BUCKET';
    }
    return 'UNKNOWN_IMPORT_ERROR';
  }

  static String _sanitizeErrorMessage(String msg) {
    // Redact any potential API keys, bearer tokens, or signature hashes
    return msg
        .replaceAll(RegExp(r'Bearer\s+[A-Za-z0-9\-_.]+'), 'Bearer [REDACTED]')
        .replaceAll(RegExp(r'signature=[A-Fa-f0-9]+'), 'signature=[REDACTED]')
        .replaceAll(RegExp(r'api_key=[A-Za-z0-9]+'), 'api_key=[REDACTED]')
        .replaceAll(
          RegExp(r'api_secret=[A-Za-z0-9]+'),
          'api_secret=[REDACTED]',
        );
  }
}
