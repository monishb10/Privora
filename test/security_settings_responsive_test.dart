import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:privora/app/providers.dart';
import 'package:privora/core/theme/app_theme.dart';
import 'package:privora/data/repositories/vault_repository.dart';
import 'package:privora/features/account/security_settings_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MockVaultRepositoryForSecurityTest extends Fake
    implements VaultRepository {
  bool hasRecovery = false;
  String? generatedRecoveryCode;

  @override
  Future<bool> hasRecoveryCode(String userId) async {
    return hasRecovery;
  }

  @override
  Future<String?> getRecoveryCode(String userId) async {
    return generatedRecoveryCode;
  }

  @override
  Future<String> generateOrReplaceRecoveryCode({
    required String userId,
    required String currentPin,
  }) async {
    generatedRecoveryCode = 'PRIV-1234-ABCD-5678-EFGH';
    hasRecovery = true;
    return generatedRecoveryCode!;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final testUser = User(
    id: 'user-security-test-123',
    appMetadata: {},
    userMetadata: {},
    aud: 'authenticated',
    createdAt: DateTime.now().toIso8601String(),
  );

  group('Requirement 3: Security & Privacy Screen Responsive Layout Tests', () {
    final testWidths = [320.0, 360.0, 412.0];
    final testTextScales = [1.0, 1.3, 2.0];

    for (final width in testWidths) {
      for (final scale in testTextScales) {
        testWidgets(
          'Security cards render without any RenderFlex overflow at ${width.toInt()}px width and ${scale}x text scale',
          (tester) async {
            // Set physical/logical size
            tester.view.physicalSize = Size(width, 800.0);
            tester.view.devicePixelRatio = 1.0;
            addTearDown(() => tester.view.resetPhysicalSize());

            final mockVaultRepo = MockVaultRepositoryForSecurityTest()
              ..hasRecovery = false;

            await tester.pumpWidget(
              ProviderScope(
                overrides: [
                  currentUserProvider.overrideWithValue(testUser),
                  vaultRepositoryProvider.overrideWithValue(mockVaultRepo),
                ],
                child: MaterialApp(
                  theme: AppTheme.lightTheme,
                  home: MediaQuery(
                    data: MediaQueryData(
                      size: Size(width, 800.0),
                      textScaler: TextScaler.linear(scale),
                    ),
                    child: const SecuritySettingsScreen(),
                  ),
                ),
              ),
            );

            await tester.pumpAndSettle();

            // Verify top Recovery Code card is rendered
            expect(find.text('Recovery Code'), findsOneWidget);

            // Scroll down to layout and verify all cards without overflow
            await tester.scrollUntilVisible(
              find.text('Change 6-Digit PIN'),
              200,
            );
            await tester.pumpAndSettle();

            expect(find.text('Anti-Bruteforce Lockout'), findsOneWidget);
            expect(find.text('Change 6-Digit PIN'), findsOneWidget);
          },
        );
      }
    }

    testWidgets(
      'Recovery Code card displays Not generated state and allows generating recovery code',
      (tester) async {
        final mockVaultRepo = MockVaultRepositoryForSecurityTest()
          ..hasRecovery = false;

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              currentUserProvider.overrideWithValue(testUser),
              vaultRepositoryProvider.overrideWithValue(mockVaultRepo),
            ],
            child: MaterialApp(
              theme: AppTheme.lightTheme,
              home: const SecuritySettingsScreen(),
            ),
          ),
        );

        await tester.pumpAndSettle();

        // Check initial state: Not generated
        expect(find.text('Not generated'), findsOneWidget);
        expect(find.text('Generate recovery code'), findsOneWidget);

        // Tap Generate recovery code button
        await tester.tap(find.text('Generate recovery code'));
        await tester.pumpAndSettle();

        // Confirm PIN dialog appears
        expect(find.text('Confirm Your PIN'), findsOneWidget);

        // Enter 6-digit PIN
        await tester.enterText(find.byType(TextField), '123456');
        await tester.pump();

        // Tap Confirm
        await tester.tap(find.text('Confirm'));
        await tester.pumpAndSettle();

        // RecoveryCodeModal appears showing the newly generated code
        expect(find.text('Your Recovery Code'), findsOneWidget);
        expect(find.text('PRIV-1234-ABCD-5678-EFGH'), findsOneWidget);
        expect(find.text('Copy code'), findsOneWidget);
        expect(find.text('I saved it'), findsOneWidget);

        // Tap I saved it to close modal
        await tester.tap(find.text('I saved it'));
        await tester.pumpAndSettle();

        // Now the card updates to "Recovery code ready" and "Replace recovery code"
        expect(find.text('Recovery code ready'), findsOneWidget);
        expect(find.text('Replace recovery code'), findsOneWidget);
      },
    );
  });
}
