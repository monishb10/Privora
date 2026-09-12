import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:privora/core/errors/app_exception.dart';
import 'package:privora/core/security/vault_crypto_service.dart';
import 'package:privora/data/models/vault_photo.dart';
import 'package:privora/data/services/cloudinary_media_service.dart';
import 'package:privora/data/services/photo_download_service.dart';
import 'package:privora/data/services/supabase_storage_service.dart';

// ---------------------------------------------------------------------------
// TEST FAKES
// ---------------------------------------------------------------------------

class MockCloudinaryMediaService extends Fake
    implements CloudinaryMediaService {
  final Map<String, Uint8List> storedAssetsByUrl = {};
  final Map<String, String> backfilledThumbnailAssets = {};
  int signedDownloadUrlCalls = 0;
  int downloadEncryptedBytesCalls = 0;

  @override
  Future<String> getSignedDownloadUrl({
    required String photoId,
    required String target,
  }) async {
    signedDownloadUrlCalls++;

    if (photoId == 'unowned_photo_by_user_b') {
      throw const StorageException(
        'Access denied: Photo not found or unowned.',
        statusCode: 403,
      );
    }

    if (photoId == 'missing_cloud_photo') {
      throw const StorageException(
        'Cloud file could not be found.',
        code: 'NOT_FOUND',
        statusCode: 404,
      );
    }

    if (photoId == 'auto_repair_photo' && target == 'thumbnail') {
      // Simulate automatic lookup & backfill in Edge Function
      backfilledThumbnailAssets[photoId] = 'repaired_asset_thumb_777';
      const url =
          'https://api.cloudinary.com/v1_1/wpi3z1ov/asset/download?api_key=key&asset_id=repaired_asset_thumb_777&expires_at=9999999999&timestamp=1111111111&signature=sig';
      return url;
    }

    if (target == 'thumbnail') {
      return 'https://api.cloudinary.com/v1_1/wpi3z1ov/asset/download?api_key=key&asset_id=asset_thumb_456&expires_at=9999999999&timestamp=1111111111&signature=sig';
    } else {
      return 'https://api.cloudinary.com/v1_1/wpi3z1ov/asset/download?api_key=key&asset_id=asset_full_123&expires_at=9999999999&timestamp=1111111111&signature=sig';
    }
  }

  @override
  Future<Uint8List> downloadEncryptedBytes(String downloadUrl) async {
    downloadEncryptedBytesCalls++;

    if (downloadUrl.contains('not_found') || downloadUrl.contains('missing')) {
      throw const StorageException(
        'Cloud file could not be found.',
        code: 'NOT_FOUND',
        statusCode: 404,
      );
    }

    for (final entry in storedAssetsByUrl.entries) {
      if (downloadUrl.contains(entry.key)) {
        return entry.value;
      }
    }

    if (storedAssetsByUrl.isNotEmpty) {
      return storedAssetsByUrl.values.first;
    }

    throw const StorageException(
      'Cloud file could not be found.',
      code: 'NOT_FOUND',
      statusCode: 404,
    );
  }
}

class FakeSupabaseStorageService extends Fake
    implements SupabaseStorageService {
  final Map<String, Uint8List> supabaseFiles = {};
  int downloadCalls = 0;

  @override
  Future<Uint8List> downloadEncryptedBytes(String path) async {
    downloadCalls++;
    final bytes = supabaseFiles[path];
    if (bytes == null) {
      throw const StorageException('Object not found in Supabase Storage');
    }
    return bytes;
  }
}

// ---------------------------------------------------------------------------
// TEST SUITE: 9 REGRESSION SCENARIOS
// ---------------------------------------------------------------------------

