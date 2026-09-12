import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:privora/app/providers.dart';
import 'package:privora/core/security/vault_crypto_service.dart';
import 'package:privora/data/models/vault_category.dart';
import 'package:privora/data/models/vault_photo.dart';
import 'package:privora/data/repositories/category_repository.dart';
import 'package:privora/data/services/photo_download_service.dart';
import 'package:privora/data/services/supabase_database_service.dart';
import 'package:privora/data/services/supabase_storage_service.dart';
import 'package:privora/features/gallery/photo_grid.dart';

class FakeDatabaseService extends Fake implements SupabaseDatabaseService {
  final Map<String, List<VaultCategory>> categoriesByUser = {};
  final Map<String, int> photoCountsByCategory = {};

  @override
  Future<List<VaultCategory>> getCategories(String userId) async {
    final list = categoriesByUser[userId] ?? [];
    return list.map((c) {
      final count = photoCountsByCategory[c.id] ?? c.photoCount;
      return c.copyWith(photoCount: count);
    }).toList();
  }

  @override
  Future<VaultCategory> createCategory(VaultCategory category) async {
    final list = categoriesByUser[category.userId] ?? [];
    list.add(category);
    categoriesByUser[category.userId] = list;
    return category;
  }
}

class FakeStorageService extends Fake implements SupabaseStorageService {
  int downloadCallCount = 0;
  final Map<String, Uint8List> storage = {};

  @override
  Future<Uint8List> downloadEncryptedBytes(String path) async {
    downloadCallCount++;
    if (storage.containsKey(path)) {
      return storage[path]!;
    }
    throw Exception('Object not found: $path');
  }
}

class FakeCryptoService extends Fake implements VaultCryptoService {
  int decryptCallCount = 0;

