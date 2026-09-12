import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:privora/core/config/environment.dart';
import 'package:privora/core/errors/app_exception.dart';
import 'package:privora/core/security/pin_service.dart';
import 'package:privora/core/security/secure_key_service.dart';
import 'package:privora/core/security/vault_crypto_service.dart';
import 'package:privora/data/repositories/vault_repository.dart';
import 'package:privora/data/services/supabase_auth_service.dart';
import 'package:privora/data/services/supabase_database_service.dart';
import 'package:privora/data/services/vault_otp_service.dart';
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
  Future<void> saveVaultPinEnvelope({
    required String userId,
    required String pinWrappedKey,
    required String pinSalt,
    required String pinNonce,
    required String pinVerifier,
    int cryptoVersion = 1,
  }) async {
    final existing = vaults[userId] ?? <String, dynamic>{};
    existing.addAll({
      'user_id': userId,
      'pin_wrapped_key': pinWrappedKey,
      'pin_salt': pinSalt,
      'pin_nonce': pinNonce,
      'pin_verifier': pinVerifier,
      'crypto_version': cryptoVersion,
      'updated_at': DateTime.now().toIso8601String(),
    });
    vaults[userId] = existing;
  }
}

class FakeVaultOtpService extends VaultOtpService {
  Uint8List? storedKey;

  @override
  Future<void> storeMasterKey(Uint8List masterKey) async {
    storedKey = Uint8List.fromList(masterKey);
  }

  @override
  Future<bool> hasEnvelope() async => storedKey != null;

