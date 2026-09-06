import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:privora/app/providers.dart';
import 'package:privora/core/errors/app_exception.dart';
import 'package:privora/core/errors/error_mapper.dart';
import 'package:privora/core/theme/app_theme.dart';
import 'package:privora/data/models/vault_category.dart';
import 'package:privora/data/repositories/category_repository.dart';
import 'package:privora/data/services/supabase_database_service.dart';
import 'package:privora/features/categories/create_category_sheet.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sp;

class FakeSupabaseDatabaseService extends Fake
    implements SupabaseDatabaseService {
  VaultCategory? lastCreatedCategory;
  int createCategoryCallCount = 0;
  Duration simulatedDelay = Duration.zero;
  Exception? errorToThrow;
  List<VaultCategory> storedCategories = [];

  @override
  Future<VaultCategory> createCategory(VaultCategory category) async {
    createCategoryCallCount++;
    if (simulatedDelay > Duration.zero) {
      await Future.delayed(simulatedDelay);
    }
    if (errorToThrow != null) {
      throw errorToThrow!;
    }
    lastCreatedCategory = category;
    storedCategories.insert(0, category);
    return category;
  }

  @override
  Future<List<VaultCategory>> getCategories(String userId) async {
    if (simulatedDelay > Duration.zero) {
      await Future.delayed(simulatedDelay);
    }
    return List.from(storedCategories);
  }
}

