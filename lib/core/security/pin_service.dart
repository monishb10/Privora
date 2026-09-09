import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import '../config/supabase_config.dart';
import '../constants/app_constants.dart';
import '../errors/app_exception.dart';
import '../utils/validators.dart';
import 'secure_key_service.dart';
import 'vault_crypto_service.dart';

/// Service managing PIN creation, verification, attempt lockout delays, and master key session unwrap.
class PinService {
  final SecureKeyService secureKeyService;
  final VaultCryptoService cryptoService;

  SecureKeyService get _secureKeyService => secureKeyService;
  VaultCryptoService get _cryptoService => cryptoService;

  // Active in-memory master key for current session. Never persisted unencrypted.
  Uint8List? _activeMasterKey;

  PinService({
    required this.secureKeyService,
    required this.cryptoService,
  });

  /// Returns true if an in-memory master key is available
  bool get hasActiveKey => _activeMasterKey != null;

  /// Accessor for active master key in memory
  Uint8List? get activeMasterKey => _activeMasterKey;

  String? _resolveUserId(String? userId) {
    if (userId != null && userId.isNotEmpty) return userId;
    return SupabaseConfig.client?.auth.currentUser?.id;
  }

  /// Sets up a new 6-digit PIN and wraps the provided master key
  Future<void> setupPin({
    required String pin,
    required Uint8List masterKey,
    String? userId,
  }) async {
    _validatePinFormat(pin);
    final effectiveUserId = _resolveUserId(userId);

    final salt = _cryptoService.generateSalt();
    final verifierBytes = await _cryptoService.derivePinVerifier(pin, salt);
    final kek = await _cryptoService.deriveKeyFromPin(pin, salt);
    final wrapped = await _cryptoService.wrapMasterKey(masterKey, kek);

    await _secureKeyService.savePinData(
      pinSalt: base64Encode(salt),
      pinVerifier: base64Encode(verifierBytes),
      wrappedMasterKey: wrapped['wrappedKey']!,
      kekNonce: wrapped['nonce']!,
      userId: effectiveUserId,
    );

    _activeMasterKey = Uint8List.fromList(masterKey);
    await _secureKeyService.resetLockout(effectiveUserId);
  }

  /// Verifies entered PIN against stored salted verifier.
  /// If valid, unwraps the master key into memory and resets lockout.
  /// If invalid, increments failed attempts and enforces lockout if >= 5.
  Future<bool> verifyAndUnlock(String pin, {String? userId}) async {
    _validatePinFormat(pin);
    final effectiveUserId = _resolveUserId(userId);

    // Check lockout
    final lockoutUntil = await _secureKeyService.getLockoutUntil(effectiveUserId);
    if (lockoutUntil != null && DateTime.now().isBefore(lockoutUntil)) {
      final remaining = lockoutUntil.difference(DateTime.now()).inSeconds + 1;
      throw PinLockoutException(remaining);
    }

    final saltBase64 = await _secureKeyService.getPinSalt(effectiveUserId);
    final verifierBase64 = await _secureKeyService.getPinVerifier(effectiveUserId);
    final wrappedKeyBase64 = await _secureKeyService.getWrappedMasterKey(
      effectiveUserId,
    );
    final kekNonceBase64 = await _secureKeyService.getKekNonce(effectiveUserId);

    if (saltBase64 == null ||
        verifierBase64 == null ||
        wrappedKeyBase64 == null ||
        kekNonceBase64 == null) {
      throw const PinException('PIN has not been set up yet.');
    }

    final salt = base64Decode(saltBase64);
    final storedVerifier = base64Decode(verifierBase64);

    final enteredVerifier = await _cryptoService.derivePinVerifier(pin, salt);

    // Timing-safe comparison
    if (!_constantTimeEquals(enteredVerifier, storedVerifier)) {
      await _handleFailedAttempt(effectiveUserId);
      return false;
    }

    // Success: unwrap master key
    try {
      final kek = await _cryptoService.deriveKeyFromPin(pin, salt);
      final masterKey = await _cryptoService.unwrapMasterKey(
        wrappedKeyBase64: wrappedKeyBase64,
        nonceBase64: kekNonceBase64,
        wrappingKey: kek,
      );

      _activeMasterKey = masterKey;
      await _secureKeyService.resetLockout(effectiveUserId);
      return true;
    } catch (e) {
      throw CryptoException('Failed to unwrap master vault key: $e');
    }
  }

  /// Changes the PIN by unwrapping with old PIN and re-wrapping with new PIN.
  Future<void> changePin({
    required String currentPin,
    required String newPin,
    String? userId,
  }) async {
    _validatePinFormat(currentPin);
    _validatePinFormat(newPin);

    final isOldValid = await verifyAndUnlock(currentPin, userId: userId);
    if (!isOldValid || _activeMasterKey == null) {
      throw const PinException('Current PIN is incorrect.');
    }

    final currentMasterKey = Uint8List.fromList(_activeMasterKey!);
    await setupPin(pin: newPin, masterKey: currentMasterKey, userId: userId);
  }

  /// In-memory clear of decrypted secrets when app locks or signs out
  void lockSession() {
    if (_activeMasterKey != null) {
      // Overwrite memory before clearing
      for (int i = 0; i < _activeMasterKey!.length; i++) {
        _activeMasterKey![i] = 0;
      }
      _activeMasterKey = null;
    }
  }

  /// Restores master key from recovery flow and sets a new PIN
  Future<void> recoverAndSetPin({
    required Uint8List masterKey,
    required String newPin,
    String? userId,
  }) async {
    await setupPin(pin: newPin, masterKey: masterKey, userId: userId);
  }

  /// Validates format of a 6-digit PIN
  static void _validatePinFormat(String pin) {
    if (!Validators.isSixDigitPin(pin)) {
      throw const ValidationException(
        'PIN must contain exactly 6 numeric digits.',
      );
    }
  }

  /// Handles failed PIN entry and updates lockout
  Future<void> _handleFailedAttempt([String? userId]) async {
    final attempts = (await _secureKeyService.getFailedAttempts(userId)) + 1;
    await _secureKeyService.setFailedAttempts(attempts, userId);

    if (attempts >= AppConstants.maxPinAttemptsBeforeLockout) {
      // Exponential/progressive lockout: 30s, 60s, 120s, 240s...
      final multiplier = attempts - AppConstants.maxPinAttemptsBeforeLockout;
      final penaltySeconds =
          AppConstants.baseLockoutSeconds * (1 << multiplier.clamp(0, 5));
      final lockoutUntil = DateTime.now().add(
        Duration(seconds: penaltySeconds),
      );
      await _secureKeyService.setLockoutUntil(lockoutUntil, userId);
      throw PinLockoutException(penaltySeconds);
    }
  }

  /// Constant-time byte array equality check to prevent timing attacks
  bool _constantTimeEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    int result = 0;
    for (int i = 0; i < a.length; i++) {
      result |= a[i] ^ b[i];
    }
    return result == 0;
  }
}
