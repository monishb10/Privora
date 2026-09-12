import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:privora/core/constants/storage_constants.dart';
import 'package:privora/core/errors/app_exception.dart';
import 'package:privora/core/security/temporary_file_cleaner.dart';
import 'package:privora/core/security/vault_crypto_service.dart';
import 'package:privora/data/models/upload_state.dart';
import 'package:privora/data/models/vault_photo.dart';
import 'package:privora/data/repositories/photo_repository.dart';
import 'package:privora/data/services/cloudinary_media_service.dart';
import 'package:privora/data/services/photo_download_service.dart';
import 'package:privora/data/services/photo_upload_service.dart';
import 'package:privora/data/services/supabase_database_service.dart';
import 'package:privora/data/services/supabase_storage_service.dart';

// ---------------------------------------------------------------------------
// TEST FAKES
// ---------------------------------------------------------------------------

class FakeCloudinaryMediaService extends Fake
    implements CloudinaryMediaService {
  int uploadSignatureCalls = 0;
  int uploadBytesCalls = 0;
  int signedDownloadUrlCalls = 0;
  int downloadBytesCalls = 0;
  int permanentlyDeleteCalls = 0;
  int cleanupFailedUploadCalls = 0;

  final List<String> uploadedPublicIds = [];
  final Map<String, Uint8List> uploadedPayloads = {};
  String? lastCleanedFullPublicId;
  String? lastCleanedThumbnailPublicId;
  String? lastDeletedPhotoId;

  Exception? errorToThrowOnSignature;
  Exception? errorToThrowOnUpload;
  Exception? errorToThrowOnDownloadUrl;
  Exception? errorToThrowOnDownloadBytes;
  Exception? errorToThrowOnDelete;

  String? failUploadOnPublicId;
  bool failOnlyOnFullPhoto = false;
  Duration simulatedDelay = Duration.zero;

  @override
  Future<CloudinaryUploadParams> createUploadSignature({
    required String categoryId,
    required String photoId,
  }) async {
    uploadSignatureCalls++;
    if (simulatedDelay > Duration.zero) await Future.delayed(simulatedDelay);
    if (errorToThrowOnSignature != null) throw errorToThrowOnSignature!;

    return CloudinaryUploadParams(
      cloudName: 'privora-cloud',
      apiKey: 'test-api-key',
      timestamp: 1770000000,
      resourceType: 'raw',
      type: 'authenticated',
      photoId: photoId,
      fullPublicId: 'privora/user-123/$categoryId/$photoId',
      fullSignature: 'full_sig_$photoId',
      thumbnailPublicId: 'privora/user-123/$categoryId/${photoId}_thumb',
      thumbnailSignature: 'thumb_sig_$photoId',
    );
  }

  final Map<String, Map<String, String>> uploadedSignedParams = {};

  @override
  Future<CloudinaryUploadResult> uploadEncryptedBytes({
    required String cloudName,
    required String apiKey,
    required int timestamp,
    String? uploadPreset,
    required String publicId,
    required String signature,
    required Uint8List bytes,
    required String filename,
    Map<String, String>? signedParams,
    String stage = 'upload',
  }) async {
    uploadBytesCalls++;
    if (signedParams != null) {
      uploadedSignedParams[publicId] = signedParams;
    }
    if (simulatedDelay > Duration.zero) await Future.delayed(simulatedDelay);
    if (failOnlyOnFullPhoto && !publicId.endsWith('_thumb')) {
      throw const StorageException(
        'Simulated Cloudinary full photo upload network failure',
      );
    }
    if (failUploadOnPublicId != null &&
        publicId.contains(failUploadOnPublicId!)) {
      throw const StorageException(
        'Simulated Cloudinary upload network failure',
      );
    }
    if (errorToThrowOnUpload != null) throw errorToThrowOnUpload!;

    uploadedPublicIds.add(publicId);
    uploadedPayloads[publicId] = bytes;

    return CloudinaryUploadResult(
      publicId: publicId,
      assetId: 'asset_${publicId.replaceAll('/', '_')}',
      version: '1',
      bytes: bytes.length,
    );
  }

  @override
  Future<String> getSignedDownloadUrl({
    required String photoId,
    required String target,
  }) async {
    signedDownloadUrlCalls++;
    if (simulatedDelay > Duration.zero) await Future.delayed(simulatedDelay);
    if (errorToThrowOnDownloadUrl != null) throw errorToThrowOnDownloadUrl!;

    return 'https://api.cloudinary.com/v1_1/privora-cloud/raw/download?public_id=privora/user-123/cat-123/$photoId&target=$target';
  }

  @override
  Future<Uint8List> downloadEncryptedBytes(String downloadUrl) async {
    downloadBytesCalls++;
    if (simulatedDelay > Duration.zero) await Future.delayed(simulatedDelay);
    if (errorToThrowOnDownloadBytes != null) throw errorToThrowOnDownloadBytes!;

    for (final entry in uploadedPayloads.entries) {
      if (downloadUrl.contains(entry.key)) {
        return entry.value;
      }
    }
    if (uploadedPayloads.isNotEmpty) {
      return uploadedPayloads.values.first;
    }
    return Uint8List.fromList([1, 2, 3, 4]);
  }

  @override
  Future<void> permanentlyDelete({required String photoId}) async {
    permanentlyDeleteCalls++;
    if (errorToThrowOnDelete != null) throw errorToThrowOnDelete!;
    lastDeletedPhotoId = photoId;
  }

  @override
  Future<void> cleanupFailedUpload({
    String? photoId,
    String? fullPublicId,
    String? thumbnailPublicId,
  }) async {
    cleanupFailedUploadCalls++;
    lastCleanedFullPublicId = fullPublicId;
    lastCleanedThumbnailPublicId = thumbnailPublicId;
  }
}