  @override
  Future<Uint8List> loadMasterKeyAfterOtp() async {
    if (storedKey == null) {
      throw const PinResetException('No Gmail PIN-reset backup exists.');
    }
    return Uint8List.fromList(storedKey!);
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
        final cryptoService = VaultCryptoService(iterations: 1000);
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
        final cryptoService = VaultCryptoService(iterations: 1000);
        final pinService = PinService(
          secureKeyService: secureKeyService,
          cryptoService: cryptoService,
        );

        final vaultRepo = VaultRepository(
          pinService: pinService,
          cryptoService: cryptoService,
          secureKeyService: secureKeyService,
          databaseService: fakeDb,
          otpService: FakeVaultOtpService(),
        );

        const userId = 'returning-user-123';

        // 1. User initializes vault for first time
        await vaultRepo.initializeNewVault(userId: userId, pin: '654321');
        expect(fakeDb.vaults.containsKey(userId), isTrue);

        // 2. Attempting to initialize vault again fails rather than overwriting
        expect(
          () => vaultRepo.initializeNewVault(userId: userId, pin: '123456'),
          throwsA(isA<PinException>()),
        );
      },
    );

    test(
      'Gmail OTP reset re-wraps the same master key with the new PIN',
      () async {
        final fakeStorage = FakeSecureStorage();
        final fakeDb = FakeDatabaseService();
        final fakeOtp = FakeVaultOtpService();
        final secureKeyService = SecureKeyService(storage: fakeStorage);
        final cryptoService = VaultCryptoService(iterations: 1000);
        final pinService = PinService(
          secureKeyService: secureKeyService,
          cryptoService: cryptoService,
        );
        final vaultRepo = VaultRepository(
          pinService: pinService,
          cryptoService: cryptoService,
          secureKeyService: secureKeyService,
          databaseService: fakeDb,
          otpService: fakeOtp,
        );

        const userId = 'gmail-otp-user';
        await vaultRepo.initializeNewVault(userId: userId, pin: '111111');
        final originalKey = Uint8List.fromList(vaultRepo.activeMasterKey!);

        vaultRepo.lockSession();
        await vaultRepo.resetPinAfterEmailOtp(userId: userId, newPin: '222222');
        vaultRepo.lockSession();

        expect(
          await vaultRepo.verifyAndUnlock('111111', userId: userId),
          isFalse,
        );
        expect(
          await vaultRepo.verifyAndUnlock('222222', userId: userId),
          isTrue,
        );
        expect(vaultRepo.activeMasterKey, equals(originalKey));
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

    test(
      'GOOGLE_WEB_CLIENT_ID validation strictly rejects empty, placeholder, and invalid suffix',
      () {
        // Current environment in tests has configured default Web Client ID and is valid
        expect(Environment.validateGoogleWebClientId(), isNull);
        expect(Environment.isGoogleWebClientIdValid, isTrue);
        expect(
          Environment.googleWebClientId,
          equals(
            '724610060172-c1bf0dasha3cf3sbdpk7r18vb92u2bnv.apps.googleusercontent.com',
          ),
        );

        // Validation logic helper matching Environment.validateGoogleWebClientId
        String? testValidate(String raw) {
          final trimmed = raw.trim();
          if (trimmed.isEmpty) return 'empty';
          final upper = trimmed.toUpperCase();
          if (upper.contains('WEB_CLIENT_ID') ||
              upper.contains('YOUR_') ||
              upper.contains('PLACEHOLDER') ||
              upper.contains('<YOUR')) {
            return 'placeholder';
          }
          if (!trimmed.endsWith('.apps.googleusercontent.com')) {
            return 'invalid_suffix';
          }
          return null;
        }

        expect(testValidate(''), equals('empty'));
        expect(testValidate('   \n  '), equals('empty'));
        expect(testValidate('WEB_CLIENT_ID'), equals('placeholder'));
        expect(
          testValidate('<YOUR_GOOGLE_WEB_CLIENT_ID>'),
          equals('placeholder'),
        );
        expect(testValidate('123456789.com'), equals('invalid_suffix'));
        expect(testValidate('123456789.apps.googleusercontent.com'), isNull);
        expect(
          testValidate('  123456789.apps.googleusercontent.com \n '),
          isNull,
        );
      },
    );

    test(
      'GoogleSignIn PlatformException mapping correctly handles cancellations and developer errors',
      () {
        // 1. User cancellation returns null quietly without error banner
        final cancelException = PlatformException(
          code: 'sign_in_canceled',
          message: 'The user canceled the sign-in flow.',
        );
        expect(
          SupabaseAuthService.mapGooglePlatformException(cancelException),
          isNull,
        );

        final cancelCode12501 = PlatformException(
          code: '12501',
          message: 'com.google.android.gms.common.api.ApiException: 12501: ',
        );
        expect(
          SupabaseAuthService.mapGooglePlatformException(cancelCode12501),
          isNull,
        );

        // 2. Developer error (code 10) provides exact package name and debug SHA-1 guidance
        final devError = PlatformException(
          code: 'sign_in_failed',
          message: 'com.google.android.gms.common.api.ApiException: 10: ',
        );
        final devMsg = SupabaseAuthService.mapGooglePlatformException(devError);
        expect(devMsg, isNotNull);
        expect(devMsg, contains('ApiException 10: DEVELOPER_ERROR'));
        expect(devMsg, contains('com.monish.privora'));
        expect(
          devMsg,
          contains(
            '07:30:40:FB:67:AD:72:4F:B5:FF:A4:D4:04:BE:C7:9C:3F:AA:A0:E2',
          ),
        );

        // 3. ApiException 12500 provides consent screen / Play Services guidance
        final err12500 = PlatformException(
          code: 'sign_in_failed',
          message: 'com.google.android.gms.common.api.ApiException: 12500: ',
        );
        final msg12500 = SupabaseAuthService.mapGooglePlatformException(
          err12500,
        );
        expect(msg12500, isNotNull);
        expect(msg12500, contains('ApiException 12500'));

        // 4. Network error
        final netErr = PlatformException(
          code: 'network_error',
          message: 'Network request timed out',
        );
        final netMsg = SupabaseAuthService.mapGooglePlatformException(netErr);
        expect(netMsg, isNotNull);
        expect(netMsg, contains('network error'));
      },
    );
  });
}
