import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:privora/core/theme/app_theme.dart';
import 'package:privora/features/account/security_settings_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Security screen', () {
    for (final width in [320.0, 360.0, 412.0]) {
      for (final scale in [1.0, 1.3, 2.0]) {
        testWidgets(
          'renders without overflow at ${width.toInt()}px and ${scale}x text',
          (tester) async {
            tester.view.physicalSize = Size(width, 800);
            tester.view.devicePixelRatio = 1;
            addTearDown(() {
              tester.view.resetPhysicalSize();
              tester.view.resetDevicePixelRatio();
            });

            await tester.pumpWidget(
              MaterialApp(
                theme: AppTheme.lightTheme,
                home: MediaQuery(
                  data: MediaQueryData(
                    size: Size(width, 800),
                    textScaler: TextScaler.linear(scale),
                  ),
                  child: const SecuritySettingsScreen(),
                ),
              ),
            );
            await tester.pumpAndSettle();

            expect(find.text('Gmail PIN Reset'), findsOneWidget);
            expect(find.textContaining('Recovery Code'), findsNothing);

            await tester.scrollUntilVisible(
              find.text('Change 6-Digit PIN'),
              220,
            );
            await tester.pumpAndSettle();
            expect(find.text('Attempt Lockout'), findsOneWidget);
            expect(find.text('Change 6-Digit PIN'), findsOneWidget);
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  });
}
