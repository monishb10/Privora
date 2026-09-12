import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import '../constants/app_constants.dart';
import '../errors/app_exception.dart';

/// Core cryptographic service handling key generation, wrapping, photo encryption, and decryption.
/// Uses AES-256-GCM and PBKDF2-HMAC-SHA256.
class VaultCryptoService {
  final AesGcm _aesGcm;
  final Pbkdf2 _pbkdf2;
  final Random _random;

  VaultCryptoService({AesGcm? aesGcm, Pbkdf2? pbkdf2, int? iterations})
    : _aesGcm = aesGcm ?? AesGcm.with256bits(),
      _pbkdf2 =
          pbkdf2 ??
          Pbkdf2(
            macAlgorithm: Hmac.sha256(),
            iterations: iterations ?? AppConstants.pbkdf2Iterations,
            bits: AppConstants.keyLengthBits,
          ),
      _random = Random.secure();

  /// Generates 32 random bytes (256-bit key)
  Uint8List generateMasterKey() {
    final keyBytes = Uint8List(32);
    for (int i = 0; i < 32; i++) {
      keyBytes[i] = _random.nextInt(256);
    }
    return keyBytes;
  }

  /// Generates a random salt of given length (default 16 bytes)
  Uint8List generateSalt([int length = AppConstants.saltLengthBytes]) {
    final salt = Uint8List(length);
    for (int i = 0; i < length; i++) {
      salt[i] = _random.nextInt(256);
    }
    return salt;
  }

  /// Generates a random 12-byte nonce for AES-GCM
  Uint8List generateNonce([int length = AppConstants.gcmNonceLengthBytes]) {
    final nonce = Uint8List(length);
    for (int i = 0; i < length; i++) {
      nonce[i] = _random.nextInt(256);
    }
    return nonce;
  }

  /// Derives a 256-bit SecretKey from a PIN and salt
  Future<SecretKey> deriveKeyFromPin(String pin, Uint8List salt) async {
    final pinBytes = utf8.encode(pin);
    return _pbkdf2.deriveKey(secretKey: SecretKey(pinBytes), nonce: salt);
  }

  /// Derives a PIN verifier hash to store locally for verification
  Future<Uint8List> derivePinVerifier(String pin, Uint8List salt) async {
    final key = await deriveKeyFromPin(pin, salt);
    final bytes = await key.extractBytes();
    return Uint8List.fromList(bytes);
  }

  /// Wraps (encrypts) the master key using a derived key and random nonce.
  /// Returns a map with base64 encoded 'wrappedKey' (ciphertext + mac) and 'nonce'.
  Future<Map<String, String>> wrapMasterKey(
    Uint8List masterKey,
    SecretKey wrappingKey,
  ) async {
    try {
      final nonce = generateNonce();
      final secretBox = await _aesGcm.encrypt(
        masterKey,
        secretKey: wrappingKey,
        nonce: nonce,
      );

      // Combine ciphertext and mac for compact storage
      final combined = Uint8List(
        secretBox.cipherText.length + secretBox.mac.bytes.length,
      );
      combined.setRange(0, secretBox.cipherText.length, secretBox.cipherText);
      combined.setRange(
        secretBox.cipherText.length,
        combined.length,
        secretBox.mac.bytes,
      );

      return {
        'wrappedKey': base64Encode(combined),
        'nonce': base64Encode(nonce),
      };
    } catch (e) {
      throw CryptoException('Failed to wrap master vault key: $e');
    }
  }

  /// Unwraps (decrypts) the master key using a derived key and stored nonce.
  Future<Uint8List> unwrapMasterKey({
    required String wrappedKeyBase64,
    required String nonceBase64,
    required SecretKey wrappingKey,
  }) async {
    try {
      final combined = base64Decode(wrappedKeyBase64);
      final nonce = base64Decode(nonceBase64);

      if (combined.length < 16) {
        throw const CryptoException('Invalid wrapped key format.');
      }

      final cipherTextLength = combined.length - 16;
      final cipherText = combined.sublist(0, cipherTextLength);
      final macBytes = combined.sublist(cipherTextLength);

      final secretBox = SecretBox(cipherText, nonce: nonce, mac: Mac(macBytes));

      final decrypted = await _aesGcm.decrypt(
        secretBox,
        secretKey: wrappingKey,
      );

      return Uint8List.fromList(decrypted);
    } catch (e) {
      throw CryptoException('Failed to unwrap master vault key: $e');
    }
  }

  /// Compatibility-only derivation used once to migrate an encrypted key from
  /// older Privora builds. No new user-facing backup codes are generated.
  Future<SecretKey> deriveKeyFromLegacyMigrationSecret(
    String code,
    Uint8List salt,
  ) async {
    final cleanCode = code.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    final codeBytes = utf8.encode(cleanCode);
    return _pbkdf2.deriveKey(secretKey: SecretKey(codeBytes), nonce: salt);
  }

  /// Encrypts binary photo or thumbnail bytes before upload.
  /// Format: [1 byte version: 0x01] + [12 bytes nonce] + [16 bytes mac] + [ciphertext]
  Future<Uint8List> encryptPhotoBytes(
    Uint8List plainBytes,
    Uint8List masterKey,
  ) async {
    try {
      final nonce = generateNonce();
      final secretKey = SecretKey(masterKey);
      final secretBox = await _aesGcm.encrypt(
        plainBytes,
        secretKey: secretKey,
        nonce: nonce,
      );

      final cipherText = secretBox.cipherText;
      final macBytes = secretBox.mac.bytes;

      // Header: 1 byte version + 12 bytes nonce + 16 bytes MAC = 29 bytes
      const headerLength = 1 + AppConstants.gcmNonceLengthBytes + 16;
      final result = Uint8List(headerLength + cipherText.length);

      result[0] = 0x01; // Version 1
      result.setRange(1, 1 + AppConstants.gcmNonceLengthBytes, nonce);
      result.setRange(
        1 + AppConstants.gcmNonceLengthBytes,
        headerLength,
        macBytes,
      );
      result.setRange(headerLength, result.length, cipherText);

      return result;
    } catch (e) {
      throw CryptoException('Photo encryption failed: $e');
    }
  }

  /// Decrypts binary encrypted bytes downloaded from Supabase Storage into memory.
  /// Format: [1 byte version: 0x01] + [12 bytes nonce] + [16 bytes mac] + [ciphertext]
  Future<Uint8List> decryptPhotoBytes(
    Uint8List encryptedBytes,
    Uint8List masterKey,
  ) async {
    try {
      const headerLength = 1 + AppConstants.gcmNonceLengthBytes + 16;
      if (encryptedBytes.length < headerLength) {
        throw const CryptoException(
          'Encrypted payload is corrupted or too short.',
        );
      }

      final version = encryptedBytes[0];
      if (version != 0x01) {
        throw CryptoException('Unsupported encryption version: $version');
      }

      final nonce = encryptedBytes.sublist(
        1,
        1 + AppConstants.gcmNonceLengthBytes,
      );
      final macBytes = encryptedBytes.sublist(
        1 + AppConstants.gcmNonceLengthBytes,
        headerLength,
      );
      final cipherText = encryptedBytes.sublist(headerLength);

      final secretBox = SecretBox(cipherText, nonce: nonce, mac: Mac(macBytes));

      final secretKey = SecretKey(masterKey);
      final decrypted = await _aesGcm.decrypt(secretBox, secretKey: secretKey);

      return Uint8List.fromList(decrypted);
    } catch (e) {
      throw CryptoException('Photo decryption failed: $e');
    }
  }
}