void main() {
  group('Category Creation Flow & Instant Local Cache', () {
    late FakeSupabaseDatabaseService fakeDb;
    late CategoryRepository categoryRepo;

    setUp(() {
      fakeDb = FakeSupabaseDatabaseService();
      categoryRepo = CategoryRepository(databaseService: fakeDb);
    });

    test('generates valid UUID v4 on client before database insert', () async {
      final created = await categoryRepo.createCategory(
        userId: 'test-user-id',
        name: 'Private Notes',
        colorValue: 0xFF123456,
      );

      // Verify returned category and DB received category has a valid client UUID v4
      expect(created.id, isNotEmpty);
      expect(fakeDb.lastCreatedCategory, isNotNull);
      expect(fakeDb.lastCreatedCategory!.id, equals(created.id));

      // UUID v4 format regex: 8-4-4-4-12 hex characters
      final uuidRegex = RegExp(
        r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-4[0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
      );
      expect(uuidRegex.hasMatch(created.id), isTrue);
      expect(created.name, equals('Private Notes'));
    });

    test('immediately adds created category to local state cache', () async {
      expect(categoryRepo.cachedCategories, isNull);

      final created = await categoryRepo.createCategory(
        userId: 'test-user-id',
        name: 'Instant Cache Test',
        colorValue: 0xFFAABBCC,
      );

      // Cache is immediately populated without requiring network getCategories
      expect(categoryRepo.cachedCategories, isNotNull);
      expect(categoryRepo.cachedCategories!.length, equals(1));
      expect(categoryRepo.cachedCategories!.first.id, equals(created.id));

      // getCategories without forceRefresh returns instantly from cache
      fakeDb.storedCategories.clear(); // Clear DB to prove it serves from cache
      final immediateCategories =
          await categoryRepo.getCategories('test-user-id');
      expect(immediateCategories.length, equals(1));
      expect(immediateCategories.first.name, equals('Instant Cache Test'));
    });

    test('silent background refresh updates local cache on forceRefresh',
        () async {
      await categoryRepo.createCategory(
        userId: 'test-user-id',
        name: 'Cat 1',
        colorValue: 0xFF111111,
      );

      // Simulate remote DB receiving an external category
      fakeDb.storedCategories.add(
        VaultCategory(
          id: 'remote-cat-2',
          userId: 'test-user-id',
          name: 'Remote Cat',
          colorValue: 0xFF222222,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      );

      // Fast get returns cached (1 category)
      final fastList = await categoryRepo.getCategories('test-user-id');
      expect(fastList.length, equals(1));

      // Silent background forceRefresh updates the cache to 2 categories
      final refreshedList = await categoryRepo.getCategories(
        'test-user-id',
        forceRefresh: true,
      );
      expect(refreshedList.length, equals(2));
      expect(categoryRepo.cachedCategories!.length, equals(2));
    });

    test('times out if database operation exceeds 10 seconds', () async {
      fakeDb.simulatedDelay = const Duration(seconds: 11);

      expect(
        () => categoryRepo.createCategory(
          userId: 'test-user-id',
          name: 'Slow Category',
          colorValue: 0xFF112233,
        ),
        throwsA(isA<TimeoutException>()),
      );
    });
  });

  group('ErrorMapper & Exception Handling', () {
    test('maps TimeoutException to user-friendly network message', () {
      final msg = ErrorMapper.mapToUserMessage(TimeoutException('Timed out'));
      expect(
        msg,
        equals('Request timed out. Please check your network connection.'),
      );
    });

    test('maps PostgrestException RLS permission error code 42501', () {
      const exception = sp.PostgrestException(
        message: 'new row violates row-level security policy for table "categories"',
        code: '42501',
      );
      final msg = ErrorMapper.mapToUserMessage(exception);
      expect(
        msg,
        equals('Access denied. You do not have permission for this action.'),
      );
    });

    test('maps expired JWT or session to Session expired message', () {
      const pgrstExp = sp.PostgrestException(
        message: 'JWT expired',
        code: 'PGRST301',
      );
      expect(
        ErrorMapper.mapToUserMessage(pgrstExp),
        equals('Session expired. Please sign in again.'),
      );

      const authExp = sp.AuthException('Invalid Refresh Token: session expired');
      expect(
        ErrorMapper.mapToUserMessage(authExp),
        equals('Session expired. Please sign in again.'),
      );
    });
  });

  group('CreateCategorySheet Widget Tests', () {
    testWidgets('shows session expired error when user is unauthenticated',
        (tester) async {
      final fakeDb = FakeSupabaseDatabaseService();
      final categoryRepo = CategoryRepository(databaseService: fakeDb);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            categoryRepositoryProvider.overrideWithValue(categoryRepo),
            currentUserProvider.overrideWithValue(null), // No authenticated user
          ],
          child: MaterialApp(
            theme: AppTheme.darkTheme,
            home: const Scaffold(body: CreateCategorySheet()),
          ),
        ),
      );

      // Enter category name
      await tester.enterText(find.byType(TextFormField), 'My Category');
      await tester.pump();

      // Tap Create Category
      await tester.tap(find.text('Create Category'));
      await tester.pump();

      // Error message should appear and database should NOT have been called
      expect(find.text('Session expired. Please sign in again.'), findsOneWidget);
      expect(fakeDb.createCategoryCallCount, equals(0));
    });

    testWidgets(
        'successful creation adds category locally, pops sheet, and shows snackbar',
        (tester) async {
      final fakeDb = FakeSupabaseDatabaseService();
      final categoryRepo = CategoryRepository(databaseService: fakeDb);

      const mockUser = sp.User(
        id: 'user-authenticated-uuid',
        appMetadata: {},
        userMetadata: {},
        aud: 'authenticated',
        createdAt: '2026-01-01T00:00:00Z',
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            categoryRepositoryProvider.overrideWithValue(categoryRepo),
            currentUserProvider.overrideWithValue(mockUser),
          ],
          child: MaterialApp(
            theme: AppTheme.darkTheme,
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

      // Open sheet
      await tester.tap(find.text('Open Sheet'));
      await tester.pumpAndSettle();

      expect(find.byType(CreateCategorySheet), findsOneWidget);

      // Enter name
      await tester.enterText(find.byType(TextFormField), 'Vacation Vault');
      await tester.pump();

      // Tap Create Category
      await tester.tap(find.text('Create Category'));
      await tester.pumpAndSettle();

      // Sheet should be popped and SnackBar shown
      expect(find.byType(CreateCategorySheet), findsNothing);
      expect(find.text('Category created'), findsOneWidget);

      // Verify category was created with valid UUID
      expect(fakeDb.createCategoryCallCount, equals(1));
      expect(fakeDb.lastCreatedCategory!.name, equals('Vacation Vault'));
      expect(categoryRepo.cachedCategories!.length, equals(1));
    });

    testWidgets(
        'error during creation displays message and stops loading state',
        (tester) async {
      final fakeDb = FakeSupabaseDatabaseService();
      fakeDb.errorToThrow =
          const StorageException('Unable to reach server. Try again.');
      final categoryRepo = CategoryRepository(databaseService: fakeDb);

      const mockUser = sp.User(
        id: 'user-authenticated-uuid',
        appMetadata: {},
        userMetadata: {},
        aud: 'authenticated',
        createdAt: '2026-01-01T00:00:00Z',
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            categoryRepositoryProvider.overrideWithValue(categoryRepo),
            currentUserProvider.overrideWithValue(mockUser),
          ],
          child: MaterialApp(
            theme: AppTheme.darkTheme,
            home: const Scaffold(body: CreateCategorySheet()),
          ),
        ),
      );

      await tester.enterText(find.byType(TextFormField), 'Failing Category');
      await tester.pump();

      await tester.tap(find.text('Create Category'));
      await tester.pumpAndSettle();

      // Error viewable
      expect(find.text('Unable to reach server. Try again.'), findsOneWidget);

      // Button is NOT loading anymore (stopped in finally)
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });
  });
}
