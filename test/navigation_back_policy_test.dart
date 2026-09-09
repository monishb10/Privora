import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:privora/app/providers.dart';
import 'package:privora/core/theme/app_theme.dart';
import 'package:privora/data/models/vault_category.dart';
import 'package:privora/data/models/vault_photo.dart';
import 'package:privora/data/repositories/category_repository.dart';
import 'package:privora/data/repositories/photo_repository.dart';
import 'package:privora/data/repositories/vault_repository.dart';
import 'package:privora/features/categories/categories_screen.dart';
import 'package:privora/features/categories/category_detail_screen.dart';
import 'package:privora/features/categories/create_category_sheet.dart';
import 'package:privora/features/categories/edit_category_sheet.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MockPhotoRepository extends Fake implements PhotoRepository {
  List<VaultPhoto> photosToReturn = [];

  static final Uint8List _dummyPng = Uint8List.fromList([
    0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
    0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
    0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
    0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
    0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49,
    0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
  ]);

  @override
  Future<Uint8List> loadThumbnail({
    String? thumbnailPath,
    VaultPhoto? photo,
    required Uint8List masterKey,
  }) async {
    return _dummyPng;
  }

  @override
  Future<List<VaultPhoto>> getPhotosByCategory(
    String userId,
    String categoryId, {
    int limit = 50,
    int offset = 0,
    bool ascending = false,
  }) async {
    return photosToReturn;
  }
}

class MockCategoryRepository extends Fake implements CategoryRepository {
  List<VaultCategory> categories = [];

  @override
  Future<List<VaultCategory>> getCategories(String userId, {bool forceRefresh = false}) async {
    return categories;
  }

  @override
  Future<void> updateCategory(VaultCategory category) async {}

  @override
  Future<VaultCategory> createCategory({
    required String userId,
    required String name,
    required int colorValue,
    String? categoryId,
  }) async {
    return VaultCategory(
      id: categoryId ?? 'new-cat-1',
      userId: userId,
      name: name,
      colorValue: colorValue,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
  }
}

class MockVaultRepositoryForNav extends Fake implements VaultRepository {
  @override
  Uint8List? get activeMasterKey => Uint8List(32);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final testUser = User(
    id: 'test-user-nav-123',
    appMetadata: {},
    userMetadata: {},
    aud: 'authenticated',
    createdAt: DateTime.now().toIso8601String(),
  );

  final testCategory = VaultCategory(
    id: 'cat-nav-1',
    userId: 'test-user-nav-123',
    name: 'Travel Memories',
    colorValue: 0xFF0A84C6,
    photoCount: 2,
    createdAt: DateTime.now(),
    updatedAt: DateTime.now(),
  );

  final testPhotos = [
    VaultPhoto(
      id: 'photo-1',
      userId: 'test-user-nav-123',
      categoryId: 'cat-nav-1',
      storagePath: 'enc/p1.enc',
      thumbnailPath: 'enc/t1.enc',
      displayName: 'Beach.jpg',
      mimeType: 'image/jpeg',
      encryptedSize: 1024,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    ),
    VaultPhoto(
      id: 'photo-2',
      userId: 'test-user-nav-123',
      categoryId: 'cat-nav-1',
      storagePath: 'enc/p2.enc',
      thumbnailPath: 'enc/t2.enc',
      displayName: 'Sunset.jpg',
      mimeType: 'image/jpeg',
      encryptedSize: 2048,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    ),
  ];

