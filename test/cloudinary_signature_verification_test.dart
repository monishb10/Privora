import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:privora/core/errors/app_exception.dart';
import 'package:privora/core/security/temporary_file_cleaner.dart';
import 'package:privora/core/security/vault_crypto_service.dart';
import 'package:privora/data/models/vault_photo.dart';
import 'package:privora/data/services/cloudinary_media_service.dart';
import 'package:privora/data/services/photo_upload_service.dart';
import 'package:privora/data/services/supabase_database_service.dart';

/// Helper matching Cloudinary canonical signature generation:
/// Alphabetical sorting of parameters, serialized as `k1=v1&k2=v2...<api_secret>`, lowercase SHA-1 hex.
Future<String> calculateCanonicalSignature(
  Map<String, String> params,
  String apiSecret,
) async {
  final sortedKeys = params.keys.toList()..sort();
  final toSign = sortedKeys.map((k) => '$k=${params[k]}').join('&') + apiSecret;
  final sha1 = Sha1();
  final hash = await sha1.hash(utf8.encode(toSign));
  return hash.bytes
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join('')
      .toLowerCase();
}

/// Fake HTTP client capturing multipart upload requests and returning mock responses
class MockCloudinaryHttpClient extends http.BaseClient {
  http.Request? capturedRequest;
  http.MultipartRequest? capturedMultipartRequest;
  Map<String, String> capturedFields = {};
  List<http.MultipartFile> capturedFiles = [];
  Uri? capturedUri;

  int responseStatusCode = 200;
  String responseBody = jsonEncode({
    'public_id': 'test-pub-id',
    'asset_id': 'test-asset-id',
    'resource_type': 'raw',
    'type': 'authenticated',
    'version': 1,
    'bytes': 1024,
  });
  Map<String, String> responseHeaders = {'content-type': 'application/json'};

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    capturedUri = request.url;
    if (request is http.MultipartRequest) {
      capturedMultipartRequest = request;
      capturedFields = Map<String, String>.from(request.fields);
      capturedFiles = List<http.MultipartFile>.from(request.files);
    }

    final stream = Stream.value(utf8.encode(responseBody));
    return http.StreamedResponse(
      stream,
      responseStatusCode,
      headers: responseHeaders,
    );
  }
}

/// Fake Database Service for rollback tests
class FakeDbForRollback extends Fake implements SupabaseDatabaseService {
  @override
  Future<VaultPhoto> insertPhoto(VaultPhoto photo) async => photo;

  @override
  Future<VaultPhoto?> getPhotoById(String photoId, String userId) async => null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Cloudinary Signature Verification & REST Upload Specification', () {
    const apiSecret = 'test_secret_abc123';
    const apiKey = 'test_key_xyz789';
    const cloudName = 'test_cloud';
    const uploadPreset = 'privora_signed';

    test('Upload timeout scales safely for mobile connections', () {
      expect(
        CloudinaryMediaService.uploadTimeoutForByteLength(0),
        CloudinaryMediaService.minimumUploadTimeout,
      );
      expect(
        CloudinaryMediaService.uploadTimeoutForByteLength(5 * 1024 * 1024),
        CloudinaryMediaService.minimumUploadTimeout,
      );
      expect(
        CloudinaryMediaService.uploadTimeoutForByteLength(50 * 1024 * 1024),
        const Duration(seconds: 860),
      );
      expect(
        CloudinaryMediaService.uploadTimeoutForByteLength(1024 * 1024 * 1024),
        CloudinaryMediaService.maximumUploadTimeout,
      );
    });