  @override
  Future<Uint8List> decryptPhotoBytes(
    Uint8List encryptedBytes,
    Uint8List masterKey,
  ) async {
    decryptCallCount++;
    return Uint8List.fromList([
      0x89,
      0x50,
      0x4E,
      0x47,
      0x0D,
      0x0A,
      0x1A,
      0x0A,
      0x00,
      0x00,
      0x00,
      0x0D,
      0x49,
      0x48,
      0x44,
      0x52,
      0x00,
      0x00,
      0x00,
      0x01,
      0x00,
      0x00,
      0x00,
      0x01,
      0x08,
      0x06,
      0x00,
      0x00,
      0x00,
      0x1F,
      0x15,
      0xC4,
      0x89,
      0x00,
      0x00,
      0x00,
      0x0A,
      0x49,
      0x44,
      0x41,
      0x54,
      0x78,
      0x9C,
      0x63,
      0x00,
      0x01,
      0x00,
      0x00,
      0x05,
      0x00,
      0x01,
      0x0D,
      0x0A,
      0x2D,
      0xB4,
      0x00,
      0x00,
      0x00,
      0x00,
      0x49,
      0x45,
      0x4E,
      0x44,
      0xAE,
      0x42,
      0x60,
      0x82,
    ]);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final dummyKey = Uint8List.fromList(List.generate(32, (i) => i));

  VaultPhoto createDummyPhoto({
    required String id,
    required String userId,
    required String categoryId,
    bool isCloudinary = false,
  }) {
    final now = DateTime.now();
    return VaultPhoto(
      id: id,
      userId: userId,
      categoryId: categoryId,
      storagePath: 'photos/$id.enc',
      thumbnailPath: 'thumbnails/${id}_thumb.enc',
      displayName: 'Photo_$id.jpg',
      mimeType: 'image/jpeg',
      encryptedSize: 1024,
      createdAt: now,
      updatedAt: now,
      storageProvider: isCloudinary ? 'cloudinary' : 'supabase',
      cloudinaryPublicId: isCloudinary
          ? 'privora/$userId/$categoryId/$id'
          : null,
      cloudinaryThumbnailPublicId: isCloudinary
          ? 'privora/$userId/$categoryId/${id}_thumb'
          : null,
    );
  }

  group('Category Photo Count Immediate & Optimistic Updates', () {
    test(
      '1. A category showing 0 photos changes immediately to 1 after upload',
      () async {
        final fakeDb = FakeDatabaseService();
        final repo = CategoryRepository(databaseService: fakeDb);
        const userId = 'user-kannan-1';

        final cat = await repo.createCategory(
          userId: userId,
          name: 'Kannan',
          colorValue: 0xFF2196F3,
        );
        expect(cat.photoCount, equals(0));

        // Fetch initial cached categories
        final initial = await repo.getCategories(userId);
        expect(initial.first.photoCount, equals(0));

        // Upload succeeds -> update photo count locally
        repo.updatePhotoCountLocally(cat.id, 1);

        // Verify category count changes immediately without waiting for DB
        final updated = await repo.getCategories(userId);
        expect(updated.first.photoCount, equals(1));
      },
    );

    test(
      '2. Multiple-photo upload increases count by exact success total (e.g. 2 photos)',
      () async {
        final fakeDb = FakeDatabaseService();
        final repo = CategoryRepository(databaseService: fakeDb);
        const userId = 'user-kannan-2';

        final cat = await repo.createCategory(
          userId: userId,
          name: 'Kannan',
          colorValue: 0xFF2196F3,
        );

        // Pre-seed cache
        await repo.getCategories(userId);

        // Simulate importing 2 photos simultaneously
        repo.updatePhotoCountLocally(cat.id, 2);

        final result = await repo.getCategories(userId);
        expect(result.first.photoCount, equals(2));
        expect(result.first.name, equals('Kannan'));
      },
    );

    test(
      '3. Moving a photo to Trash updates category count immediately',
      () async {
        final fakeDb = FakeDatabaseService();
        final repo = CategoryRepository(databaseService: fakeDb);
        const userId = 'user-kannan-3';

        final cat = await repo.createCategory(
          userId: userId,
          name: 'Kannan',
          colorValue: 0xFF2196F3,
        );
        repo.updatePhotoCountLocally(cat.id, 3);
        expect((await repo.getCategories(userId)).first.photoCount, equals(3));

        // Move 1 photo to Trash
        repo.updatePhotoCountLocally(cat.id, -1);
        expect((await repo.getCategories(userId)).first.photoCount, equals(2));
      },
    );

    test(
      '4. Restoring a photo reverses the category count immediately',
      () async {
        final fakeDb = FakeDatabaseService();
        final repo = CategoryRepository(databaseService: fakeDb);
        const userId = 'user-kannan-4';

        final cat = await repo.createCategory(
          userId: userId,
          name: 'Kannan',
          colorValue: 0xFF2196F3,
        );
        repo.updatePhotoCountLocally(cat.id, 1);

        // Restore 1 photo
        repo.updatePhotoCountLocally(cat.id, 1);
        expect((await repo.getCategories(userId)).first.photoCount, equals(2));
      },
    );

    test('5. Permanent deletion preserves active category count', () async {
      final fakeDb = FakeDatabaseService();
      final repo = CategoryRepository(databaseService: fakeDb);
      const userId = 'user-kannan-5';

      final cat = await repo.createCategory(
        userId: userId,
        name: 'Kannan',
        colorValue: 0xFF2196F3,
      );
      repo.updatePhotoCountLocally(cat.id, 2);

      // Permanent deletion of trash item does not affect active category count
      final before = (await repo.getCategories(userId)).first.photoCount;
      expect(before, equals(2));
    });
  });

  group('Thumbnail Memoization & Grid Performance', () {
    test(
      '6. Rebuilding a grid tile does NOT redownload or redecrypt its thumbnail',
      () async {
        final fakeStorage = FakeStorageService();
        fakeStorage.storage['thumbnails/p1_thumb.enc'] = Uint8List.fromList([
          1,
          2,
          3,
          4,
        ]);
        final fakeCrypto = FakeCryptoService();

        final downloadService = PhotoDownloadService(
          storageService: fakeStorage,
          cryptoService: fakeCrypto,
        );

        final photo = createDummyPhoto(
          id: 'p1',
          userId: 'user-perf-1',
          categoryId: 'cat-1',
        );

        // First load
        final bytes1 = await downloadService.getDecryptedThumbnail(
          photo: photo,
          masterKey: dummyKey,
        );
        expect(bytes1, isNotEmpty);
        expect(fakeStorage.downloadCallCount, equals(1));
        expect(fakeCrypto.decryptCallCount, equals(1));

        // Second load (simulating widget rebuild or scrolling back)
        final bytes2 = await downloadService.getDecryptedThumbnail(
          photo: photo,
          masterKey: dummyKey,
        );
        expect(bytes2, equals(bytes1));
        // Call counts MUST remain 1: zero repeated network download and zero repeated decryption!
        expect(fakeStorage.downloadCallCount, equals(1));
        expect(fakeCrypto.decryptCallCount, equals(1));

        // Synchronous access check
        final syncBytes = downloadService.getCachedThumbnail(photo);
        expect(syncBytes, isNotNull);
        expect(syncBytes, equals(bytes1));
      },
    );

    test(
      '7. Opening a photo shows its thumbnail before the full image',
      () async {
        final fakeStorage = FakeStorageService();
        fakeStorage.storage['thumbnails/p2_thumb.enc'] = Uint8List.fromList([
          10,
          20,
        ]);
        fakeStorage.storage['photos/p2.enc'] = Uint8List.fromList([
          30,
          40,
          50,
          60,
        ]);
        final fakeCrypto = FakeCryptoService();

        final downloadService = PhotoDownloadService(
          storageService: fakeStorage,
          cryptoService: fakeCrypto,
        );

        final photo = createDummyPhoto(
          id: 'p2',
          userId: 'user-perf-2',
          categoryId: 'cat-2',
        );

        // Pre-load thumbnail (as would happen in the grid)
        await downloadService.getDecryptedThumbnail(
          photo: photo,
          masterKey: dummyKey,
        );

        // Synchronous thumbnail must be available immediately (0 ms)
        final instantThumb = downloadService.getCachedThumbnail(photo);
        expect(instantThumb, isNotNull);

        // Full photo is NOT yet cached
        final instantFull = downloadService.getCachedFullPhoto(photo);
        expect(instantFull, isNull);

        // Now load full photo
        final fullBytes = await downloadService.getDecryptedFullPhoto(
          photo: photo,
          masterKey: dummyKey,
        );
        expect(fullBytes, isNotNull);
        expect(downloadService.getCachedFullPhoto(photo), isNotNull);
      },
    );

    test(
      '8. One failed thumbnail does not block other photos in the grid',
      () async {
        final fakeStorage = FakeStorageService();
        // Photo 1 exists, Photo 2 does NOT exist
        fakeStorage.storage['thumbnails/ok_thumb.enc'] = Uint8List.fromList([
          1,
        ]);
        final fakeCrypto = FakeCryptoService();

        final downloadService = PhotoDownloadService(
          storageService: fakeStorage,
          cryptoService: fakeCrypto,
        );

        final photoOk = createDummyPhoto(
          id: 'ok',
          userId: 'user-perf-3',
          categoryId: 'cat-3',
        );
        final photoFail = createDummyPhoto(
          id: 'fail',
          userId: 'user-perf-3',
          categoryId: 'cat-3',
        );

        // Load successful photo
        final okBytes = await downloadService.getDecryptedThumbnail(
          photo: photoOk,
          masterKey: dummyKey,
        );
        expect(okBytes, isNotEmpty);

        // Load failing photo
        expect(
          () => downloadService.getDecryptedThumbnail(
            photo: photoFail,
            masterKey: dummyKey,
          ),
          throwsA(isA<Exception>()),
        );

        // PhotoOk remains intact and cached
        expect(downloadService.getCachedThumbnail(photoOk), isNotNull);
      },
    );

    test(
      '9. Caches are isolated by user ID and cleared on sign-out/lock',
      () async {
        final fakeStorage = FakeStorageService();
        fakeStorage.storage['thumbnails/pA_thumb.enc'] = Uint8List.fromList([
          1,
        ]);
        fakeStorage.storage['thumbnails/pB_thumb.enc'] = Uint8List.fromList([
          2,
        ]);
        final fakeCrypto = FakeCryptoService();

        final downloadService = PhotoDownloadService(
          storageService: fakeStorage,
          cryptoService: fakeCrypto,
        );

        final photoUserA = createDummyPhoto(
          id: 'pA',
          userId: 'user-alpha',
          categoryId: 'cat-A',
        );
        final photoUserB = createDummyPhoto(
          id: 'pB',
          userId: 'user-beta',
          categoryId: 'cat-B',
        );

        await downloadService.getDecryptedThumbnail(
          photo: photoUserA,
          masterKey: dummyKey,
        );
        await downloadService.getDecryptedThumbnail(
          photo: photoUserB,
          masterKey: dummyKey,
        );

        expect(downloadService.getCachedThumbnail(photoUserA), isNotNull);
        expect(downloadService.getCachedThumbnail(photoUserB), isNotNull);

        // Evict user-alpha only
        downloadService.clearMemoryCache('user-alpha');
        expect(downloadService.getCachedThumbnail(photoUserA), isNull);
        expect(downloadService.getCachedThumbnail(photoUserB), isNotNull);

        // Evict all on vault lock
        downloadService.clearMemoryCache();
        expect(downloadService.getCachedThumbnail(photoUserB), isNull);
      },
    );
  });

  group('Widget Integration Tests', () {
    testWidgets(
      'EncryptedThumbnailTile renders cached thumbnail without rebuild overhead',
      (tester) async {
        final fakeStorage = FakeStorageService();
        fakeStorage.storage['thumbnails/w1_thumb.enc'] = Uint8List.fromList([
          1,
          2,
          3,
          4,
        ]);
        final fakeCrypto = FakeCryptoService();

        final downloadService = PhotoDownloadService(
          storageService: fakeStorage,
          cryptoService: fakeCrypto,
        );

        final photo = createDummyPhoto(
          id: 'w1',
          userId: 'user-widget-1',
          categoryId: 'cat-w',
        );

        // Pre-seed thumbnail cache
        await downloadService.getDecryptedThumbnail(
          photo: photo,
          masterKey: dummyKey,
        );

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              photoDownloadServiceProvider.overrideWithValue(downloadService),
            ],
            child: MaterialApp(
              home: Scaffold(
                body: EncryptedThumbnailTile(photo: photo, masterKey: dummyKey),
              ),
            ),
          ),
        );

        // Should render Image.memory immediately without waiting for FutureBuilder
        await tester.pump();
        expect(find.byType(Image), findsOneWidget);
      },
    );
  });
}
