import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/constants/app_constants.dart';
import '../core/theme/app_theme.dart';
import 'app_lifecycle_observer.dart';
import 'providers.dart';
import 'router.dart';

/// Root application widget for Privora.
class PrivoraApp extends ConsumerStatefulWidget {
  const PrivoraApp({super.key});

  @override
  ConsumerState<PrivoraApp> createState() => _PrivoraAppState();
}

class _PrivoraAppState extends ConsumerState<PrivoraApp> {
  late AppLifecycleObserver _lifecycleObserver;

  @override
  void initState() {
    super.initState();
    final lockService = ref.read(sessionLockServiceProvider.notifier);
    _lifecycleObserver = AppLifecycleObserver(lockService);
    _lifecycleObserver.initialize();
  }

  @override
  void dispose() {
    _lifecycleObserver.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(routerProvider);

    // Auto-lock listener: when app becomes locked, navigate to unlock if session exists
    ref.listen<bool>(sessionLockServiceProvider, (previous, isLocked) {
      if (isLocked && previous == false) {
        final user = ref.read(currentUserProvider);
        if (user != null) {
          router.go('/unlock');
        }
      }
    });

    return MaterialApp.router(
      title: AppConstants.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      routerConfig: router,
    );
  }
}
