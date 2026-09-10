import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/providers.dart';
import '../models/pending_import_context.dart';
import 'pin_service.dart';
import 'temporary_file_cleaner.dart';

/// Manages session locking, memory eviction, external activity tracking,
/// and pending import context preservation across lifecycle events.
/// State is boolean: `true` = locked, `false` = unlocked.
class SessionLockNotifier extends Notifier<bool> {
  late final PinService _pinService;
  late final TemporaryFileCleaner _cleaner;
  VoidCallback? _onMemoryClearCallback;

  DateTime? _pausedAt;
  bool _isExternalActivityActive = false;
  PendingImportContext? _pendingImportContext;

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
  bool get isExternalActivityActive => _isExternalActivityActive;
  PendingImportContext? get pendingImportContext => _pendingImportContext;

  /// Marks whether an external system activity (e.g. Gallery photo picker) is active.
  /// When active, lifecycle transitions (inactive/hidden/paused) must not drop
  /// the active import context or prematurely evict authentication.
  void markExternalActivityActive(bool active) {
    _isExternalActivityActive = active;
    debugPrint(
      'Privora: External activity active = $active (pendingContext: ${_pendingImportContext?.requestId})',
    );
  }

  /// Sets or updates the in-flight pending import context.
  void setPendingImportContext(PendingImportContext? context) {
    _pendingImportContext = context;
    debugPrint(
      'Privora: Saved pending import context: ${context?.requestId} '
      '(user: ${context?.userId}, category: ${context?.categoryId})',
    );
  }

  /// Clears the pending import context safely.
  void clearPendingImportContext() {
    debugPrint(
      'Privora: Cleared pending import context: ${_pendingImportContext?.requestId}',
    );
    _pendingImportContext = null;
  }

  /// Validates whether a pending import context matches the current user.
  /// If the user matches, returns the context.
  /// If user does not match, discards the context and returns null.
  PendingImportContext? getValidPendingImportForUser(String currentUserId) {
    if (_pendingImportContext == null) return null;
    if (_pendingImportContext!.userId == currentUserId) {
      return _pendingImportContext;
    } else {
      debugPrint(
        'Privora: User changed from ${_pendingImportContext!.userId} to $currentUserId. Discarding pending import.',
      );
      _pendingImportContext = null;
      return null;
    }
  }

  /// Registers a callback to clear in-memory photo caches
  void registerMemoryClearCallback(VoidCallback callback) {
    _onMemoryClearCallback = callback;
  }

  /// Locks the app immediately, evicts master key and in-memory photos.
  /// Preserves non-sensitive [_pendingImportContext] if an import is pending.
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
      debugPrint(
        'Privora: App backgrounded/paused at $_pausedAt (externalActivity: $_isExternalActivityActive)',
      );
    }
  }

  /// Handles app resume. Evaluates whether background duration was 5 minutes or longer.
  /// Requests PIN (locks) only if background duration was >= 5 minutes.
  /// When external activity was open, preserves pending import context.
  void onAppResumed([DateTime? currentTime]) {
    if (state) {
      _pausedAt = null;
      return;
    }

    if (_pausedAt != null) {
      final now = currentTime ?? DateTime.now();
      final difference = now.difference(_pausedAt!);
      debugPrint(
        'Privora: App resumed after ${difference.inSeconds}s '
        '(threshold: ${autoLockTimeout.inSeconds}s, externalActivity: $_isExternalActivityActive)',
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
      'Privora: Inactive state ignored (notification panel / overlay, externalActivity: $_isExternalActivityActive)',
    );
  }

  /// Resets lock state to locked upon logout and clears any pending import context
  void resetToLocked() {
    _pausedAt = null;
    _isExternalActivityActive = false;
    _pendingImportContext = null;
    state = true;
    _pinService.lockSession();
    _onMemoryClearCallback?.call();
  }
}