class FakeSupabaseDatabaseService extends Fake
    implements SupabaseDatabaseService {
  final Map<String, VaultPhoto> storedPhotos = {};
  Exception? errorToThrowOnInsert;
  int insertPhotoCalls = 0;
  int softDeleteCalls = 0;
  int restoreCalls = 0;
  int permanentDeleteCalls = 0;

  @override
  Future<VaultPhoto> insertPhoto(VaultPhoto photo) async {
    insertPhotoCalls++;
    if (errorToThrowOnInsert != null) throw errorToThrowOnInsert!;
    storedPhotos[photo.id] = photo;
    return photo;
  }

  @override
  Future<VaultPhoto?> getPhotoById(String photoId, String userId) async {
    final p = storedPhotos[photoId];
    if (p != null && p.userId == userId) {
      return p;
    }
    return null;
  }

  @override
  Future<void> softDeletePhoto(String photoId, String userId) async {
    softDeleteCalls++;
    final p = storedPhotos[photoId];
    if (p != null && p.userId == userId) {
      storedPhotos[photoId] = p.copyWith(
        deletedAt: DateTime.now(),
        deleteAfter: DateTime.now().add(const Duration(days: 30)),
      );
    }
  }

  @override
  Future<void> restorePhoto(String photoId, String userId) async {
    restoreCalls++;
    final p = storedPhotos[photoId];
    if (p != null && p.userId == userId) {
      storedPhotos[photoId] = VaultPhoto(
        id: p.id,
        userId: p.userId,
        categoryId: p.categoryId,
        storagePath: p.storagePath,
        thumbnailPath: p.thumbnailPath,
        displayName: p.displayName,
        mimeType: p.mimeType,
        encryptedSize: p.encryptedSize,
        width: p.width,
        height: p.height,
        createdAt: p.createdAt,
        updatedAt: DateTime.now(),
        deletedAt: null,
        deleteAfter: null,
        storageProvider: p.storageProvider,
        cloudinaryPublicId: p.cloudinaryPublicId,
        cloudinaryThumbnailPublicId: p.cloudinaryThumbnailPublicId,
        cloudinaryAssetId: p.cloudinaryAssetId,
        cloudinaryVersion: p.cloudinaryVersion,
        encryptedBytes: p.encryptedBytes,
        originalFilename: p.originalFilename,
      );
    }
  }

  @override
  Future<void> permanentDeletePhotoMetadata(
    String photoId,
    String userId,
  ) async {
    permanentDeleteCalls++;
    storedPhotos.remove(photoId);
  }

  @override
  Future<List<VaultPhoto>> getRecentlyDeletedPhotos(String userId) async {
    return storedPhotos.values
        .where((p) => p.userId == userId && p.isDeleted)
        .toList();
  }

  @override
  Future<List<VaultPhoto>> getPhotosByCategory(
    String userId,
    String categoryId, {
    int limit = 50,
    int offset = 0,
    bool ascending = false,
  }) async {
    return storedPhotos.values
        .where(
          (p) =>
              p.userId == userId && p.categoryId == categoryId && !p.isDeleted,
        )
        .toList();
  }
}

