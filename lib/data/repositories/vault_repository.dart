import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../../core/errors/app_exception.dart';
import '../../core/security/pin_service.dart';
import '../../core/security/secure_key_service.dart';
import '../../core/security/vault_crypto_service.dart';
import '../services/supabase_database_service.dart';

/// Repository managing vault master keys, recovery setup, and PIN unlock.
class VaultRepository {
  final PinService pinService;
  final VaultCryptoService cryptoService;
  final SecureKeyService secureKeyService;
  final SupabaseDatabaseService databaseService;

  VaultRepository({
    required this.pinService,
    required this.cryptoService,
    required this.secureKeyService,
    required this.databaseService,
  });

  bool get hasActiveKey => pinService.hasActiveKey;
  Uint8List? get activeMasterKey => pinService.activeMasterKey;

  Future<bool> hasCompletedSetup([String? userId]) {
    return secureKeyService.hasCompletedSetup(userId);
  }

  Future<Map<String, dynamic>?> getServerVaultData(String userId) {
    return databaseService.getVaultKeys(userId);
  }

  /// First installation setup:
  /// First installation setup:
  /// 1. Verifies that server does not already have an existing vault record (prevents overwriting).
  /// 2. Generates 256-bit random master key.
  /// 3. Sets up 6-digit PIN locally namespaced to userId.
  /// 4. Generates unique 128-bit recovery code for this account.
  /// 5. Wraps master key with recovery key and stores in Supabase vault_keys table.
  /// 6. Saves recovery code in local secure storage for this account.
  Future<String> initializeNewVault({
    required String userId,
    required String pin,
  }) async {
    try {
      // Check if existing vault record already exists on the server to prevent accidental overwrite
      final existingVault = await databaseService.getVaultKeys(userId);
      if (existingVault != null &&
          existingVault['recovery_wrapped_key'] != null &&
          existingVault['recovery_wrapped_key'].toString().isNotEmpty) {
        throw const CryptoException(
          'An existing vault was found for this account. To prevent data loss, please use vault recovery.',
        );
      }

      final masterKey = cryptoService.generateMasterKey();

      // 1. Setup local PIN and local wrapped key namespaced to this user
      await pinService.setupPin(pin: pin, masterKey: masterKey, userId: userId);

      // 2. Generate unique 128-bit cryptographically secure recovery code for this account
      final recoveryCode = cryptoService.generateRecoveryCode();
      final recoverySalt = cryptoService.generateSalt();
      final recoveryKek = await cryptoService.deriveKeyFromRecoveryCode(
        recoveryCode,
        recoverySalt,
      );

      // 3. Wrap master key with recovery key
      final recoveryWrapped = await cryptoService.wrapMasterKey(
        masterKey,
        recoveryKek,
      );

      // 4. Save recovery envelope to Supabase vault_keys
      // Fulfills remote NOT NULL constraints on recovery_wrapped_key, recovery_salt, recovery_nonce!
      try {
        await databaseService.saveRecoveryEnvelope(
          userId: userId,
          recoveryWrappedKey: recoveryWrapped['wrappedKey']!,
          recoverySalt: base64Encode(recoverySalt),
          recoveryNonce: recoveryWrapped['nonce']!,
          cryptoVersion: 1,
        );
      } catch (dbErr) {
        debugPrint('Supabase saveRecoveryEnvelope note: $dbErr');
      }

      // 5. Store recovery code in local secure storage for this account
      await secureKeyService.saveRecoveryCode(userId, recoveryCode);

      // 6. Optional: persist PIN envelope if supported by remote schema
      final pinSalt = await secureKeyService.getPinSalt(userId);
      final pinVerifier = await secureKeyService.getPinVerifier(userId);
      final wrappedMasterKey = await secureKeyService.getWrappedMasterKey(
        userId,
      );
      final kekNonce = await secureKeyService.getKekNonce(userId);

      if (pinSalt != null &&
          pinVerifier != null &&
          wrappedMasterKey != null &&
          kekNonce != null) {
        try {
          await databaseService.saveVaultPinEnvelope(
            userId: userId,
            pinWrappedKey: wrappedMasterKey,
            pinSalt: pinSalt,
            pinNonce: kekNonce,
            pinVerifier: pinVerifier,
          );
        } catch (_) {}
      }

      return recoveryCode;
    } catch (e) {
      debugPrint('initializeNewVault error: $e');
      if (e is AppException) rethrow;
      throw CryptoException('Failed to initialize vault keys: $e');
    }
  }

  /// Retrieves the saved recovery code for this user from local secure storage
  Future<String?> getRecoveryCode(String userId) {
    return secureKeyService.getRecoveryCode(userId);
  }

  /// Checks whether user has an active recovery code envelope stored in Supabase
  Future<bool> hasRecoveryCode(String userId) {
    return databaseService.hasRecoveryCode(userId);
  }

  /// Synchronizes server PIN envelope into local secure storage if missing on this device
  Future<bool> syncServerPinEnvelopeIfMissing(String userId) async {
    final hasLocal = await hasCompletedSetup(userId);
    if (hasLocal) return true;

    final serverVault = await getServerVaultData(userId);
    if (serverVault == null) return false;

    final pinWrappedKey = serverVault['pin_wrapped_key'] as String?;
    final pinSalt = serverVault['pin_salt'] as String?;
    final pinNonce = serverVault['pin_nonce'] as String?;
    final pinVerifier = serverVault['pin_verifier'] as String?;

    if (pinWrappedKey != null &&
        pinSalt != null &&
        pinNonce != null &&
        pinVerifier != null) {
      await secureKeyService.savePinData(
        pinSalt: pinSalt,
        pinVerifier: pinVerifier,
        wrappedMasterKey: pinWrappedKey,
        kekNonce: pinNonce,
        userId: userId,
      );
      return true;
    }
    return false;
  }

