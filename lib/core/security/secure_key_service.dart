import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../constants/storage_constants.dart';

/// Manages secure local persistence for tokens, PIN verifiers, and wrapped keys.
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

  Future<void> savePinData({
    required String pinSalt,
    required String pinVerifier,
    required String wrappedMasterKey,
    required String kekNonce,
  }) async {
    await Future.wait([
      _storage.write(key: StorageConstants.securePinSalt, value: pinSalt),
      _storage.write(
        key: StorageConstants.securePinVerifier,
        value: pinVerifier,
      ),
      _storage.write(
        key: StorageConstants.securePinWrappedMasterKey,
        value: wrappedMasterKey,
      ),
      _storage.write(key: StorageConstants.securePinKekNonce, value: kekNonce),
      _storage.write(
        key: StorageConstants.secureHasCompletedSetup,
        value: 'true',
      ),
    ]);
  }

  Future<String?> getPinSalt() =>
      _storage.read(key: StorageConstants.securePinSalt);
  Future<String?> getPinVerifier() =>
      _storage.read(key: StorageConstants.securePinVerifier);
  Future<String?> getWrappedMasterKey() =>
      _storage.read(key: StorageConstants.securePinWrappedMasterKey);
  Future<String?> getKekNonce() =>
      _storage.read(key: StorageConstants.securePinKekNonce);

  Future<bool> hasCompletedSetup() async {
    final val = await _storage.read(
      key: StorageConstants.secureHasCompletedSetup,
    );
    return val == 'true';
  }

  Future<int> getFailedAttempts() async {
    final val = await _storage.read(
      key: StorageConstants.secureFailedPinAttempts,
    );
    if (val == null) return 0;
    return int.tryParse(val) ?? 0;
  }

  Future<void> setFailedAttempts(int attempts) async {
    await _storage.write(
      key: StorageConstants.secureFailedPinAttempts,
      value: attempts.toString(),
    );
  }

  Future<DateTime?> getLockoutUntil() async {
    final val = await _storage.read(key: StorageConstants.secureLockoutUntil);
    if (val == null) return null;
    final ms = int.tryParse(val);
    if (ms == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(ms);
  }

  Future<void> setLockoutUntil(DateTime? until) async {
    if (until == null) {
      await _storage.delete(key: StorageConstants.secureLockoutUntil);
    } else {
      await _storage.write(
        key: StorageConstants.secureLockoutUntil,
        value: until.millisecondsSinceEpoch.toString(),
      );
    }
  }

  Future<void> resetLockout() async {
    await Future.wait([
      _storage.delete(key: StorageConstants.secureFailedPinAttempts),
      _storage.delete(key: StorageConstants.secureLockoutUntil),
    ]);
  }

  /// Clears all local vault secrets when the user logs out or deletes the account
  Future<void> clearAll() async {
    await _storage.deleteAll();
  }
}
