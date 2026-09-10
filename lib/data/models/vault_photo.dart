/// Encrypted photo metadata model.
/// Supports both legacy Supabase Storage and Cloudinary raw authenticated assets.
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

  /// Defines whether encrypted bytes reside on 'supabase' or 'cloudinary'
  final String storageProvider;

  /// Cloudinary public identifier for full photo (privora/{userId}/{categoryId}/{photoId})
  final String? cloudinaryPublicId;

  /// Cloudinary public identifier for thumbnail (privora/{userId}/{categoryId}/{photoId}_thumb)
  final String? cloudinaryThumbnailPublicId;

  /// Cloudinary internal asset UUID
  final String? cloudinaryAssetId;

  /// Cloudinary asset version string
  final String? cloudinaryVersion;

  /// Exact ciphertext size in bytes
  final int? encryptedBytes;

  /// Original unencrypted filename before vault import
  final String? originalFilename;

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
    this.storageProvider = 'supabase',
    this.cloudinaryPublicId,
    this.cloudinaryThumbnailPublicId,
    this.cloudinaryAssetId,
    this.cloudinaryVersion,
    this.encryptedBytes,
    this.originalFilename,
  });

  bool get isDeleted => deletedAt != null;
  bool get isCloudinary =>
      storageProvider == 'cloudinary' ||
      storagePath.startsWith('privora/') ||
      thumbnailPath.startsWith('privora/') ||
      (cloudinaryPublicId != null && cloudinaryPublicId!.isNotEmpty);

  int get remainingDays {
    if (deleteAfter == null) return 30;
    final now = DateTime.now();
    final diff = deleteAfter!.difference(now).inDays;
    return diff < 0 ? 0 : diff;
  }

  factory VaultPhoto.fromJson(Map<String, dynamic> json) {
    final cPubId = json['cloudinary_public_id'] as String?;
    final cThumbId = json['cloudinary_thumbnail_public_id'] as String?;
    final rawStoragePath = json['storage_path'] as String? ?? cPubId ?? '';
    final rawThumbPath = json['thumbnail_path'] as String? ?? cThumbId ?? '';

    // Smart provider detection:
    // If 'storage_provider' column is explicit in the record, respect it.
    // If absent (null), check if storagePath or thumbnailPath starts with 'privora/'
    // or if Cloudinary IDs exist. If so, it is Cloudinary. Otherwise default to 'supabase'.
    final rawProvider = json['storage_provider'] as String?;
    final provider =
        rawProvider ??
        ((rawStoragePath.startsWith('privora/') ||
                rawThumbPath.startsWith('privora/') ||
                cPubId != null)
            ? 'cloudinary'
            : 'supabase');

    final isCloud = provider == 'cloudinary';

    return VaultPhoto(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      categoryId: json['category_id'] as String? ?? '',
      storagePath: rawStoragePath,
      thumbnailPath: rawThumbPath,
      displayName: json['display_name'] as String? ?? 'Encrypted Photo',
      mimeType: json['mime_type'] as String? ?? 'image/jpeg',
      encryptedSize: (json['encrypted_size'] is int)
          ? json['encrypted_size'] as int
          : (json['encrypted_size'] != null
                ? int.parse(json['encrypted_size'].toString())
                : (json['encrypted_bytes'] as int? ?? 0)),
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
      storageProvider: provider,
      cloudinaryPublicId: cPubId ?? (isCloud ? rawStoragePath : null),
      cloudinaryThumbnailPublicId: cThumbId ?? (isCloud ? rawThumbPath : null),
      cloudinaryAssetId: json['cloudinary_asset_id'] as String?,
      cloudinaryVersion: json['cloudinary_version']?.toString(),
      encryptedBytes: json['encrypted_bytes'] as int?,
      originalFilename:
          json['original_filename'] as String? ??
          json['display_name'] as String?,
    );
  }

  /// Base schema serialization strictly using columns guaranteed in 001_privora_schema.sql
  Map<String, dynamic> toBaseJson() {
    return {
      'id': id,
      'user_id': userId,
      'category_id': categoryId.isNotEmpty ? categoryId : null,
      'storage_path': storagePath.isNotEmpty
          ? storagePath
          : (cloudinaryPublicId ?? ''),
      'thumbnail_path': thumbnailPath.isNotEmpty
          ? thumbnailPath
          : (cloudinaryThumbnailPublicId ?? ''),
      'display_name': displayName,
      'mime_type': mimeType,
      'encrypted_size': encryptedSize,
      if (width != null) 'width': width,
      if (height != null) 'height': height,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      if (deletedAt != null) 'deleted_at': deletedAt?.toIso8601String(),
      if (deleteAfter != null) 'delete_after': deleteAfter?.toIso8601String(),
    };
  }

  /// Extended schema serialization including optional migration 003 columns
  Map<String, dynamic> toExtendedJson() {
    final base = toBaseJson();
    return {
      ...base,
      if (storageProvider != 'supabase') 'storage_provider': storageProvider,
      if (cloudinaryPublicId != null)
        'cloudinary_public_id': cloudinaryPublicId,
      if (cloudinaryThumbnailPublicId != null)
        'cloudinary_thumbnail_public_id': cloudinaryThumbnailPublicId,
      if (cloudinaryAssetId != null) 'cloudinary_asset_id': cloudinaryAssetId,
      if (cloudinaryVersion != null) 'cloudinary_version': cloudinaryVersion,
      if (encryptedBytes != null) 'encrypted_bytes': encryptedBytes,
      if (originalFilename != null) 'original_filename': originalFilename,
    };
  }

  Map<String, dynamic> toJson() => toExtendedJson();

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
    String? storageProvider,
    String? cloudinaryPublicId,
    String? cloudinaryThumbnailPublicId,
    String? cloudinaryAssetId,
    String? cloudinaryVersion,
    int? encryptedBytes,
    String? originalFilename,
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
      storageProvider: storageProvider ?? this.storageProvider,
      cloudinaryPublicId: cloudinaryPublicId ?? this.cloudinaryPublicId,
      cloudinaryThumbnailPublicId:
          cloudinaryThumbnailPublicId ?? this.cloudinaryThumbnailPublicId,
      cloudinaryAssetId: cloudinaryAssetId ?? this.cloudinaryAssetId,
      cloudinaryVersion: cloudinaryVersion ?? this.cloudinaryVersion,
      encryptedBytes: encryptedBytes ?? this.encryptedBytes,
      originalFilename: originalFilename ?? this.originalFilename,
    );
  }
}
