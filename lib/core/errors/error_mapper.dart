import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sp;
import 'app_exception.dart';

/// Centralized mapper to convert any error or exception into a safe, user-friendly message.
class ErrorMapper {
  ErrorMapper._();

  static String mapToUserMessage(dynamic error) {
    if (error is AppException) {
      return error.message;
    }

    if (error is PlatformException) {
      final code = error.code.toLowerCase();
      final msg = (error.message ?? '').toLowerCase();
      final details = error.details?.toString().toLowerCase() ?? '';
      final combined = '$code $msg $details';

      if (combined.contains('10') &&
          (combined.contains('apiexception') ||
              combined.contains('developer_error'))) {
        return 'Google Sign-In configuration error (ApiException 10: DEVELOPER_ERROR). '
            'Ensure package name "com.monish.privora" and debug SHA-1 '
            '07:30:40:FB:67:AD:72:4F:B5:FF:A4:D4:04:BE:C7:9C:3F:AA:A0:E2 are registered in Google Cloud Console.';
      }
      if (combined.contains('12500')) {
        return 'Google Sign-In failed (ApiException 12500). Verify OAuth consent screen and Google Play Services.';
      }
      if (combined.contains('network')) {
        return 'Google Sign-In network error. Please check your internet connection.';
      }
      return 'Platform operation failed: ${error.message ?? error.code}';
    }

    if (error is TimeoutException) {
      return 'Request timed out. Please check your network connection.';
    }

    if (error is SocketException) {
      return 'Unable to connect to the server. Please check your internet connection.';
    }

    if (error is sp.AuthException) {
      final msg = error.message.toLowerCase();
      if (msg.contains('invalid login credentials') ||
          msg.contains('invalid_grant')) {
        return 'Invalid email or password. Please try again.';
      }
      if (msg.contains('email already in use') ||
          msg.contains('user already registered')) {
        return 'An account with this email already exists.';
      }
      if (msg.contains('rate limit')) {
        return 'Too many requests. Please wait a moment and try again.';
      }
      if (msg.contains('jwt') ||
          msg.contains('session') ||
          msg.contains('expired')) {
        return 'Session expired. Please sign in again.';
      }
      return 'Authentication failed. Please verify your credentials.';
    }

    if (error is sp.PostgrestException) {
      debugPrint(
        'PostgrestException caught: '
        'code=${error.code}, '
        'message=${error.message}, '
        'details=${error.details}, '
        'hint=${error.hint}',
      );
      final code = error.code;
      final msg = error.message.toLowerCase();
      if (code == '42501' || msg.contains('row-level security')) {
        return 'Access denied. You do not have permission for this action.';
      }
      if (code == 'PGRST301' ||
          msg.contains('jwt') ||
          msg.contains('expired') ||
          msg.contains('session')) {
        return 'Session expired. Please sign in again.';
      }
      return 'Database operation could not be completed. Please try again.';
    }

    if (error is sp.StorageException) {
      final status = error.statusCode;
      if (status == '403') {
        return 'Storage access denied. Your session may have expired.';
      }
      if (status == '413') {
        return 'File size is too large to upload.';
      }
      return 'Storage transfer failed. Please check your connection and retry.';
    }

    // Default fallback - never leak internal system stack traces
    return 'An unexpected error occurred. Please try again later.';
  }
}
