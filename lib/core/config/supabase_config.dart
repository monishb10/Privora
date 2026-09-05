import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'environment.dart';

/// Manages Supabase client initialization and lifecycle.
class SupabaseConfig {
  SupabaseConfig._();

  static bool _isInitialized = false;
  static bool get isInitialized => _isInitialized;

  /// Initializes Supabase with client keys from environment
  static Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      if (Environment.isConfigured) {
        await Supabase.initialize(
          url: Environment.supabaseUrl,
          publishableKey: Environment.supabaseAnonKey,
          authOptions: const FlutterAuthClientOptions(
            authFlowType: AuthFlowType.pkce,
          ),
        );
        _isInitialized = true;
        debugPrint('Privora: Supabase initialized successfully.');
      } else {
        debugPrint(
          'Privora: Running with placeholder configuration. Provide SUPABASE_URL and SUPABASE_ANON_KEY via --dart-define.',
        );
      }
    } catch (e) {
      debugPrint('Privora: Error initializing Supabase: $e');
    }
  }

  /// Safe accessor for Supabase instance.
  static SupabaseClient? get client {
    if (_isInitialized) {
      try {
        return Supabase.instance.client;
      } catch (_) {
        return null;
      }
    }
    return null;
  }
}
