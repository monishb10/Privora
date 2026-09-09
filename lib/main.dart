import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app/app.dart';
import 'core/config/supabase_config.dart';
import 'core/security/temporary_file_cleaner.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Register Manrope OFL license
  LicenseRegistry.addLicense(() async* {
    final license = await rootBundle.loadString('assets/fonts/OFL.txt');
    yield LicenseEntryWithLineBreaks(['manrope'], license);
  });

  // Enforce portrait orientation for mobile-only experience
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      statusBarBrightness: Brightness.light,
      systemNavigationBarColor: Color(0xFFF7FCFF),
      systemNavigationBarIconBrightness: Brightness.dark,
    ),
  );

  // Clean any temporary media leftovers from prior sessions or unexpected terminations
  final cleaner = TemporaryFileCleaner();
  await cleaner.cleanTemporaryFiles();

  // Initialize Supabase client
  await SupabaseConfig.initialize();

  runApp(const ProviderScope(child: PrivoraApp()));
}
