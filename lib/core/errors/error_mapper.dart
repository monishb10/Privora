import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart' as sp;
import 'app_exception.dart';

/// Centralized mapper to convert any error or exception into a safe, user-friendly message.
class ErrorMapper {
  ErrorMapper._();

  static String mapToUserMessage(dynamic error) {
    if (error is AppException) {
      return error.message;
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
      return 'Authentication failed. Please verify your credentials.';
    }

    if (error is sp.PostgrestException) {
      final code = error.code;
      if (code == '42501' || error.message.contains('row-level security')) {
        return 'Access denied. You do not have permission for this action.';
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
