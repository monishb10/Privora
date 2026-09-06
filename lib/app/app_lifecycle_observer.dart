import 'package:flutter/material.dart';
import '../core/security/session_lock_service.dart';

/// Monitors application lifecycle and coordinates background timeout-based locking.
/// Rules:
/// - Inactive (notification panel, permission dialogs, system overlays) does NOT lock.
/// - Paused / hidden (backgrounded) records background timestamp.
/// - Resumed checks whether the app remained in background for 5 minutes or longer.
class AppLifecycleObserver with WidgetsBindingObserver {
  final SessionLockNotifier _sessionLockNotifier;

  AppLifecycleObserver(this._sessionLockNotifier);

  void initialize() {
    WidgetsBinding.instance.addObserver(this);
  }

  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    switch (state) {
      case AppLifecycleState.inactive:
        // Do NOT lock when notification panel, permission dialog, or system overlay appears
        debugPrint(
          'Privora: Lifecycle changed to inactive (notification shade / overlay) -> No lock.',
        );
        _sessionLockNotifier.onAppInactive();
        break;

      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        // Record background timestamp when entering background/minimized state
        debugPrint(
          'Privora: Lifecycle changed to $state -> Recording background timestamp.',
        );
        _sessionLockNotifier.onAppPaused();
        break;

      case AppLifecycleState.resumed:
        // When resuming, check if background duration was >= 5 minutes
        debugPrint(
          'Privora: Lifecycle changed to resumed -> Checking 5-minute timeout threshold.',
        );
        _sessionLockNotifier.onAppResumed();
        break;

      case AppLifecycleState.detached:
        break;
    }
  }
}
