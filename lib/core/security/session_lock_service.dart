import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/providers.dart';
import 'pin_service.dart';
import 'temporary_file_cleaner.dart';

/// Manages session locking, memory eviction, and lock state using Riverpod Notifier.
/// State is boolean: `true` = locked, `false` = unlocked.
class SessionLockNotifier extends Notifier<bool> {
  late final PinService _pinService;
  late final TemporaryFileCleaner _cleaner;
  VoidCallback? _onMemoryClearCallback;

  DateTime? _pausedAt;

  /// Background timeout duration before requiring PIN unlock again (5 minutes).
  static const Duration autoLockTimeout = Duration(minutes: 5);

  @override
  bool build() {
    _pinService = ref.watch(pinServiceProvider);
    _cleaner = ref.watch(temporaryFileCleanerProvider);
    return true; // initially locked (fresh/cold launch)
  }

  bool get isLocked => state;
  DateTime? get pausedAt => _pausedAt;

  /// Registers a callback to clear in-memory photo caches
  void registerMemoryClearCallback(VoidCallback callback) {
    _onMemoryClearCallback = callback;
  }

  /// Locks the app immediately, evicts master key and in-memory photos
  Future<void> lock() async {
    _pausedAt = null;
    if (state) return;

    state = true;
    _pinService.lockSession();
    _onMemoryClearCallback?.call();

    // Clean any temporary decrypted share/export files
    await _cleaner.cleanTemporaryFiles();
  }

  /// Unlocks the session once valid PIN has been verified
  void unlock() {
    _pausedAt = null;
    state = false;
  }

  /// Records timestamp when app enters paused/background state.
  /// Does NOT lock if the app was unlocked.
  void onAppPaused([DateTime? timestamp]) {
    if (!state && _pausedAt == null) {
      _pausedAt = timestamp ?? DateTime.now();
      debugPrint('Privora: App backgrounded/paused at $_pausedAt');
    }
  }

  /// Handles app resume. Evaluates whether background duration was 5 minutes or longer.
  /// Requests PIN (locks) only if background duration was >= 5 minutes.
  void onAppResumed([DateTime? currentTime]) {
    if (state) {
      _pausedAt = null;
      return;
    }

    if (_pausedAt != null) {
      final now = currentTime ?? DateTime.now();
      final difference = now.difference(_pausedAt!);
      debugPrint(
        'Privora: App resumed after ${difference.inSeconds}s (threshold: ${autoLockTimeout.inSeconds}s)',
      );
      if (difference >= autoLockTimeout) {
        lock();
      }
      _pausedAt = null;
    }
  }

  /// Explicitly does NOT lock on inactive state (e.g. notification panel, permission dialogs, system overlays)
  void onAppInactive() {
    debugPrint(
      'Privora: Inactive state ignored (notification panel / overlay)',
    );
  }

  /// Resets lock state to locked upon logout
  void resetToLocked() {
    _pausedAt = null;
    state = true;
    _pinService.lockSession();
    _onMemoryClearCallback?.call();
  }
}
