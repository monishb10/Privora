import 'package:flutter/foundation.dart';
import '../../core/errors/app_exception.dart';
import '../../core/security/vault_crypto_service.dart';
import 'supabase_storage_service.dart';

/// Service managing memory-only download and decryption of photos and thumbnails.
/// Strict rule: Decrypted bytes are kept in RAM only and cleared immediately when locked.
class PhotoDownloadService {
  final SupabaseStorageService storageService;
  final VaultCryptoService cryptoService;

  // In-memory memory cache keyed by storage path (e.g. "path/thumb.enc" -> decrypted Uint8List)
  final Map<String, Uint8List> _memoryCache = {};

  // Track pending downloads to avoid duplicate concurrent network requests
  final Map<String, Future<Uint8List>> _pendingLoads = {};

  PhotoDownloadService({
    required this.storageService,
    required this.cryptoService,
  });

  /// Loads and decrypts a thumbnail into memory, using memory cache if already decrypted.
  Future<Uint8List> getDecryptedThumbnail({
    required String thumbnailPath,
    required Uint8List masterKey,
  }) async {
    return _loadAndDecrypt(thumbnailPath, masterKey);
  }

  /// Loads and decrypts a full-resolution photo into memory for the full-screen viewer.
  Future<Uint8List> getDecryptedFullPhoto({
    required String photoPath,
    required Uint8List masterKey,
  }) async {
    return _loadAndDecrypt(photoPath, masterKey);
  }

  Future<Uint8List> _loadAndDecrypt(String path, Uint8List masterKey) async {
    // 1. Check in-memory RAM cache
    if (_memoryCache.containsKey(path)) {
      return _memoryCache[path]!;
    }

    // 2. Check if a download for this path is already in flight
    if (_pendingLoads.containsKey(path)) {
      return _pendingLoads[path]!;
    }

    final future = _fetchDecryptAndCache(path, masterKey);
    _pendingLoads[path] = future;

    try {
      final result = await future;
      return result;
    } finally {
      _pendingLoads.remove(path);
    }
  }

  Future<Uint8List> _fetchDecryptAndCache(
    String path,
    Uint8List masterKey,
  ) async {
    try {
      // Authenticated download from private bucket
      final encryptedBytes = await storageService.downloadEncryptedBytes(path);

      // Decrypt in RAM
      final decrypted = await cryptoService.decryptPhotoBytes(
        encryptedBytes,
        masterKey,
      );

      // Store in memory-only cache
      _memoryCache[path] = decrypted;
      return decrypted;
    } catch (e) {
      debugPrint('Failed to download or decrypt $path: $e');
      throw CryptoException('Failed to load image: ${e.toString()}');
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
