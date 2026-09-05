import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app/app.dart';
import 'core/config/supabase_config.dart';
import 'core/security/temporary_file_cleaner.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Enforce portrait orientation for mobile-only experience
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Clean any temporary media leftovers from prior sessions or unexpected terminations
  final cleaner = TemporaryFileCleaner();
  await cleaner.cleanTemporaryFiles();

  // Initialize Supabase client
  await SupabaseConfig.initialize();

  runApp(const ProviderScope(child: PrivoraApp()));
}