    // -------------------------------------------------------------------------
    // 1. Full and thumbnail signatures are independent
    // -------------------------------------------------------------------------
    test('1. Full and thumbnail signatures are strictly independent', () async {
      final timestamp = '1770000000';
      final photoId = '550e8400-e29b-41d4-a716-446655440000';
      final fullPublicId = 'privora/user-1/cat-1/$photoId';
      final thumbPublicId = 'privora/user-1/cat-1/${photoId}_thumb';

      final fullSignedParams = <String, String>{
        'public_id': fullPublicId,
        'timestamp': timestamp,
        'type': 'authenticated',
        'upload_preset': uploadPreset,
      };

      final thumbSignedParams = <String, String>{
        'public_id': thumbPublicId,
        'timestamp': timestamp,
        'type': 'authenticated',
        'upload_preset': uploadPreset,
      };

      final fullSignature = await calculateCanonicalSignature(
        fullSignedParams,
        apiSecret,
      );
      final thumbSignature = await calculateCanonicalSignature(
        thumbSignedParams,
        apiSecret,
      );

      // Signatures must be 40-character lowercase hex strings
      expect(fullSignature, hasLength(40));
      expect(thumbSignature, hasLength(40));
      expect(RegExp(r'^[a-f0-9]{40}$').hasMatch(fullSignature), isTrue);
      expect(RegExp(r'^[a-f0-9]{40}$').hasMatch(thumbSignature), isTrue);

      // Signatures must NEVER be equal
      expect(fullSignature, isNot(equals(thumbSignature)));

      // Modifying thumbnail public_id does not alter full photo signature
      final alteredThumbParams = <String, String>{
        'public_id': '${thumbPublicId}_v2',
        'timestamp': timestamp,
        'type': 'authenticated',
        'upload_preset': uploadPreset,
      };
      final alteredThumbSignature = await calculateCanonicalSignature(
        alteredThumbParams,
        apiSecret,
      );
      expect(alteredThumbSignature, isNot(equals(thumbSignature)));
      expect(fullSignature, isNot(equals(alteredThumbSignature)));
    });

    // -------------------------------------------------------------------------
    // 2. Signed and submitted parameter maps are identical
    // -------------------------------------------------------------------------
    test(
      '2. Signed and submitted parameter maps are identical in multipart request',
      () async {
        final mockClient = MockCloudinaryHttpClient();
        final service = CloudinaryMediaService(httpClient: mockClient);

        final signedParams = <String, String>{
          'public_id': 'privora/user-1/cat-1/my-photo',
          'timestamp': '1770000000',
          'type': 'authenticated',
          'upload_preset': uploadPreset,
        };
        final signature = await calculateCanonicalSignature(
          signedParams,
          apiSecret,
        );

        final fakeBytes = Uint8List.fromList([1, 2, 3, 4, 5]);

        await service.uploadEncryptedBytes(
          cloudName: cloudName,
          apiKey: apiKey,
          timestamp: 1770000000,
          publicId: signedParams['public_id']!,
          signature: signature,
          signedParams: signedParams,
          bytes: fakeBytes,
          filename: 'photo.enc',
        );

        expect(mockClient.capturedMultipartRequest, isNotNull);
        final fields = mockClient.capturedFields;

        // Every entry in signedParams must be present in request.fields with exact unchanged string value
        for (final entry in signedParams.entries) {
          expect(
            fields[entry.key],
            equals(entry.value),
            reason:
                'Field ${entry.key} must exactly match signed parameter value',
          );
        }

        // Must hit /raw/upload endpoint, NOT /raw/authenticated
        expect(
          mockClient.capturedUri.toString(),
          'https://api.cloudinary.com/v1_1/$cloudName/raw/upload',
        );
        expect(
          mockClient.capturedUri.toString().contains('/raw/authenticated'),
          isFalse,
          reason: 'Must never use /raw/authenticated as the upload endpoint',
        );
      },
    );

