import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sp;
import '../../core/config/environment.dart';
import '../../core/config/supabase_config.dart';
import '../../core/errors/app_exception.dart';
import '../../core/errors/error_mapper.dart';

/// Service managing Supabase authentication (Email/Password, Google OAuth).
class SupabaseAuthService {
  sp.SupabaseClient get _client {
    final client = SupabaseConfig.client;
    if (client == null) {
      throw const AuthException(
        'Supabase is not configured. Please supply SUPABASE_URL and SUPABASE_ANON_KEY.',
      );
    }
    return client;
  }

  sp.User? get currentUser => SupabaseConfig.client?.auth.currentUser;
  sp.Session? get currentSession => SupabaseConfig.client?.auth.currentSession;
  bool get isAuthenticated => currentUser != null;

  Stream<sp.AuthState> get authStateChanges {
    final client = SupabaseConfig.client;
    if (client == null) return const Stream.empty();
    return client.auth.onAuthStateChange;
  }

  /// Sign up with email, password, and display name
  Future<sp.AuthResponse> signUp({
    required String email,
    required String password,
    String? displayName,
  }) async {
    try {
      final response = await _client.auth.signUp(
        email: email.trim(),
        password: password,
        data: {
          if (displayName != null && displayName.isNotEmpty)
            'display_name': displayName.trim(),
        },
      );
      return response;
    } catch (e) {
      debugPrint('SignUp error: $e');
      throw AuthException(ErrorMapper.mapToUserMessage(e));
    }
  }

  /// Sign in with email and password
  Future<sp.AuthResponse> signIn({
    required String email,
    required String password,
  }) async {
    try {
      final response = await _client.auth.signInWithPassword(
        email: email.trim(),
        password: password,
      );
      return response;
    } catch (e) {
      debugPrint('SignIn error: $e');
      throw AuthException(ErrorMapper.mapToUserMessage(e));
    }
  }

  /// Sign in with Google OAuth using PKCE flow
  Future<bool> signInWithGoogle() async {
    if (!Environment.enableGoogleLogin) {
      throw const AuthException(
        'Google login is not enabled in this configuration.',
      );
    }
    try {
      return await _client.auth.signInWithOAuth(
        sp.OAuthProvider.google,
        redirectTo: 'com.monish.privora://login-callback',
      );
    } catch (e) {
      debugPrint('Google Sign In error: $e');
      throw AuthException(ErrorMapper.mapToUserMessage(e));
    }
  }

  /// Send password reset email
  Future<void> sendPasswordResetEmail(String email) async {
    try {
      await _client.auth.resetPasswordForEmail(
        email.trim(),
        redirectTo: 'com.monish.privora://reset-callback',
      );
    } catch (e) {
      debugPrint('Password reset error: $e');
      throw AuthException(ErrorMapper.mapToUserMessage(e));
    }
  }

  /// Sign out current session
  Future<void> signOut() async {
    try {
      if (SupabaseConfig.client != null) {
        await _client.auth.signOut();
      }
    } catch (e) {
      debugPrint('SignOut error: $e');
    }
  }
}
