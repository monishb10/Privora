import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart' as sp;
import '../../core/config/supabase_config.dart';
import '../../core/errors/app_exception.dart';
import '../../core/errors/error_mapper.dart';

/// Parameters returned by the Supabase Edge Function for Cloudinary authenticated uploads.
class CloudinaryUploadParams {
  final String cloudName;
  final String apiKey;
  final int timestamp;
  final String? uploadPreset;
  final String resourceType;
  final String type;
  final String photoId;
  final String fullPublicId;
  final String fullSignature;
  final String thumbnailPublicId;
  final String thumbnailSignature;
  final Map<String, String> fullSignedParams;
  final Map<String, String> thumbnailSignedParams;

  const CloudinaryUploadParams({
    required this.cloudName,
    required this.apiKey,
    required this.timestamp,
    this.uploadPreset,
    this.resourceType = 'raw',
    this.type = 'authenticated',
    required this.photoId,
    required this.fullPublicId,
    required this.fullSignature,
    required this.thumbnailPublicId,
    required this.thumbnailSignature,
    this.fullSignedParams = const {},
    this.thumbnailSignedParams = const {},
  });

  factory CloudinaryUploadParams.fromJson(Map<String, dynamic> json) {
    final full = json['full'] as Map<String, dynamic>? ?? {};
    final thumb = json['thumbnail'] as Map<String, dynamic>? ?? {};

    final fullPublicId = full['publicId'] as String? ?? '';
    final fullSignature = full['signature'] as String? ?? '';
    final thumbPublicId = thumb['publicId'] as String? ?? '';
    final thumbSignature = thumb['signature'] as String? ?? '';

    final fullSigned = <String, String>{};
    if (full['signedParams'] is Map) {
      (full['signedParams'] as Map).forEach((k, v) {
        fullSigned[k.toString()] = v.toString();
      });
    } else {
      if (fullPublicId.isNotEmpty) fullSigned['public_id'] = fullPublicId;
      if (json['timestamp'] != null) {
        fullSigned['timestamp'] = json['timestamp'].toString();
      }
      if (json['uploadPreset'] != null &&
          (json['uploadPreset'] as String).isNotEmpty) {
        fullSigned['upload_preset'] = json['uploadPreset'] as String;
      }
    }
    if (!fullSigned.containsKey('type')) {
      fullSigned['type'] = json['type'] as String? ?? 'authenticated';
    }

    final thumbSigned = <String, String>{};
    if (thumb['signedParams'] is Map) {
      (thumb['signedParams'] as Map).forEach((k, v) {
        thumbSigned[k.toString()] = v.toString();
      });
    } else {
      if (thumbPublicId.isNotEmpty) thumbSigned['public_id'] = thumbPublicId;
      if (json['timestamp'] != null) {
        thumbSigned['timestamp'] = json['timestamp'].toString();
      }
      if (json['uploadPreset'] != null &&
          (json['uploadPreset'] as String).isNotEmpty) {
        thumbSigned['upload_preset'] = json['uploadPreset'] as String;
      }
    }
    if (!thumbSigned.containsKey('type')) {
      thumbSigned['type'] = json['type'] as String? ?? 'authenticated';
    }

    final timestampInt = json['timestamp'] is int
        ? json['timestamp'] as int
        : (int.tryParse(json['timestamp']?.toString() ?? '') ??
              int.tryParse(fullSigned['timestamp'] ?? '') ??
              DateTime.now().millisecondsSinceEpoch ~/ 1000);

    return CloudinaryUploadParams(
      cloudName: json['cloudName'] as String? ?? '',
      apiKey: json['apiKey'] as String? ?? '',
      timestamp: timestampInt,
      uploadPreset:
          json['uploadPreset'] as String? ?? fullSigned['upload_preset'],
      resourceType: json['resourceType'] as String? ?? 'raw',
      type: json['type'] as String? ?? 'authenticated',
      photoId: json['photoId'] as String? ?? '',
      fullPublicId: fullPublicId,
      fullSignature: fullSignature,
      thumbnailPublicId: thumbPublicId,
      thumbnailSignature: thumbSignature,
      fullSignedParams: fullSigned,
      thumbnailSignedParams: thumbSigned,
    );
  }
}

