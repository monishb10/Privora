import 'package:flutter/material.dart';
import '../core/security/session_lock_service.dart';

/// Monitors application lifecycle and triggers immediate vault lock
/// when minimized, backgrounded, inactive, or when the screen turns off.
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
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
        debugPrint(
          'Privora: Lifecycle changed to $state -> Locking immediately.',
        );
        _sessionLockNotifier.lock();
        break;
      case AppLifecycleState.resumed:
      case AppLifecycleState.detached:
        break;
    }
  }
}
