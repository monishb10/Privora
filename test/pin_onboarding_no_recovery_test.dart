import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:privora/app/providers.dart';
import 'package:privora/core/theme/app_theme.dart';
import 'package:privora/core/theme/app_typography.dart';
import 'package:privora/core/utils/validators.dart';
import 'package:privora/data/repositories/vault_repository.dart';
import 'package:privora/features/pin/confirm_pin_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MockVaultRepository extends Fake implements VaultRepository {
  bool initializeNewVaultCalled = false;
  String? initializedUserId;
  String? initializedPin;

  @override
  Future<void> initializeNewVault({
    required String userId,
    required String pin,
  }) async {
    initializeNewVaultCalled = true;
    initializedUserId = userId;
    initializedPin = pin;
  }
}

void main() {
  group('PIN Onboarding Without Recovery Gate Tests', () {
    test(
      'Validators.isSixDigitPin enforces strict 6-digit numeric string preserving leading zeros',
      () {
        // Valid cases
        expect(Validators.isSixDigitPin('000000'), isTrue);
        expect(Validators.isSixDigitPin('012345'), isTrue);
        expect(Validators.isSixDigitPin('123456'), isTrue);
        expect(Validators.isSixDigitPin('999999'), isTrue);

        // Invalid lengths
        expect(Validators.isSixDigitPin(''), isFalse);
        expect(Validators.isSixDigitPin('1'), isFalse);
        expect(Validators.isSixDigitPin('12345'), isFalse);
        expect(Validators.isSixDigitPin('1234567'), isFalse);

        // Invalid characters
        expect(Validators.isSixDigitPin('12345a'), isFalse);
        expect(Validators.isSixDigitPin('abcdef'), isFalse);
        expect(Validators.isSixDigitPin('12 345'), isFalse);
        expect(Validators.isSixDigitPin('12.345'), isFalse);
        expect(Validators.isSixDigitPin('-12345'), isFalse);

        // Validator message
        expect(Validators.validatePin('000000'), isNull);
        expect(
          Validators.validatePin('12345'),
          equals('PIN must be exactly 6 numeric digits.'),
        );
        expect(Validators.validatePin(null), equals('PIN is required.'));
      },
    );

    test('Typography hierarchy uses Manrope and prescribed styles', () {
      final textTheme = AppTheme.lightTheme.textTheme;

      // Font Family
      expect(textTheme.displayLarge?.fontFamily, equals('Manrope'));
      expect(textTheme.bodyLarge?.fontFamily, equals('Manrope'));
      expect(textTheme.titleMedium?.fontFamily, equals('Manrope'));

      // Token Specifications:
      // Heading: 28, w600
      expect(AppTypography.displayLarge.fontSize, equals(28));
      expect(AppTypography.displayLarge.fontWeight, equals(FontWeight.w600));

      // AppBar title: 20, w600
      expect(AppTypography.appBarTitle.fontSize, equals(20));
      expect(AppTypography.appBarTitle.fontWeight, equals(FontWeight.w600));

      // Section title / titleLarge: 20, w600
      expect(AppTypography.titleLarge.fontSize, equals(20));
      expect(AppTypography.titleLarge.fontWeight, equals(FontWeight.w600));

      // Card title / titleMedium: 18, w600
      expect(AppTypography.titleMedium.fontSize, equals(18));
      expect(AppTypography.titleMedium.fontWeight, equals(FontWeight.w600));

      // Body text: 16, w400
      expect(AppTypography.bodyLarge.fontSize, equals(16));
      expect(AppTypography.bodyLarge.fontWeight, equals(FontWeight.w400));

      // Button text: 15.5, w600
      expect(AppTypography.buttonText.fontSize, equals(15.5));
      expect(AppTypography.buttonText.fontWeight, equals(FontWeight.w600));

      // Supporting / Caption / bodySmall: 13, w400
      expect(AppTypography.bodySmall.fontSize, equals(13));
      expect(AppTypography.bodySmall.fontWeight, equals(FontWeight.w400));

      // Supporting meta / photoCount: 13, w500
      expect(AppTypography.photoCount.fontSize, equals(13));
      expect(AppTypography.photoCount.fontWeight, equals(FontWeight.w500));
    });

    testWidgets(
      'ConfirmPinScreen completes vault initialization and routes directly without recovery code screen',
      (tester) async {
        final mockVaultRepo = MockVaultRepository();
        final testUser = User(
          id: 'test-user-456',
          appMetadata: {},
          userMetadata: {},
          aud: 'authenticated',
          createdAt: DateTime.now().toIso8601String(),
        );

        String currentPath = '/confirm-pin';

        final router = GoRouter(
          initialLocation: '/confirm-pin',
          routes: [
            GoRoute(
              path: '/confirm-pin',
              builder: (context, state) =>
                  const ConfirmPinScreen(originalPin: '012345'),
            ),
            GoRoute(
              path: '/categories',
              builder: (context, state) =>
                  const Scaffold(body: Text('Categories Main Screen')),
            ),
          ],
          redirect: (context, state) {
            currentPath = state.uri.path;
            return null;
          },
        );

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              vaultRepositoryProvider.overrideWithValue(mockVaultRepo),
              currentUserProvider.overrideWithValue(testUser),
            ],
            child: MaterialApp.router(
              theme: AppTheme.lightTheme,
              routerConfig: router,
            ),
          ),
        );

        await tester.pumpAndSettle();

        // Verify Confirm PIN screen is showing
        expect(find.text('Confirm Your PIN'), findsOneWidget);
        expect(
          find.text('Re-enter the 6-digit PIN to confirm.'),
          findsOneWidget,
        );

        // Enter 6 digits matching originalPin ('012345')
        await tester.tap(find.text('0'));
        await tester.pump();
        await tester.tap(find.text('1'));
        await tester.pump();
        await tester.tap(find.text('2'));
        await tester.pump();
        await tester.tap(find.text('3'));
        await tester.pump();
        await tester.tap(find.text('4'));
        await tester.pump();
        await tester.tap(find.text('5'));
        await tester.pumpAndSettle();

        // Verify initializeNewVault was called with exact pin preserving leading zero
        expect(mockVaultRepo.initializeNewVaultCalled, isTrue);
        expect(mockVaultRepo.initializedUserId, equals('test-user-456'));
        expect(mockVaultRepo.initializedPin, equals('012345'));

        // Verify router navigated directly to /categories
        expect(currentPath, equals('/categories'));
        expect(find.text('Categories Main Screen'), findsOneWidget);

        // STRICT VERIFICATION: Ensure no Recovery Code dialog was ever displayed
        expect(find.textContaining('Recovery Code'), findsNothing);
        expect(find.textContaining('Save this code'), findsNothing);
        expect(
          find.textContaining('I have saved my recovery code'),
          findsNothing,
        );
      },
    );
  });
}