    // -------------------------------------------------------------------------
    // 3. upload_preset is included on both sides (or omitted on both sides)
    // -------------------------------------------------------------------------
    test(
      '3. upload_preset is included on both sides when specified, or omitted from both',
      () async {
        final mockClient = MockCloudinaryHttpClient();
        final service = CloudinaryMediaService(httpClient: mockClient);

        // Case A: Preset is included
        final signedWithPreset = <String, String>{
          'public_id': 'privora/u/c/p1',
          'timestamp': '1770000000',
          'type': 'authenticated',
          'upload_preset': 'privora_signed',
        };
        final sigWithPreset = await calculateCanonicalSignature(
          signedWithPreset,
          apiSecret,
        );

        await service.uploadEncryptedBytes(
          cloudName: cloudName,
          apiKey: apiKey,
          timestamp: 1770000000,
          publicId: 'privora/u/c/p1',
          signature: sigWithPreset,
          signedParams: signedWithPreset,
          bytes: Uint8List.fromList([10, 20]),
          filename: 'p1.enc',
        );

        // Both signedParams and submitted fields contain upload_preset
        expect(signedWithPreset.containsKey('upload_preset'), isTrue);
        expect(
          mockClient.capturedFields['upload_preset'],
          equals('privora_signed'),
        );
        expect(mockClient.capturedFields['type'], equals('authenticated'));

        // Case B: Preset is omitted
        final signedWithoutPreset = <String, String>{
          'public_id': 'privora/u/c/p2',
          'timestamp': '1770000000',
          'type': 'authenticated',
        };
        final sigWithoutPreset = await calculateCanonicalSignature(
          signedWithoutPreset,
          apiSecret,
        );

        await service.uploadEncryptedBytes(
          cloudName: cloudName,
          apiKey: apiKey,
          timestamp: 1770000000,
          publicId: 'privora/u/c/p2',
          signature: sigWithoutPreset,
          signedParams: signedWithoutPreset,
          bytes: Uint8List.fromList([30, 40]),
          filename: 'p2.enc',
        );

        // Omitted from both sides
        expect(signedWithoutPreset.containsKey('upload_preset'), isFalse);
        expect(mockClient.capturedFields.containsKey('upload_preset'), isFalse);
        expect(mockClient.capturedFields['type'], equals('authenticated'));
      },
    );

    // -------------------------------------------------------------------------
    // 4. No unsigned extra parameter is submitted (resource_type excluded)
    // -------------------------------------------------------------------------
    test(
      '4. Multipart request contains only file, api_key, signature, and signedParams (including type=authenticated); excludes resource_type',
      () async {
        final mockClient = MockCloudinaryHttpClient();
        final service = CloudinaryMediaService(httpClient: mockClient);

        final signedParams = <String, String>{
          'public_id': 'privora/u/c/p3',
          'timestamp': '1770000000',
          'type': 'authenticated',
          'upload_preset': 'privora_signed',
        };
        final signature = await calculateCanonicalSignature(
          signedParams,
          apiSecret,
        );

        await service.uploadEncryptedBytes(
          cloudName: cloudName,
          apiKey: apiKey,
          timestamp: 1770000000,
          publicId: 'privora/u/c/p3',
          signature: signature,
          signedParams: signedParams,
          bytes: Uint8List.fromList([1, 2, 3]),
          filename: 'p3.enc',
        );

        final fields = mockClient.capturedFields;

        // Strictly forbidden in fields because raw is already in the endpoint URL
        expect(
          fields.containsKey('resource_type'),
          isFalse,
          reason: 'resource_type must NOT be sent in multipart fields',
        );

        // type=authenticated must be present
        expect(fields['type'], equals('authenticated'));

        // Allowed field keys are strictly: api_key, signature, and every key in signedParams
        final expectedKeys = {'api_key', 'signature', ...signedParams.keys};
        expect(
          fields.keys.toSet(),
          equals(expectedKeys),
          reason:
              'No extra unsigned parameters should be submitted to Cloudinary',
        );

        // Files contains exactly one file named 'file'
        expect(mockClient.capturedFiles.length, 1);
        expect(mockClient.capturedFiles.first.field, 'file');
      },
    );