  group('Part 2: Navigation & Android Back Policy Tests', () {
    testWidgets(
      'CategoryDetailScreen: Android Back clears selection mode before popping screen',
      (tester) async {
        final mockPhotoRepo = MockPhotoRepository()..photosToReturn = testPhotos;
        final mockVaultRepo = MockVaultRepositoryForNav();

        bool screenPopped = false;

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              currentUserProvider.overrideWithValue(testUser),
              photoRepositoryProvider.overrideWithValue(mockPhotoRepo),
              vaultRepositoryProvider.overrideWithValue(mockVaultRepo),
            ],
            child: MaterialApp(
              theme: AppTheme.lightTheme,
              home: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () async {
                    await Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => CategoryDetailScreen(category: testCategory),
                      ),
                    );
                    screenPopped = true;
                  },
                  child: const Text('Open Category'),
                ),
              ),
            ),
          ),
        );

        // Open Category Detail Screen
        await tester.tap(find.text('Open Category'));
        await tester.pumpAndSettle();

        expect(find.text('Travel Memories'), findsOneWidget);
        expect(find.text('2 Selected'), findsNothing);

        // Long press first photo to enter selection mode
        await tester.longPress(find.byType(GestureDetector).first);
        await tester.pumpAndSettle();

        // Verify selection mode is now active
        expect(find.text('1 Selected'), findsOneWidget);
        expect(find.byTooltip('Close Selection'), findsOneWidget);

        // First Android Back press: MUST NOT pop the screen; MUST clear selection mode
        final backHandledFirst = await tester.binding.handlePopRoute();
        expect(backHandledFirst, isTrue);
        await tester.pumpAndSettle();

        // Selection is now cleared, screen is still mounted!
        expect(find.text('1 Selected'), findsNothing);
        expect(find.text('Travel Memories'), findsOneWidget);
        expect(screenPopped, isFalse);

        // Verify leading button is now 'Back' with 48x48 min bounds
        final backFinder = find.byTooltip('Back');
        expect(backFinder, findsOneWidget);
        final RenderBox renderBox = tester.renderObject(backFinder);
        expect(renderBox.size.width, greaterThanOrEqualTo(48));
        expect(renderBox.size.height, greaterThanOrEqualTo(48));

        // Second Android Back press: pops the screen normally
        final backHandledSecond = await tester.binding.handlePopRoute();
        expect(backHandledSecond, isTrue);
        await tester.pumpAndSettle();

        expect(screenPopped, isTrue);
      },
    );

    testWidgets(
      'CategoriesScreen: Android Back dismisses active search mode before leaving',
      (tester) async {
        final mockCategoryRepo = MockCategoryRepository()..categories = [testCategory];

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              currentUserProvider.overrideWithValue(testUser),
              categoryRepositoryProvider.overrideWithValue(mockCategoryRepo),
            ],
            child: MaterialApp(
              theme: AppTheme.lightTheme,
              home: const CategoriesScreen(),
            ),
          ),
        );

        await tester.pumpAndSettle();

        // Verify Search icon is visible
        final searchIconFinder = find.byIcon(Icons.search_rounded);
        expect(searchIconFinder, findsOneWidget);

        // Tap search icon to enter search mode
        await tester.tap(searchIconFinder);
        await tester.pumpAndSettle();

        // Enter search query
        await tester.enterText(find.byType(TextField), 'Travel');
        await tester.pump();
        expect(find.text('Travel'), findsOneWidget);

        // Trigger Android Back: should dismiss search without popping out
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();

        // Search textfield is dismissed
        expect(find.byType(TextField), findsNothing);
        expect(find.text('Travel Memories'), findsOneWidget);
      },
    );

    testWidgets(
      'EditCategorySheet: dirty edits show discard confirmation on Back/Cancel',
      (tester) async {
        final mockCategoryRepo = MockCategoryRepository();

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              categoryRepositoryProvider.overrideWithValue(mockCategoryRepo),
            ],
            child: MaterialApp(
              theme: AppTheme.lightTheme,
              home: Scaffold(
                body: Builder(
                  builder: (context) => ElevatedButton(
                    onPressed: () => EditCategorySheet.show(context, testCategory),
                    child: const Text('Open Edit Sheet'),
                  ),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Open Edit Sheet'));
        await tester.pumpAndSettle();

        // Modify category name so it is dirty
        await tester.enterText(find.byType(TextFormField), 'Changed Vacation');
        await tester.pump();

        // Tap Cancel button
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();

        // Confirmation dialog MUST appear
        expect(find.text('Discard Changes?'), findsOneWidget);
        expect(find.text('Keep Editing'), findsOneWidget);
        expect(find.text('Discard'), findsOneWidget);

        // Tap 'Keep Editing' -> stays on sheet
        await tester.tap(find.text('Keep Editing'));
        await tester.pumpAndSettle();
        expect(find.byType(EditCategorySheet), findsOneWidget);

        // Tap Cancel again and choose 'Discard'
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Discard'));
        await tester.pumpAndSettle();

        // Sheet is now dismissed
        expect(find.byType(EditCategorySheet), findsNothing);
      },
    );

    testWidgets(
      'CreateCategorySheet: non-empty input shows discard confirmation on Cancel',
      (tester) async {
        final mockCategoryRepo = MockCategoryRepository();

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              currentUserProvider.overrideWithValue(testUser),
              categoryRepositoryProvider.overrideWithValue(mockCategoryRepo),
            ],
            child: MaterialApp(
              theme: AppTheme.lightTheme,
              home: Scaffold(
                body: Builder(
                  builder: (context) => ElevatedButton(
                    onPressed: () => CreateCategorySheet.show(context),
                    child: const Text('Open Create Sheet'),
                  ),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Open Create Sheet'));
        await tester.pumpAndSettle();

        // Enter a category name so it is dirty
        await tester.enterText(find.byType(TextFormField), 'Work Documents');
        await tester.pump();

        // Tap Cancel
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();

        // Discard Category dialog appears
        expect(find.text('Discard Category?'), findsOneWidget);
        expect(find.text('Keep Editing'), findsOneWidget);

        // Choose 'Discard'
        await tester.tap(find.text('Discard'));
        await tester.pumpAndSettle();

        expect(find.byType(CreateCategorySheet), findsNothing);
      },
    );
  });
}
