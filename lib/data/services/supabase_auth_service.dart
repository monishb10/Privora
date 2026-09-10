import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sp;
import '../../core/config/environment.dart';
import '../../core/config/supabase_config.dart';
import '../../core/errors/app_exception.dart';
import '../../core/errors/error_mapper.dart';

/// Service managing Supabase authentication (Native Google Sign-In with IdToken, Email/Password).
class SupabaseAuthService {
  GoogleSignIn _googleSignIn;
  bool _isGoogleSignInRunning = false;

  SupabaseAuthService({GoogleSignIn? googleSignIn})
    : _googleSignIn =
          googleSignIn ??
          GoogleSignIn(
            serverClientId: Environment.googleWebClientId.isNotEmpty
                ? Environment.googleWebClientId
                : null,
            scopes: const ['email'],
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
      debugPrint(
        '[Auth] Google Sign-In already in progress, ignoring duplicate tap.',
      );
      return null;
    }

    // 1. Validate GOOGLE_WEB_CLIENT_ID before starting authentication flow
    final validationError = Environment.validateGoogleWebClientId();
    if (validationError != null) {
      debugPrint('[Auth] Google Sign-In configuration error: $validationError');
      throw AuthException(validationError);
    }

    _isGoogleSignInRunning = true;
    try {
      final webClientId = Environment.googleWebClientId;
      debugPrint(
        '[Auth] Initiating Google Sign-In with serverClientId audience: $webClientId',
      );

      // Ensure GoogleSignIn has the correct serverClientId and scopes
      if (_googleSignIn.serverClientId != webClientId) {
        _googleSignIn = GoogleSignIn(
          serverClientId: webClientId,
          scopes: const ['email'],
        );
      }

      // If an account is already cached locally, clear it so the account chooser appears
      if (_googleSignIn.currentUser != null) {
        try {
          await _googleSignIn.signOut();
        } catch (e) {
          debugPrint('[Auth] GoogleSignIn pre-sign-in signOut note: $e');
        }
      }

      // 2. Display native Android / iOS Google account chooser
      GoogleSignInAccount? googleUser;
      try {
        googleUser = await _googleSignIn.signIn().timeout(
          const Duration(seconds: 45),
          onTimeout: () {
            throw const AuthException(
              'Google Sign-In timed out. Please check your network and try again.',
            );
          },
        );
      } on PlatformException catch (pe) {
        debugPrint(
          '[Auth] GoogleSignIn.signIn PlatformException: '
          'code="${pe.code}", message="${pe.message}", details="${pe.details}"',
        );
        final mapped = mapGooglePlatformException(pe);
        if (mapped == null) {
          // User intentionally cancelled account picker
          debugPrint('[Auth] Google Sign-In cancelled by user.');
          return null;
        }
        throw AuthException(mapped);
      }

      // User cancelled account selection
      if (googleUser == null) {
        debugPrint('[Auth] Google account selection cancelled by user.');
        return null;
      }

      debugPrint('[Auth] Google account selected: ${googleUser.email}');

      // 3. Obtain Google ID token and access token
      GoogleSignInAuthentication googleAuth;
      try {
        googleAuth = await googleUser.authentication.timeout(
          const Duration(seconds: 30),
          onTimeout: () {
            throw const AuthException(
              'Obtaining Google credentials timed out. Please try again.',
            );
          },
        );
      } on PlatformException catch (pe) {
        debugPrint(
          '[Auth] googleUser.authentication PlatformException: '
          'code="${pe.code}", message="${pe.message}", details="${pe.details}"',
        );
        final mapped = mapGooglePlatformException(pe);
        if (mapped == null) return null;
        throw AuthException(mapped);
      }

      final idToken = googleAuth.idToken;
      final accessToken = googleAuth.accessToken;

      if (idToken == null || idToken.isEmpty) {
        debugPrint(
          '[Auth] Google authentication succeeded but returned null/empty idToken. '
          'serverClientId: $webClientId, '
          'hasAccessToken: ${accessToken != null && accessToken.isNotEmpty}, '
          'hasServerAuthCode: ${googleUser.serverAuthCode != null}',
        );

        throw const AuthException(
          'Google authentication did not return an ID token. '
          'Verify that GOOGLE_WEB_CLIENT_ID is your Google Web Application Client ID '
          'and that your Android client (com.monish.privora with SHA-1 '
          '07:30:40:FB:67:AD:72:4F:B5:FF:A4:D4:04:BE:C7:9C:3F:AA:A0:E2) '
          'is registered in the same Google Cloud Console project.',
        );
      }

      debugPrint(
        '[Auth] ID token obtained successfully. Exchanging with Supabase...',
      );

      // 4. Authenticate with Supabase using signInWithIdToken
      try {
        final response = await _client.auth.signInWithIdToken(
          provider: sp.OAuthProvider.google,
          idToken: idToken,
          accessToken: accessToken,
        );

        debugPrint(
          '[Auth] Supabase authentication successful. User ID: ${response.user?.id}',
        );
        return response;
      } on sp.AuthException catch (sae) {
        debugPrint(
          '[Auth] Supabase signInWithIdToken AuthException: '
          'message="${sae.message}", statusCode="${sae.statusCode}"',
        );
        final msg = sae.message.toLowerCase();
        if (msg.contains('provider') &&
            (msg.contains('disabled') || msg.contains('not enabled'))) {
          throw const AuthException(
            'Google provider is not enabled in your Supabase project. '
            'Please enable Google in Supabase Dashboard -> Authentication -> Providers.',
          );
        }
        if (msg.contains('unauthorized') ||
            msg.contains('audience') ||
            msg.contains('client id')) {
          throw AuthException(
            'Supabase rejected the Google ID token. In Supabase Dashboard -> Authentication -> Providers -> Google, '
            'ensure Client ID is set to "$webClientId" and Authorized Client IDs contains both Web and Android Client IDs.',
          );
        }
        throw AuthException('Supabase login failed: ${sae.message}');
      }
    } on AuthException {
      rethrow;
    } catch (e, stack) {
      debugPrint('[Auth] Unexpected Google Sign In error: $e\n$stack');
      throw AuthException(ErrorMapper.mapToUserMessage(e));
    } finally {
      _isGoogleSignInRunning = false;
    }
  }

  /// Maps Google Sign-In PlatformExceptions to clear, actionable messages or null for user cancellation
  @visibleForTesting
  static String? mapGooglePlatformException(PlatformException pe) {
    final code = pe.code.toLowerCase();
    final message = (pe.message ?? '').toLowerCase();
    final details = pe.details?.toString().toLowerCase() ?? '';
    final combined = '$code $message $details';

    // User cancellation - return null quietly
    if (combined.contains('sign_in_canceled') ||
        combined.contains('sign_in_cancelled') ||
        combined.contains('canceled') ||
        combined.contains('cancelled') ||
        combined.contains('12501')) {
      return null;
    }

    // ApiException 10: DEVELOPER_ERROR
    if (combined.contains('10') &&
        (combined.contains('apiexception') ||
            combined.contains('developer_error') ||
            combined.contains(': 10'))) {
      return 'Google Sign-In configuration error (ApiException 10: DEVELOPER_ERROR). '
          'Ensure package name "com.monish.privora" and debug SHA-1 '
          '07:30:40:FB:67:AD:72:4F:B5:FF:A4:D4:04:BE:C7:9C:3F:AA:A0:E2 are registered '
          'in Google Cloud Console under an Android OAuth 2.0 Client.';
    }

    // ApiException 12500: SIGN_IN_FAILED
    if (combined.contains('12500')) {
      return 'Google Sign-In failed (ApiException 12500). '
          'Please verify that your Google Cloud OAuth consent screen is configured '
          'and Google Play Services is up to date.';
    }

    // Network error
    if (combined.contains('network_error') ||
        combined.contains('7:') ||
        combined.contains('network error')) {
      return 'Google Sign-In network error. Please check your internet connection and retry.';
    }

    if (pe.message != null && pe.message!.trim().isNotEmpty) {
      return 'Google Sign-In failed: ${pe.message}';
    }

    return 'Google Sign-In failed. Please try again.';
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
  Future<void> signOut() async {
    // 1. Sign out of Google independently with bounded wait
    try {
      await _googleSignIn.signOut().timeout(const Duration(seconds: 5));
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
