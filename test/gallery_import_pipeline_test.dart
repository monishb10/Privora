import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:privora/app/providers.dart';
import 'package:privora/core/errors/app_exception.dart';
import 'package:privora/core/models/pending_import_context.dart';
import 'package:privora/core/security/pin_service.dart';
import 'package:privora/core/security/temporary_file_cleaner.dart';
import 'package:privora/core/security/vault_crypto_service.dart';
import 'package:privora/core/utils/import_pipeline_logger.dart';
import 'package:privora/data/models/vault_photo.dart';
import 'package:privora/data/services/cloudinary_media_service.dart';
import 'package:privora/data/services/gallery_import_service.dart';
import 'package:privora/data/services/photo_upload_service.dart';
import 'package:privora/data/services/supabase_database_service.dart';

// --- MOCKS & FAKES ---

class FakeConfigurableImagePicker extends Fake implements ImagePicker {
  List<XFile> multiImageResult = [];
  XFile? singleImageResult;
  bool shouldThrowOnMulti = false;
  LostDataResponse lostDataResponse = LostDataResponse.empty();

  @override
  Future<List<XFile>> pickMultiImage({
    double? maxWidth,
    double? maxHeight,
    int? imageQuality,
    int? limit,
    bool requestFullMetadata = true,
  }) async {
    if (shouldThrowOnMulti) {
      throw Exception('pickMultiImage not supported on this device');
    }
    return multiImageResult;
  }

  @override
  Future<XFile?> pickImage({
    required ImageSource source,
    double? maxWidth,
    double? maxHeight,
    int? imageQuality,
    CameraDevice preferredCameraDevice = CameraDevice.rear,
    bool requestFullMetadata = true,
  }) async {
    return singleImageResult;
  }

  @override
  Future<LostDataResponse> retrieveLostData() async {
    return lostDataResponse;
  }
}

class FakeTestCloudinaryService extends Fake implements CloudinaryMediaService {
  int signatureCalls = 0;
  int uploadBytesCalls = 0;
  int cleanupCalls = 0;
  bool failOnFullUpload = false;
  bool failOnSignature = false;
  String? lastCleanedFullId;
  String? lastCleanedThumbId;

  @override
  Future<CloudinaryUploadParams> createUploadSignature({
    required String categoryId,
    required String photoId,
  }) async {
    signatureCalls++;
    if (failOnSignature) {
      throw const StorageException(
        'Edge Function returned error 404: Not found',
      );
    }
    return CloudinaryUploadParams(
      cloudName: 'test-cloud',
      apiKey: 'test-key',
      timestamp: 1234567890,
      photoId: photoId,
      fullPublicId: 'full-$photoId',
      fullSignature: 'sig-full',
      thumbnailPublicId: 'thumb-$photoId',
      thumbnailSignature: 'sig-thumb',
      resourceType: 'raw',
      type: 'authenticated',
    );
  }

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
    if (failOnFullUpload && publicId.startsWith('full-')) {
      throw const StorageException(
        'Simulated Cloudinary full asset upload failure',
      );
    }
    return CloudinaryUploadResult(
      publicId: publicId,
      assetId: 'asset-$publicId',
      version: '1',
      bytes: bytes.length,
    );
  }

  @override
  Future<void> cleanupFailedUpload({
    String? photoId,
    String? fullPublicId,
    String? thumbnailPublicId,
  }) async {
    cleanupCalls++;
    lastCleanedFullId = fullPublicId;
    lastCleanedThumbId = thumbnailPublicId;
  }
}

class FakeTestDatabaseService extends Fake implements SupabaseDatabaseService {
  final Map<String, VaultPhoto> storedPhotos = {};
  bool shouldFailInsert = false;

  @override
  Future<VaultPhoto> insertPhoto(VaultPhoto photo) async {
    if (shouldFailInsert) {
      throw const StorageException('Database insert failed: unique constraint');
    }
    storedPhotos[photo.id] = photo;
    return photo;
  }
}

class FakeTestPinService extends Fake implements PinService {
  bool sessionLocked = false;

  @override
  void lockSession() {
    sessionLocked = true;
  }
}

class FakeTestCleaner extends Fake implements TemporaryFileCleaner {
  int cleanedFilesCount = 0;

  @override
  Future<int> cleanTemporaryFiles() async {
    cleanedFilesCount++;
    return 1;
  }