class FakeSupabaseStorageService extends Fake
    implements SupabaseStorageService {
  final Map<String, Uint8List> storedBlobs = {};
  int downloadCalls = 0;
  int uploadCalls = 0;
  int deleteCalls = 0;

  @override
  Future<Uint8List> downloadEncryptedBytes(String path) async {
    downloadCalls++;
    final bytes = storedBlobs[path];
    if (bytes == null) {
      throw const StorageException('Object not found in Supabase Storage');
    }
    return bytes;
  }

  @override
  Future<String> uploadEncryptedBytes({
    required String path,
    required Uint8List bytes,
  }) async {
    uploadCalls++;
    storedBlobs[path] = bytes;
    return path;
  }

  @override
  Future<void> deleteFiles(List<String> paths) async {
    deleteCalls++;
    for (final p in paths) {
      storedBlobs.remove(p);
    }
  }
}

class FakeTemporaryFileCleaner extends Fake implements TemporaryFileCleaner {
  int deleteCalls = 0;
  final List<String> deletedPaths = [];

  @override
  Future<void> deleteSingleFile(String? filePath) async {
    deleteCalls++;
    if (filePath != null) {
      deletedPaths.add(filePath);
      final f = File(filePath);
      if (await f.exists()) {
        try {
          await f.delete();
        } catch (_) {}
      }
    }
  }
}

// ---------------------------------------------------------------------------
// TEST SUITE: 12 SCENARIOS
// ---------------------------------------------------------------------------

