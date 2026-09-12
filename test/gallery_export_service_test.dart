import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:privora/app/providers.dart';
import 'package:privora/core/errors/app_exception.dart';
import 'package:privora/data/models/vault_photo.dart';
import 'package:privora/data/services/gallery_export_service.dart';
import 'package:privora/data/services/photo_download_service.dart';
import 'package:privora/features/gallery/photo_viewer_screen.dart';

class _FakePhotoDownloadService extends Fake implements PhotoDownloadService {
  bool fullPhotoRequested = false;
  bool thumbnailRequested = false;
  Uint8List? bytesToReturn;
  Exception? exceptionToThrow;

  @override
  Future<Uint8List> getDecryptedFullPhoto({
    required VaultPhoto photo,
    required Uint8List masterKey,
  }) async {
    fullPhotoRequested = true;
    if (exceptionToThrow != null) throw exceptionToThrow!;
    return bytesToReturn ??
        Uint8List.fromList([
          0xFF,
          0xD8,
          0xFF,
          0xE0,
          0x00,
          0x10,
          0x4A,
          0x46,
          0x49,
          0x46,
          0x00,
          0x01,
        ]);
  }

  @override
  Future<Uint8List> getDecryptedThumbnail({
    required VaultPhoto photo,
    required Uint8List masterKey,
  }) async {
    thumbnailRequested = true;
    return Uint8List.fromList([0xFF, 0xD8, 0xFF]);
  }

  @override
  Uint8List? getCachedFullPhoto(VaultPhoto photo, {String? userId}) => null;

  @override
  Uint8List? getCachedThumbnail(VaultPhoto photo, {String? userId}) => null;

  @override
  void clearFullPhotoCache() {}

  @override
  void clearMemoryCache([String? userId]) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final testPhoto = VaultPhoto(
    id: 'test-photo-id-1234',
    userId: 'user-1',
    categoryId: 'cat-1',
    storagePath: 'privora/user-1/cat-1/test-photo-id-1234.enc',
    thumbnailPath: 'privora/user-1/cat-1/test-photo-id-1234_thumb.enc',
    displayName: 'vacation_photo.jpg',
    mimeType: 'image/jpeg',
    encryptedSize: 1024,
    createdAt: DateTime.now(),
    updatedAt: DateTime.now(),
    storageProvider: 'cloudinary',
    cloudinaryPublicId: 'privora/user-1/cat-1/test-photo-id-1234.enc',
    cloudinaryThumbnailPublicId:
        'privora/user-1/cat-1/test-photo-id-1234_thumb.enc',
    cloudinaryAssetId: 'asset-full-1',
    cloudinaryThumbnailAssetId: 'asset-thumb-1',
  );

  final testMasterKey = Uint8List.fromList(List.generate(32, (i) => i));

