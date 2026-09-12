import 'package:flutter/foundation.dart';
import '../../core/errors/app_exception.dart';
import '../../core/security/vault_crypto_service.dart';
import '../models/vault_photo.dart';
import 'cloudinary_media_service.dart';
import 'supabase_storage_service.dart';

/// Service managing memory-only download and decryption of photos and thumbnails.
/// Supports both Cloudinary signed authenticated assets and legacy Supabase Storage.
/// Strict rule: Decrypted bytes are kept in RAM only and cleared immediately when locked.
class PhotoDownloadService {
  final SupabaseStorageService? storageService;
  final CloudinaryMediaService? cloudinaryService;
  final VaultCryptoService cryptoService;

  // In-memory memory cache keyed by ID/path (e.g. "thumb_photoId" -> decrypted Uint8List)
  final Map<String, Uint8List> _memoryCache = {};

  // Track pending downloads to avoid duplicate concurrent network requests
  final Map<String, Future<Uint8List>> _pendingLoads = {};

  PhotoDownloadService({
    this.storageService,
    this.cloudinaryService,
    required this.cryptoService,
  });

  /// Loads and decrypts a thumbnail into memory, using memory cache if already decrypted.
  Future<Uint8List> getDecryptedThumbnail({
    required VaultPhoto photo,
    required Uint8List masterKey,
  }) async {
    final cacheKey = 'thumb_${photo.id}';
    return _loadAndDecrypt(
      cacheKey: cacheKey,
      photo: photo,
      isThumbnail: true,
      masterKey: masterKey,
    );
  }

  /// Backward-compatible overload for raw thumbnail storage path.
  Future<Uint8List> getDecryptedThumbnailByPath({
    required String thumbnailPath,
    required Uint8List masterKey,
  }) async {
    return _loadAndDecryptLegacy(thumbnailPath, masterKey);
  }

  /// Loads and decrypts a full-resolution photo into memory for the full-screen viewer.
  Future<Uint8List> getDecryptedFullPhoto({
    required VaultPhoto photo,
    required Uint8List masterKey,
  }) async {
    final cacheKey = 'full_${photo.id}';
    return _loadAndDecrypt(
      cacheKey: cacheKey,
      photo: photo,
      isThumbnail: false,
      masterKey: masterKey,
    );
  }

  /// Backward-compatible overload for raw full photo storage path.
  Future<Uint8List> getDecryptedFullPhotoByPath({
    required String photoPath,
    required Uint8List masterKey,
  }) async {
    return _loadAndDecryptLegacy(photoPath, masterKey);
  }

  Future<Uint8List> _loadAndDecrypt({
    required String cacheKey,
    required VaultPhoto photo,
    required bool isThumbnail,
    required Uint8List masterKey,
  }) async {
    // 1. Check in-memory RAM cache
    if (_memoryCache.containsKey(cacheKey)) {
      return _memoryCache[cacheKey]!;
    }

    // 2. Check if a download for this asset is already in flight
    if (_pendingLoads.containsKey(cacheKey)) {
      return _pendingLoads[cacheKey]!;
    }

    final future = _fetchDecryptAndCache(
      cacheKey: cacheKey,
      photo: photo,
      isThumbnail: isThumbnail,
      masterKey: masterKey,
    );
    _pendingLoads[cacheKey] = future;

    try {
      final result = await future;
      return result;
    } finally {
      _pendingLoads.remove(cacheKey);
    }
  }

  Future<Uint8List> _fetchDecryptAndCache({
    required String cacheKey,
    required VaultPhoto photo,
    required bool isThumbnail,
    required Uint8List masterKey,
  }) async {
    Uint8List encryptedBytes;

    if (photo.isCloudinary) {
      final cService = cloudinaryService;
      if (cService == null) {
        throw const StorageException('Cloudinary service is not configured.');
      }

      // 1. Request signed delivery URL from Edge Function
      final target = isThumbnail ? 'thumbnail' : 'full';
      final signedUrl = await cService.getSignedDownloadUrl(
        photoId: photo.id,
        target: target,
      );

      // 2. Download encrypted ciphertext bytes via HTTP
      encryptedBytes = await cService.downloadEncryptedBytes(signedUrl);
    } else {
      // Legacy Supabase Storage download
      final sService = storageService;
      if (sService == null) {
        throw const StorageException(
          'Supabase storage service is not configured.',
        );
      }
      final path = isThumbnail ? photo.thumbnailPath : photo.storagePath;
      encryptedBytes = await sService.downloadEncryptedBytes(path);
    }

    // 3. Decrypt in RAM strictly after successful download
    try {
      final decrypted = await cryptoService.decryptPhotoBytes(
        encryptedBytes,
        masterKey,
      );

      // Store in memory-only cache
      _memoryCache[cacheKey] = decrypted;
      return decrypted;
    } catch (e) {
      debugPrint('Failed to decrypt photo ${photo.id}: $e');
      if (e is CryptoException) rethrow;
      throw const CryptoException('Failed to decrypt photo');
    }
  }

  Future<Uint8List> _loadAndDecryptLegacy(
    String path,
    Uint8List masterKey,
  ) async {
    if (_memoryCache.containsKey(path)) {
      return _memoryCache[path]!;
    }
    if (_pendingLoads.containsKey(path)) {
      return _pendingLoads[path]!;
    }

    final future = () async {
      final sService = storageService;
      if (sService == null) {
        throw const StorageException(
          'Supabase storage service is not configured.',
        );
      }
      final encryptedBytes = await sService.downloadEncryptedBytes(path);
      try {
        final decrypted = await cryptoService.decryptPhotoBytes(
          encryptedBytes,
          masterKey,
        );
        _memoryCache[path] = decrypted;
        return decrypted;
      } catch (e) {
        debugPrint('Failed to decrypt photo: $e');
        if (e is CryptoException) rethrow;
        throw const CryptoException('Failed to decrypt photo');
      }
    }();

    _pendingLoads[path] = future;
    try {
      return await future;
    } finally {
      _pendingLoads.remove(path);
    }
  }

  /// Clears all decrypted image bytes from memory immediately.
  /// Called when the app is locked, minimized, or the user logs out.
  void clearMemoryCache() {
    _memoryCache.clear();
    _pendingLoads.clear();
    debugPrint('Privora: In-memory decrypted photo cache cleared.');
  }
}
