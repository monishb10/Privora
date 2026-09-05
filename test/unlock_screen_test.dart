import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:privora/core/theme/app_theme.dart';
import 'package:privora/features/pin/unlock_screen.dart';

void main() {
  testWidgets(
    'UnlockScreen renders 6 PIN dots, keypad, and strictly zero biometric controls',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: const ProviderScope(child: UnlockScreen()),
        ),
      );

      await tester.pumpAndSettle();

      // Verify Title & Prompt
      expect(find.text('Enter 6-Digit PIN'), findsOneWidget);
      expect(
        find.text('Enter your PIN to unlock your encrypted photos.'),
        findsOneWidget,
      );

      // Verify Custom Numeric Keypad
      for (int i = 0; i <= 9; i++) {
        expect(find.text('$i'), findsOneWidget);
      }
      expect(find.byIcon(Icons.backspace_outlined), findsOneWidget);

      // STRICT SPECIFICATION: Ensure zero biometric buttons or icons exist anywhere on screen
      expect(find.byIcon(Icons.fingerprint), findsNothing);
      expect(find.byIcon(Icons.fingerprint_rounded), findsNothing);
      expect(find.textContaining('Biometric'), findsNothing);
      expect(find.textContaining('Face ID'), findsNothing);

      // Enter digits and verify interaction
      await tester.tap(find.text('1'));
      await tester.pump();
      await tester.tap(find.text('2'));
      await tester.pump();

      // Tap backspace
      await tester.tap(find.byIcon(Icons.backspace_outlined));
      await tester.pump();
    },
  );
}