  group('GalleryExportService Byte Validation & Format Tests', () {
    test('validateDecryptedImageBytes accepts valid JPEG bytes', () {
      final jpegBytes = Uint8List.fromList([
        0xFF,
        0xD8,
        0xFF,
        0xE0,
        0x00,
        0x10,
        0x4A,
        0x46,
        0x49,
        0x46,
        0x00,
        0x01,
      ]);
      expect(
        () => GalleryExportService.validateDecryptedImageBytes(jpegBytes),
        returnsNormally,
      );
    });

    test('validateDecryptedImageBytes accepts valid PNG bytes', () {
      final pngBytes = Uint8List.fromList([
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
      ]);
      expect(
        () => GalleryExportService.validateDecryptedImageBytes(pngBytes),
        returnsNormally,
      );
    });

    test('validateDecryptedImageBytes accepts valid WebP bytes', () {
      final webpBytes = Uint8List.fromList([
        0x52,
        0x49,
        0x46,
        0x46,
        0x24,
        0x00,
        0x00,
        0x00,
        0x57,
        0x45,
        0x42,
        0x50,
      ]);
      expect(
        () => GalleryExportService.validateDecryptedImageBytes(webpBytes),
        returnsNormally,
      );
    });

    test(
      'validateDecryptedImageBytes strictly rejects ciphertext starting with 0x01',
      () {
        final ciphertextEnvelope = Uint8List.fromList([
          0x01, // Envelope version byte
          ...List.generate(12, (i) => i), // 12-byte nonce
          ...List.generate(16, (i) => i), // 16-byte GCM tag
          ...List.generate(50, (i) => i), // ciphertext payload
        ]);

        expect(
          () => GalleryExportService.validateDecryptedImageBytes(
            ciphertextEnvelope,
          ),
          throwsA(isA<CryptoException>()),
        );
      },
    );

    test(
      'validateDecryptedImageBytes rejects short or random non-image bytes',
      () {
        final shortBytes = Uint8List.fromList([1, 2, 3]);
        expect(
          () => GalleryExportService.validateDecryptedImageBytes(shortBytes),
          throwsA(isA<ImageDecodeException>()),
        );

        final randomBytes = Uint8List.fromList(
          List.generate(20, (i) => i + 50),
        );
        expect(
          () => GalleryExportService.validateDecryptedImageBytes(randomBytes),
          throwsA(isA<ImageDecodeException>()),
        );
      },
    );

    test('detectExtension accurately extracts format extensions', () {
      final jpeg = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0x00]);
      expect(
        GalleryExportService.detectExtension(jpeg, 'image/jpeg'),
        equals('.jpg'),
      );

      final png = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47]);
      expect(
        GalleryExportService.detectExtension(png, 'image/png'),
        equals('.png'),
      );

      final webp = Uint8List.fromList([
        0x52,
        0x49,
        0x46,
        0x46,
        0,
        0,
        0,
        0,
        0x57,
        0x45,
        0x42,
        0x50,
      ]);
      expect(
        GalleryExportService.detectExtension(webp, 'image/webp'),
        equals('.webp'),
      );
    });
  });

  group('GalleryExportService Download Contract Tests', () {
    test(
      'savePhotoToGallery calls getDecryptedFullPhoto and never thumbnail',
      () async {
        final fakeDownload = _FakePhotoDownloadService();
        final exportService = GalleryExportService(
          downloadService: fakeDownload,
        );

        try {
          await exportService.savePhotoToGallery(
            photo: testPhoto,
            masterKey: testMasterKey,
          );
        } catch (_) {
          // May throw in headless test without native MediaStore channel, but full photo check is verifiable
        }

        expect(fakeDownload.fullPhotoRequested, isTrue);
        expect(fakeDownload.thumbnailRequested, isFalse);
      },
    );

    test(
      'savePhotoToGallery does not modify the original VaultPhoto',
      () async {
        final fakeDownload = _FakePhotoDownloadService();
        final exportService = GalleryExportService(
          downloadService: fakeDownload,
        );

        final originalId = testPhoto.id;
        final originalStoragePath = testPhoto.storagePath;

        try {
          await exportService.savePhotoToGallery(
            photo: testPhoto,
            masterKey: testMasterKey,
          );
        } catch (_) {}

        expect(testPhoto.id, equals(originalId));
        expect(testPhoto.storagePath, equals(originalStoragePath));
      },
    );
  });

  group('PhotoViewerScreen Save to Gallery Action Tests', () {
    testWidgets(
      'PhotoViewerScreen displays exactly one Save to Gallery button with tooltip',
      (tester) async {
        final fakeDownload = _FakePhotoDownloadService();

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              photoDownloadServiceProvider.overrideWithValue(fakeDownload),
            ],
            child: MaterialApp(
              home: PhotoViewerScreen(
                photos: [testPhoto],
                initialIndex: 0,
                categoryId: 'cat-1',
              ),
            ),
          ),
        );

        // Verify bottom action bar has Save to Gallery action
        final saveButtonFinder = find.byTooltip('Save to Gallery');
        expect(saveButtonFinder, findsOneWidget);

        // Verify other actions remain present and non-duplicated
        expect(find.byTooltip('Share'), findsOneWidget);
        expect(find.byTooltip('Move Category'), findsOneWidget);
        expect(find.byTooltip('Move to Trash'), findsOneWidget);
      },
    );
  });
}
