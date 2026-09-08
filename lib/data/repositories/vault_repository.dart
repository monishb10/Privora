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
  /// 1. Verifies that server does not already have an existing vault record (prevents overwriting).
  /// 2. Generates 256-bit random master key.
  /// 3. Sets up 6-digit PIN locally namespaced to userId.
  /// 4. Generates high-entropy recovery code.
  /// 5. Wraps master key with recovery key and stores in Supabase vault_keys table.
  /// 6. Returns plaintext recovery code to show user ONCE.
  Future<String> initializeNewVault({
    required String userId,
    required String pin,
  }) async {
    try {
      // Check if existing vault record already exists on the server to prevent accidental overwrite
      final existingVault = await databaseService.getVaultKeys(userId);
      if (existingVault != null) {
        throw const CryptoException(
          'An existing vault was found for this account. To prevent data loss, please use vault recovery.',
        );
      }

      final masterKey = cryptoService.generateMasterKey();

      // 1. Setup local PIN and local wrapped key namespaced to this user
      await pinService.setupPin(pin: pin, masterKey: masterKey, userId: userId);

      // 2. Generate recovery code & wrap for cloud backup
      final recoveryCode = cryptoService.generateRecoveryCode();
      final recoverySalt = cryptoService.generateSalt();
      final recoveryKek = await cryptoService.deriveKeyFromRecoveryCode(
        recoveryCode,
        recoverySalt,
      );
      final recoveryWrapped = await cryptoService.wrapMasterKey(
        masterKey,
        recoveryKek,
      );

      // 3. Save recovery-wrapped key to Supabase database
      await databaseService.saveVaultKeys(
        userId: userId,
        recoveryWrappedKey: recoveryWrapped['wrappedKey']!,
        recoverySalt: base64Encode(recoverySalt),
        recoveryNonce: recoveryWrapped['nonce']!,
        cryptoVersion: 1,
      );

      return recoveryCode;
    } catch (e) {
      debugPrint('initializeNewVault error: $e');
      if (e is CryptoException) rethrow;
      throw CryptoException('Failed to initialize vault keys: $e');
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
      if (vaultData == null) {
        throw const RecoveryException(
          'No vault recovery data found for this account.',
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
