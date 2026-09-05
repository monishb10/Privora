/// Encrypted photo metadata model.
/// Binary data is stored encrypted in Supabase Storage.
class VaultPhoto {
  final String id;
  final String userId;
  final String categoryId;
  final String storagePath;
  final String thumbnailPath;
  final String displayName;
  final String mimeType;
  final int encryptedSize;
  final int? width;
  final int? height;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  final DateTime? deleteAfter;

  const VaultPhoto({
    required this.id,
    required this.userId,
    required this.categoryId,
    required this.storagePath,
    required this.thumbnailPath,
    required this.displayName,
    required this.mimeType,
    required this.encryptedSize,
    this.width,
    this.height,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
    this.deleteAfter,
  });

  bool get isDeleted => deletedAt != null;

  int get remainingDays {
    if (deleteAfter == null) return 30;
    final now = DateTime.now();
    final diff = deleteAfter!.difference(now).inDays;
    return diff < 0 ? 0 : diff;
  }

  factory VaultPhoto.fromJson(Map<String, dynamic> json) {
    return VaultPhoto(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      categoryId: json['category_id'] as String,
      storagePath: json['storage_path'] as String,
      thumbnailPath: json['thumbnail_path'] as String,
      displayName: json['display_name'] as String,
      mimeType: json['mime_type'] as String,
      encryptedSize: (json['encrypted_size'] is int)
          ? json['encrypted_size'] as int
          : int.parse(json['encrypted_size'].toString()),
      width: json['width'] as int?,
      height: json['height'] as int?,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : DateTime.now(),
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'] as String)
          : DateTime.now(),
      deletedAt: json['deleted_at'] != null
          ? DateTime.parse(json['deleted_at'] as String)
          : null,
      deleteAfter: json['delete_after'] != null
          ? DateTime.parse(json['delete_after'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'category_id': categoryId,
      'storage_path': storagePath,
      'thumbnail_path': thumbnailPath,
      'display_name': displayName,
      'mime_type': mimeType,
      'encrypted_size': encryptedSize,
      'width': width,
      'height': height,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'deleted_at': deletedAt?.toIso8601String(),
      'delete_after': deleteAfter?.toIso8601String(),
    };
  }

  VaultPhoto copyWith({
    String? id,
    String? userId,
    String? categoryId,
    String? storagePath,
    String? thumbnailPath,
    String? displayName,
    String? mimeType,
    int? encryptedSize,
    int? width,
    int? height,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? deletedAt,
    DateTime? deleteAfter,
  }) {
    return VaultPhoto(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      categoryId: categoryId ?? this.categoryId,
      storagePath: storagePath ?? this.storagePath,
      thumbnailPath: thumbnailPath ?? this.thumbnailPath,
      displayName: displayName ?? this.displayName,
      mimeType: mimeType ?? this.mimeType,
      encryptedSize: encryptedSize ?? this.encryptedSize,
      width: width ?? this.width,
      height: height ?? this.height,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      deleteAfter: deleteAfter ?? this.deleteAfter,
    );
  }
}
