import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:privora/app/providers.dart';
import 'package:privora/core/errors/app_exception.dart';
import 'package:privora/core/security/vault_crypto_service.dart';
import 'package:privora/core/theme/app_theme.dart';
import 'package:privora/core/widgets/privora_brand_app_bar.dart';
import 'package:privora/core/widgets/privora_logo.dart';
import 'package:privora/data/models/vault_photo.dart';
import 'package:privora/data/services/cloudinary_media_service.dart';
import 'package:privora/data/services/photo_upload_service.dart';
import 'package:privora/features/account/account_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sp;
import 'cloudinary_flow_test.dart';

class Failing404CloudinaryMediaService extends Fake
    implements CloudinaryMediaService {
  @override
  Future<CloudinaryUploadParams> createUploadSignature({
    required String categoryId,
    required String photoId,
  }) async {
    throw Exception(
      'Edge Function returned error 404: Requested function was not found',
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('VaultPhoto Migration 001 Backward Compatibility', () {
    test('toJson omits storage_provider when provider is supabase', () {
      final photo = VaultPhoto(
        id: 'photo-1',
        userId: 'user-1',
        categoryId: 'cat-1',
        storagePath: 'user-1/photos/photo-1.enc',
        thumbnailPath: 'user-1/thumbnails/photo-1.enc',
        displayName: 'test.jpg',
        mimeType: 'image/jpeg',
        encryptedSize: 1024,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        storageProvider: 'supabase',
      );

      final json = photo.toJson();
      expect(json.containsKey('storage_provider'), isFalse);
      expect(json['storage_path'], 'user-1/photos/photo-1.enc');
      expect(json['thumbnail_path'], 'user-1/thumbnails/photo-1.enc');
    });

    test('toJson includes storage_provider when provider is cloudinary', () {
      final photo = VaultPhoto(
        id: 'photo-2',
        userId: 'user-1',
        categoryId: 'cat-1',
        storagePath: 'cloudinary/photo-2',
        thumbnailPath: 'cloudinary/photo-2_thumb',
        displayName: 'test.jpg',
        mimeType: 'image/jpeg',
        encryptedSize: 1024,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        storageProvider: 'cloudinary',
        cloudinaryPublicId: 'cloudinary/photo-2',
      );

      final json = photo.toJson();
      expect(json.containsKey('storage_provider'), isTrue);
      expect(json['storage_provider'], 'cloudinary');
      expect(json['cloudinary_public_id'], 'cloudinary/photo-2');
    });
  });

  group('PhotoUploadService Cloudinary Strict Upload and Supabase Storage', () {
    test(
      'Throws StorageException with Stage 9 details when Cloudinary Edge Function returns 404 (no silent fallback)',
      () async {
        final crypto = VaultCryptoService(iterations: 1000);
        final fakeCloudinary404 = Failing404CloudinaryMediaService();
        final fakeStorage = FakeSupabaseStorageService();
        final fakeDb = FakeSupabaseDatabaseService();
        final fakeCleaner = FakeTemporaryFileCleaner();

        final uploadService = PhotoUploadService(
          cryptoService: crypto,
          cloudinaryService: fakeCloudinary404,
          storageService: fakeStorage,
          databaseService: fakeDb,
          cleaner: fakeCleaner,
        );

        final tempDir = await Directory.systemTemp.createTemp('upload_test_');
        final testFile = File('${tempDir.path}/sample.jpg');
        await testFile.writeAsBytes(List.generate(100, (i) => i));

        final masterKey = crypto.generateMasterKey();

        await expectLater(
          uploadService.uploadPhoto(
            sourceFile: testFile,
            userId: 'user-123',
            categoryId: 'cat-123',
            masterKey: masterKey,
          ),
          throwsA(
            isA<StorageException>().having(
              (e) => e.message,
              'message',
              contains('Cloud authorization failed'),
            ),
          ),
        );

        // Verify storage was NOT silently written to
        expect(fakeStorage.uploadCalls, equals(0));

        await tempDir.delete(recursive: true);
      },
    );

    test(
      'Uploads to Supabase Storage when cloudinaryService is not configured',
      () async {
        final crypto = VaultCryptoService(iterations: 1000);
        final fakeStorage = FakeSupabaseStorageService();
        final fakeDb = FakeSupabaseDatabaseService();
        final fakeCleaner = FakeTemporaryFileCleaner();

        final uploadService = PhotoUploadService(
          cryptoService: crypto,
          cloudinaryService: null,
          storageService: fakeStorage,
          databaseService: fakeDb,
          cleaner: fakeCleaner,
        );

        final tempDir = await Directory.systemTemp.createTemp('upload_test_');
        final testFile = File('${tempDir.path}/sample.jpg');
        await testFile.writeAsBytes(List.generate(100, (i) => i));

        final masterKey = crypto.generateMasterKey();

        final result = await uploadService.uploadPhoto(
          sourceFile: testFile,
          userId: 'user-123',
          categoryId: 'cat-123',
          masterKey: masterKey,
        );

        expect(result.storageProvider, equals('supabase'));
        expect(fakeStorage.uploadCalls, equals(2));
        expect(fakeDb.storedPhotos.containsKey(result.id), isTrue);

        await tempDir.delete(recursive: true);
      },
    );
  });

  group('Privora Brand App Bar Layout', () {
    testWidgets('Logo is at left corner and title is mathematically centered', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(400, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            appBar: PrivoraBrandAppBar(
              isSearching: false,
              onToggleSearch: () {},
              onLock: () {},
            ),
          ),
        ),
      );

      final logoPos = tester.getTopLeft(find.byType(PrivoraLogo));
      expect(logoPos.dx, equals(16.0));

      final titleCenter = tester.getCenter(
        find.byKey(const Key('privora_brand_wordmark')),
      );
      expect(titleCenter.dx, equals(200.0));
    });
  });

  group('AccountScreen Profile Photo', () {
    testWidgets('Renders data URI avatar and camera icon badge', (
      tester,
    ) async {
      // 1x1 transparent PNG data URI
      const sampleDataUri =
          'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=';

      final mockUser = sp.User(
        id: 'user-123',
        appMetadata: {},
        userMetadata: {
          'full_name': 'Test Google User',
          'avatar_url': sampleDataUri,
        },
        aud: 'authenticated',
        createdAt: DateTime.now().toIso8601String(),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentUserProvider.overrideWith((ref) => mockUser),
            storageUsageProvider.overrideWith((ref) => 1024),
          ],
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            home: const AccountScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Test Google User'), findsOneWidget);
      // Verify camera edit badge is present on avatar
      expect(find.byIcon(Icons.camera_alt_rounded), findsOneWidget);
      // Verify Image widget rendered
      expect(find.byType(Image), findsOneWidget);
    });

    testWidgets('Renders initial letter fallback when avatar is not set', (
      tester,
    ) async {
      final mockUser = sp.User(
        id: 'user-456',
        appMetadata: {},
        userMetadata: {'full_name': 'Alex Smith', 'avatar_url': ''},
        aud: 'authenticated',
        createdAt: DateTime.now().toIso8601String(),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentUserProvider.overrideWith((ref) => mockUser),
            storageUsageProvider.overrideWith((ref) => 1024),
          ],
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            home: const AccountScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Alex Smith'), findsOneWidget);
      // Fallback initial letter
      expect(find.text('A'), findsOneWidget);
      // Verify camera edit badge is present
      expect(find.byIcon(Icons.camera_alt_rounded), findsOneWidget);
    });
  });
}