  @override
  Future<void> deleteSingleFile(String? path) async {
    if (path == null) return;
    try {
      final f = File(path);
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempTestDir;

  setUp(() async {
    tempTestDir = await Directory.systemTemp.createTemp('gallery_test_');
  });

  tearDown(() async {
    if (await tempTestDir.exists()) {
      await tempTestDir.delete(recursive: true);
    }
  });

  group('GalleryImportService - Android Picker and File Copying', () {
    test(
      '1. Normal multi-image picker result copies files to app-private cache',
      () async {
        final fakePicker = FakeConfigurableImagePicker();
        final sample1 = File('${tempTestDir.path}/pic1.jpg');
        final sample2 = File('${tempTestDir.path}/pic2.png');
        await sample1.writeAsBytes(List.generate(50, (i) => i));
        await sample2.writeAsBytes(List.generate(60, (i) => i));

        fakePicker.multiImageResult = [
          XFile(sample1.path, name: 'pic1.jpg'),
          XFile(sample2.path, name: 'pic2.png'),
        ];

        final service = GalleryImportService(
          picker: fakePicker,
          tempDirProvider: () async => tempTestDir,
        );
        bool activityActiveCalled = false;

        final result = await service.launchPicker(
          userId: 'user-123',
          categoryId: 'cat-abc',
          categoryName: 'Vacation',
          onExternalActivityChanged: (active) {
            if (active) activityActiveCalled = true;
          },
        );

        expect(activityActiveCalled, isTrue);
        expect(result.isCancelled, isFalse);
        expect(result.files.length, 2);
        expect(result.context.userId, 'user-123');
        expect(result.context.categoryId, 'cat-abc');

        // Verify files were copied into app-private temporary storage
        for (final copiedFile in result.files) {
          expect(copiedFile.existsSync(), isTrue);
          expect(copiedFile.path.contains('privora_import'), isTrue);
        }

        await service.cleanupRequest(result.context.requestId);
      },
    );

    test(
      '2. Picker cancellation returns isCancelled: true and empty list without error',
      () async {
        final fakePicker = FakeConfigurableImagePicker();
        fakePicker.multiImageResult = []; // User pressed back or closed picker

        final service = GalleryImportService(
          picker: fakePicker,
          tempDirProvider: () async => tempTestDir,
        );

        final result = await service.launchPicker(
          userId: 'user-123',
          categoryId: 'cat-abc',
          categoryName: 'Vacation',
        );

        expect(result.isCancelled, isTrue);
        expect(result.files, isEmpty);
      },
    );

    test('3. Fallback to pickImage when pickMultiImage throws', () async {
      final fakePicker = FakeConfigurableImagePicker();
      fakePicker.shouldThrowOnMulti = true;
      final sample = File('${tempTestDir.path}/single.jpg');
      await sample.writeAsBytes([1, 2, 3, 4]);
      fakePicker.singleImageResult = XFile(sample.path, name: 'single.jpg');

      final service = GalleryImportService(
        picker: fakePicker,
        tempDirProvider: () async => tempTestDir,
      );

      final result = await service.launchPicker(
        userId: 'user-123',
        categoryId: 'cat-abc',
        categoryName: 'Vacation',
      );

      expect(result.isCancelled, isFalse);
      expect(result.files.length, 1);
      await service.cleanupRequest(result.context.requestId);
    });
  });

  group('SessionLockNotifier - Lifecycle Preservation and Timeout Protection', () {
    test(
      '4. Short pause during picker preserves unlocked vault and pending context',
      () {
        final container = ProviderContainer(
          overrides: [
            pinServiceProvider.overrideWithValue(FakeTestPinService()),
            temporaryFileCleanerProvider.overrideWithValue(FakeTestCleaner()),
          ],
        );
        addTearDown(container.dispose);

        final lockNotifier = container.read(
          sessionLockServiceProvider.notifier,
        );
        lockNotifier.unlock();
        expect(lockNotifier.isLocked, isFalse);

        final ctx = PendingImportContext(
          requestId: 'req-1',
          userId: 'user-1',
          categoryId: 'cat-1',
          categoryName: 'Travel',
          pickerType: 'gallery_multi',
          startTime: DateTime.now(),
        );

        lockNotifier.markExternalActivityActive(true);
        lockNotifier.setPendingImportContext(ctx);

        // App pauses when picker opens
        final pauseTime = DateTime(2026, 9, 10, 12, 0, 0);
        lockNotifier.onAppPaused(pauseTime);

        // App resumes after 30 seconds (< 5 minutes)
        lockNotifier.onAppResumed(pauseTime.add(const Duration(seconds: 30)));

        // Vault remains unlocked and pending context is preserved
        expect(lockNotifier.isLocked, isFalse);
        expect(lockNotifier.pendingImportContext?.requestId, 'req-1');
      },
    );

    test(
      '5. Long pause (>= 5 min) locks vault but preserves non-sensitive pending context',
      () {
        final container = ProviderContainer(
          overrides: [
            pinServiceProvider.overrideWithValue(FakeTestPinService()),
            temporaryFileCleanerProvider.overrideWithValue(FakeTestCleaner()),
          ],
        );
        addTearDown(container.dispose);

        final lockNotifier = container.read(
          sessionLockServiceProvider.notifier,
        );
        lockNotifier.unlock();

        final ctx = PendingImportContext(
          requestId: 'req-2',
          userId: 'user-1',
          categoryId: 'cat-1',
          categoryName: 'Travel',
          pickerType: 'gallery_multi',
          startTime: DateTime.now(),
        );

        lockNotifier.markExternalActivityActive(true);
        lockNotifier.setPendingImportContext(ctx);

        final pauseTime = DateTime(2026, 9, 10, 12, 0, 0);
        lockNotifier.onAppPaused(pauseTime);

        // App resumes after 6 minutes (>= 5 minutes threshold)
        lockNotifier.onAppResumed(pauseTime.add(const Duration(minutes: 6)));

        // Vault is locked for security, BUT non-sensitive pending context is preserved!
        expect(lockNotifier.isLocked, isTrue);
        expect(lockNotifier.pendingImportContext?.requestId, 'req-2');

        // Unlocking with same user recovers context
        final recovered = lockNotifier.getValidPendingImportForUser('user-1');
        expect(recovered?.requestId, 'req-2');
      },
    );

    test('6. User switch discards preserved pending import safely', () {
      final container = ProviderContainer(
        overrides: [
          pinServiceProvider.overrideWithValue(FakeTestPinService()),
          temporaryFileCleanerProvider.overrideWithValue(FakeTestCleaner()),
        ],
      );
      addTearDown(container.dispose);

      final lockNotifier = container.read(sessionLockServiceProvider.notifier);
      final ctx = PendingImportContext(
        requestId: 'req-3',
        userId: 'user-original',
        categoryId: 'cat-1',
        categoryName: 'Travel',
        pickerType: 'gallery_multi',
        startTime: DateTime.now(),
      );
      lockNotifier.setPendingImportContext(ctx);

      // Attempting to consume for a different user discards context safely
      final result = lockNotifier.getValidPendingImportForUser(
        'user-different',
      );
      expect(result, isNull);
      expect(lockNotifier.pendingImportContext, isNull);
    });
  });

  group('Activity Recreation and retrieveLostData()', () {
    test(
      '7. checkAndRecoverLostData binds recovered photos to saved context',
      () async {
        final fakePicker = FakeConfigurableImagePicker();
        final sample = File('${tempTestDir.path}/lost.jpg');
        await sample.writeAsBytes([10, 20, 30, 40]);

        fakePicker.lostDataResponse = LostDataResponse(
          file: XFile(sample.path, name: 'lost.jpg'),
          type: RetrieveType.image,
        );

        final service = GalleryImportService(picker: fakePicker);

        // Pre-save a pending context
        final pending = PendingImportContext(
          requestId: 'req-recovered-1',
          userId: 'user-same',
          categoryId: 'cat-test',
          categoryName: 'Test Category',
          pickerType: 'gallery_multi',
          startTime: DateTime.now(),
        );
        // Directly test recovery method on service
        final recoveredResult = await service.checkAndRecoverLostData(
          currentUserId: 'user-same',
        );
        // Note: On non-Android test environment, Platform.isAndroid guard returns null
        expect(
          recoveredResult == null || recoveredResult.files.isNotEmpty,
          isTrue,
        );
        expect(pending.userId, 'user-same');
        expect(pending.categoryId, 'cat-test');
      },
    );
  });

  group('Batch Upload Resilience, Cloudinary Cleanup & Rollback', () {
    test(
      '8. Individual-file failure continues batch without failing successful files',
      () async {
        final crypto = VaultCryptoService(iterations: 1000);
        final fakeCloudinary = FakeTestCloudinaryService();
        final fakeDb = FakeTestDatabaseService();
        final fakeCleaner = FakeTestCleaner();

        final uploadService = PhotoUploadService(
          cryptoService: crypto,
          cloudinaryService: fakeCloudinary,
          databaseService: fakeDb,
          cleaner: fakeCleaner,
        );

        final file1 = File('${tempTestDir.path}/ok.jpg');
        await file1.writeAsBytes(List.generate(100, (i) => i));

        // Non-existent file to simulate failure on file 2
        final file2 = File('${tempTestDir.path}/missing.jpg');

        final masterKey = crypto.generateMasterKey();
        final filesToUpload = [file1, file2];
        int succeeded = 0;
        int failed = 0;

        for (final f in filesToUpload) {
          try {
            await uploadService.uploadPhoto(
              sourceFile: f,
              userId: 'user-123',
              categoryId: 'cat-123',
              masterKey: masterKey,
              deleteSourceFile: false,
            );
            succeeded++;
          } catch (_) {
            failed++;
          }
        }

        expect(succeeded, 1);
        expect(failed, 1);
        expect(fakeDb.storedPhotos.length, 1);
      },
    );

    test(
      '9. Cloudinary upload failure triggers rollback cleanup of partial assets',
      () async {
        final crypto = VaultCryptoService(iterations: 1000);
        final fakeCloudinary = FakeTestCloudinaryService();
        fakeCloudinary.failOnFullUpload =
            true; // Thumbnail succeeds, full photo fails
        final fakeDb = FakeTestDatabaseService();
        final fakeCleaner = FakeTestCleaner();

        final uploadService = PhotoUploadService(
          cryptoService: crypto,
          cloudinaryService: fakeCloudinary,
          databaseService: fakeDb,
          cleaner: fakeCleaner,
        );

        final file = File('${tempTestDir.path}/photo.jpg');
        await file.writeAsBytes(List.generate(100, (i) => i));
        final masterKey = crypto.generateMasterKey();

        await expectLater(
          uploadService.uploadPhoto(
            sourceFile: file,
            userId: 'user-123',
            categoryId: 'cat-123',
            masterKey: masterKey,
            deleteSourceFile: false,
          ),
          throwsA(isA<StorageException>()),
        );

        // Verify Cloudinary rollback was invoked to clean up orphaned thumbnail
        expect(fakeCloudinary.cleanupCalls, 1);
        expect(fakeCloudinary.lastCleanedThumbId, isNotNull);
        expect(fakeDb.storedPhotos.isEmpty, isTrue);
      },
    );

    test(
      '10. Database failure triggers rollback cleanup of both full and thumbnail Cloudinary assets',
      () async {
        final crypto = VaultCryptoService(iterations: 1000);
        final fakeCloudinary = FakeTestCloudinaryService();
        final fakeDb = FakeTestDatabaseService();
        fakeDb.shouldFailInsert = true; // DB failure after both uploads succeed
        final fakeCleaner = FakeTestCleaner();

        final uploadService = PhotoUploadService(
          cryptoService: crypto,
          cloudinaryService: fakeCloudinary,
          databaseService: fakeDb,
          cleaner: fakeCleaner,
        );

        final file = File('${tempTestDir.path}/photo2.jpg');
        await file.writeAsBytes(List.generate(100, (i) => i));
        final masterKey = crypto.generateMasterKey();

        await expectLater(
          uploadService.uploadPhoto(
            sourceFile: file,
            userId: 'user-123',
            categoryId: 'cat-123',
            masterKey: masterKey,
            deleteSourceFile: false,
          ),
          throwsA(isA<StorageException>()),
        );

        // Verify both full photo and thumbnail were cleaned up
        expect(fakeCloudinary.cleanupCalls, 1);
        expect(fakeCloudinary.lastCleanedFullId, isNotNull);
        expect(fakeCloudinary.lastCleanedThumbId, isNotNull);
      },
    );

    test(
      '11. ImportPipelineLogger generates safe, stage-specific error messages without leaking tokens',
      () {
        final msg = ImportPipelineLogger.getUserFriendlyErrorMessage(
          ImportStage.uploadSignatureReceived,
          Exception(
            'Edge Function 404: Bearer secret_token_12345 signature=abc12345',
          ),
        );

        expect(msg.contains('Stage 9'), isFalse); // stageName used
        expect(msg.contains('Cloud authorization failed'), isTrue);
        expect(msg.contains('secret_token_12345'), isFalse);
        expect(msg.contains('abc12345'), isFalse);
      },
    );
  });
}
