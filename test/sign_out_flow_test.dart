import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:privora/app/providers.dart';
import 'package:privora/core/security/pin_service.dart';
import 'package:privora/core/security/secure_key_service.dart';
import 'package:privora/core/security/session_lock_service.dart';
import 'package:privora/core/security/temporary_file_cleaner.dart';
import 'package:privora/core/security/vault_crypto_service.dart';
import 'package:privora/core/widgets/confirmation_dialog.dart';
import 'package:privora/data/repositories/auth_repository.dart';
import 'package:privora/data/services/supabase_auth_service.dart';
import 'package:privora/data/services/supabase_storage_service.dart';
import 'google_auth_and_routing_test.dart';

class FakeSupabaseAuthService extends SupabaseAuthService {
  bool isSignedOut = false;

  @override
  Future<void> signOut() async {
    isSignedOut = true;
  }
}

class FakeTemporaryCleaner extends TemporaryFileCleaner {
  bool wasCleaned = false;

  @override
  Future<void> cleanTemporaryFiles() async {
    wasCleaned = true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Part 2: Clean Sign Out Flow Tests', () {
    testWidgets('Sign Out displays confirmation dialog before proceeding', (
      tester,
    ) async {
      bool dialogConfirmed = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  final confirmed = await ConfirmationDialog.show(
                    context: context,
                    title: 'Sign Out?',
                    message:
                        'You will need your Google account and 6-digit PIN to sign back in.',
                    confirmText: 'Sign Out',
                  );
                  dialogConfirmed = confirmed == true;
                },
                child: const Text('Trigger Sign Out'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Trigger Sign Out'));
      await tester.pumpAndSettle();

      // Verify dialog is shown
      expect(find.text('Sign Out?'), findsOneWidget);
      expect(
        find.textContaining('You will need your Google account'),
        findsOneWidget,
      );

      // Tap Sign Out button in dialog
      await tester.tap(find.text('Sign Out').last);
      await tester.pumpAndSettle();

      expect(dialogConfirmed, isTrue);
    });

    test(
      'Sign Out executes complete cleanup protocol: locks session, clears memory key, cleans disk, signs out',
      () async {
        final container = ProviderContainer();
        addTearDown(container.dispose);

        final fakeStorage = FakeSecureStorage();
        final secureKey = SecureKeyService(storage: fakeStorage);
        final crypto = VaultCryptoService();
        final pinService = PinService(
          secureKeyService: secureKey,
          cryptoService: crypto,
        );
        final lockNotifier = container.read(
          sessionLockServiceProvider.notifier,
        );
        final fakeAuth = FakeSupabaseAuthService();
        final fakeCleaner = FakeTemporaryCleaner();

        final authRepo = AuthRepository(
          authService: fakeAuth,
          databaseService: FakeDatabaseService(),
          storageService: SupabaseStorageService(),
          secureKeyService: secureKey,
          lockService: lockNotifier,
          pinService: pinService,
          temporaryFileCleaner: fakeCleaner,
        );

        // Simulate unlocked session with active master key
        final masterKey = Uint8List.fromList(List.generate(32, (i) => i));
        await pinService.setupPin(
          pin: '123456',
          masterKey: masterKey,
          userId: 'user-1',
        );
        lockNotifier.unlock();

        expect(pinService.hasActiveKey, isTrue);
        expect(container.read(sessionLockServiceProvider), isFalse); // False = unlocked

        // Execute Sign Out
        await authRepo.signOut();

        // 1. Session must be locked
        expect(container.read(sessionLockServiceProvider), isTrue); // True = locked

        // 2. Active master key in memory must be completely cleared
        expect(pinService.hasActiveKey, isFalse);
        expect(pinService.activeMasterKey, isNull);

        // 3. Temporary files must have been cleaned
        expect(fakeCleaner.wasCleaned, isTrue);

        // 4. Auth service must be signed out
        expect(fakeAuth.isSignedOut, isTrue);
      },
    );
  });
}
