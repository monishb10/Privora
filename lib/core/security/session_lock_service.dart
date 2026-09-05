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

  @override
  bool build() {
    _pinService = ref.watch(pinServiceProvider);
    _cleaner = ref.watch(temporaryFileCleanerProvider);
    return true; // initially locked
  }

  bool get isLocked => state;

  /// Registers a callback to clear in-memory photo caches
  void registerMemoryClearCallback(VoidCallback callback) {
    _onMemoryClearCallback = callback;
  }

  /// Locks the app immediately, evicts master key and in-memory photos
  Future<void> lock() async {
    if (state) return;

    state = true;
    _pinService.lockSession();
    _onMemoryClearCallback?.call();

    // Clean any temporary decrypted share/export files
    await _cleaner.cleanTemporaryFiles();
  }

  /// Unlocks the session once valid PIN has been verified
  void unlock() {
    state = false;
  }

  /// Resets lock state to locked upon logout
  void resetToLocked() {
    state = true;
    _pinService.lockSession();
    _onMemoryClearCallback?.call();
  }
}
