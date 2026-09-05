import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:privora/core/errors/app_exception.dart';
import 'package:privora/core/security/vault_crypto_service.dart';

void main() {
  late VaultCryptoService crypto;

  setUp(() {
    crypto = VaultCryptoService(iterations: 1000);
  });

  group('VaultCryptoService Tests', () {
    test('generates valid 256-bit random master keys and nonces', () {
      final key1 = crypto.generateMasterKey();
      final key2 = crypto.generateMasterKey();

      expect(key1.length, 32);
      expect(key2.length, 32);
      expect(key1, isNot(equals(key2))); // Unique random keys

      final nonce = crypto.generateNonce();
      expect(nonce.length, 12);
    });

    test('round-trip photo encryption and decryption succeeds', () async {
      final masterKey = crypto.generateMasterKey();
      final originalData = utf8.encode(
        'Top Secret Privora Image Payload - 2026',
      );

      final encrypted = await crypto.encryptPhotoBytes(
        Uint8List.fromList(originalData),
        masterKey,
      );

      // Verify envelope: 1 byte version + 12 bytes nonce + 16 bytes MAC = 29 bytes header
      expect(encrypted.length, originalData.length + 29);
      expect(encrypted[0], 0x01); // Version byte

      final decrypted = await crypto.decryptPhotoBytes(encrypted, masterKey);
      expect(utf8.decode(decrypted), 'Top Secret Privora Image Payload - 2026');
    });

    test('wrong key decryption fails with CryptoException', () async {
      final correctKey = crypto.generateMasterKey();
      final wrongKey = crypto.generateMasterKey();

      final data = utf8.encode('Confidential Moment');
      final encrypted = await crypto.encryptPhotoBytes(
        Uint8List.fromList(data),
        correctKey,
      );

      expect(
        () => crypto.decryptPhotoBytes(encrypted, wrongKey),
        throwsA(isA<CryptoException>()),
      );
    });

    test('tampered encrypted payload fails decryption', () async {
      final key = crypto.generateMasterKey();
      final data = utf8.encode('Original Payload');
      final encrypted = await crypto.encryptPhotoBytes(
        Uint8List.fromList(data),
        key,
      );

      // Tamper with ciphertext byte
      final tampered = Uint8List.fromList(encrypted);
      tampered[tampered.length - 1] ^= 0xFF;

      expect(
        () => crypto.decryptPhotoBytes(tampered, key),
        throwsA(isA<CryptoException>()),
      );
    });

    test(
      'recovery code generation, key wrapping, and unwrapping round trip',
      () async {
        final masterKey = crypto.generateMasterKey();
        final recoveryCode = crypto.generateRecoveryCode();
        expect(recoveryCode.startsWith('PRIV-'), isTrue);

        final salt = crypto.generateSalt();
        final recoveryKek = await crypto.deriveKeyFromRecoveryCode(
          recoveryCode,
          salt,
        );

        // Wrap master key
        final wrapped = await crypto.wrapMasterKey(masterKey, recoveryKek);
        expect(wrapped['wrappedKey'], isNotEmpty);
        expect(wrapped['nonce'], isNotEmpty);

        // Unwrap master key with same code
        final unwrapped = await crypto.unwrapMasterKey(
          wrappedKeyBase64: wrapped['wrappedKey']!,
          nonceBase64: wrapped['nonce']!,
          wrappingKey: recoveryKek,
        );

        expect(unwrapped, equals(masterKey));

        // Attempt unwrap with wrong recovery code fails
        final wrongCodeKek = await crypto.deriveKeyFromRecoveryCode(
          'PRIV-0000-0000-0000-0000',
          salt,
        );
        expect(
          () => crypto.unwrapMasterKey(
            wrappedKeyBase64: wrapped['wrappedKey']!,
            nonceBase64: wrapped['nonce']!,
            wrappingKey: wrongCodeKek,
          ),
          throwsA(isA<CryptoException>()),
        );
      },
    );
  });
}
