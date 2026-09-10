/// Application environment configuration populated via --dart-define flags.
class Environment {
  Environment._();

  /// Supabase Project URL
  static const String supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://crpglfjxrxnmfgssijcq.supabase.co',
  );

  /// Supabase Anonymous/Publishable Key (Never use the service-role key!)
  static const String supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: 'sb_publishable_qdgGSBhS8Dzi2Jl-XZgo4w_4mwsR9sl',
  );

  /// Flag to enable or hide Google Login
  static const bool enableGoogleLogin = bool.fromEnvironment(
    'ENABLE_GOOGLE_LOGIN',
    defaultValue: true,
  );

  /// Google Web OAuth Client ID used as serverClientId for native Google Sign-In.
  static const String googleWebClientId = String.fromEnvironment(
    'GOOGLE_WEB_CLIENT_ID',
    defaultValue:
        '724610060172-c1bf0dasha3cf3sbdpk7r18vb92u2bnv.apps.googleusercontent.com',
  );

  /// Validates the GOOGLE_WEB_CLIENT_ID according to strict requirements:
  /// - Reject empty value
  /// - Reject placeholder text such as WEB_CLIENT_ID, YOUR_, etc.
  /// - Require .apps.googleusercontent.com suffix
  /// Returns an error message if invalid, or null if valid.
  static String? validateGoogleWebClientId() {
    final clientId = googleWebClientId.trim();
    if (clientId.isEmpty) {
      return 'GOOGLE_WEB_CLIENT_ID is not configured. Supply your Web client ID via --dart-define=GOOGLE_WEB_CLIENT_ID=<id>.apps.googleusercontent.com';
    }
    final upper = clientId.toUpperCase();
    if (upper.contains('WEB_CLIENT_ID') ||
        upper.contains('YOUR_') ||
        upper.contains('PLACEHOLDER') ||
        upper.contains('<YOUR')) {
      return 'GOOGLE_WEB_CLIENT_ID contains placeholder text. Replace with your actual Web application Client ID.';
    }
    if (!clientId.endsWith('.apps.googleusercontent.com')) {
      return 'GOOGLE_WEB_CLIENT_ID must end in ".apps.googleusercontent.com". Ensure you are using the Web client ID, not the Android client ID.';
    }
    return null;
  }

  /// Whether GOOGLE_WEB_CLIENT_ID is present and formatted correctly
  static bool get isGoogleWebClientIdValid =>
      validateGoogleWebClientId() == null;

  /// Checks if Supabase is configured with valid non-placeholder values
  static bool get isConfigured {
    return supabaseUrl.isNotEmpty &&
        !supabaseUrl.contains('placeholder-project') &&
        supabaseAnonKey.isNotEmpty &&
        !supabaseAnonKey.contains('placeholder-anon-key');
  }
}
