import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:privora/app/app_lifecycle_observer.dart';
import 'package:privora/app/providers.dart';
import 'package:privora/core/security/pin_service.dart';
import 'package:privora/core/security/session_lock_service.dart';
import 'package:privora/core/security/temporary_file_cleaner.dart';

class FakePinService extends Fake implements PinService {
  bool lockSessionCalled = false;

  @override
  void lockSession() {
    lockSessionCalled = true;
  }
}

class FakeTemporaryFileCleaner extends Fake implements TemporaryFileCleaner {
  @override
  Future<void> cleanTemporaryFiles() async {}
}

void main() {
  group('Privora Security Flow & Session Lock Tests', () {
    late FakePinService fakePinService;
    late FakeTemporaryFileCleaner fakeCleaner;
    late ProviderContainer container;
    late SessionLockNotifier lockNotifier;

    setUp(() {
      fakePinService = FakePinService();
      fakeCleaner = FakeTemporaryFileCleaner();

      container = ProviderContainer(
        overrides: [
          pinServiceProvider.overrideWithValue(fakePinService),
          temporaryFileCleanerProvider.overrideWithValue(fakeCleaner),
        ],
      );

      lockNotifier = container.read(sessionLockServiceProvider.notifier);
    });

    tearDown(() {
      container.dispose();
    });

    test('1. Fresh / cold launch requests PIN (starts in locked state)', () {
      // Rule 5: On fresh/cold launch, app starts locked
      expect(lockNotifier.isLocked, isTrue);
      expect(container.read(sessionLockServiceProvider), isTrue);
    });

    test('2. Unlocking sets isLocked to false', () {
      lockNotifier.unlock();
      expect(lockNotifier.isLocked, isFalse);
      expect(container.read(sessionLockServiceProvider), isFalse);
    });

    test(
      '3. Notification panel / inactive state does NOT lock the app and records no timestamp',
      () {
        // Unlock app first
        lockNotifier.unlock();
        expect(lockNotifier.isLocked, isFalse);

        // Simulate notification panel pull-down or system overlay (inactive)
        lockNotifier.onAppInactive();

        // Rule 1 & 2: Must not lock on inactive state
        expect(lockNotifier.isLocked, isFalse);
        expect(lockNotifier.pausedAt, isNull);
        expect(fakePinService.lockSessionCalled, isFalse);
      },
    );

    test(
      '4. Short background duration (< 5 minutes) does NOT lock the app upon resume',
      () {
        // Unlock app
        lockNotifier.unlock();
        expect(lockNotifier.isLocked, isFalse);

        final t0 = DateTime(2026, 9, 6, 12, 0, 0);

        // App enters paused/background state
        lockNotifier.onAppPaused(t0);
        expect(lockNotifier.isLocked, isFalse);
        expect(lockNotifier.pausedAt, t0);

        // Resume after 30 seconds (e.g. quick app switch)
        lockNotifier.onAppResumed(t0.add(const Duration(seconds: 30)));
        expect(lockNotifier.isLocked, isFalse);
        expect(lockNotifier.pausedAt, isNull);
        expect(fakePinService.lockSessionCalled, isFalse);

        // Test again at 4 minutes 59 seconds (just under 5-minute threshold)
        lockNotifier.onAppPaused(t0);
        lockNotifier.onAppResumed(
          t0.add(const Duration(minutes: 4, seconds: 59)),
        );
        expect(lockNotifier.isLocked, isFalse);
        expect(lockNotifier.pausedAt, isNull);
        expect(fakePinService.lockSessionCalled, isFalse);
      },
    );

    test(
      '5. Background duration of 5 minutes or longer triggers lock upon resume',
      () async {
        // Unlock app
        lockNotifier.unlock();
        expect(lockNotifier.isLocked, isFalse);

        final t0 = DateTime(2026, 9, 6, 12, 0, 0);

        // App enters paused/background state
        lockNotifier.onAppPaused(t0);
        expect(lockNotifier.isLocked, isFalse);
        expect(lockNotifier.pausedAt, t0);

        // Resume at exactly 5 minutes (300 seconds)
        lockNotifier.onAppResumed(t0.add(const Duration(minutes: 5)));

        // Rule 4: Must lock when resumed after 5 minutes
        expect(lockNotifier.isLocked, isTrue);
        expect(lockNotifier.pausedAt, isNull);
        expect(fakePinService.lockSessionCalled, isTrue);
      },
    );

    test(
      '6. Extended background duration (e.g. 15 minutes) triggers lock upon resume',
      () async {
        lockNotifier.unlock();
        expect(lockNotifier.isLocked, isFalse);

        final t0 = DateTime(2026, 9, 6, 12, 0, 0);
        lockNotifier.onAppPaused(t0);

        // Resume after 15 minutes
        lockNotifier.onAppResumed(t0.add(const Duration(minutes: 15)));

        expect(lockNotifier.isLocked, isTrue);
        expect(lockNotifier.pausedAt, isNull);
      },
    );

    test('7. Lock icon (manual lock) locks the app immediately', () async {
      // Unlock app
      lockNotifier.unlock();
      expect(lockNotifier.isLocked, isFalse);

      // Rule 6: Lock icon must lock the app immediately
      await lockNotifier.lock();

      expect(lockNotifier.isLocked, isTrue);
      expect(fakePinService.lockSessionCalled, isTrue);
    });

    test(
      '8. AppLifecycleObserver dispatches inactive without locking, and paused/resumed correctly',
      () {
        lockNotifier.unlock();
        expect(lockNotifier.isLocked, isFalse);

        final observer = AppLifecycleObserver(lockNotifier);

        // Notification panel / system overlay
        observer.didChangeAppLifecycleState(AppLifecycleState.inactive);
        expect(lockNotifier.isLocked, isFalse);
        expect(lockNotifier.pausedAt, isNull);

        // Backgrounded
        observer.didChangeAppLifecycleState(AppLifecycleState.paused);
        expect(lockNotifier.isLocked, isFalse);
        expect(lockNotifier.pausedAt, isNotNull);

        // Immediate resume (< 5 minutes)
        observer.didChangeAppLifecycleState(AppLifecycleState.resumed);
        expect(lockNotifier.isLocked, isFalse);
        expect(lockNotifier.pausedAt, isNull);
      },
    );
  });
}