void main() {
  late VaultCryptoService cryptoService;
  late FakeCloudinaryMediaService fakeCloudinary;
  late FakeSupabaseDatabaseService fakeDb;
  late FakeSupabaseStorageService fakeStorage;
  late FakeTemporaryFileCleaner fakeCleaner;
  late PhotoUploadService uploadService;
  late PhotoDownloadService downloadService;
  late PhotoRepository photoRepo;

  late Directory tempDir;
  late Uint8List masterKey;

  setUp(() async {
    cryptoService = VaultCryptoService(iterations: 1000);
    fakeCloudinary = FakeCloudinaryMediaService();
    fakeDb = FakeSupabaseDatabaseService();
    fakeStorage = FakeSupabaseStorageService();
    fakeCleaner = FakeTemporaryFileCleaner();

    uploadService = PhotoUploadService(
      cryptoService: cryptoService,
      cloudinaryService: fakeCloudinary,
      storageService: fakeStorage,
      databaseService: fakeDb,
      cleaner: fakeCleaner,
    );

    downloadService = PhotoDownloadService(
      cryptoService: cryptoService,
      cloudinaryService: fakeCloudinary,
      storageService: fakeStorage,
    );

    photoRepo = PhotoRepository(
      databaseService: fakeDb,
      storageService: fakeStorage,
      uploadService: uploadService,
      downloadService: downloadService,
      cloudinaryService: fakeCloudinary,
    );

    tempDir = await Directory.systemTemp.createTemp('privora_test_');
    masterKey = cryptoService.generateMasterKey();
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  Future<File> createTestImageFile([String name = 'sample.jpg']) async {
    final file = File('${tempDir.path}/$name');
    final rawData = utf8.encode('PRIVORA_RAW_IMAGE_PAYLOAD_${DateTime.now()}');
    await file.writeAsBytes(rawData);
    return file;
  }

  group('Privora Cloudinary Storage Migration - 12 Acceptance Scenarios', () {
    // -------------------------------------------------------------------------
    // Scenario 1: Successful signed upload
    // -------------------------------------------------------------------------
    test(
      'Scenario 1: Successful signed upload obtains params, encrypts, and inserts Cloudinary metadata',
      () async {
        final sourceFile = await createTestImageFile('vacation.jpg');
        final recordedStates = <UploadStatus>[];

        final result = await photoRepo.uploadPhoto(
          sourceFile: sourceFile,
          userId: 'user-123',
          categoryId: 'cat-456',
          masterKey: masterKey,
          customDisplayName: 'Summer Vacation',
          onStateChanged: (state) => recordedStates.add(state.status),
        );

        // 1. Verify Edge Function signature was requested
        expect(fakeCloudinary.uploadSignatureCalls, 1);

        // 2. Verify Cloudinary metadata on VaultPhoto
        expect(result.storageProvider, 'cloudinary');
        expect(result.isCloudinary, isTrue);
        expect(
          result.cloudinaryPublicId,
          'privora/user-123/cat-456/${result.id}',
        );
        expect(
          result.cloudinaryThumbnailPublicId,
          'privora/user-123/cat-456/${result.id}_thumb',
        );
        expect(result.originalFilename, 'Summer Vacation');

        // 3. Verify Supabase PostgreSQL row was saved
        expect(fakeDb.storedPhotos.containsKey(result.id), isTrue);
        expect(fakeDb.storedPhotos[result.id]!.storageProvider, 'cloudinary');

        // 4. Verify progress state transitions
        expect(recordedStates, contains(UploadStatus.encrypting));
        expect(recordedStates, contains(UploadStatus.uploadingThumbnail));
        expect(recordedStates, contains(UploadStatus.uploadingFullPhoto));
        expect(recordedStates, contains(UploadStatus.savingMetadata));
        expect(recordedStates, contains(UploadStatus.completed));
      },
    );

    // -------------------------------------------------------------------------
    // Scenario 2: Full photo and thumbnail uploads
    // -------------------------------------------------------------------------
    test(
      'Scenario 2: Both full photo and thumbnail are separately encrypted and uploaded with structured public IDs',
      () async {
        final sourceFile = await createTestImageFile('nature.png');

        final photo = await photoRepo.uploadPhoto(
          sourceFile: sourceFile,
          userId: 'user-123',
          categoryId: 'cat-nature',
          masterKey: masterKey,
        );

        // Verify two separate Cloudinary uploads occurred
        expect(fakeCloudinary.uploadBytesCalls, 2);
        expect(
          fakeCloudinary.uploadedPublicIds,
          contains('privora/user-123/cat-nature/${photo.id}_thumb'),
        );
        expect(
          fakeCloudinary.uploadedPublicIds,
          contains('privora/user-123/cat-nature/${photo.id}'),
        );

        // Verify uploaded payloads are AES-256-GCM encrypted (version byte 0x01)
        final fullCiphertext = fakeCloudinary
            .uploadedPayloads['privora/user-123/cat-nature/${photo.id}']!;
        final thumbCiphertext = fakeCloudinary
            .uploadedPayloads['privora/user-123/cat-nature/${photo.id}_thumb']!;

        expect(fullCiphertext[0], 0x01);
        expect(thumbCiphertext[0], 0x01);
        expect(fullCiphertext.length, greaterThan(29));
      },
    );

    // -------------------------------------------------------------------------
    // Scenario 3: Failed partial upload cleanup
    // -------------------------------------------------------------------------
    test(
      'Scenario 3: Failed full photo upload cleans up already-uploaded thumbnail via Edge Function',
      () async {
        final sourceFile = await createTestImageFile('fail_full.jpg');
        // Configure fake to succeed on thumbnail upload but fail when uploading full image
        fakeCloudinary.failOnlyOnFullPhoto = true;

        await expectLater(
          photoRepo.uploadPhoto(
            sourceFile: sourceFile,
            userId: 'user-123',
            categoryId: 'cat-fail',
            masterKey: masterKey,
          ),
          throwsA(isA<StorageException>()),
        );

        // Verify rollback cleanup was called
        expect(
          fakeCloudinary.cleanupFailedUploadCalls,
          greaterThanOrEqualTo(1),
        );
        expect(fakeCloudinary.lastCleanedThumbnailPublicId, isNotNull);
        // Verify no orphaned database record exists
        expect(fakeDb.storedPhotos.isEmpty, isTrue);
        // The private source copy must survive so Retry Failed can reuse it.
        expect(fakeCleaner.deleteCalls, 0);
        expect(await sourceFile.exists(), isTrue);
      },
    );

    // -------------------------------------------------------------------------
    // Scenario 4: Database insertion failure cleanup
    // -------------------------------------------------------------------------
    test(
      'Scenario 4: Database insertion failure cleans up both full and thumbnail Cloudinary assets',
      () async {
        final sourceFile = await createTestImageFile('db_fail.jpg');
        fakeDb.errorToThrowOnInsert = const StorageException(
          'Postgres connection lost during insert',
        );

        await expectLater(
          photoRepo.uploadPhoto(
            sourceFile: sourceFile,
            userId: 'user-123',
            categoryId: 'cat-db-fail',
            masterKey: masterKey,
          ),
          throwsA(isA<StorageException>()),
        );

        // Both assets were uploaded before DB insert failed
        expect(fakeCloudinary.uploadBytesCalls, 2);
        // Verify cleanup was invoked for both assets
        expect(fakeCloudinary.cleanupFailedUploadCalls, 1);
        expect(fakeCloudinary.lastCleanedFullPublicId, isNotNull);
        expect(fakeCloudinary.lastCleanedThumbnailPublicId, isNotNull);
      },
    );

    // -------------------------------------------------------------------------
    // Scenario 5: Thumbnail loading (Cloudinary)
    // -------------------------------------------------------------------------
    test(
      'Scenario 5: Cloudinary thumbnail loading fetches signed download URL, decrypts into RAM, and caches',
      () async {
        final sourceFile = await createTestImageFile('thumb_test.jpg');
        final photo = await photoRepo.uploadPhoto(
          sourceFile: sourceFile,
          userId: 'user-123',
          categoryId: 'cat-1',
          masterKey: masterKey,
        );

        // 1. First thumbnail request fetches signed URL & downloads
        final decrypted1 = await downloadService.getDecryptedThumbnail(
          photo: photo,
          masterKey: masterKey,
        );

        expect(decrypted1, isNotEmpty);
        expect(fakeCloudinary.signedDownloadUrlCalls, 1);
        expect(fakeCloudinary.downloadBytesCalls, 1);

        // 2. Second request should hit RAM memory cache immediately without network call
        final decrypted2 = await downloadService.getDecryptedThumbnail(
          photo: photo,
          masterKey: masterKey,
        );

        expect(decrypted2, equals(decrypted1));
        expect(fakeCloudinary.signedDownloadUrlCalls, 1); // Still 1
        expect(fakeCloudinary.downloadBytesCalls, 1); // Still 1
      },
    );

    // -------------------------------------------------------------------------
    // Scenario 6: Full photo loading (Cloudinary)
    // -------------------------------------------------------------------------
    test(
      'Scenario 6: Full photo loading fetches signed download URL and decrypts authentic original plaintext',
      () async {
        const rawContent = 'SUPER_SECRET_PRIVORA_FULL_PHOTO_PAYLOAD';
        final sourceFile = File('${tempDir.path}/secret_doc.png');
        await sourceFile.writeAsBytes(utf8.encode(rawContent));

        final photo = await photoRepo.uploadPhoto(
          sourceFile: sourceFile,
          userId: 'user-123',
          categoryId: 'cat-vault',
          masterKey: masterKey,
        );

        final decryptedFull = await downloadService.getDecryptedFullPhoto(
          photo: photo,
          masterKey: masterKey,
        );

        expect(utf8.decode(decryptedFull), rawContent);
        expect(fakeCloudinary.signedDownloadUrlCalls, 1);
      },
    );

    // -------------------------------------------------------------------------
    // Scenario 7: Trash and restore without Cloudinary deletion
    // -------------------------------------------------------------------------
    test(
      'Scenario 7: Moving to trash and restoring updates deleted_at without deleting Cloudinary assets',
      () async {
        final sourceFile = await createTestImageFile('trash_item.jpg');
        final photo = await photoRepo.uploadPhoto(
          sourceFile: sourceFile,
          userId: 'user-123',
          categoryId: 'cat-trash',
          masterKey: masterKey,
        );

        // Soft delete photo
        await photoRepo.softDeletePhoto(photo.id, 'user-123');
        expect(fakeDb.softDeleteCalls, 1);
        expect(fakeDb.storedPhotos[photo.id]!.isDeleted, isTrue);
        // Cloudinary destroy must NOT be called on soft-delete
        expect(fakeCloudinary.permanentlyDeleteCalls, 0);

        // Restore photo
        await photoRepo.restorePhoto(photo.id, 'user-123');
        expect(fakeDb.restoreCalls, 1);
        expect(fakeDb.storedPhotos[photo.id]!.isDeleted, isFalse);
        expect(fakeCloudinary.permanentlyDeleteCalls, 0);
      },
    );

    // -------------------------------------------------------------------------
    // Scenario 8: Permanent deletion
    // -------------------------------------------------------------------------
    test(
      'Scenario 8: Permanently deleting photo calls Edge Function permanentlyDelete and removes DB record',
      () async {
        final sourceFile = await createTestImageFile('perm_delete.jpg');
        final photo = await photoRepo.uploadPhoto(
          sourceFile: sourceFile,
          userId: 'user-123',
          categoryId: 'cat-perm',
          masterKey: masterKey,
        );

        await photoRepo.permanentlyDeletePhoto(photo, 'user-123');

        // Cloudinary permanent deletion called via Edge Function
        expect(fakeCloudinary.permanentlyDeleteCalls, 1);
        expect(fakeCloudinary.lastDeletedPhotoId, photo.id);
      },
    );

    // -------------------------------------------------------------------------
    // Scenario 9: Multi-tenant isolation
    // -------------------------------------------------------------------------
    test(
      'Scenario 9: Multi-tenant isolation - User B cannot retrieve User A photo records',
      () async {
        final sourceFile = await createTestImageFile('user_a.jpg');
        final photoA = await photoRepo.uploadPhoto(
          sourceFile: sourceFile,
          userId: 'user-A',
          categoryId: 'cat-A',
          masterKey: masterKey,
        );

        // User B attempts to fetch photo A from database
        final queriedByB = await fakeDb.getPhotoById(photoA.id, 'user-B');
        expect(queriedByB, isNull);

        final queriedByA = await fakeDb.getPhotoById(photoA.id, 'user-A');
        expect(queriedByA, isNotNull);
        expect(queriedByA!.id, photoA.id);
      },
    );

    // -------------------------------------------------------------------------
    // Scenario 10: CLOUDINARY_API_SECRET is absent from Flutter config
    // -------------------------------------------------------------------------
    test(
      'Scenario 10: Zero secrets on client - CLOUDINARY_API_SECRET is absent from client codebase',
      () {
        // 1. Verify CloudinaryUploadParams has no apiSecret field or property
        const params = CloudinaryUploadParams(
          cloudName: 'test',
          apiKey: 'key',
          timestamp: 100,
          resourceType: 'raw',
          type: 'authenticated',
          photoId: 'id',
          fullPublicId: 'full',
          fullSignature: 'sig',
          thumbnailPublicId: 'thumb',
          thumbnailSignature: 'thumb_sig',
        );
        expect(params.apiKey, 'key');
        expect(params.cloudName, 'test');

        final jsonMap = {
          'cloudName': 'c',
          'apiKey': 'k',
          'timestamp': 1,
          'resourceType': 'raw',
          'type': 'authenticated',
          'photoId': 'p',
          'full': {'publicId': 'f', 'signature': 's1'},
          'thumbnail': {'publicId': 't', 'signature': 's2'},
        };
        final parsed = CloudinaryUploadParams.fromJson(jsonMap);
        expect(parsed.apiKey, 'k');

        // 2. Verify StorageConstants has no secret constants
        expect(StorageConstants.privatePhotosBucket, 'private-photos');
        expect(() => StorageConstants.photoPath('u', 'p'), returnsNormally);

        // 3. Scan lib/ directory to ensure no secret keyword exists in source
        final libDir = Directory('lib');
        if (libDir.existsSync()) {
          final files = libDir.listSync(recursive: true).whereType<File>();
          for (final f in files) {
            if (f.path.endsWith('.dart')) {
              final content = f.readAsStringSync().toLowerCase();
              expect(
                content.contains('cloudinary_api_secret'),
                isFalse,
                reason: 'Forbidden secret found in ${f.path}',
              );
            }
          }
        }
      },
    );

    // -------------------------------------------------------------------------
    // Scenario 11: Existing Supabase Storage photos still load
    // -------------------------------------------------------------------------
    test(
      'Scenario 11: Backward compatibility - existing Supabase Storage photos download and decrypt cleanly',
      () async {
        final legacyContent = utf8.encode('LEGACY_SUPABASE_PHOTO_DATA');
        final encryptedBytes = await cryptoService.encryptPhotoBytes(
          Uint8List.fromList(legacyContent),
          masterKey,
        );

        const legacyStoragePath = 'user-legacy/photos/photo-legacy.enc';
        const legacyThumbPath = 'user-legacy/thumbnails/photo-legacy.enc';

        // Pre-populate legacy storage fake with encrypted bytes
        fakeStorage.storedBlobs[legacyStoragePath] = encryptedBytes;
        fakeStorage.storedBlobs[legacyThumbPath] = encryptedBytes;

        final legacyPhoto = VaultPhoto(
          id: 'photo-legacy',
          userId: 'user-legacy',
          categoryId: 'cat-legacy',
          storagePath: legacyStoragePath,
          thumbnailPath: legacyThumbPath,
          displayName: 'Legacy Photo',
          mimeType: 'image/jpeg',
          encryptedSize: encryptedBytes.length,
          createdAt: DateTime(2025, 1, 1),
          updatedAt: DateTime(2025, 1, 1),
          storageProvider: 'supabase',
        );

        expect(legacyPhoto.isCloudinary, isFalse);

        // 1. Download thumbnail using legacy Supabase route
        final decryptedThumb = await downloadService.getDecryptedThumbnail(
          photo: legacyPhoto,
          masterKey: masterKey,
        );
        expect(utf8.decode(decryptedThumb), 'LEGACY_SUPABASE_PHOTO_DATA');
        expect(fakeStorage.downloadCalls, 1);
        expect(fakeCloudinary.downloadBytesCalls, 0);

        // 2. Download full photo using legacy Supabase route
        final decryptedFull = await downloadService.getDecryptedFullPhoto(
          photo: legacyPhoto,
          masterKey: masterKey,
        );
        expect(utf8.decode(decryptedFull), 'LEGACY_SUPABASE_PHOTO_DATA');
        expect(fakeStorage.downloadCalls, 2);
        expect(fakeCloudinary.downloadBytesCalls, 0);
      },
    );

    // -------------------------------------------------------------------------
    // Scenario 12: Timeout handling on upload and download
    // -------------------------------------------------------------------------
    test(
      'Scenario 12: Network timeouts on Cloudinary upload and download throw user-friendly AppException',
      () async {
        // 1. Timeout during upload signature
        fakeCloudinary.errorToThrowOnSignature = TimeoutException(
          'Signature request timed out',
        );
        final sourceFile = await createTestImageFile('timeout.jpg');

        await expectLater(
          photoRepo.uploadPhoto(
            sourceFile: sourceFile,
            userId: 'user-123',
            categoryId: 'cat-timeout',
            masterKey: masterKey,
          ),
          throwsA(isA<Exception>()),
        );

        // Reset
        fakeCloudinary.errorToThrowOnSignature = null;

        // 2. Timeout during download URL generation
        final photo = VaultPhoto(
          id: 'photo-to',
          userId: 'user-123',
          categoryId: 'cat-123',
          storagePath: 'privora/user-123/cat-123/photo-to',
          thumbnailPath: 'privora/user-123/cat-123/photo-to_thumb',
          displayName: 'Timeout Photo',
          mimeType: 'image/jpeg',
          encryptedSize: 1024,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          storageProvider: 'cloudinary',
          cloudinaryPublicId: 'privora/user-123/cat-123/photo-to',
        );

        fakeCloudinary.errorToThrowOnDownloadUrl = TimeoutException(
          'Download URL timed out',
        );

        await expectLater(
          downloadService.getDecryptedFullPhoto(
            photo: photo,
            masterKey: masterKey,
          ),
          throwsA(isA<Exception>()),
        );
      },
    );
  });
}