void main() {
  late VaultCryptoService cryptoService;
  late MockCloudinaryMediaService mockCloudinary;
  late FakeSupabaseStorageService fakeSupabaseStorage;
  late PhotoDownloadService downloadService;
  late Uint8List masterKey;

  setUp(() {
    cryptoService = VaultCryptoService(iterations: 1000);
    mockCloudinary = MockCloudinaryMediaService();
    fakeSupabaseStorage = FakeSupabaseStorageService();
    downloadService = PhotoDownloadService(
      storageService: fakeSupabaseStorage,
      cloudinaryService: mockCloudinary,
      cryptoService: cryptoService,
    );
    masterKey = cryptoService.generateMasterKey();
  });

  group('Cloudinary Asset Identity & Download Repair Contract Tests', () {
    // -------------------------------------------------------------------------
    // Scenario 1: New Full-Photo Asset-ID Download
    // -------------------------------------------------------------------------
    test(
      'Scenario 1: New full-photo download requests signed /asset/download URL with asset_id and decrypts plaintext',
      () async {
        final originalBytes = utf8.encode('FULL_PHOTO_ORIGINAL_SECRET_PAYLOAD');
        final encryptedBytes = await cryptoService.encryptPhotoBytes(
          originalBytes,
          masterKey,
        );

        mockCloudinary.storedAssetsByUrl['asset_full_123'] = encryptedBytes;

        final photo = VaultPhoto(
          id: 'photo-full-1',
          userId: 'user-1',
          categoryId: 'cat-1',
          storagePath: 'privora/user-1/cat-1/photo-full-1.enc',
          thumbnailPath: 'privora/user-1/cat-1/photo-full-1_thumb.enc',
          displayName: 'Full Photo',
          mimeType: 'image/jpeg',
          encryptedSize: encryptedBytes.length,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          storageProvider: 'cloudinary',
          cloudinaryPublicId: 'privora/user-1/cat-1/photo-full-1.enc',
          cloudinaryAssetId: 'asset_full_123',
        );

        final decrypted = await downloadService.getDecryptedFullPhoto(
          photo: photo,
          masterKey: masterKey,
        );

        expect(decrypted, equals(originalBytes));
        expect(mockCloudinary.signedDownloadUrlCalls, equals(1));
        expect(mockCloudinary.downloadEncryptedBytesCalls, equals(1));
      },
    );

    // -------------------------------------------------------------------------
    // Scenario 2: New Thumbnail Asset-ID Download
    // -------------------------------------------------------------------------
    test(
      'Scenario 2: New thumbnail download requests signed /asset/download URL with thumbnail asset_id and decrypts preview',
      () async {
        final thumbOriginal = utf8.encode('THUMBNAIL_PREVIEW_PAYLOAD');
        final encryptedThumb = await cryptoService.encryptPhotoBytes(
          thumbOriginal,
          masterKey,
        );

        mockCloudinary.storedAssetsByUrl['asset_thumb_456'] = encryptedThumb;

        final photo = VaultPhoto(
          id: 'photo-thumb-2',
          userId: 'user-1',
          categoryId: 'cat-1',
          storagePath: 'privora/user-1/cat-1/photo-thumb-2.enc',
          thumbnailPath: 'privora/user-1/cat-1/photo-thumb-2_thumb.enc',
          displayName: 'Thumbnail Photo',
          mimeType: 'image/jpeg',
          encryptedSize: encryptedThumb.length,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          storageProvider: 'cloudinary',
          cloudinaryPublicId: 'privora/user-1/cat-1/photo-thumb-2.enc',
          cloudinaryThumbnailPublicId:
              'privora/user-1/cat-1/photo-thumb-2_thumb.enc',
          cloudinaryAssetId: 'asset_full_123',
          cloudinaryThumbnailAssetId: 'asset_thumb_456',
        );

        final decrypted = await downloadService.getDecryptedThumbnail(
          photo: photo,
          masterKey: masterKey,
        );

        expect(decrypted, equals(thumbOriginal));
        expect(mockCloudinary.signedDownloadUrlCalls, equals(1));
        expect(mockCloudinary.downloadEncryptedBytesCalls, equals(1));
      },
    );

    // -------------------------------------------------------------------------
    // Scenario 3: Current .enc Public IDs
    // -------------------------------------------------------------------------
    test(
      'Scenario 3: Current .enc public IDs are preserved in storagePath and correctly delivered',
      () async {
        final rawData = utf8.encode('ENC_PUBLIC_ID_TEST_PAYLOAD');
        final encrypted = await cryptoService.encryptPhotoBytes(
          rawData,
          masterKey,
        );

        mockCloudinary.storedAssetsByUrl['asset_full_123'] = encrypted;

        final photo = VaultPhoto(
          id: 'photo-enc-3',
          userId: 'user-1',
          categoryId: 'cat-1',
          storagePath: 'privora/user-1/cat-1/photo-enc-3.enc',
          thumbnailPath: 'privora/user-1/cat-1/photo-enc-3_thumb.enc',
          displayName: 'Enc Photo',
          mimeType: 'image/jpeg',
          encryptedSize: encrypted.length,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          storageProvider: 'cloudinary',
          cloudinaryPublicId: 'privora/user-1/cat-1/photo-enc-3.enc',
          cloudinaryThumbnailPublicId:
              'privora/user-1/cat-1/photo-enc-3_thumb.enc',
          cloudinaryAssetId: 'asset_full_123',
        );

        expect(photo.storagePath.endsWith('.enc'), isTrue);
        expect(photo.thumbnailPath.endsWith('.enc'), isTrue);
        expect(photo.cloudinaryPublicId!.endsWith('.enc'), isTrue);

        final result = await downloadService.getDecryptedFullPhoto(
          photo: photo,
          masterKey: masterKey,
        );
        expect(result, equals(rawData));
      },
    );

    // -------------------------------------------------------------------------
    // Scenario 4: Legacy Public IDs Without .enc
    // -------------------------------------------------------------------------
    test(
      'Scenario 4: Legacy public IDs without .enc remain compatible and decrypt properly',
      () async {
        final legacyData = utf8.encode('LEGACY_UNMODIFIED_ASSET_BYTES');
        final encrypted = await cryptoService.encryptPhotoBytes(
          legacyData,
          masterKey,
        );

        mockCloudinary.storedAssetsByUrl['asset_full_123'] = encrypted;

        final legacyPhoto = VaultPhoto(
          id: 'photo-legacy-4',
          userId: 'user-1',
          categoryId: 'cat-1',
          storagePath: 'privora/user-1/cat-1/photo-legacy-4',
          thumbnailPath: 'privora/user-1/cat-1/photo-legacy-4_thumb',
          displayName: 'Legacy Photo',
          mimeType: 'image/jpeg',
          encryptedSize: encrypted.length,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          storageProvider: 'cloudinary',
          cloudinaryPublicId: 'privora/user-1/cat-1/photo-legacy-4',
          cloudinaryThumbnailPublicId:
              'privora/user-1/cat-1/photo-legacy-4_thumb',
          cloudinaryAssetId: 'asset_full_123',
        );

        expect(legacyPhoto.storagePath.endsWith('.enc'), isFalse);
        expect(legacyPhoto.isCloudinary, isTrue);

        final decrypted = await downloadService.getDecryptedFullPhoto(
          photo: legacyPhoto,
          masterKey: masterKey,
        );
        expect(decrypted, equals(legacyData));
      },
    );

    // -------------------------------------------------------------------------
    // Scenario 5: Automatic Missing-Asset-ID Lookup and Backfill
    // -------------------------------------------------------------------------
    test(
      'Scenario 5: Automatic missing-asset-ID lookup resolves asset_id and completes download',
      () async {
        final payload = utf8.encode('AUTO_REPAIR_THUMBNAIL_PAYLOAD');
        final encrypted = await cryptoService.encryptPhotoBytes(
          payload,
          masterKey,
        );

        mockCloudinary.storedAssetsByUrl['repaired_asset_thumb_777'] =
            encrypted;

        // Photo with missing cloudinaryThumbnailAssetId
        final photoWithMissingThumbAssetId = VaultPhoto(
          id: 'auto_repair_photo',
          userId: 'user-1',
          categoryId: 'cat-1',
          storagePath: 'privora/user-1/cat-1/auto_repair_photo.enc',
          thumbnailPath: 'privora/user-1/cat-1/auto_repair_photo_thumb.enc',
          displayName: 'Needs Repair',
          mimeType: 'image/jpeg',
          encryptedSize: encrypted.length,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          storageProvider: 'cloudinary',
          cloudinaryPublicId: 'privora/user-1/cat-1/auto_repair_photo.enc',
          cloudinaryAssetId: 'asset_full_123',
          cloudinaryThumbnailAssetId: null, // MISSING
        );

        final decrypted = await downloadService.getDecryptedThumbnail(
          photo: photoWithMissingThumbAssetId,
          masterKey: masterKey,
        );

        expect(decrypted, equals(payload));
        expect(
          mockCloudinary.backfilledThumbnailAssets['auto_repair_photo'],
          equals('repaired_asset_thumb_777'),
        );
      },
    );

    // -------------------------------------------------------------------------
    // Scenario 6: Wrong-User Access Denial
    // -------------------------------------------------------------------------
    test(
      'Scenario 6: Wrong-user access denial blocks downloading other users photos',
      () async {
        final unownedPhoto = VaultPhoto(
          id: 'unowned_photo_by_user_b',
          userId: 'user-b',
          categoryId: 'cat-b',
          storagePath: 'privora/user-b/cat-b/photo.enc',
          thumbnailPath: 'privora/user-b/cat-b/photo_thumb.enc',
          displayName: 'Victim Photo',
          mimeType: 'image/jpeg',
          encryptedSize: 1024,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          storageProvider: 'cloudinary',
          cloudinaryPublicId: 'privora/user-b/cat-b/photo.enc',
          cloudinaryAssetId: 'asset_user_b',
        );

        expect(
          () => downloadService.getDecryptedFullPhoto(
            photo: unownedPhoto,
            masterKey: masterKey,
          ),
          throwsA(
            isA<StorageException>().having(
              (e) => e.message,
              'message',
              contains('Access denied'),
            ),
          ),
        );
      },
    );

    // -------------------------------------------------------------------------
    // Scenario 7: Upload Response Type/Resource Validation
    // -------------------------------------------------------------------------
    test(
      'Scenario 7: Upload response validation rejects non-raw or non-authenticated uploads',
      () async {
        // 1. Valid response parsing
        final validJson = {
          'asset_id': 'asset_valid_999',
          'public_id': 'privora/u/c/p.enc',
          'resource_type': 'raw',
          'type': 'authenticated',
          'format': 'enc',
          'version': 1234567,
          'bytes': 2048,
        };
        final validResult = CloudinaryUploadResult.fromJson(validJson);
        expect(validResult.assetId, equals('asset_valid_999'));
        expect(validResult.publicId, equals('privora/u/c/p.enc'));
        expect(validResult.resourceType, equals('raw'));
        expect(validResult.type, equals('authenticated'));

        // 2. Client rejecting unexpected resource_type (e.g. image instead of raw)
        final invalidResourceClient = MockClient((request) async {
          return http.Response(
            jsonEncode({
              'asset_id': 'asset_bad',
              'public_id': 'bad_pub',
              'resource_type': 'image', // INVALID
              'type': 'authenticated',
              'bytes': 100,
            }),
            200,
          );
        });

        final serviceWithBadResource = CloudinaryMediaService(
          httpClient: invalidResourceClient,
        );

        expect(
          () => serviceWithBadResource.uploadEncryptedBytes(
            cloudName: 'test',
            apiKey: 'key',
            timestamp: 123,
            publicId: 'bad_pub',
            signature: 'sig',
            bytes: Uint8List.fromList([1, 2, 3]),
            filename: 'test.enc',
          ),
          throwsA(
            isA<StorageException>().having(
              (e) => e.message,
              'message',
              contains('unexpected resource_type'),
            ),
          ),
        );

        // 3. Client rejecting delivery type upload instead of authenticated
        final invalidTypeClient = MockClient((request) async {
          return http.Response(
            jsonEncode({
              'asset_id': 'asset_bad_type',
              'public_id': 'bad_pub_type',
              'resource_type': 'raw',
              'type': 'upload', // INVALID
              'bytes': 100,
            }),
            200,
          );
        });

        final serviceWithBadType = CloudinaryMediaService(
          httpClient: invalidTypeClient,
        );

        expect(
          () => serviceWithBadType.uploadEncryptedBytes(
            cloudName: 'test',
            apiKey: 'key',
            timestamp: 123,
            publicId: 'bad_pub_type',
            signature: 'sig',
            bytes: Uint8List.fromList([1, 2, 3]),
            filename: 'test.enc',
          ),
          throwsA(
            isA<StorageException>().having(
              (e) => e.message,
              'message',
              contains('unexpected type "upload"'),
            ),
          ),
        );

        // 4. Client rejecting missing asset_id
        final missingAssetIdClient = MockClient((request) async {
          return http.Response(
            jsonEncode({
              'public_id': 'missing_asset_id',
              'resource_type': 'raw',
              'type': 'authenticated',
              'bytes': 100,
            }),
            200,
          );
        });

        final serviceWithMissingAssetId = CloudinaryMediaService(
          httpClient: missingAssetIdClient,
        );

        expect(
          () => serviceWithMissingAssetId.uploadEncryptedBytes(
            cloudName: 'test',
            apiKey: 'key',
            timestamp: 123,
            publicId: 'missing_asset_id',
            signature: 'sig',
            bytes: Uint8List.fromList([1, 2, 3]),
            filename: 'test.enc',
          ),
          throwsA(
            isA<StorageException>().having(
              (e) => e.message,
              'message',
              contains('missing asset_id'),
            ),
          ),
        );
      },
    );

    // -------------------------------------------------------------------------
    // Scenario 8: Cloudinary 404 is Not Reported as a Decryption Failure
    // -------------------------------------------------------------------------
    test(
      'Scenario 8: Cloudinary 404 returns Cloud file could not be found and is NEVER reported as a decryption failure',
      () async {
        final missingPhoto = VaultPhoto(
          id: 'missing_cloud_photo',
          userId: 'user-1',
          categoryId: 'cat-1',
          storagePath: 'privora/user-1/cat-1/missing.enc',
          thumbnailPath: 'privora/user-1/cat-1/missing_thumb.enc',
          displayName: 'Missing Asset',
          mimeType: 'image/jpeg',
          encryptedSize: 1024,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          storageProvider: 'cloudinary',
          cloudinaryPublicId: 'privora/user-1/cat-1/missing.enc',
          cloudinaryAssetId: 'asset_missing',
        );

        try {
          await downloadService.getDecryptedFullPhoto(
            photo: missingPhoto,
            masterKey: masterKey,
          );
          fail('Should have thrown StorageException');
        } catch (e) {
          // CRITICAL: Must be StorageException, NOT CryptoException
          expect(e, isA<StorageException>());
          expect(e, isNot(isA<CryptoException>()));
          final se = e as StorageException;
          expect(se.message, equals('Cloud file could not be found.'));
          expect(se.statusCode, equals(404));
        }
      },
    );

    // -------------------------------------------------------------------------
    // Scenario 9: Existing Supabase Storage Photos Remain Unchanged
    // -------------------------------------------------------------------------
    test(
      'Scenario 9: Existing Supabase Storage photos remain completely unaffected and download via Supabase',
      () async {
        final legacySupabaseData = utf8.encode('LEGACY_SUPABASE_RAW_BYTES');
        final encryptedBytes = await cryptoService.encryptPhotoBytes(
          legacySupabaseData,
          masterKey,
        );

        const supabasePath = 'photos/user-123/legacy_supabase_photo.enc';
        fakeSupabaseStorage.supabaseFiles[supabasePath] = encryptedBytes;

        final supabasePhoto = VaultPhoto(
          id: 'supabase-legacy-99',
          userId: 'user-123',
          categoryId: 'cat-default',
          storagePath: supabasePath,
          thumbnailPath: 'thumbnails/user-123/legacy_supabase_photo.enc',
          displayName: 'Old Supabase Photo.jpg',
          mimeType: 'image/jpeg',
          encryptedSize: encryptedBytes.length,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          storageProvider: 'supabase', // Explicit Supabase provider
        );

        expect(supabasePhoto.isCloudinary, isFalse);

        final decrypted = await downloadService.getDecryptedFullPhoto(
          photo: supabasePhoto,
          masterKey: masterKey,
        );

        expect(decrypted, equals(legacySupabaseData));
        expect(fakeSupabaseStorage.downloadCalls, equals(1));
        expect(mockCloudinary.signedDownloadUrlCalls, equals(0));
        expect(mockCloudinary.downloadEncryptedBytesCalls, equals(0));
      },
    );
  });
}
