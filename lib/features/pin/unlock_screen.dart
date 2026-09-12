import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../app/providers.dart';
import '../../core/config/supabase_config.dart';
import '../../core/constants/app_constants.dart';
import '../../core/errors/app_exception.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/confirmation_dialog.dart';
import '../gallery/import_photo_screen.dart';
import 'widgets/pin_keyboard.dart';

/// Everyday application unlock screen.
/// Requires 6-digit PIN. Strictly isolates biometric bypasses.
class UnlockScreen extends ConsumerStatefulWidget {
  const UnlockScreen({super.key});

  @override
  ConsumerState<UnlockScreen> createState() => _UnlockScreenState();
}

class _UnlockScreenState extends ConsumerState<UnlockScreen> {
  String _enteredPin = '';
  bool _hasError = false;
  String? _errorMessage;
  bool _isVerifying = false;

  int _lockoutSecondsRemaining = 0;
  Timer? _lockoutTimer;

  @override
  void initState() {
    super.initState();
    _checkLockoutStatus();
  }

  @override
  void dispose() {
    _lockoutTimer?.cancel();
    super.dispose();
  }

  Future<void> _checkLockoutStatus() async {
    final secureStorage = ref.read(secureKeyServiceProvider);
    final lockoutUntil = await secureStorage.getLockoutUntil();
    if (lockoutUntil != null && DateTime.now().isBefore(lockoutUntil)) {
      final remaining = lockoutUntil.difference(DateTime.now()).inSeconds + 1;
      _startLockoutCountdown(remaining);
    }
  }

