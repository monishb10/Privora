import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../../core/errors/app_exception.dart';
import '../../core/security/pin_service.dart';
import '../../core/security/secure_key_service.dart';
import '../../core/security/vault_crypto_service.dart';
import '../services/supabase_database_service.dart';
import '../services/vault_otp_service.dart';

/// Coordinates local PIN wrapping, the server PIN envelope, and Gmail-OTP PIN
/// reset. New builds never create or display a user-managed recovery code.
class VaultRepository {
  final PinService pinService;
  final VaultCryptoService cryptoService;
  final SecureKeyService secureKeyService;
  final SupabaseDatabaseService databaseService;
  final VaultOtpService otpService;

  VaultRepository({
    required this.pinService,
    required this.cryptoService,
    required this.secureKeyService,
    required this.databaseService,
    VaultOtpService? otpService,
  }) : otpService = otpService ?? VaultOtpService();

  bool get hasActiveKey => pinService.hasActiveKey;
  Uint8List? get activeMasterKey => pinService.activeMasterKey;

  Future<bool> hasCompletedSetup([String? userId]) {
    return secureKeyService.hasCompletedSetup(userId);
  }

  Future<Map<String, dynamic>?> getServerVaultData(String userId) {
    return databaseService.getVaultKeys(userId);
  }

  bool hasServerPinEnvelope(Map<String, dynamic>? data) {
    if (data == null) return false;
    return _nonEmpty(data['pin_wrapped_key']) &&
        _nonEmpty(data['pin_salt']) &&
        _nonEmpty(data['pin_nonce']) &&
        _nonEmpty(data['pin_verifier']);
  }

  bool _nonEmpty(dynamic value) => value != null && value.toString().isNotEmpty;

  /// Creates a new vault, saves the per-user PIN envelope, and creates the
  /// server-encrypted key backup required for Gmail OTP PIN reset.
  Future<void> initializeNewVault({
    required String userId,
    required String pin,
  }) async {
    try {
      final existing = await databaseService.getVaultKeys(userId);
      if (hasServerPinEnvelope(existing) ||
          _nonEmpty(existing?['recovery_wrapped_key'])) {
        throw const PinException(
          'This Google account already has a vault. Enter its PIN or use Forgot PIN.',
        );
      }

      final masterKey = cryptoService.generateMasterKey();

      // The reset backup is mandatory. If the protected function is not
      // configured, onboarding stops before committing a new PIN envelope.
      await otpService.storeMasterKey(masterKey);
      await pinService.setupPin(pin: pin, masterKey: masterKey, userId: userId);
      await _persistPinEnvelope(userId);
      await secureKeyService.setOtpBackupConfigured(userId, true);
      await secureKeyService.deleteLegacyMigrationSecret(userId);
    } catch (error) {
      if (kDebugMode) debugPrint('initializeNewVault error: $error');
      if (error is AppException) rethrow;
      throw const CryptoException('Failed to create the encrypted vault.');
    }
  }

  /// Downloads this user's server PIN envelope to a new device. It is still
  /// encrypted by the user's six-digit PIN; no plaintext key is downloaded.
  Future<bool> syncServerPinEnvelopeIfMissing(
    String userId, {
    Map<String, dynamic>? serverVault,
  }) async {
    if (await hasCompletedSetup(userId)) return true;

    final data = serverVault ?? await getServerVaultData(userId);
    if (!hasServerPinEnvelope(data)) return false;

    await secureKeyService.savePinData(
      pinSalt: data!['pin_salt'].toString(),
      pinVerifier: data['pin_verifier'].toString(),
      wrappedMasterKey: data['pin_wrapped_key'].toString(),
      kekNonce: data['pin_nonce'].toString(),
      userId: userId,
    );
    return true;
  }

  Future<bool> hasEmailOtpBackup() {
    return otpService.hasEnvelope();
  }

  /// One-time, invisible upgrade path for people who created vaults in an
  /// older build. It converts the deprecated local migration secret into the
  /// Gmail-OTP key envelope and immediately deletes the local secret. Nothing
  /// is shown to or requested from the user.
  Future<bool> migrateLegacyKeyBackupIfPossible(
    String userId, {
    Map<String, dynamic>? serverVault,
  }) async {
    if (await secureKeyService.hasOtpBackupConfigured(userId)) return true;

    try {
      if (await otpService.hasEnvelope()) {
        await secureKeyService.setOtpBackupConfigured(userId, true);
        await secureKeyService.deleteLegacyMigrationSecret(userId);
        return true;
      }
    } catch (_) {
      // Continue with the local one-time migration attempt below.
    }

    final migrationSecret = await secureKeyService.getLegacyMigrationSecret(
      userId,
    );
    if (migrationSecret == null || migrationSecret.isEmpty) return false;

    final data = serverVault ?? await databaseService.getVaultKeys(userId);
    if (!_nonEmpty(data?['recovery_wrapped_key']) ||
        !_nonEmpty(data?['recovery_salt']) ||
        !_nonEmpty(data?['recovery_nonce'])) {
      return false;
    }

    Uint8List? masterKey;
    try {
      final salt = base64Decode(data!['recovery_salt'].toString());
      final legacyKey = await cryptoService.deriveKeyFromLegacyMigrationSecret(
        migrationSecret,
        salt,
      );
      masterKey = await cryptoService.unwrapMasterKey(
        wrappedKeyBase64: data['recovery_wrapped_key'].toString(),
        nonceBase64: data['recovery_nonce'].toString(),
        wrappingKey: legacyKey,
      );
      await otpService.storeMasterKey(masterKey);
      await secureKeyService.setOtpBackupConfigured(userId, true);
      await secureKeyService.deleteLegacyMigrationSecret(userId);
      return true;
    } catch (error) {
      if (kDebugMode) debugPrint('Legacy key-backup migration skipped: $error');
      return false;
    } finally {
      if (masterKey != null) {
        for (var index = 0; index < masterKey.length; index++) {
          masterKey[index] = 0;
        }
      }
    }
  }

