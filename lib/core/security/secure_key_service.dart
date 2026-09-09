import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../constants/storage_constants.dart';

/// Manages secure local persistence for tokens, PIN verifiers, and wrapped keys.
/// Keys are namespaced with the Supabase User ID to guarantee complete cryptographic
/// isolation between different Google accounts on the same device.
/// Strict rule: Photos and thumbnails are NEVER stored here or anywhere permanently on disk.
class SecureKeyService {
  final FlutterSecureStorage _storage;

  SecureKeyService({FlutterSecureStorage? storage})
    : _storage =
          storage ??
          const FlutterSecureStorage(
            aOptions: AndroidOptions(resetOnError: true),
            iOptions: IOSOptions(
              accessibility: KeychainAccessibility.first_unlock,
            ),
          );

  String _key(String baseKey, [String? userId]) {
    if (userId != null && userId.isNotEmpty) {
      return '${userId}_$baseKey';
    }
    return baseKey;
  }

  Future<void> savePinData({
    required String pinSalt,
    required String pinVerifier,
    required String wrappedMasterKey,
    required String kekNonce,
    String? userId,
  }) async {
    await Future.wait([
      _storage.write(
        key: _key(StorageConstants.securePinSalt, userId),
        value: pinSalt,
      ),
      _storage.write(
        key: _key(StorageConstants.securePinVerifier, userId),
        value: pinVerifier,
      ),
      _storage.write(
        key: _key(StorageConstants.securePinWrappedMasterKey, userId),
        value: wrappedMasterKey,
      ),
      _storage.write(
        key: _key(StorageConstants.securePinKekNonce, userId),
        value: kekNonce,
      ),
      _storage.write(
        key: _key(StorageConstants.secureHasCompletedSetup, userId),
        value: 'true',
      ),
    ]);
  }

  Future<String?> getPinSalt([String? userId]) async {
    return _storage.read(key: _key(StorageConstants.securePinSalt, userId));
  }

  Future<String?> getPinVerifier([String? userId]) async {
    return _storage.read(key: _key(StorageConstants.securePinVerifier, userId));
  }

  Future<String?> getWrappedMasterKey([String? userId]) async {
    return _storage.read(
      key: _key(StorageConstants.securePinWrappedMasterKey, userId),
    );
  }

  Future<String?> getKekNonce([String? userId]) async {
    return _storage.read(key: _key(StorageConstants.securePinKekNonce, userId));
  }

  Future<bool> hasCompletedSetup([String? userId]) async {
    final val = await _storage.read(
      key: _key(StorageConstants.secureHasCompletedSetup, userId),
    );
    return val == 'true';
  }

  Future<int> getFailedAttempts([String? userId]) async {
    final val = await _storage.read(
      key: _key(StorageConstants.secureFailedPinAttempts, userId),
    );
    if (val == null) return 0;
    return int.tryParse(val) ?? 0;
  }

  Future<void> setFailedAttempts(int attempts, [String? userId]) async {
    await _storage.write(
      key: _key(StorageConstants.secureFailedPinAttempts, userId),
      value: attempts.toString(),
    );
  }

  Future<DateTime?> getLockoutUntil([String? userId]) async {
    final val = await _storage.read(
      key: _key(StorageConstants.secureLockoutUntil, userId),
    );
    if (val == null) return null;
    final ms = int.tryParse(val);
    if (ms == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(ms);
  }

  Future<void> setLockoutUntil(DateTime? until, [String? userId]) async {
    final key = _key(StorageConstants.secureLockoutUntil, userId);
    if (until == null) {
      await _storage.delete(key: key);
    } else {
      await _storage.write(
        key: key,
        value: until.millisecondsSinceEpoch.toString(),
      );
    }
  }

  Future<void> resetLockout([String? userId]) async {
    await Future.wait([
      _storage.delete(
        key: _key(StorageConstants.secureFailedPinAttempts, userId),
      ),
      _storage.delete(key: _key(StorageConstants.secureLockoutUntil, userId)),
    ]);
  }

  /// Deletes encrypted credentials and PIN verifier for a specific user ID
  Future<void> clearUserKeys(String userId) async {
    await Future.wait([
      _storage.delete(key: _key(StorageConstants.securePinSalt, userId)),
      _storage.delete(key: _key(StorageConstants.securePinVerifier, userId)),
      _storage.delete(
        key: _key(StorageConstants.securePinWrappedMasterKey, userId),
      ),
      _storage.delete(key: _key(StorageConstants.securePinKekNonce, userId)),
      _storage.delete(
        key: _key(StorageConstants.secureHasCompletedSetup, userId),
      ),
      _storage.delete(
        key: _key(StorageConstants.secureFailedPinAttempts, userId),
      ),
      _storage.delete(key: _key(StorageConstants.secureLockoutUntil, userId)),
    ]);
  }

  /// Clears all local vault secrets across all users (e.g. device wipe)
  Future<void> clearAll() async {
    await _storage.deleteAll();
  }
}
