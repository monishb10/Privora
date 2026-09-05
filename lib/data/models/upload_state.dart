enum UploadStatus {
  idle,
  reading,
  generatingThumbnail,
  encrypting,
  uploadingThumbnail,
  uploadingFullPhoto,
  savingMetadata,
  completed,
  error,
}

/// Represents the real-time state of a photo encryption and upload process.
class UploadState {
  final UploadStatus status;
  final double progress; // 0.0 to 1.0
  final String? currentFileName;
  final int totalCount;
  final int currentIndex;
  final String? errorMessage;

  const UploadState({
    this.status = UploadStatus.idle,
    this.progress = 0.0,
    this.currentFileName,
    this.totalCount = 0,
    this.currentIndex = 0,
    this.errorMessage,
  });

  bool get isInProgress =>
      status != UploadStatus.idle &&
      status != UploadStatus.completed &&
      status != UploadStatus.error;

  String get statusMessage {
    switch (status) {
      case UploadStatus.idle:
        return 'Ready';
      case UploadStatus.reading:
        return 'Reading media...';
      case UploadStatus.generatingThumbnail:
        return 'Generating preview...';
      case UploadStatus.encrypting:
        return 'Encrypting with AES-256-GCM...';
      case UploadStatus.uploadingThumbnail:
        return 'Uploading encrypted thumbnail...';
      case UploadStatus.uploadingFullPhoto:
        return 'Uploading encrypted photo...';
      case UploadStatus.savingMetadata:
        return 'Securing vault records...';
      case UploadStatus.completed:
        return 'Upload complete';
      case UploadStatus.error:
        return errorMessage ?? 'Upload failed';
    }
  }

  UploadState copyWith({
    UploadStatus? status,
    double? progress,
    String? currentFileName,
    int? totalCount,
    int? currentIndex,
    String? errorMessage,
  }) {
    return UploadState(
      status: status ?? this.status,
      progress: progress ?? this.progress,
      currentFileName: currentFileName ?? this.currentFileName,
      totalCount: totalCount ?? this.totalCount,
      currentIndex: currentIndex ?? this.currentIndex,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}
