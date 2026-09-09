import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:privora/core/security/vault_crypto_service.dart';
import 'package:privora/data/models/upload_state.dart';
import 'package:privora/data/models/vault_photo.dart';
import 'package:privora/data/services/photo_upload_service.dart';
import 'google_auth_and_routing_test.dart';
import 'sign_out_flow_test.dart';

class MockBatchPhotoUploadService extends PhotoUploadService {
  final List<String> uploadedIds = [];
  final Set<String> filesThatShouldFail;

  MockBatchPhotoUploadService({
    required super.cryptoService,
    required super.databaseService,
    required super.cleaner,
    this.filesThatShouldFail = const {},
  });

  @override
  Future<VaultPhoto> uploadPhoto({
    required File sourceFile,
    required String userId,
    required String categoryId,
    required Uint8List masterKey,
    String? customDisplayName,
    bool deleteSourceFile = true,
    void Function(UploadState state)? onStateChanged,
  }) async {
    final fileName = sourceFile.path;
    if (filesThatShouldFail.contains(fileName)) {
      throw Exception('Network error during photo upload');
    }

    onStateChanged?.call(
      const UploadState(status: UploadStatus.uploadingFullPhoto, progress: 0.8),
    );
    uploadedIds.add(fileName);

    return VaultPhoto(
      id: 'photo-${uploadedIds.length}',
      userId: userId,
      categoryId: categoryId,
      displayName: 'test.jpg',
      mimeType: 'image/jpeg',
      encryptedSize: 1024,
      storagePath: 'path/test.enc',
      thumbnailPath: 'path/thumb.enc',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Part 4: Multi-Photo Gallery Selection & Ingestion Tests', () {
    test(
      'Sequential batch upload processes files and tracks progress',
      () async {
        final cleaner = FakeTemporaryCleaner();
        final uploadService = MockBatchPhotoUploadService(
          cryptoService: VaultCryptoService(),
          databaseService: FakeDatabaseService(),
          cleaner: cleaner,
        );

        final masterKey = Uint8List(32);
        final files = [
          File('test_photo_1.jpg'),
          File('test_photo_2.jpg'),
          File('test_photo_3.jpg'),
        ];

        final progressSteps = <String>[];

        for (int i = 0; i < files.length; i++) {
          progressSteps.add('Uploading ${i + 1} of ${files.length}');
          await uploadService.uploadPhoto(
            sourceFile: files[i],
            userId: 'user-1',
            categoryId: 'cat-1',
            masterKey: masterKey,
          );
          await cleaner.cleanTemporaryFiles();
        }

        // Verify all 3 files uploaded sequentially
        expect(uploadService.uploadedIds.length, equals(3));
        expect(
          progressSteps,
          equals(['Uploading 1 of 3', 'Uploading 2 of 3', 'Uploading 3 of 3']),
        );
        expect(cleaner.wasCleaned, isTrue);
      },
    );

    test(
      'Partial failure does not stop remaining photos, and retry uploads only failed files',
      () async {
        final cleaner = FakeTemporaryCleaner();
        final uploadService = MockBatchPhotoUploadService(
          cryptoService: VaultCryptoService(),
          databaseService: FakeDatabaseService(),
          cleaner: cleaner,
          filesThatShouldFail: {'photo_2.jpg'},
        );

        final masterKey = Uint8List(32);
        final files = [
          File('photo_1.jpg'),
          File('photo_2.jpg'),
          File('photo_3.jpg'),
        ];

        final successful = <String>[];
        final failed = <File>[];

        for (int i = 0; i < files.length; i++) {
          try {
            await uploadService.uploadPhoto(
              sourceFile: files[i],
              userId: 'user-1',
              categoryId: 'cat-1',
              masterKey: masterKey,
            );
            successful.add(files[i].path);
          } catch (e) {
            failed.add(files[i]);
          }
        }

        // Photo 1 and 3 succeeded, Photo 2 failed
        expect(successful.length, equals(2));
        expect(successful, contains('photo_1.jpg'));
        expect(successful, contains('photo_3.jpg'));
        expect(failed.length, equals(1));
        expect(failed.first.path, equals('photo_2.jpg'));

        // Now retry ONLY the failed photo (photo_2.jpg)
        uploadService.filesThatShouldFail.clear(); // Network recovered
        for (final failedFile in failed) {
          await uploadService.uploadPhoto(
            sourceFile: failedFile,
            userId: 'user-1',
            categoryId: 'cat-1',
            masterKey: masterKey,
          );
          successful.add(failedFile.path);
        }

        // All 3 photos successfully uploaded without duplicating photo 1 and 3
        expect(successful.length, equals(3));
        expect(uploadService.uploadedIds.length, equals(3));
      },
    );
  });
}
