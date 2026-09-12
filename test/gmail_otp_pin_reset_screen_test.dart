import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:privora/app/providers.dart';
import 'package:privora/core/theme/app_theme.dart';
import 'package:privora/features/pin/forgot_pin_otp_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  testWidgets('forgot PIN uses only the signed-in Gmail address', (
    tester,
  ) async {
    final user = User(
      id: 'otp-user-1',
      appMetadata: const {'provider': 'google'},
      userMetadata: const {},
      aud: 'authenticated',
      email: 'owner@gmail.com',
      createdAt: DateTime.now().toIso8601String(),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [currentUserProvider.overrideWithValue(user)],
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          home: const ForgotPinOtpScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Reset Your PIN'), findsOneWidget);
    expect(find.text('Send 6-Digit Code'), findsOneWidget);
    expect(find.textContaining('@gmail.com'), findsWidgets);
    expect(find.byType(TextField), findsNothing);
    expect(find.textContaining('Recovery Code'), findsNothing);
  });
}
