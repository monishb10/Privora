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
    defaultValue: '',
  );

  /// Checks if Supabase is configured with valid non-placeholder values
  static bool get isConfigured {
    return supabaseUrl.isNotEmpty &&
        !supabaseUrl.contains('placeholder-project') &&
        supabaseAnonKey.isNotEmpty &&
        !supabaseAnonKey.contains('placeholder-anon-key');
  }
}