  void _startLockoutCountdown(int seconds) {
    setState(() {
      _lockoutSecondsRemaining = seconds;
      _errorMessage = 'Too many failed attempts. Locked for $seconds seconds.';
    });

    _lockoutTimer?.cancel();
    _lockoutTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      if (_lockoutSecondsRemaining <= 1) {
        timer.cancel();
        setState(() {
          _lockoutSecondsRemaining = 0;
          _errorMessage = null;
          _hasError = false;
        });
      } else {
        setState(() {
          _lockoutSecondsRemaining--;
          _errorMessage =
              'Too many failed attempts. Locked for $_lockoutSecondsRemaining seconds.';
        });
      }
    });
  }

  void _onDigitPressed(String digit) {
    if (_lockoutSecondsRemaining > 0 || _isVerifying) return;

    if (_enteredPin.length < AppConstants.pinLength) {
      setState(() {
        _hasError = false;
        _errorMessage = null;
        _enteredPin += digit;
      });

      if (_enteredPin.length == AppConstants.pinLength) {
        _verifyPin();
      }
    }
  }

  void _onDeletePressed() {
    if (_lockoutSecondsRemaining > 0 || _isVerifying) return;

    if (_enteredPin.isNotEmpty) {
      setState(() {
        _hasError = false;
        _errorMessage = null;
        _enteredPin = _enteredPin.substring(0, _enteredPin.length - 1);
      });
    }
  }

  Future<void> _verifyPin() async {
    setState(() {
      _isVerifying = true;
    });

    try {
      final user =
          ref.read(currentUserProvider) ??
          SupabaseConfig.client?.auth.currentUser;
      final vaultRepo = ref.read(vaultRepositoryProvider);
      final isValid = await vaultRepo.verifyAndUnlock(
        _enteredPin,
        userId: user?.id,
      );

      if (!mounted) return;

      if (isValid) {
        final lockNotifier = ref.read(sessionLockServiceProvider.notifier);
        lockNotifier.unlock();
        ref.read(categoryRepositoryProvider).clearCache(user?.id);
        ref.invalidate(categoriesProvider);

        final pendingImport = user?.id != null
            ? lockNotifier.getValidPendingImportForUser(user!.id)
            : null;

        context.go('/categories');

        if (pendingImport != null &&
            pendingImport.tempFilePaths.isNotEmpty &&
            mounted) {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => ImportPhotoScreen(
                categoryId: pendingImport.categoryId,
                categoryName: pendingImport.categoryName,
              ),
            ),
          );
        }
      } else {
        HapticFeedback.heavyImpact();
        setState(() {
          _hasError = true;
          _errorMessage = 'Incorrect PIN. Please try again.';
          _enteredPin = '';
        });
      }
    } on PinLockoutException catch (e) {
      HapticFeedback.heavyImpact();
      _enteredPin = '';
      _startLockoutCountdown(e.remainingSeconds);
    } catch (e) {
      HapticFeedback.heavyImpact();
      setState(() {
        _hasError = true;
        _errorMessage = e.toString();
        _enteredPin = '';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isVerifying = false;
        });
      }
    }
  }

  Future<void> _handleBackToLogin() async {
    final confirmed = await ConfirmationDialog.show(
      context: context,
      title: 'Sign Out?',
      message:
          'Are you sure you want to return to Google Login? You will need to sign in again to access your private vault.',
      confirmText: 'Sign Out',
      icon: Icons.logout_rounded,
    );
    if (confirmed == true && mounted) {
      await ref.read(authRepositoryProvider).signOut();
      ref.read(categoryRepositoryProvider).clearCache();
      ref.invalidate(currentUserProvider);
      ref.invalidate(categoriesProvider);
      ref.invalidate(recentlyDeletedPhotosProvider);
      ref.invalidate(storageUsageProvider);
      if (mounted) {
        context.go('/login');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLockedOut = _lockoutSecondsRemaining > 0;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        await _handleBackToLogin();
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                physics: const ClampingScrollPhysics(),
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: IntrinsicHeight(
                    child: Column(
                      children: [
                        // Top actions
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          child: Row(
                            children: [
                              TextButton.icon(
                                icon: const Icon(
                                  Icons.arrow_back_ios_new_rounded,
                                  size: 16,
                                ),
                                label: const Text('Back to Login'),
                                style: TextButton.styleFrom(
                                  foregroundColor: AppColors.secondaryTextColor,
                                  minimumSize: const Size(48, 48),
                                ),
                                onPressed: _handleBackToLogin,
                              ),
                            ],
                          ),
                        ),
                        const Spacer(flex: 1),
                        Container(
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            color: isLockedOut
                                ? AppColors.errorDestructive.withValues(
                                    alpha: 0.1,
                                  )
                                : AppColors.softBlueSurface,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: isLockedOut
                                  ? AppColors.errorDestructive
                                  : AppColors.borderDivider,
                              width: 1,
                            ),
                          ),
                          child: Center(
                            child: Icon(
                              isLockedOut
                                  ? Icons.lock_clock_outlined
                                  : Icons.lock_outline_rounded,
                              size: 26,
                              color: isLockedOut
                                  ? AppColors.errorDestructive
                                  : AppColors.primaryActionBlue,
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                        const Text(
                          'Enter 6-Digit PIN',
                          style: AppTypography.displayMedium,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 32),
                          child: Text(
                            _errorMessage ??
                                'Enter your PIN to unlock your encrypted photos.',
                            style: AppTypography.bodyMedium.copyWith(
                              color: _hasError || isLockedOut
                                  ? AppColors.errorDestructive
                                  : AppColors.secondaryTextColor,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                        const SizedBox(height: 36),
                        if (_isVerifying) ...[
                          const SizedBox(
                            width: 32,
                            height: 32,
                            child: CircularProgressIndicator(
                              strokeWidth: 3,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                AppColors.primaryAccent,
                              ),
                            ),
                          ),
                        ] else ...[
                          PinDots(
                            length: _enteredPin.length,
                            hasError: _hasError || isLockedOut,
                          ),
                        ],
                        const Spacer(flex: 2),
                        PinKeypad(
                          enabled: !isLockedOut && !_isVerifying,
                          onDigitPressed: _onDigitPressed,
                          onDeletePressed: _onDeletePressed,
                        ),
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed:
                              (_lockoutSecondsRemaining > 0 || _isVerifying)
                              ? null
                              : () => context.push('/forgot-pin'),
                          child: Text(
                            'Forgot PIN? Reset with Gmail code',
                            style: AppTypography.labelMedium.copyWith(
                              color: AppColors.primaryActionBlue,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
