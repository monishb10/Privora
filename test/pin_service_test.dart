import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:privora/core/errors/app_exception.dart';
import 'package:privora/core/security/pin_service.dart';
import 'package:privora/core/security/secure_key_service.dart';
import 'package:privora/core/security/vault_crypto_service.dart';

// In-memory mock for FlutterSecureStorage to isolate tests
class MemorySecureStorage extends Fake implements FlutterSecureStorage {
  final Map<String, String> _data = {};

  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (value != null) {
      _data[key] = value;
    } else {
      _data.remove(key);
    }
  }

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    return _data[key];
  }

  @override
  Future<void> delete({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    _data.remove(key);
  }

  @override
  Future<void> deleteAll({
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    _data.clear();
  }
}

void main() {
  late SecureKeyService secureKeyService;
  late VaultCryptoService cryptoService;
  late PinService pinService;

  setUp(() {
    secureKeyService = SecureKeyService(storage: MemorySecureStorage());
    cryptoService = VaultCryptoService(iterations: 1000); // Fast KDF for tests
    pinService = PinService(
      secureKeyService: secureKeyService,
      cryptoService: cryptoService,
    );
  });

  group('PinService Tests', () {
    test('rejects PINs not containing exactly 6 numeric digits', () async {
      final key = Uint8List(32);
      expect(
        () => pinService.setupPin(pin: '12345', masterKey: key),
        throwsA(isA<ValidationException>()),
      );
      expect(
        () => pinService.setupPin(pin: '1234567', masterKey: key),
        throwsA(isA<ValidationException>()),
      );
      expect(
        () => pinService.setupPin(pin: '12345a', masterKey: key),
        throwsA(isA<ValidationException>()),
      );
    });

    test('sets up PIN, verifies correct PIN, and unwraps master key', () async {
      final originalMasterKey = cryptoService.generateMasterKey();
      await pinService.setupPin(pin: '654321', masterKey: originalMasterKey);

      expect(pinService.hasActiveKey, isTrue);
      expect(pinService.activeMasterKey, equals(originalMasterKey));

      // Lock session (clears active master key from memory)
      pinService.lockSession();
      expect(pinService.hasActiveKey, isFalse);
      expect(pinService.activeMasterKey, isNull);

      // Verify and unwrap with correct PIN
      final success = await pinService.verifyAndUnlock('654321');
      expect(success, isTrue);
      expect(pinService.hasActiveKey, isTrue);
      expect(pinService.activeMasterKey, equals(originalMasterKey));
    });

    test('rejects wrong PIN and increments failed attempts', () async {
      final originalMasterKey = cryptoService.generateMasterKey();
      await pinService.setupPin(pin: '112233', masterKey: originalMasterKey);
      pinService.lockSession();

      final result = await pinService.verifyAndUnlock('999999');
      expect(result, isFalse);
      expect(pinService.hasActiveKey, isFalse);

      final failed = await secureKeyService.getFailedAttempts();
      expect(failed, 1);
    });

    test(
      'enforces progressive lockout delay after 5 failed attempts',
      () async {
        final masterKey = cryptoService.generateMasterKey();
        await pinService.setupPin(pin: '123456', masterKey: masterKey);
        pinService.lockSession();

        // Enter 4 wrong PINs
        for (int i = 0; i < 4; i++) {
          final res = await pinService.verifyAndUnlock('000000');
          expect(res, isFalse);
        }

        // 5th attempt must throw PinLockoutException
        await expectLater(
          pinService.verifyAndUnlock('000000'),
          throwsA(isA<PinLockoutException>()),
        );

        // Subsequent attempt while locked out also throws
        await expectLater(
          pinService.verifyAndUnlock('123456'),
          throwsA(isA<PinLockoutException>()),
        );
      },
    );

    test('change PIN requires valid current PIN', () async {
      final masterKey = cryptoService.generateMasterKey();
      await pinService.setupPin(pin: '123456', masterKey: masterKey);

      // Wrong old PIN throws
      await expectLater(
        pinService.changePin(currentPin: '000000', newPin: '654321'),
        throwsA(isA<PinException>()),
      );

      // Correct old PIN successfully changes to new PIN
      await pinService.changePin(currentPin: '123456', newPin: '654321');
      pinService.lockSession();

      final canUnlockWithNew = await pinService.verifyAndUnlock('654321');
      expect(canUnlockWithNew, isTrue);
      expect(pinService.activeMasterKey, equals(masterKey));
    });
  });
}
