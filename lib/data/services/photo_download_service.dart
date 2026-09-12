import 'dart:async';
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

  static const int maxCachedThumbnails = 150;
  static const int maxCachedFullPhotos = 5;
  static const int maxConcurrentThumbnailDownloads = 4;

  // Bounded in-memory LRU caches
  final Map<String, Uint8List> _thumbnailCache = {};
  final Map<String, Uint8List> _fullPhotoCache = {};

  // Track pending downloads to avoid duplicate concurrent network requests
  final Map<String, Future<Uint8List>> _pendingLoads = {};

  // Session cache for signed download URLs (memoized during viewer session)
  final Map<String, String> _signedUrlCache = {};

  // Bounded concurrency tracking for thumbnail downloads
  int _activeThumbnailDownloads = 0;
  final List<Completer<void>> _concurrencyQueue = [];

  PhotoDownloadService({
    this.storageService,
    this.cloudinaryService,
    required this.cryptoService,
  });

  /// Backward-compatible view of in-memory cache
  Map<String, Uint8List> get memoryCache => {
    ..._thumbnailCache,
    ..._fullPhotoCache,
  };

  /// Constructs a user-isolated thumbnail memoization key.
  String getThumbnailKey(VaultPhoto photo, [String? userId]) {
    final uid = userId ?? photo.userId;
    final assetIdentifier = photo.isCloudinary
        ? (photo.cloudinaryThumbnailPublicId ??
              photo.cloudinaryPublicId ??
              photo.id)
        : photo.thumbnailPath;
    return '$uid:thumb:${photo.id}:$assetIdentifier';
  }

  /// Constructs a user-isolated full-photo memoization key.
  String getFullPhotoKey(VaultPhoto photo, [String? userId]) {
    final uid = userId ?? photo.userId;
    final assetIdentifier = photo.isCloudinary
        ? (photo.cloudinaryPublicId ?? photo.id)
        : photo.storagePath;
    return '$uid:full:${photo.id}:$assetIdentifier';
  }

  /// Synchronously checks whether a decrypted thumbnail is already in memory.
  Uint8List? getCachedThumbnail(VaultPhoto photo, {String? userId}) {
    final key = getThumbnailKey(photo, userId);
    final cached = _thumbnailCache[key];
    if (cached != null) {
      // Refresh LRU order
      _thumbnailCache.remove(key);
      _thumbnailCache[key] = cached;
    }
    return cached;
  }

  /// Synchronously checks whether a decrypted full photo is already in memory.
  Uint8List? getCachedFullPhoto(VaultPhoto photo, {String? userId}) {
    final key = getFullPhotoKey(photo, userId);
    final cached = _fullPhotoCache[key];
    if (cached != null) {
      // Refresh LRU order
      _fullPhotoCache.remove(key);
      _fullPhotoCache[key] = cached;
    }
    return cached;
  }

  /// Loads and decrypts a thumbnail into memory, using memory cache if already decrypted.
  Future<Uint8List> getDecryptedThumbnail({
    required VaultPhoto photo,
    required Uint8List masterKey,
  }) async {
    final cacheKey = getThumbnailKey(photo);
    final cached = getCachedThumbnail(photo);
    if (cached != null) return cached;

    if (_pendingLoads.containsKey(cacheKey)) {
      return _pendingLoads[cacheKey]!;
    }

    final future = _withThumbnailConcurrencyLimit(
      () => _fetchDecryptAndCache(
        cacheKey: cacheKey,
        photo: photo,
        isThumbnail: true,
        masterKey: masterKey,
      ),
    );
    _pendingLoads[cacheKey] = future;

    try {
      final result = await future;
      return result;
    } finally {
      _pendingLoads.remove(cacheKey);
    }
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
    final cacheKey = getFullPhotoKey(photo);
    final cached = getCachedFullPhoto(photo);
    if (cached != null) return cached;

    if (_pendingLoads.containsKey(cacheKey)) {
      return _pendingLoads[cacheKey]!;
    }

    final future = _fetchDecryptAndCache(
      cacheKey: cacheKey,
      photo: photo,
      isThumbnail: false,
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

  /// Backward-compatible overload for raw full photo storage path.
  Future<Uint8List> getDecryptedFullPhotoByPath({
    required String photoPath,
    required Uint8List masterKey,
  }) async {
    return _loadAndDecryptLegacy(photoPath, masterKey);
  }

  Future<T> _withThumbnailConcurrencyLimit<T>(Future<T> Function() task) async {
    if (_activeThumbnailDownloads >= maxConcurrentThumbnailDownloads) {
      final completer = Completer<void>();
      _concurrencyQueue.add(completer);
      await completer.future;
    }
    _activeThumbnailDownloads++;
    try {
      return await task();
    } finally {
      _activeThumbnailDownloads--;
      if (_concurrencyQueue.isNotEmpty) {
        final next = _concurrencyQueue.removeAt(0);
        if (!next.isCompleted) {
          next.complete();
        }
      }
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

      final target = isThumbnail ? 'thumbnail' : 'full';
      final urlKey = '${photo.id}:$target';

      // 1. Check or request signed delivery URL from Edge Function
      String? signedUrl = _signedUrlCache[urlKey];
      if (signedUrl == null) {
        signedUrl = await cService.getSignedDownloadUrl(
          photoId: photo.id,
          target: target,
        );
        _signedUrlCache[urlKey] = signedUrl;
      }

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

      // Store in appropriate bounded LRU memory-only cache
      if (isThumbnail) {
        _putThumbnailInCache(cacheKey, decrypted);
      } else {
        _putFullPhotoInCache(cacheKey, decrypted);
      }

      return decrypted;
    } catch (e) {
      debugPrint('Failed to decrypt photo ${photo.id}: $e');
      if (e is CryptoException) rethrow;
      throw const CryptoException('Failed to decrypt photo');
    }
  }

  void _putThumbnailInCache(String key, Uint8List bytes) {
    _thumbnailCache.remove(key);
    _thumbnailCache[key] = bytes;
    if (_thumbnailCache.length > maxCachedThumbnails) {
      _thumbnailCache.remove(_thumbnailCache.keys.first);
    }
  }

  void _putFullPhotoInCache(String key, Uint8List bytes) {
    _fullPhotoCache.remove(key);
    _fullPhotoCache[key] = bytes;
    if (_fullPhotoCache.length > maxCachedFullPhotos) {
      _fullPhotoCache.remove(_fullPhotoCache.keys.first);
    }
  }

  Future<Uint8List> _loadAndDecryptLegacy(
    String path,
    Uint8List masterKey,
  ) async {
    final cached = _thumbnailCache[path] ?? _fullPhotoCache[path];
    if (cached != null) return cached;

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
        _putThumbnailInCache(path, decrypted);
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

  /// Clears full-resolution photo bytes when closing the viewer.
  void clearFullPhotoCache() {
    _fullPhotoCache.clear();
    _signedUrlCache.clear();
    debugPrint('Privora: Full photo memory cache cleared.');
  }

  /// Clears all decrypted image bytes from memory immediately.
  /// Called when the app is locked, minimized, or the user logs out.
  void clearMemoryCache([String? userId]) {
    if (userId == null) {
      _thumbnailCache.clear();
      _fullPhotoCache.clear();
      _pendingLoads.clear();
      _signedUrlCache.clear();
    } else {
      _thumbnailCache.removeWhere((k, _) => k.startsWith('$userId:'));
      _fullPhotoCache.removeWhere((k, _) => k.startsWith('$userId:'));
      _pendingLoads.removeWhere((k, _) => k.startsWith('$userId:'));
      _signedUrlCache.removeWhere((k, _) => k.startsWith('$userId:'));
    }
    debugPrint('Privora: In-memory decrypted photo cache cleared.');
  }
}
