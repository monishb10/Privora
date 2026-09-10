import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../config/supabase_config.dart';
import '../constants/storage_constants.dart';
import '../errors/app_exception.dart';

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
    final effectiveId = (userId != null && userId.isNotEmpty)
        ? userId
        : SupabaseConfig.client?.auth.currentUser?.id;
    if (effectiveId != null && effectiveId.isNotEmpty) {
      return '${effectiveId}_$baseKey';
    }
    return 'local_$baseKey';
  }

  /// Cleans legacy non-namespaced keys from earlier versions to prevent
  /// cross-account credential leakage.
  Future<void> cleanLegacySharedKeys() async {
    await Future.wait([
      _storage.delete(key: StorageConstants.securePinSalt),
      _storage.delete(key: StorageConstants.securePinVerifier),
      _storage.delete(key: StorageConstants.securePinWrappedMasterKey),
      _storage.delete(key: StorageConstants.securePinKekNonce),
      _storage.delete(key: StorageConstants.secureHasCompletedSetup),
      _storage.delete(key: StorageConstants.secureRecoveryCode),
      _storage.delete(key: StorageConstants.secureFailedPinAttempts),
      _storage.delete(key: StorageConstants.secureLockoutUntil),
    ]);
  }

  Future<void> savePinData({
    required String pinSalt,
    required String pinVerifier,
    required String wrappedMasterKey,
    required String kekNonce,
    String? userId,
  }) async {
    final effectiveUserId = (userId != null && userId.isNotEmpty)
        ? userId
        : SupabaseConfig.client?.auth.currentUser?.id;

    await Future.wait([
      _storage.write(
        key: _key(StorageConstants.securePinSalt, effectiveUserId),
        value: pinSalt,
      ),
      _storage.write(
        key: _key(StorageConstants.securePinVerifier, effectiveUserId),
        value: pinVerifier,
      ),
      _storage.write(
        key: _key(StorageConstants.securePinWrappedMasterKey, effectiveUserId),
        value: wrappedMasterKey,
      ),
      _storage.write(
        key: _key(StorageConstants.securePinKekNonce, effectiveUserId),
        value: kekNonce,
      ),
      _storage.write(
        key: _key(StorageConstants.secureHasCompletedSetup, effectiveUserId),
        value: 'true',
      ),
    ]);

    // Read back and verify persistence
    final verifiedSetup = await hasCompletedSetup(effectiveUserId);
    final verifiedVerifier = await getPinVerifier(effectiveUserId);
    if (!verifiedSetup || verifiedVerifier == null) {
      throw const CryptoException(
        'Failed to verify secure local PIN storage. Please try again.',
      );
    }
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

  Future<void> saveRecoveryCode(String userId, String code) async {
    await _storage.write(
      key: _key(StorageConstants.secureRecoveryCode, userId),
      value: code,
    );
  }

  Future<String?> getRecoveryCode(String userId) async {
    return _storage.read(
      key: _key(StorageConstants.secureRecoveryCode, userId),
    );
  }

  Future<void> deleteRecoveryCode(String userId) async {
    await _storage.delete(
      key: _key(StorageConstants.secureRecoveryCode, userId),
    );
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
      _storage.delete(key: _key(StorageConstants.secureRecoveryCode, userId)),
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
