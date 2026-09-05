/// Application environment configuration populated via --dart-define flags.
class Environment {
  Environment._();

  /// Supabase Project URL
  static const String supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://placeholder-project.supabase.co',
  );

  /// Supabase Anonymous/Publishable Key (Never use the service-role key!)
  static const String supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.placeholder-anon-key',
  );

  /// Flag to enable or hide Google Login
  static const bool enableGoogleLogin = bool.fromEnvironment(
    'ENABLE_GOOGLE_LOGIN',
    defaultValue: false,
  );

  /// Checks if Supabase is configured with valid non-placeholder values
  static bool get isConfigured {
    return supabaseUrl.isNotEmpty &&
        !supabaseUrl.contains('placeholder-project') &&
        supabaseAnonKey.isNotEmpty &&
        !supabaseAnonKey.contains('placeholder-anon-key');
  }
}