    // -------------------------------------------------------------------------
    // 5. Cloudinary error bodies are parsed correctly and safely
    // -------------------------------------------------------------------------
    group('5. Cloudinary non-2xx error handling and redaction', () {
      test('Parses JSON error.message from Cloudinary 400 response', () {
        const body =
            '{"error":{"message":"Upload preset privora_signed not found"}}';
        final parsed = CloudinaryMediaService.parseCloudinaryErrorMessage(
          statusCode: 400,
          responseBody: body,
        );

        expect(parsed, contains('Upload preset privora_signed not found'));
        expect(parsed, isNot(contains('unexpected error')));
      });

      test('Parses X-Cld-Error header when present', () {
        final parsed = CloudinaryMediaService.parseCloudinaryErrorMessage(
          statusCode: 401,
          responseBody: '',
          headers: {'x-cld-error': 'Invalid Signature for raw asset'},
        );

        expect(parsed, contains('Invalid Signature for raw asset'));
      });

      test(
        'Redacts signatures, secrets, and string-to-sign from error messages',
        () {
          const sensitiveBody =
              '{"error":{"message":"Invalid Signature 5d41402abc4b2a76b9719d911017c592. String to sign - \'public_id=foo&timestamp=123my_api_secret_value\'."}}';

          final safeMsg = CloudinaryMediaService.parseCloudinaryErrorMessage(
            statusCode: 401,
            responseBody: sensitiveBody,
          );

          // The raw secret and raw signature must NOT be present
          expect(safeMsg, isNot(contains('my_api_secret_value')));
          expect(safeMsg, isNot(contains('5d41402abc4b2a76b9719d911017c592')));
          // Redacted markers should be present
          expect(safeMsg, contains('[REDACTED'));
        },
      );

      test(
        'uploadEncryptedBytes throws StorageException with parsed safe message on 401',
        () async {
          final mockClient = MockCloudinaryHttpClient();
          mockClient.responseStatusCode = 401;
          mockClient.responseBody = jsonEncode({
            'error': {'message': 'Invalid signature or expired timestamp'},
          });

          final service = CloudinaryMediaService(httpClient: mockClient);

          expect(
            () => service.uploadEncryptedBytes(
              cloudName: cloudName,
              apiKey: apiKey,
              timestamp: 1770000000,
              publicId: 'privora/u/c/p',
              signature: 'sig',
              signedParams: {'public_id': 'privora/u/c/p'},
              bytes: Uint8List(10),
              filename: 'p.enc',
            ),
            throwsA(
              isA<StorageException>().having(
                (e) => e.message,
                'message',
                allOf(
                  contains('401'),
                  contains('Invalid signature or expired timestamp'),
                ),
              ),
            ),
          );
        },
      );
    });