/// Metadata returned by Cloudinary following a successful raw asset upload.
class CloudinaryUploadResult {
  final String publicId;
  final String assetId;
  final String resourceType;
  final String type;
  final String? format;
  final String? version;
  final int bytes;

  const CloudinaryUploadResult({
    required this.publicId,
    required this.assetId,
    this.resourceType = 'raw',
    this.type = 'authenticated',
    this.format,
    this.version,
    required this.bytes,
  });

  factory CloudinaryUploadResult.fromJson(Map<String, dynamic> json) {
    return CloudinaryUploadResult(
      publicId: json['public_id'] as String? ?? '',
      assetId: json['asset_id'] as String? ?? '',
      resourceType: json['resource_type'] as String? ?? '',
      type: json['type'] as String? ?? '',
      format: json['format'] as String?,
      version: json['version']?.toString(),
      bytes: (json['bytes'] as int?) ?? 0,
    );
  }

  Map<String, dynamic> toSafeLogMap() {
    return {
      'asset_id': assetId,
      'public_id': publicId,
      'resource_type': resourceType,
      'type': type,
      if (format != null) 'format': format,
      if (version != null) 'version': version,
      'bytes': bytes,
    };
  }
}

/// Service managing client-side interaction with Cloudinary and the
/// Supabase Edge Function for signed uploads, downloads, commits, and deletions.
class CloudinaryMediaService {
  /// Cloud uploads must tolerate real mobile-network speeds.
  static const Duration minimumUploadTimeout = Duration(minutes: 3);
  static const Duration maximumUploadTimeout = Duration(minutes: 15);
  static const int _assumedSlowUploadBytesPerSecond = 64 * 1024;
  static const int _uploadResponseGraceSeconds = 60;

  final http.Client _httpClient;

  CloudinaryMediaService({http.Client? httpClient})
    : _httpClient = httpClient ?? http.Client();

  /// Returns a bounded upload timeout based on ciphertext size.
  @visibleForTesting
  static Duration uploadTimeoutForByteLength(int byteLength) {
    final safeByteLength = byteLength < 0 ? 0 : byteLength;
    final transferSeconds = (safeByteLength / _assumedSlowUploadBytesPerSecond)
        .ceil();
    final estimatedSeconds = _uploadResponseGraceSeconds + transferSeconds;
    final boundedSeconds = estimatedSeconds
        .clamp(minimumUploadTimeout.inSeconds, maximumUploadTimeout.inSeconds)
        .toInt();

    return Duration(seconds: boundedSeconds);
  }

  sp.SupabaseClient get _client {
    final client = SupabaseConfig.client;
    if (client == null) {
      throw const StorageException('Supabase is not configured.');
    }
    return client;
  }

  /// Obtains server-signed upload parameters from the Supabase Edge Function.
  Future<CloudinaryUploadParams> createUploadSignature({
    required String categoryId,
    required String photoId,
  }) async {
    try {
      final response = await _client.functions
          .invoke(
            'cloudinary-media',
            body: {
              'action': 'createUploadSignature',
              'categoryId': categoryId,
              'photoId': photoId,
            },
          )
          .timeout(const Duration(seconds: 15));

      if (response.status != 200) {
        final errorMsg = response.data is Map
            ? response.data['error']?.toString()
            : 'Edge Function returned error ${response.status}';
        throw StorageException(
          errorMsg ?? 'Failed to create upload signature.',
        );
      }

      final data = response.data is Map
          ? response.data as Map<String, dynamic>
          : jsonDecode(response.data.toString()) as Map<String, dynamic>;

      return CloudinaryUploadParams.fromJson(data);
    } catch (e) {
      debugPrint('createUploadSignature error: $e');
      if (e is AppException) rethrow;
      throw StorageException(ErrorMapper.mapToUserMessage(e));
    }
  }