  /// Generates or replaces an optional recovery code for the user's existing vault master key.
  /// Strictly requires re-authenticating with current 6-digit PIN.
  /// Never rotates or re-encrypts photos.
  Future<String> generateOrReplaceRecoveryCode({
    required String userId,
    required String currentPin,
  }) async {
    try {
      // 1. Re-authenticate user with current PIN
      final isValid = await pinService.verifyAndUnlock(
        currentPin,
        userId: userId,
      );
      if (!isValid || !pinService.hasActiveKey) {
        throw const PinException(
          'Incorrect PIN. Please enter your valid 6-digit PIN.',
        );
      }

      final masterKey = pinService.activeMasterKey!;

      // 2. Generate 128-bit cryptographically secure random recovery code
      final recoveryCode = cryptoService.generateRecoveryCode();
      final recoverySalt = cryptoService.generateSalt();
      final recoveryKek = await cryptoService.deriveKeyFromRecoveryCode(
        recoveryCode,
        recoverySalt,
      );

      // 3. Wrap current master key using AES-256-GCM
      final recoveryWrapped = await cryptoService.wrapMasterKey(
        masterKey,
        recoveryKek,
      );

      // 4. Save recovery envelope to Supabase vault_keys
      await databaseService.saveRecoveryEnvelope(
        userId: userId,
        recoveryWrappedKey: recoveryWrapped['wrappedKey']!,
        recoverySalt: base64Encode(recoverySalt),
        recoveryNonce: recoveryWrapped['nonce']!,
        cryptoVersion: 1,
      );

      // Save recovery code to local secure storage for this account
      await secureKeyService.saveRecoveryCode(userId, recoveryCode);

      return recoveryCode;
    } catch (e) {
      debugPrint('generateOrReplaceRecoveryCode error: $e');
      if (e is AppException) rethrow;
      throw CryptoException('Failed to generate recovery code: $e');
    }
  }

  /// Verifies entered PIN and unwraps the master key for the current session.
  Future<bool> verifyAndUnlock(String pin, {String? userId}) {
    return pinService.verifyAndUnlock(pin, userId: userId);
  }

  /// Changes the user's PIN using the current PIN.
  Future<void> changePin({
    required String currentPin,
    required String newPin,
    String? userId,
  }) {
    return pinService.changePin(
      currentPin: currentPin,
      newPin: newPin,
      userId: userId,
    );
  }

  /// Recovers master key from cloud using the user's recovery code and sets a new PIN.
  Future<void> recoverVault({
    required String userId,
    required String recoveryCode,
    required String newPin,
  }) async {
    try {
      final vaultData = await databaseService.getVaultKeys(userId);
      if (vaultData == null || vaultData['recovery_wrapped_key'] == null) {
        throw const RecoveryException(
          'No recovery code has been set up for this account.',
        );
      }

      final wrappedKeyBase64 = vaultData['recovery_wrapped_key'] as String;
      final saltBase64 = vaultData['recovery_salt'] as String;
      final nonceBase64 = vaultData['recovery_nonce'] as String;

      final salt = base64Decode(saltBase64);
      final recoveryKek = await cryptoService.deriveKeyFromRecoveryCode(
        recoveryCode,
        salt,
      );

      // Unwrap master key
      final masterKey = await cryptoService.unwrapMasterKey(
        wrappedKeyBase64: wrappedKeyBase64,
        nonceBase64: nonceBase64,
        wrappingKey: recoveryKek,
      );

      // Setup new PIN with the recovered master key namespaced to this user
      await pinService.recoverAndSetPin(
        masterKey: masterKey,
        newPin: newPin,
        userId: userId,
      );

      // Save recovery code to local secure storage for this account
      await secureKeyService.saveRecoveryCode(userId, recoveryCode);

      // Read back local PIN envelope
      final pinSalt = await secureKeyService.getPinSalt(userId);
      final pinVerifier = await secureKeyService.getPinVerifier(userId);
      final wrappedMasterKey = await secureKeyService.getWrappedMasterKey(
        userId,
      );
      final kekNonce = await secureKeyService.getKekNonce(userId);

      // Also persist updated PIN envelope to Supabase vault_keys if supported
      if (pinSalt != null &&
          pinVerifier != null &&
          wrappedMasterKey != null &&
          kekNonce != null) {
        try {
          await databaseService.saveVaultPinEnvelope(
            userId: userId,
            pinWrappedKey: wrappedMasterKey,
            pinSalt: pinSalt,
            pinNonce: kekNonce,
            pinVerifier: pinVerifier,
          );
        } catch (dbErr) {
          debugPrint(
            'Server PIN envelope update skipped during recovery: $dbErr',
          );
        }
      }
    } catch (e) {
      debugPrint('recoverVault error: $e');
      if (e is RecoveryException) rethrow;
      throw const RecoveryException(
        'Invalid recovery code or corrupted recovery data.',
      );
    }
  }

  void lockSession() {
    pinService.lockSession();
  }
}
