import 'dart:convert';
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

  const CloudinaryUploadParams({
    required this.cloudName,
    required this.apiKey,
    required this.timestamp,
    this.uploadPreset,
    required this.resourceType,
    required this.type,
    required this.photoId,
    required this.fullPublicId,
    required this.fullSignature,
    required this.thumbnailPublicId,
    required this.thumbnailSignature,
  });

  factory CloudinaryUploadParams.fromJson(Map<String, dynamic> json) {
    final full = json['full'] as Map<String, dynamic>;
    final thumb = json['thumbnail'] as Map<String, dynamic>;

    return CloudinaryUploadParams(
      cloudName: json['cloudName'] as String,
      apiKey: json['apiKey'] as String,
      timestamp: json['timestamp'] as int,
      uploadPreset: json['uploadPreset'] as String?,
      resourceType: json['resourceType'] as String? ?? 'raw',
      type: json['type'] as String? ?? 'authenticated',
      photoId: json['photoId'] as String,
      fullPublicId: full['publicId'] as String,
      fullSignature: full['signature'] as String,
      thumbnailPublicId: thumb['publicId'] as String,
      thumbnailSignature: thumb['signature'] as String,
    );
  }
}

/// Metadata returned by Cloudinary following a successful raw asset upload.
class CloudinaryUploadResult {
  final String publicId;
  final String? assetId;
  final String? version;
  final int bytes;

  const CloudinaryUploadResult({
    required this.publicId,
    this.assetId,
    this.version,
    required this.bytes,
  });
}

/// Service managing client-side interaction with Cloudinary and the
/// Supabase Edge Function for signed uploads, downloads, commits, and deletions.
class CloudinaryMediaService {
  final http.Client _httpClient;

  CloudinaryMediaService({http.Client? httpClient})
    : _httpClient = httpClient ?? http.Client();

  sp.SupabaseClient get _client {
    final client = SupabaseConfig.client;
    if (client == null) {
      throw const StorageException('Supabase is not configured.');
    }
    return client;
  }

  /// Obtains server-signed upload parameters from the Supabase Edge Function.
  /// Strictly requires a valid authenticated user session.
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

  /// Uploads encrypted ciphertext bytes directly to Cloudinary using multipart/form-data.
  Future<CloudinaryUploadResult> uploadEncryptedBytes({
    required String cloudName,
    required String apiKey,
    required int timestamp,
    String? uploadPreset,
    required String publicId,
    required String signature,
    required Uint8List bytes,
    required String filename,
  }) async {
    try {
      final uri = Uri.parse(
        'https://api.cloudinary.com/v1_1/$cloudName/raw/upload',
      );
      final request = http.MultipartRequest('POST', uri);

      request.fields['api_key'] = apiKey;
      request.fields['timestamp'] = timestamp.toString();
      request.fields['public_id'] = publicId;
      request.fields['type'] = 'authenticated';
      request.fields['signature'] = signature;
      if (uploadPreset != null && uploadPreset.isNotEmpty) {
        request.fields['upload_preset'] = uploadPreset;
      }

      request.files.add(
        http.MultipartFile.fromBytes('file', bytes, filename: filename),
      );

      final streamedResponse = await _httpClient
          .send(request)
          .timeout(const Duration(seconds: 45));

      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode != 200 && response.statusCode != 201) {
        debugPrint(
          'Cloudinary upload failed (${response.statusCode}): ${response.body}',
        );
        throw StorageException(
          'Cloudinary upload failed with status ${response.statusCode}.',
        );
      }

      final responseBody = jsonDecode(response.body) as Map<String, dynamic>;
      return CloudinaryUploadResult(
        publicId: responseBody['public_id'] as String? ?? publicId,
        assetId: responseBody['asset_id'] as String?,
        version: responseBody['version']?.toString(),
        bytes: (responseBody['bytes'] as int?) ?? bytes.length,
      );
    } catch (e) {
      debugPrint('uploadEncryptedBytes error: $e');
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
    String? assetId,
    String? version,
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
              'width': ?width,
              'height': ?height,
              'assetId': ?assetId,
              'version': ?version,
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
        throw StorageException(
          errorMsg ?? 'Failed to get signed download URL.',
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

      if (response.statusCode != 200) {
        throw StorageException(
          'Failed to download asset: HTTP ${response.statusCode}',
        );
      }

      return response.bodyBytes;
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
  /// Prefers server-tracked photoId from pending_uploads table.
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
              'photoId': ?photoId,
              'fullPublicId': ?fullPublicId,
              'thumbnailPublicId': ?thumbnailPublicId,
            },
          )
          .timeout(const Duration(seconds: 15));
    } catch (e) {
      debugPrint('cleanupFailedUpload warning: $e');
    }
  }
}
