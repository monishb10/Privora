import 'dart:typed_data';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:privora/core/errors/app_exception.dart';
import 'package:privora/core/security/pin_service.dart';
import 'package:privora/core/security/secure_key_service.dart';
import 'package:privora/core/security/vault_crypto_service.dart';
import 'package:privora/data/repositories/vault_repository.dart';
import 'package:privora/data/services/supabase_database_service.dart';

class InMemorySecureStorage extends Fake implements FlutterSecureStorage {
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

class InMemorySupabaseDatabaseService extends Fake
    implements SupabaseDatabaseService {
  final Map<String, Map<String, dynamic>> _vaults = {};
  bool shouldSimulateNetworkFailure = false;

  @override
  Future<Map<String, dynamic>?> getVaultKeys(String userId) async {
    if (shouldSimulateNetworkFailure) {
      throw const CryptoException('Network error connecting to Supabase');
    }
    return _vaults[userId];
  }

  @override
  Future<void> saveVaultPinEnvelope({
    required String userId,
    required String pinWrappedKey,
    required String pinSalt,
    required String pinNonce,
    required String pinVerifier,
    int cryptoVersion = 1,
  }) async {
    final existing = _vaults[userId] ?? {'has_recovery_code': false};
    if (!existing.containsKey('has_recovery_code')) {
      existing['has_recovery_code'] = false;
    }
    existing.addAll({
      'user_id': userId,
      'pin_wrapped_key': pinWrappedKey,
      'pin_salt': pinSalt,
      'pin_nonce': pinNonce,
      'pin_verifier': pinVerifier,
      'crypto_version': cryptoVersion,
      'updated_at': DateTime.now().toIso8601String(),
    });
    _vaults[userId] = existing;
  }

  @override
  Future<void> saveRecoveryEnvelope({
    required String userId,
    required String recoveryWrappedKey,
    required String recoverySalt,
    required String recoveryNonce,
    int cryptoVersion = 1,
  }) async {
    final existing = _vaults[userId] ?? {};
    existing.addAll({
      'user_id': userId,
      'recovery_wrapped_key': recoveryWrappedKey,
      'recovery_salt': recoverySalt,
      'recovery_nonce': recoveryNonce,
      'has_recovery_code': true,
      'crypto_version': cryptoVersion,
      'updated_at': DateTime.now().toIso8601String(),
    });
    _vaults[userId] = existing;
  }

  @override
  Future<bool> hasRecoveryCode(String userId) async {
    final vault = _vaults[userId];
    if (vault == null) return false;
    return vault['has_recovery_code'] == true;
  }
}

void main() {
  late InMemorySecureStorage storage;
  late SecureKeyService secureKeyService;
  late VaultCryptoService cryptoService;
  late PinService pinService;
  late InMemorySupabaseDatabaseService dbService;
  late VaultRepository vaultRepository;

  setUp(() {
    storage = InMemorySecureStorage();
    secureKeyService = SecureKeyService(storage: storage);
    cryptoService = VaultCryptoService(
      iterations: 1000,
    ); // Fast KDF for test runs
    pinService = PinService(
      secureKeyService: secureKeyService,
      cryptoService: cryptoService,
    );
    dbService = InMemorySupabaseDatabaseService();
    vaultRepository = VaultRepository(
      pinService: pinService,
      cryptoService: cryptoService,
      secureKeyService: secureKeyService,
      databaseService: dbService,
    );
  });

  group('Requirement 4: Six-Digit PIN Login & Isolation Tests', () {
    test(
      'Fresh account sets up 6-digit PIN and verifies persistence in local storage and cloud envelope',
      () async {
        const userId = 'user-fresh-1';
        const pin = '012345'; // Preserves leading zero

        await vaultRepository.initializeNewVault(userId: userId, pin: pin);

        expect(vaultRepository.hasActiveKey, isTrue);
        final activeKey = vaultRepository.activeMasterKey;
        expect(activeKey, isNotNull);
        expect(activeKey!.length, equals(32));

        // Local storage must have user-namespaced PIN setup completed
        final hasLocal = await secureKeyService.hasCompletedSetup(userId);
        expect(hasLocal, isTrue);

        // Cloud must have recovery envelope and local secure storage must store recovery code
        final serverVault = await dbService.getVaultKeys(userId);
        expect(serverVault, isNotNull);
        expect(serverVault!['recovery_wrapped_key'], isNotNull);
        expect(serverVault['has_recovery_code'], isTrue);
        final recoveryCode = await vaultRepository.getRecoveryCode(userId);
        expect(recoveryCode, isNotNull);
        expect(recoveryCode, isNotEmpty);
      },
    );

    test(
      'Correct PIN opens original vault after restart; Wrong PIN does not unlock',
      () async {
        const userId = 'user-returning-1';
        const pin = '987654';

        await vaultRepository.initializeNewVault(userId: userId, pin: pin);
        final originalMasterKey = Uint8List.fromList(
          vaultRepository.activeMasterKey!,
        );

        // Simulate app restart / session lock
        vaultRepository.lockSession();
        expect(vaultRepository.hasActiveKey, isFalse);
        expect(vaultRepository.activeMasterKey, isNull);

        // Wrong PIN fails to unlock
        final wrongResult = await vaultRepository.verifyAndUnlock(
          '000000',
          userId: userId,
        );
        expect(wrongResult, isFalse);
        expect(vaultRepository.hasActiveKey, isFalse);

        // Correct PIN unlocks and recovers original master key
        final correctResult = await vaultRepository.verifyAndUnlock(
          pin,
          userId: userId,
        );
        expect(correctResult, isTrue);
        expect(vaultRepository.hasActiveKey, isTrue);
        expect(vaultRepository.activeMasterKey, equals(originalMasterKey));
      },
    );

    test(
      'Failed server vault lookup does not report that the PIN is absent',
      () async {
        const userId = 'user-offline-1';
        dbService.shouldSimulateNetworkFailure = true;

        // When network fails, getServerVaultData throws an error rather than returning null
        expect(
          () => vaultRepository.getServerVaultData(userId),
          throwsA(isA<CryptoException>()),
        );
      },
    );

    test(
      'Different Google accounts have separate isolated PIN and recovery states',
      () async {
        const userA = 'user-alice-123';
        const userB = 'user-bob-456';
        const pinA = '111222';
        const pinB = '333444';

        // Setup User A
        await vaultRepository.initializeNewVault(userId: userA, pin: pinA);
        final keyA = Uint8List.fromList(vaultRepository.activeMasterKey!);
        vaultRepository.lockSession();

        // Setup User B
        await vaultRepository.initializeNewVault(userId: userB, pin: pinB);
        final keyB = Uint8List.fromList(vaultRepository.activeMasterKey!);
        vaultRepository.lockSession();

        // Master keys must be unique
        expect(keyA, isNot(equals(keyB)));

        // User A's PIN cannot unlock User B's vault
        final unlockBwithA = await vaultRepository.verifyAndUnlock(
          pinA,
          userId: userB,
        );
        expect(unlockBwithA, isFalse);

        // User B's PIN cannot unlock User A's vault
        final unlockAwithB = await vaultRepository.verifyAndUnlock(
          pinB,
          userId: userA,
        );
        expect(unlockAwithB, isFalse);

        // User A unlocks with PIN A and gets key A
        final unlockA = await vaultRepository.verifyAndUnlock(
          pinA,
          userId: userA,
        );
        expect(unlockA, isTrue);
        expect(vaultRepository.activeMasterKey, equals(keyA));
      },
    );

    test('Recovery codes are unique per user and automatically generated', () async {
      const userA = 'user-rec-alice';
      const userB = 'user-rec-bob';
      const pin = '555666';

      final initCodeA = await vaultRepository.initializeNewVault(
        userId: userA,
        pin: pin,
      );
      final initCodeB = await vaultRepository.initializeNewVault(
        userId: userB,
        pin: pin,
      );

      // Recovery codes are generated and unique
      expect(initCodeA, isNotEmpty);
      expect(initCodeB, isNotEmpty);
      expect(initCodeA, isNot(equals(initCodeB)));
      expect(await vaultRepository.hasRecoveryCode(userA), isTrue);
      expect(await vaultRepository.hasRecoveryCode(userB), isTrue);
      expect(await vaultRepository.getRecoveryCode(userA), equals(initCodeA));
      expect(await vaultRepository.getRecoveryCode(userB), equals(initCodeB));

      // Can replace recovery codes for both
      final codeA = await vaultRepository.generateOrReplaceRecoveryCode(
        userId: userA,
        currentPin: pin,
      );
      final codeB = await vaultRepository.generateOrReplaceRecoveryCode(
        userId: userB,
        currentPin: pin,
      );

      expect(codeA, isNotEmpty);
      expect(codeB, isNotEmpty);
      expect(codeA, isNot(equals(codeB)));
      expect(codeA, isNot(equals(initCodeA)));

      expect(await vaultRepository.hasRecoveryCode(userA), isTrue);
      expect(await vaultRepository.hasRecoveryCode(userB), isTrue);
      expect(await vaultRepository.getRecoveryCode(userA), equals(codeA));
      expect(await vaultRepository.getRecoveryCode(userB), equals(codeB));
    });

    test(
      'Recovery code resets PIN while preserving the original master key',
      () async {
        const userId = 'user-recover-pin';
        const originalPin = '123456';
        const newPin = '654321';

        await vaultRepository.initializeNewVault(
          userId: userId,
          pin: originalPin,
        );
        final originalMasterKey = Uint8List.fromList(
          vaultRepository.activeMasterKey!,
        );

        // User generates recovery code
        final recoveryCode = await vaultRepository
            .generateOrReplaceRecoveryCode(
              userId: userId,
              currentPin: originalPin,
            );

        // User forgets PIN and session locks
        vaultRepository.lockSession();

        // Recovers vault with recovery code and sets new PIN
        await vaultRepository.recoverVault(
          userId: userId,
          recoveryCode: recoveryCode,
          newPin: newPin,
        );

        // Session locks again
        vaultRepository.lockSession();

        // Old PIN must fail
        final oldUnlock = await vaultRepository.verifyAndUnlock(
          originalPin,
          userId: userId,
        );
        expect(oldUnlock, isFalse);

        // New PIN must succeed and yield EXACT original master key (photos preserved!)
        final newUnlock = await vaultRepository.verifyAndUnlock(
          newPin,
          userId: userId,
        );
        expect(newUnlock, isTrue);
        expect(vaultRepository.activeMasterKey, equals(originalMasterKey));
      },
    );

    test('Old recovery code fails after successful replacement', () async {
      const userId = 'user-replace-code';
      const pin = '222333';

      await vaultRepository.initializeNewVault(userId: userId, pin: pin);

      // Generate first recovery code
      final oldCode = await vaultRepository.generateOrReplaceRecoveryCode(
        userId: userId,
        currentPin: pin,
      );

      // Replace with new recovery code
      final newCode = await vaultRepository.generateOrReplaceRecoveryCode(
        userId: userId,
        currentPin: pin,
      );

      expect(newCode, isNot(equals(oldCode)));

      // Attempting to recover with old code must throw RecoveryException
      expect(
        () => vaultRepository.recoverVault(
          userId: userId,
          recoveryCode: oldCode,
          newPin: '999888',
        ),
        throwsA(isA<RecoveryException>()),
      );

      // Recovering with new code succeeds
      await vaultRepository.recoverVault(
        userId: userId,
        recoveryCode: newCode,
        newPin: '999888',
      );
      expect(vaultRepository.hasActiveKey, isTrue);
    });

    test('A user cannot read or use another user recovery record', () async {
      const userAlice = 'user-alice-vault';
      const userBob = 'user-bob-vault';
      const pin = '777888';

      await vaultRepository.initializeNewVault(userId: userAlice, pin: pin);
      final aliceCode = await vaultRepository.generateOrReplaceRecoveryCode(
        userId: userAlice,
        currentPin: pin,
      );

      // Bob tries to recover his vault using Alice's code
      expect(
        () => vaultRepository.recoverVault(
          userId: userBob,
          recoveryCode: aliceCode,
          newPin: '111111',
        ),
        throwsA(isA<RecoveryException>()),
      );
    });
  });
}
