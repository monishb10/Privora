import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:privora/app/providers.dart';
import 'package:privora/core/theme/app_theme.dart';
import 'package:privora/data/models/vault_category.dart';
import 'package:privora/features/categories/categories_screen.dart';

void main() {
  testWidgets(
    'CategoriesScreen displays exact zero-demo empty state when no categories exist',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            // Override categoriesProvider with empty list
            categoriesProvider.overrideWith(
              (ref) => Future.value(<VaultCategory>[]),
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.darkTheme,
            home: const CategoriesScreen(),
          ),
        ),
      );

      // Let the Future resolve
      await tester.pumpAndSettle();

      // Verify exact deliberate empty state mandated by design requirements
      expect(find.text('Your private space starts here'), findsOneWidget);
      expect(find.text('Create your first category'), findsOneWidget);

      // Verify strictly zero demo categories are displayed
      expect(find.text('Friends'), findsNothing);
      expect(find.text('College'), findsNothing);
      expect(find.text('Trips'), findsNothing);
      expect(find.text('All Photos'), findsNothing);
      expect(find.text('Favourites'), findsNothing);
    },
  );
}