    // -------------------------------------------------------------------------
    // 6. Partial-upload cleanup: full succeeds and thumb fails, or vice-versa
    // -------------------------------------------------------------------------
    group('6. Partial-upload cleanup', () {
      test(
        'If full asset succeeds and thumbnail fails, full asset is cleaned up',
        () async {
          String? cleanedFullId;
          String? cleanedThumbId;

          final mockMediaService = _RollbackTrackingCloudinaryService(
            onCleanup: (photoId, fullId, thumbId) {
              cleanedFullId = fullId;
              cleanedThumbId = thumbId;
            },
          );

          // Simulate partial state: full asset succeeded, thumbnail failed
          await mockMediaService.cleanupFailedUpload(
            photoId: 'photo-full-only',
            fullPublicId: 'privora/user-1/cat-1/photo-full-only',
            thumbnailPublicId: null,
          );

          expect(mockMediaService.cleanupCalls, 1);
          expect(cleanedFullId, equals('privora/user-1/cat-1/photo-full-only'));
          expect(cleanedThumbId, isNull);
        },
      );

      test(
        'If thumbnail succeeds and full asset fails, thumbnail is cleaned up via PhotoUploadService rollback',
        () async {
          String? cleanedThumbId;

          final mockMediaService = _RollbackTrackingCloudinaryService(
            onCleanup: (photoId, fullId, thumbId) {
              cleanedThumbId = thumbId;
            },
            failFull: true,
          );

          final cryptoService = VaultCryptoService();
          final masterKey = cryptoService.generateMasterKey();
          final tempDir = await Directory.systemTemp.createTemp(
            'privora_rollback_test_2_',
          );
          final tempFile = File('${tempDir.path}/test2.jpg');
          await tempFile.writeAsBytes(utf8.encode('DUMMY_IMAGE_BYTES_2'));

          final uploadService = PhotoUploadService(
            cryptoService: cryptoService,
            cloudinaryService: mockMediaService,
            databaseService: FakeDbForRollback(),
            cleaner: TemporaryFileCleaner(),
          );

          try {
            await uploadService.uploadPhoto(
              sourceFile: tempFile,
              userId: 'user-1',
              categoryId: 'cat-1',
              masterKey: masterKey,
            );
          } catch (_) {
            // Expected failure
          } finally {
            if (await tempDir.exists()) await tempDir.delete(recursive: true);
          }

          // Thumbnail succeeded, then full photo failed -> thumbnail must be targeted for cleanup
          expect(mockMediaService.cleanupCalls, 1);
          expect(cleanedThumbId, isNotNull);
          expect(cleanedThumbId, contains('_thumb'));
        },
      );

      test(
        'If both assets succeed and metadata commit fails, both assets are cleaned up',
        () async {
          String? cleanedFullId;
          String? cleanedThumbId;

          final mockMediaService = _RollbackTrackingCloudinaryService(
            onCleanup: (photoId, fullId, thumbId) {
              cleanedFullId = fullId;
              cleanedThumbId = thumbId;
            },
          );

          await mockMediaService.cleanupFailedUpload(
            photoId: 'photo-both',
            fullPublicId: 'privora/user-1/cat-1/photo-both',
            thumbnailPublicId: 'privora/user-1/cat-1/photo-both_thumb',
          );

          expect(mockMediaService.cleanupCalls, 1);
          expect(cleanedFullId, equals('privora/user-1/cat-1/photo-both'));
          expect(
            cleanedThumbId,
            equals('privora/user-1/cat-1/photo-both_thumb'),
          );
        },
      );
    });
  });
}

class _RollbackTrackingCloudinaryService extends Fake
    implements CloudinaryMediaService {
  final void Function(
    String? photoId,
    String? fullPublicId,
    String? thumbnailPublicId,
  )
  onCleanup;
  final bool failFull;
  int cleanupCalls = 0;

  _RollbackTrackingCloudinaryService({
    required this.onCleanup,
    this.failFull = false,
  });

  @override
  Future<CloudinaryUploadParams> createUploadSignature({
    required String categoryId,
    required String photoId,
  }) async {
    return CloudinaryUploadParams(
      cloudName: 'test-cloud',
      apiKey: 'test-key',
      timestamp: 1770000000,
      photoId: photoId,
      fullPublicId: 'privora/user-1/$categoryId/$photoId',
      fullSignature: 'sig_full',
      thumbnailPublicId: 'privora/user-1/$categoryId/${photoId}_thumb',
      thumbnailSignature: 'sig_thumb',
      fullSignedParams: {
        'public_id': 'privora/user-1/$categoryId/$photoId',
        'timestamp': '1770000000',
        'type': 'authenticated',
        'upload_preset': 'privora_signed',
      },
      thumbnailSignedParams: {
        'public_id': 'privora/user-1/$categoryId/${photoId}_thumb',
        'timestamp': '1770000000',
        'type': 'authenticated',
        'upload_preset': 'privora_signed',
      },
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
    if (failFull && !publicId.endsWith('_thumb')) {
      throw const StorageException('Simulated full photo upload failure');
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
    onCleanup(photoId, fullPublicId, thumbnailPublicId);
  }
}