  /// Verifies the PIN and opportunistically creates the Gmail OTP backup for
  /// upgraded installations after the first successful unlock.
  Future<bool> verifyAndUnlock(String pin, {String? userId}) async {
    final valid = await pinService.verifyAndUnlock(pin, userId: userId);
    if (valid && userId != null && pinService.activeMasterKey != null) {
      try {
        // Repairs older accounts whose server PIN envelope was not persisted,
        // so the same PIN also works after reinstalling or changing devices.
        await _persistPinEnvelope(userId);
      } catch (error) {
        if (kDebugMode) debugPrint('Deferred server PIN sync: $error');
      }

      try {
        if (!await secureKeyService.hasOtpBackupConfigured(userId)) {
          await otpService.storeMasterKey(pinService.activeMasterKey!);
          await secureKeyService.setOtpBackupConfigured(userId, true);
          await secureKeyService.deleteLegacyMigrationSecret(userId);
        }
      } catch (error) {
        // A temporary network failure must not block a correct local PIN.
        if (kDebugMode) debugPrint('Deferred OTP backup setup: $error');
      }
    }
    return valid;
  }

  Future<void> changePin({
    required String currentPin,
    required String newPin,
    required String userId,
  }) async {
    await pinService.changePin(
      currentPin: currentPin,
      newPin: newPin,
      userId: userId,
    );
    await _persistPinEnvelope(userId);

    if (pinService.activeMasterKey != null &&
        !await secureKeyService.hasOtpBackupConfigured(userId)) {
      await otpService.storeMasterKey(pinService.activeMasterKey!);
      await secureKeyService.setOtpBackupConfigured(userId, true);
    }
  }

  /// Called only after Supabase has verified the six-digit email OTP. The Edge
  /// Function independently checks the fresh `amr=otp` JWT before releasing
  /// the original master key, so encrypted photos remain readable.
  Future<void> resetPinAfterEmailOtp({
    required String userId,
    required String newPin,
  }) async {
    Uint8List? masterKey;
    try {
      try {
        masterKey = await otpService.loadMasterKeyAfterOtp();
      } on PinResetException {
        final migrated = await migrateLegacyKeyBackupIfPossible(userId);
        if (!migrated) rethrow;
        masterKey = await otpService.loadMasterKeyAfterOtp();
      }

      await pinService.setPinWithMasterKey(
        masterKey: masterKey,
        newPin: newPin,
        userId: userId,
      );
      await _persistPinEnvelope(userId);
      await secureKeyService.setOtpBackupConfigured(userId, true);
      await secureKeyService.deleteLegacyMigrationSecret(userId);
    } catch (error) {
      if (error is AppException) rethrow;
      throw const PinResetException(
        'The PIN could not be reset. Your photos were not changed.',
      );
    } finally {
      if (masterKey != null &&
          !identical(masterKey, pinService.activeMasterKey)) {
        for (var index = 0; index < masterKey.length; index++) {
          masterKey[index] = 0;
        }
      }
    }
  }

  Future<void> _persistPinEnvelope(String userId) async {
    final pinSalt = await secureKeyService.getPinSalt(userId);
    final pinVerifier = await secureKeyService.getPinVerifier(userId);
    final wrappedMasterKey = await secureKeyService.getWrappedMasterKey(userId);
    final pinNonce = await secureKeyService.getKekNonce(userId);

    if (pinSalt == null ||
        pinVerifier == null ||
        wrappedMasterKey == null ||
        pinNonce == null) {
      throw const CryptoException('The PIN envelope was not saved correctly.');
    }

    await databaseService.saveVaultPinEnvelope(
      userId: userId,
      pinWrappedKey: wrappedMasterKey,
      pinSalt: pinSalt,
      pinNonce: pinNonce,
      pinVerifier: pinVerifier,
    );
  }

  void lockSession() {
    pinService.lockSession();
  }
}
