import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:privora/app/providers.dart';
import 'package:privora/data/models/vault_category.dart';
import 'package:privora/data/repositories/category_repository.dart';
import 'package:privora/features/categories/edit_category_sheet.dart';
import 'google_auth_and_routing_test.dart';

class FakeCategoryRepoDatabaseService extends FakeDatabaseService {
  VaultCategory? updatedCategory;

  @override
  Future<void> updateCategory(VaultCategory category) async {
    updatedCategory = category;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Part 3: Edit Category Modal Bottom Sheet Overlap Tests', () {
    final testCategory = VaultCategory(
      id: 'cat-100',
      userId: 'user-1',
      name: 'Old Category Name',
      colorValue: 0xFF0A84C6,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    testWidgets(
      'Edit Category displays category name, color choices, Cancel and Save buttons',
      (tester) async {
        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              home: Scaffold(
                body: Builder(
                  builder: (context) => ElevatedButton(
                    onPressed: () =>
                        EditCategorySheet.show(context, testCategory),
                    child: const Text('Open Edit Sheet'),
                  ),
                ),
              ),
            ),
          ),
        );

        // Open Edit Sheet
        await tester.tap(find.text('Open Edit Sheet'));
        await tester.pumpAndSettle();

        // Verify header
        expect(find.text('Edit Category'), findsOneWidget);

        // Verify category name text field with initial value
        expect(find.text('Old Category Name'), findsOneWidget);

        // Verify Category Color label
        expect(find.text('Category Color'), findsOneWidget);

        // Verify BOTH Cancel and Save Changes buttons are visible
        expect(find.text('Cancel'), findsOneWidget);
        expect(find.text('Save Changes'), findsOneWidget);

        // Verify tapping Cancel dismisses without saving
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();

        expect(find.byType(EditCategorySheet), findsNothing);
      },
    );

    testWidgets('Edit Category Save updates category and pops sheet', (
      tester,
    ) async {
      final fakeDb = FakeCategoryRepoDatabaseService();
      final categoryRepo = CategoryRepository(databaseService: fakeDb);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            categoryRepositoryProvider.overrideWithValue(categoryRepo),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () =>
                      EditCategorySheet.show(context, testCategory),
                  child: const Text('Open Edit Sheet'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Edit Sheet'));
      await tester.pumpAndSettle();

      // Enter new name
      await tester.enterText(find.byType(TextFormField), 'Updated Travel');
      await tester.pump();

      // Tap Save Changes
      await tester.tap(find.text('Save Changes'));
      await tester.pumpAndSettle();

      // Sheet should be dismissed
      expect(find.byType(EditCategorySheet), findsNothing);
      expect(fakeDb.updatedCategory?.name, equals('Updated Travel'));
    });
  });
}
