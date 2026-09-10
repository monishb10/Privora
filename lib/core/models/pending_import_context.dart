import 'dart:convert';

/// Represents the non-sensitive state of an in-flight gallery photo import operation.
/// Preserved across lifecycle transitions, background timeouts, and Android activity death.
class PendingImportContext {
  final String requestId;
  final String userId;
  final String categoryId;
  final String categoryName;
  final String pickerType;
  final DateTime startTime;
  final List<String> tempFilePaths;

  const PendingImportContext({
    required this.requestId,
    required this.userId,
    required this.categoryId,
    required this.categoryName,
    required this.pickerType,
    required this.startTime,
    this.tempFilePaths = const [],
  });

  PendingImportContext copyWith({
    String? requestId,
    String? userId,
    String? categoryId,
    String? categoryName,
    String? pickerType,
    DateTime? startTime,
    List<String>? tempFilePaths,
  }) {
    return PendingImportContext(
      requestId: requestId ?? this.requestId,
      userId: userId ?? this.userId,
      categoryId: categoryId ?? this.categoryId,
      categoryName: categoryName ?? this.categoryName,
      pickerType: pickerType ?? this.pickerType,
      startTime: startTime ?? this.startTime,
      tempFilePaths: tempFilePaths ?? this.tempFilePaths,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'request_id': requestId,
      'user_id': userId,
      'category_id': categoryId,
      'category_name': categoryName,
      'picker_type': pickerType,
      'start_time': startTime.toIso8601String(),
      'temp_file_paths': tempFilePaths,
    };
  }

  factory PendingImportContext.fromJson(Map<String, dynamic> json) {
    return PendingImportContext(
      requestId: json['request_id'] as String,
      userId: json['user_id'] as String,
      categoryId: json['category_id'] as String,
      categoryName: json['category_name'] as String? ?? 'Category',
      pickerType: json['picker_type'] as String? ?? 'gallery_multi',
      startTime:
          DateTime.tryParse(json['start_time'] as String? ?? '') ??
          DateTime.now(),
      tempFilePaths:
          (json['temp_file_paths'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
    );
  }

  String serialize() => jsonEncode(toJson());

  static PendingImportContext? deserialize(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return PendingImportContext.fromJson(decoded);
    } catch (_) {
      return null;
    }
  }

  @override
  String toString() {
    return 'PendingImportContext(requestId: $requestId, userId: $userId, '
        'categoryId: $categoryId, pickerType: $pickerType, '
        'filesCount: ${tempFilePaths.length}, startTime: $startTime)';
  }
}
