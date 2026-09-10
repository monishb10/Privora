import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:privora/app/providers.dart';
import 'package:privora/core/theme/app_theme.dart';
import 'package:privora/data/models/vault_category.dart';
import 'package:privora/data/repositories/category_repository.dart';
import 'package:privora/features/categories/categories_screen.dart';
import 'package:privora/features/categories/create_category_sheet.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MockCategoryRepositoryForActionTest extends Fake
    implements CategoryRepository {
  List<VaultCategory> categories = [];
  int createCategoryCallCount = 0;

  @override
  Future<List<VaultCategory>> getCategories(
    String userId, {
    bool forceRefresh = false,
  }) async {
    return categories;
  }

  @override
  Future<VaultCategory> createCategory({
    required String userId,
    required String name,
    required int colorValue,
    String? categoryId,
  }) async {
    createCategoryCallCount++;
    // Simulate realistic async network delay
    await Future.delayed(const Duration(milliseconds: 150));
    final newCat = VaultCategory(
      id: categoryId ?? 'cat-$createCategoryCallCount',
      userId: userId,
      name: name,
      colorValue: colorValue,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    categories.add(newCat);
    return newCat;
  }

  @override
  void addCategoryLocally(VaultCategory category) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final testUser = User(
    id: 'user-single-action-123',
    appMetadata: {},
    userMetadata: {},
    aud: 'authenticated',
    createdAt: DateTime.now().toIso8601String(),
  );

  group('Requirement 1: Single Create-Category Option Tests', () {
    testWidgets(
      'When user has ZERO categories, shows exactly one centred action and ZERO FABs or header buttons',
      (tester) async {
        final mockRepo = MockCategoryRepositoryForActionTest()..categories = [];

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              currentUserProvider.overrideWithValue(testUser),
              categoryRepositoryProvider.overrideWithValue(mockRepo),
            ],
            child: MaterialApp(
              theme: AppTheme.lightTheme,
              home: const CategoriesScreen(),
            ),
          ),
        );

        await tester.pumpAndSettle();

        // 1. One centred empty-state button labelled "Create your first category"
        expect(find.text('Create your first category'), findsOneWidget);

        // 2. Hide every other New/Create Category button
        expect(find.text('New category'), findsNothing);
        expect(find.text('New Category'), findsNothing);

        // 3. ZERO FloatingActionButton exists anywhere
        expect(find.byType(FloatingActionButton), findsNothing);
      },
    );

    testWidgets(
      'When user has ONE OR MORE categories, shows exactly one header action and hides empty state & FAB',
      (tester) async {
        final testCategory = VaultCategory(
          id: 'cat-1',
          userId: 'user-single-action-123',
          name: 'Personal Documents',
          colorValue: 0xFF2B63D9,
          photoCount: 5,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );

        final mockRepo = MockCategoryRepositoryForActionTest()
          ..categories = [testCategory];

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              currentUserProvider.overrideWithValue(testUser),
              categoryRepositoryProvider.overrideWithValue(mockRepo),
            ],
            child: MaterialApp(
              theme: AppTheme.lightTheme,
              home: const CategoriesScreen(),
            ),
          ),
        );

        await tester.pumpAndSettle();

        // 1. Exactly one 'New category' action in normal page header
        expect(find.text('New category'), findsOneWidget);

        // 2. Empty-state action is completely hidden
        expect(find.text('Create your first category'), findsNothing);

        // 3. ZERO FloatingActionButton exists anywhere
        expect(find.byType(FloatingActionButton), findsNothing);
      },
    );

    testWidgets(
      'Repeated rapid taps on Create Category sheet submit cannot create duplicate database rows',
      (tester) async {
        final mockRepo = MockCategoryRepositoryForActionTest();

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              currentUserProvider.overrideWithValue(testUser),
              categoryRepositoryProvider.overrideWithValue(mockRepo),
            ],
            child: MaterialApp(
              theme: AppTheme.lightTheme,
              home: Scaffold(
                body: Builder(
                  builder: (context) => ElevatedButton(
                    onPressed: () => CreateCategorySheet.show(context),
                    child: const Text('Open Sheet'),
                  ),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Open Sheet'));
        await tester.pumpAndSettle();

        // Enter category name
        await tester.enterText(
          find.byType(TextFormField),
          'Confidential Vault',
        );
        await tester.pump();

        // Find the 'Create Category' action button in sheet
        final createBtn = find.text('Create Category');
        expect(createBtn, findsOneWidget);

        // Fire 4 rapid taps without waiting for async completion (simulating frantic double/multi-tap)
        await tester.tap(createBtn);
        await tester.tap(createBtn);
        await tester.tap(createBtn);
        await tester.tap(createBtn);

        // Now let async network call settle
        await tester.pumpAndSettle();

        // Crucial Assertion: Despite 4 taps, repo createCategory was called EXACTLY ONCE
        expect(mockRepo.createCategoryCallCount, equals(1));
        expect(mockRepo.categories.length, equals(1));
        expect(mockRepo.categories.first.name, equals('Confidential Vault'));
      },
    );
  });
}
