import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/config/supabase_config.dart';
import '../../core/errors/app_exception.dart';

/// Talks to the protected Supabase function that stores and releases the
/// encrypted vault-key backup used by Gmail OTP PIN reset.
///
/// The service never stores an OTP or a plaintext master key on disk. The
/// master key is sent only over the authenticated TLS function request and is
/// encrypted again inside the Edge Function before it is persisted.
class VaultOtpService {
  static const String _functionName = 'vault-key-otp';

  SupabaseClient get _client {
    final client = SupabaseConfig.client;
    if (client == null) {
      throw const PinResetException('Supabase is not configured.');
    }
    return client;
  }

  Future<Map<String, dynamic>> _invoke(
    String action, {
    Map<String, dynamic> body = const {},
  }) async {
    try {
      final response = await _client.functions
          .invoke(_functionName, body: {'action': action, ...body})
          .timeout(const Duration(seconds: 20));

      final data = response.data is Map
          ? Map<String, dynamic>.from(response.data as Map)
          : jsonDecode(response.data.toString()) as Map<String, dynamic>;

      if (response.status != 200) {
        throw PinResetException(
          data['error']?.toString() ??
              'Email PIN reset service returned HTTP ${response.status}.',
        );
      }
      return data;
    } on PinResetException {
      rethrow;
    } on TimeoutException {
      throw const PinResetException(
        'PIN reset service timed out. Check your connection and try again.',
      );
    } catch (error, stackTrace) {
      if (kDebugMode) {
        debugPrint('VaultOtpService $action failed: $error\n$stackTrace');
      }
      throw const PinResetException(
        'PIN reset service is unavailable. Please try again shortly.',
      );
    }
  }

  Future<void> storeMasterKey(Uint8List masterKey) async {
    if (masterKey.length != 32) {
      throw const PinResetException('Invalid vault key length.');
    }
    await _invoke(
      'storeEnvelope',
      body: {'masterKey': base64Encode(masterKey)},
    );
  }

  Future<bool> hasEnvelope() async {
    final data = await _invoke('hasEnvelope');
    return data['exists'] == true;
  }

  /// The deployed function releases this key only when the current verified
  /// Supabase JWT contains a recent email-OTP authentication method.
  Future<Uint8List> loadMasterKeyAfterOtp() async {
    final data = await _invoke('releaseEnvelope');
    final encoded = data['masterKey']?.toString();
    if (encoded == null || encoded.isEmpty) {
      throw const PinResetException(
        'No Gmail PIN-reset backup exists for this vault yet.',
      );
    }

    try {
      final key = base64Decode(encoded);
      if (key.length != 32) throw const FormatException('invalid key');
      return Uint8List.fromList(key);
    } catch (_) {
      throw const PinResetException(
        'The PIN-reset backup could not be opened safely.',
      );
    }
  }
}