  /// Parses and sanitizes Cloudinary error response without leaking sensitive secrets.
  static String parseCloudinaryErrorMessage({
    required int statusCode,
    required String responseBody,
    Map<String, String>? headers,
  }) {
    String? rawError;

    if (headers != null) {
      for (final entry in headers.entries) {
        if (entry.key.toLowerCase() == 'x-cld-error') {
          rawError = entry.value;
          break;
        }
      }
    }

    if (responseBody.isNotEmpty) {
      try {
        final decoded = jsonDecode(responseBody);
        if (decoded is Map) {
          if (decoded['error'] is Map && decoded['error']['message'] != null) {
            rawError = decoded['error']['message'].toString();
          } else if (decoded['message'] != null) {
            rawError = decoded['message'].toString();
          }
        }
      } catch (_) {}
    }

    return sanitizeCloudinaryError(rawError, statusCode);
  }

  /// Sanitizes raw error text, stripping sensitive secrets, signatures, and tokens.
  static String sanitizeCloudinaryError(String? rawError, int statusCode) {
    if (rawError == null || rawError.trim().isEmpty) {
      return 'Cloudinary request failed with HTTP $statusCode';
    }

    var sanitized = rawError
        .replaceAll(RegExp(r'\b[a-fA-F0-9]{32,64}\b'), '[REDACTED_SIGNATURE]')
        .replaceAll(
          RegExp(r'String to sign\s*[-:=]?\s*.*', caseSensitive: false),
          'String to sign: [REDACTED]',
        )
        .replaceAll(
          RegExp(r'api_secret\s*[:=]\s*[^\s,]+', caseSensitive: false),
          'api_secret=[REDACTED]',
        )
        .replaceAll(
          RegExp(r'api_key\s*[:=]\s*[^\s,]+', caseSensitive: false),
          'api_key=[REDACTED]',
        )
        .replaceAll(
          RegExp(r'Bearer\s+[A-Za-z0-9\-._~+/]+=*', caseSensitive: false),
          'Bearer [REDACTED]',
        );

    sanitized = sanitized.trim();
    if (sanitized.isEmpty) {
      return 'Cloudinary request failed with HTTP $statusCode';
    }
    return sanitized;
  }

  /// Uploads encrypted ciphertext bytes directly to Cloudinary using multipart/form-data.
  /// Uses REST endpoint: https://api.cloudinary.com/v1_1/{cloud_name}/raw/upload
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
    final uploadTimeout = uploadTimeoutForByteLength(bytes.length);

    try {
      final uri = Uri.parse(
        'https://api.cloudinary.com/v1_1/$cloudName/raw/upload',
      );
      final request = http.MultipartRequest('POST', uri);

      request.fields['api_key'] = apiKey;
      request.fields['signature'] = signature;

      final effectiveSignedParams =
          signedParams ??
          {
            'public_id': publicId,
            'timestamp': timestamp.toString(),
            'type': 'authenticated',
            if (uploadPreset != null && uploadPreset.isNotEmpty)
              'upload_preset': uploadPreset,
          };

      for (final entry in effectiveSignedParams.entries) {
        request.fields[entry.key] = entry.value;
      }

      if (!request.fields.containsKey('type')) {
        request.fields['type'] = 'authenticated';
      }

      request.files.add(
        http.MultipartFile.fromBytes('file', bytes, filename: filename),
      );

      if (kDebugMode) {
        debugPrint(
          '[CloudinaryMediaService] Starting $stage upload '
          '(${bytes.length} encrypted bytes, timeout ${uploadTimeout.inSeconds}s)',
        );
      }

      final streamedResponse = await _httpClient
          .send(request)
          .timeout(uploadTimeout);

      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode != 200 && response.statusCode != 201) {
        final safeError = parseCloudinaryErrorMessage(
          statusCode: response.statusCode,
          responseBody: response.body,
          headers: response.headers,
        );

        if (kDebugMode) {
          debugPrint(
            '[CloudinaryMediaService] Upload failed ($stage) HTTP ${response.statusCode}: $safeError',
          );
        }

        throw StorageException(
          'Cloudinary upload failed (HTTP ${response.statusCode}): $safeError',
          statusCode: response.statusCode,
        );
      }

      final responseBody = jsonDecode(response.body) as Map<String, dynamic>;
      final result = CloudinaryUploadResult.fromJson(responseBody);

      if (kDebugMode) {
        debugPrint(
          '[CloudinaryMediaService] Upload success ($stage): ${result.publicId}',
        );
      }

