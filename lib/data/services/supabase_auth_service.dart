import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sp;
import '../../core/config/environment.dart';
import '../../core/config/supabase_config.dart';
import '../../core/errors/app_exception.dart';
import '../../core/errors/error_mapper.dart';

/// Service managing Supabase authentication (Native Google Sign-In with IdToken, Email/Password).
class SupabaseAuthService {
  final GoogleSignIn _googleSignIn;
  bool _isGoogleSignInRunning = false;

  SupabaseAuthService({GoogleSignIn? googleSignIn})
    : _googleSignIn =
          googleSignIn ??
          GoogleSignIn(
            serverClientId: Environment.googleWebClientId.isNotEmpty
                ? Environment.googleWebClientId
                : null,
            scopes: const ['email', 'profile', 'openid'],
          );

  GoogleSignIn get googleSignIn => _googleSignIn;

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

  /// Sign up with email, password, and display name (preserved for fallback recovery)
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

  /// Sign in with email and password (preserved for fallback recovery)
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

  /// Sign in with Google using native GoogleSignIn and exchange idToken with Supabase.
  /// Returns null if user cancelled the account selection.
  Future<sp.AuthResponse?> signInWithGoogle() async {
    if (_isGoogleSignInRunning) {
      return null;
    }

    _isGoogleSignInRunning = true;
    try {
      // 1. Display native Android / iOS Google account chooser
      final googleUser = await _googleSignIn.signIn().timeout(
        const Duration(seconds: 45),
        onTimeout: () {
          throw const AuthException(
            'Google Sign-In timed out. Please check your network and try again.',
          );
        },
      );

      // User cancelled account selection
      if (googleUser == null) {
        return null;
      }

      // 2. Obtain Google ID token
      final googleAuth = await googleUser.authentication.timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          throw const AuthException(
            'Obtaining Google credentials timed out. Please try again.',
          );
        },
      );

      final idToken = googleAuth.idToken;
      if (idToken == null || idToken.isEmpty) {
        throw const AuthException(
          'Failed to retrieve Google authentication token. Please ensure Google Play Services is available.',
        );
      }

      // 3. Authenticate with Supabase using signInWithIdToken
      final response = await _client.auth.signInWithIdToken(
        provider: sp.OAuthProvider.google,
        idToken: idToken,
        accessToken: googleAuth.accessToken,
      );

      return response;
    } catch (e) {
      if (e is AuthException) rethrow;
      debugPrint('Google Sign In error: $e');
      throw AuthException(ErrorMapper.mapToUserMessage(e));
    } finally {
      _isGoogleSignInRunning = false;
    }
  }

  /// Send password reset email (preserved)
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

  /// Signs out of Google and Supabase independently with bounded waits.
  /// Uses disconnect() so the next login allows account selection rather than
  /// silently reusing the previous account.
  Future<void> signOut() async {
    // 1. Sign out of Google independently with bounded wait
    try {
      await _googleSignIn.signOut().timeout(const Duration(seconds: 5));
      try {
        await _googleSignIn.disconnect().timeout(const Duration(seconds: 5));
      } catch (discErr) {
        debugPrint('Google disconnect note: $discErr');
      }
    } catch (e) {
      debugPrint('Google signOut warning: $e');
    }

    // 2. Sign out of Supabase independently with bounded wait
    try {
      if (SupabaseConfig.client != null) {
        await _client.auth.signOut().timeout(const Duration(seconds: 5));
      }
    } catch (e) {
      debugPrint('Supabase signOut error: $e');
    }
  }
}
