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

  Future<bool> hasCompletedSetup() {
    return secureKeyService.hasCompletedSetup();
  }

  /// First installation setup:
  /// 1. Generates 256-bit random master key.
  /// 2. Sets up 6-digit PIN locally.
  /// 3. Generates high-entropy recovery code.
  /// 4. Wraps master key with recovery key and stores in Supabase vault_keys table.
  /// 5. Returns plaintext recovery code to show user ONCE.
  Future<String> initializeNewVault({
    required String userId,
    required String pin,
  }) async {
    try {
      final masterKey = cryptoService.generateMasterKey();

      // 1. Setup local PIN and local wrapped key
      await pinService.setupPin(pin: pin, masterKey: masterKey);

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
      throw CryptoException('Failed to initialize vault keys: $e');
    }
  }

  /// Verifies entered PIN and unwraps the master key for the current session.
  Future<bool> verifyAndUnlock(String pin) {
    return pinService.verifyAndUnlock(pin);
  }

  /// Changes the user's PIN using the current PIN.
  Future<void> changePin({required String currentPin, required String newPin}) {
    return pinService.changePin(currentPin: currentPin, newPin: newPin);
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

      // Setup new PIN with the recovered master key
      await pinService.recoverAndSetPin(masterKey: masterKey, newPin: newPin);
    } catch (e) {
      debugPrint('recoverVault error: $e');
      throw RecoveryException(
        'Invalid recovery code or corrupted recovery data.',
      );
    }
  }

  void lockSession() {
    pinService.lockSession();
  }
}