      // Verification of required identity fields
      if (result.assetId.isEmpty) {
        throw const StorageException(
          'Cloudinary upload validation failed: missing asset_id in response.',
          code: 'INVALID_ASSET_ID',
        );
      }
      if (result.publicId.isEmpty) {
        throw const StorageException(
          'Cloudinary upload validation failed: missing public_id in response.',
          code: 'INVALID_PUBLIC_ID',
        );
      }
      if (result.resourceType != 'raw') {
        throw StorageException(
          'Cloudinary upload validation failed: unexpected resource_type "${result.resourceType}" (expected raw).',
          code: 'INVALID_RESOURCE_TYPE',
        );
      }
      if (result.type != 'authenticated') {
        throw StorageException(
          'Cloudinary upload validation failed: unexpected type "${result.type}" (expected authenticated).',
          code: 'INVALID_DELIVERY_TYPE',
        );
      }

      return result;
    } on TimeoutException {
      if (kDebugMode) {
        debugPrint(
          '[CloudinaryMediaService] $stage upload timed out after ${uploadTimeout.inSeconds}s',
        );
      }
      throw StorageException(
        'The encrypted photo upload timed out after ${uploadTimeout.inMinutes} minutes. Keep Privora open and try again on a stable connection.',
        code: 'CLOUDINARY_UPLOAD_TIMEOUT',
      );
    } on SocketException {
      throw const StorageException(
        'Check your internet connection.',
        code: 'NETWORK_ERROR',
      );
    } catch (e) {
      if (kDebugMode) {
        debugPrint(
          '[CloudinaryMediaService] uploadEncryptedBytes error ($stage): $e',
        );
      }
      if (e is AppException) rethrow;
      throw StorageException(ErrorMapper.mapToUserMessage(e));
    }
  }

  /// Commits photo metadata via Edge Function after verifying Cloudinary assets.
  Future<Map<String, dynamic>> commitUpload({
    required String photoId,
    required String categoryId,
    required String displayName,
    required String mimeType,
    required int encryptedSize,
    int? width,
    int? height,
    required String fullPublicId,
    required String thumbnailPublicId,
    required String fullAssetId,
    required String thumbnailAssetId,
    String? fullVersion,
    int? fullBytes,
  }) async {
    try {
      final response = await _client.functions
          .invoke(
            'cloudinary-media',
            body: {
              'action': 'commitUpload',
              'photoId': photoId,
              'categoryId': categoryId,
              'displayName': displayName,
              'mimeType': mimeType,
              'encryptedSize': encryptedSize,
              'width': width,
              'height': height,
              'fullPublicId': fullPublicId,
              'thumbnailPublicId': thumbnailPublicId,
              'fullAssetId': fullAssetId,
              'thumbnailAssetId': thumbnailAssetId,
              'fullVersion': fullVersion,
              'fullBytes': fullBytes,
            },
          )
          .timeout(const Duration(seconds: 20));

      if (response.status != 200) {
        final errorMsg = response.data is Map
            ? response.data['error']?.toString()
            : 'Edge Function returned error ${response.status}';
        throw StorageException(errorMsg ?? 'Failed to commit photo metadata.');
      }

      final data = response.data is Map
          ? response.data as Map<String, dynamic>
          : jsonDecode(response.data.toString()) as Map<String, dynamic>;

      return data['photo'] as Map<String, dynamic>? ?? data;
    } catch (e) {
      debugPrint('commitUpload error: $e');
      if (e is AppException) rethrow;
      throw StorageException(ErrorMapper.mapToUserMessage(e));
    }
  }

  /// Requests a server-signed download URL for an encrypted photo or thumbnail.
  Future<String> getSignedDownloadUrl({
    required String photoId,
    required String target, // 'full' or 'thumbnail'
  }) async {
    try {
      final response = await _client.functions
          .invoke(
            'cloudinary-media',
            body: {
              'action': 'getDownloadUrl',
              'photoId': photoId,
              'target': target,
            },
          )
          .timeout(const Duration(seconds: 15));

      if (response.status != 200) {
        final errorMsg = response.data is Map
            ? response.data['error']?.toString()
            : 'Edge Function returned error ${response.status}';
        if (response.status == 404 ||
            (errorMsg != null &&
                (errorMsg.toLowerCase().contains('not found') ||
                    errorMsg.contains('Cloud file could not be found')))) {
          throw const StorageException(
            'Cloud file could not be found.',
            code: 'NOT_FOUND',
            statusCode: 404,
          );
        }
        throw StorageException(
          errorMsg ?? 'Failed to get signed download URL.',
          statusCode: response.status,
        );
      }

      final data = response.data is Map
          ? response.data as Map<String, dynamic>
          : jsonDecode(response.data.toString()) as Map<String, dynamic>;

      final url = data['downloadUrl'] as String?;
      if (url == null || url.isEmpty) {
        throw const StorageException('Invalid download URL received.');
      }
      return url;
    } on SocketException {
      throw const StorageException(
        'Check your internet connection.',
        code: 'NETWORK_ERROR',
      );
    } on TimeoutException {
      throw const StorageException(
        'Check your internet connection.',
        code: 'TIMEOUT',
      );
    } catch (e) {
      debugPrint('getSignedDownloadUrl error: $e');
      if (e is AppException) rethrow;
      throw StorageException(ErrorMapper.mapToUserMessage(e));
    }
  }

  /// Downloads raw encrypted ciphertext bytes from the signed delivery URL.
  Future<Uint8List> downloadEncryptedBytes(String downloadUrl) async {
    try {
      final uri = Uri.parse(downloadUrl);
      final response = await _httpClient
          .get(uri)
          .timeout(const Duration(seconds: 30));

      if (response.statusCode == 404) {
        throw const StorageException(
          'Cloud file could not be found.',
          code: 'NOT_FOUND',
          statusCode: 404,
        );
      }

      if (response.statusCode != 200) {
        throw StorageException(
          'Failed to download asset: HTTP ${response.statusCode}',
          statusCode: response.statusCode,
        );
      }

      return response.bodyBytes;
    } on SocketException {
      throw const StorageException(
        'Check your internet connection.',
        code: 'NETWORK_ERROR',
      );
    } on TimeoutException {
      throw const StorageException(
        'Check your internet connection.',
        code: 'TIMEOUT',
      );
    } on http.ClientException {
      throw const StorageException(
        'Check your internet connection.',
        code: 'NETWORK_ERROR',
      );
    } catch (e) {
      debugPrint('downloadEncryptedBytes error: $e');
      if (e is AppException) rethrow;
      throw StorageException(ErrorMapper.mapToUserMessage(e));
    }
  }

  /// Permanently deletes both full photo and thumbnail from Cloudinary
  /// and removes the database record via the Edge Function.
  Future<void> permanentlyDelete({required String photoId}) async {
    try {
      final response = await _client.functions
          .invoke(
            'cloudinary-media',
            body: {'action': 'permanentlyDelete', 'photoId': photoId},
          )
          .timeout(const Duration(seconds: 20));

      if (response.status != 200) {
        final errorMsg = response.data is Map
            ? response.data['error']?.toString()
            : 'Edge Function returned error ${response.status}';
        throw StorageException(errorMsg ?? 'Permanent deletion failed.');
      }
    } catch (e) {
      debugPrint('permanentlyDelete error: $e');
      if (e is AppException) rethrow;
      throw StorageException(ErrorMapper.mapToUserMessage(e));
    }
  }

  /// Cleans up orphaned or partially uploaded assets in Cloudinary.
  Future<void> cleanupFailedUpload({
    String? photoId,
    String? fullPublicId,
    String? thumbnailPublicId,
  }) async {
    if (photoId == null && fullPublicId == null && thumbnailPublicId == null) {
      return;
    }
    try {
      await _client.functions
          .invoke(
            'cloudinary-media',
            body: {
              'action': 'cleanupFailedUpload',
              'photoId': photoId,
              'fullPublicId': fullPublicId,
              'thumbnailPublicId': thumbnailPublicId,
            },
          )
          .timeout(const Duration(seconds: 15));
    } catch (e) {
      debugPrint('cleanupFailedUpload warning: $e');
    }
  }
}
