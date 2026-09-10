import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:privora/app/providers.dart';
import 'package:privora/core/theme/app_theme.dart';
import 'package:privora/data/repositories/vault_repository.dart';
import 'package:privora/features/account/recovery_code_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MockVaultRepositoryForRecoveryScreenTest extends Fake
    implements VaultRepository {
  String? currentCode = 'PRIV-1234-ABCD-5678-EFGH';
  bool hasRecovery = true;

  @override
  Future<String?> getRecoveryCode(String userId) async {
    return currentCode;
  }

  @override
  Future<bool> hasRecoveryCode(String userId) async {
    return hasRecovery;
  }

  @override
  Future<String> generateOrReplaceRecoveryCode({
    required String userId,
    required String currentPin,
  }) async {
    currentCode = 'PRIV-9999-ZZZZ-8888-YYYY';
    return currentCode!;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final testUser = User(
    id: 'user-rec-test-123',
    appMetadata: {},
    userMetadata: {},
    aud: 'authenticated',
    createdAt: DateTime.now().toIso8601String(),
  );

  testWidgets(
    'RecoveryCodeScreen displays account recovery code, allows toggle, copy, and replace',
    (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final mockRepo = MockVaultRepositoryForRecoveryScreenTest();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentUserProvider.overrideWithValue(testUser),
            vaultRepositoryProvider.overrideWithValue(mockRepo),
          ],
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            home: const RecoveryCodeScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Header and titles
      expect(find.text('Vault Recovery Code'), findsOneWidget);
      expect(find.text('Unique Account Recovery Code'), findsOneWidget);
      expect(find.text('Active'), findsOneWidget);

      // Masked code by default
      expect(find.text('PRIV-••••-••••-••••-••••'), findsOneWidget);
      expect(find.text('PRIV-1234-ABCD-5678-EFGH'), findsNothing);

      // Reveal toggle
      final revealButton = find.byTooltip('Reveal');
      expect(revealButton, findsOneWidget);
      await tester.tap(revealButton);
      await tester.pumpAndSettle();

      // Now code is revealed
      expect(find.text('PRIV-1234-ABCD-5678-EFGH'), findsOneWidget);
      expect(find.text('PRIV-••••-••••-••••-••••'), findsNothing);

      // Action buttons
      expect(find.text('Copy Recovery Code'), findsOneWidget);
      expect(find.text('Change PIN with Recovery Code'), findsOneWidget);
      expect(find.text('Replace Recovery Code'), findsOneWidget);

      // Tap Replace Recovery Code
      await tester.tap(find.text('Replace Recovery Code'));
      await tester.pumpAndSettle();

      // PIN confirmation dialog appears
      expect(find.text('Confirm Your Current PIN'), findsOneWidget);
      await tester.enterText(find.byType(TextField), '123456');
      await tester.pump();

      await tester.tap(find.text('Confirm'));
      await tester.pumpAndSettle();

      // Code is updated and revealed
      expect(find.text('PRIV-9999-ZZZZ-8888-YYYY'), findsOneWidget);
    },
  );
}
