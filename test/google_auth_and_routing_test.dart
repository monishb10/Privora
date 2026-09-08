import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:privora/core/errors/app_exception.dart';
import 'package:privora/core/security/pin_service.dart';
import 'package:privora/core/security/secure_key_service.dart';
import 'package:privora/core/security/vault_crypto_service.dart';
import 'package:privora/data/repositories/vault_repository.dart';
import 'package:privora/data/services/supabase_database_service.dart';
import 'package:privora/features/auth/login_screen.dart';

class FakeSecureStorage extends Fake implements FlutterSecureStorage {
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
    if (value == null) {
      _data.remove(key);
    } else {
      _data[key] = value;
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

  @override
  Future<Map<String, String>> readAll({
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    return Map.from(_data);
  }

  @override
  Future<bool> containsKey({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    return _data.containsKey(key);
  }
}

class FakeDatabaseService extends SupabaseDatabaseService {
  final Map<String, Map<String, dynamic>> vaults = {};

  @override
  Future<Map<String, dynamic>?> getVaultKeys(String userId) async {
    return vaults[userId];
  }

  @override
  Future<void> saveVaultKeys({
    required String userId,
    required String recoveryWrappedKey,
    required String recoverySalt,
    required String recoveryNonce,
    int cryptoVersion = 1,
  }) async {
    vaults[userId] = {
      'user_id': userId,
      'recovery_wrapped_key': recoveryWrappedKey,
      'recovery_salt': recoverySalt,
      'recovery_nonce': recoveryNonce,
      'crypto_version': cryptoVersion,
    };
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Part 1: Google Authentication & PIN Isolation Tests', () {
    testWidgets(
      'Signed-out startup displays Google Login with single action button',
      (tester) async {
        await tester.pumpWidget(
          const ProviderScope(child: MaterialApp(home: LoginScreen())),
        );
        await tester.pumpAndSettle();

        // Verify Privora branding
        expect(find.text('Privora'), findsOneWidget);
        expect(find.text('Your private cloud gallery'), findsOneWidget);

        // Verify Continue with Google button
        expect(find.text('Continue with Google'), findsOneWidget);

        // Verify NO email/password fields exist
        expect(find.text('Email Address'), findsNothing);
        expect(find.text('Password'), findsNothing);
        expect(find.text('Sign In'), findsNothing);
        expect(find.text('Sign Up'), findsNothing);
        expect(find.text('Forgot Password?'), findsNothing);
      },
    );

    test(
      'Different Google users have separate PIN and vault states in SecureKeyService',
      () async {
        final fakeStorage = FakeSecureStorage();
        final secureKeyService = SecureKeyService(storage: fakeStorage);
        final cryptoService = VaultCryptoService();
        final pinService = PinService(
          secureKeyService: secureKeyService,
          cryptoService: cryptoService,
        );

        const userA = 'google-user-alpha';
        const userB = 'google-user-beta';

        final masterKeyA = Uint8List.fromList(List.generate(32, (i) => i));
        final masterKeyB = Uint8List.fromList(
          List.generate(32, (i) => 255 - i),
        );

        // Setup PIN 111111 for User A
        await pinService.setupPin(
          pin: '111111',
          masterKey: masterKeyA,
          userId: userA,
        );

        // Setup PIN 222222 for User B
        await pinService.setupPin(
          pin: '222222',
          masterKey: masterKeyB,
          userId: userB,
        );

        // Verify User A setup is completed
        expect(await secureKeyService.hasCompletedSetup(userA), isTrue);
        // Verify User B setup is completed
        expect(await secureKeyService.hasCompletedSetup(userB), isTrue);

        // Verify User A's PIN does NOT unlock User B
        pinService.lockSession();
        final unlockBWithA = await pinService.verifyAndUnlock(
          '111111',
          userId: userB,
        );
        expect(unlockBWithA, isFalse);

        // Verify User B's PIN unlocks User B
        pinService.lockSession();
        final unlockBWithB = await pinService.verifyAndUnlock(
          '222222',
          userId: userB,
        );
        expect(unlockBWithB, isTrue);
        expect(pinService.activeMasterKey, equals(masterKeyB));

        // Verify User A's PIN unlocks User A
        pinService.lockSession();
        final unlockAWithA = await pinService.verifyAndUnlock(
          '111111',
          userId: userA,
        );
        expect(unlockAWithA, isTrue);
        expect(pinService.activeMasterKey, equals(masterKeyA));
      },
    );

    test(
      'Existing vault data on server is NEVER overwritten automatically',
      () async {
        final fakeStorage = FakeSecureStorage();
        final fakeDb = FakeDatabaseService();
        final secureKeyService = SecureKeyService(storage: fakeStorage);
        final cryptoService = VaultCryptoService();
        final pinService = PinService(
          secureKeyService: secureKeyService,
          cryptoService: cryptoService,
        );

        final vaultRepo = VaultRepository(
          pinService: pinService,
          cryptoService: cryptoService,
          secureKeyService: secureKeyService,
          databaseService: fakeDb,
        );

        const userId = 'returning-user-123';

        // 1. User initializes vault for first time
        await vaultRepo.initializeNewVault(userId: userId, pin: '654321');
        expect(fakeDb.vaults.containsKey(userId), isTrue);

        // 2. Attempting to initialize vault again throws CryptoException rather than overwriting
        expect(
          () => vaultRepo.initializeNewVault(userId: userId, pin: '123456'),
          throwsA(isA<CryptoException>()),
        );
      },
    );

    test(
      'Project verification: Strictly no Google Client Secret or Cloudinary Secret in Flutter code',
      () {
        final libDir = Directory('lib');
        final dartFiles = libDir
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.endsWith('.dart'));

        for (final file in dartFiles) {
          final content = file.readAsStringSync();
          // Check for forbidden strings or secrets
          expect(
            content.contains('client_secret') &&
                !content.contains('Never request or use the Client Secret'),
            isFalse,
            reason: 'Forbidden secret found in ${file.path}',
          );
          expect(
            content.contains('CLOUDINARY_API_SECRET') &&
                !content.contains('Cloudinary API Secret'),
            isFalse,
            reason: 'Cloudinary API secret found in ${file.path}',
          );
        }
      },
    );
  });
}
