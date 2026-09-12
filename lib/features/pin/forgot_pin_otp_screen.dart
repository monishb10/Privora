import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../app/providers.dart';
import '../../core/config/supabase_config.dart';
import '../../core/constants/app_constants.dart';
import '../../core/errors/error_mapper.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_motion.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/privora_button.dart';
import '../../core/widgets/privora_logo.dart';
import 'widgets/pin_keyboard.dart';

enum _PinResetStep { requestCode, verifyCode, createPin, confirmPin }

/// Forgot-PIN flow tied to the email address of the currently authenticated
/// Google account. The user cannot type or substitute a different address.
class ForgotPinOtpScreen extends ConsumerStatefulWidget {
  const ForgotPinOtpScreen({super.key});

  @override
  ConsumerState<ForgotPinOtpScreen> createState() => _ForgotPinOtpScreenState();
}

class _ForgotPinOtpScreenState extends ConsumerState<ForgotPinOtpScreen> {
  _PinResetStep _step = _PinResetStep.requestCode;
  String _digits = '';
  String _newPin = '';
  String _userId = '';
  String _email = '';
  String? _errorMessage;
  bool _isBusy = false;
  int _resendSeconds = 0;
  Timer? _resendTimer;

  @override
  void initState() {
    super.initState();
    final user =
        ref.read(currentUserProvider) ??
        SupabaseConfig.client?.auth.currentUser;
    _userId = user?.id ?? '';
    _email = user?.email ?? '';

    if (_userId.isEmpty || _email.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) context.go('/login');
      });
    }
  }

  @override
  void dispose() {
    _resendTimer?.cancel();
    super.dispose();
  }

  String get _maskedEmail {
    final parts = _email.split('@');
    if (parts.length != 2 || parts.first.isEmpty) return _email;
    final name = parts.first;
    final visible = name.length <= 2
        ? name.substring(0, 1)
        : '${name.substring(0, 1)}${List.filled(name.length - 2, '*').join()}${name.substring(name.length - 1)}';
    return '$visible@${parts.last}';
  }

  void _startResendTimer() {
    _resendTimer?.cancel();
    setState(() => _resendSeconds = 60);
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      if (_resendSeconds <= 1) {
        timer.cancel();
        setState(() => _resendSeconds = 0);
      } else {
        setState(() => _resendSeconds--);
      }
    });
  }

  Future<void> _sendCode() async {
    if (_isBusy || _resendSeconds > 0 || _email.isEmpty) return;
    setState(() {
      _isBusy = true;
      _errorMessage = null;
    });

    try {
      await ref.read(authRepositoryProvider).sendPinResetOtp(_email);
      if (!mounted) return;
      setState(() {
        _step = _PinResetStep.verifyCode;
        _digits = '';
      });
      _startResendTimer();
    } catch (error) {
      if (!mounted) return;
      setState(() => _errorMessage = ErrorMapper.mapToUserMessage(error));
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  void _onDigitPressed(String digit) {
    if (_isBusy || _digits.length >= AppConstants.pinLength) return;
    setState(() {
      _errorMessage = null;
      _digits += digit;
    });

    if (_digits.length != AppConstants.pinLength) return;
    switch (_step) {
      case _PinResetStep.verifyCode:
        _verifyCode();
        break;
      case _PinResetStep.createPin:
        _newPin = _digits;
        Future<void>.delayed(const Duration(milliseconds: 140), () {
          if (!mounted) return;
          setState(() {
            _step = _PinResetStep.confirmPin;
            _digits = '';
          });
        });
        break;
      case _PinResetStep.confirmPin:
        _completeReset();
        break;
      case _PinResetStep.requestCode:
        break;
    }
  }

  void _onDeletePressed() {
    if (_isBusy || _digits.isEmpty) return;
    setState(() {
      _errorMessage = null;
      _digits = _digits.substring(0, _digits.length - 1);
    });
  }

  Future<void> _verifyCode() async {
    if (_isBusy) return;
    setState(() => _isBusy = true);
    try {
      await ref
          .read(authRepositoryProvider)
          .verifyPinResetOtp(
            email: _email,
            token: _digits,
            expectedUserId: _userId,
          );
      if (!mounted) return;
      setState(() {
        _step = _PinResetStep.createPin;
        _digits = '';
        _errorMessage = null;
      });
    } catch (error) {
      if (!mounted) return;
      HapticFeedback.heavyImpact();
      setState(() {
        _digits = '';
        _errorMessage = ErrorMapper.mapToUserMessage(error);
      });
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _completeReset() async {
    if (_isBusy) return;
    if (_digits != _newPin) {
      HapticFeedback.heavyImpact();
      setState(() {
        _step = _PinResetStep.createPin;
        _digits = '';
        _newPin = '';
        _errorMessage = 'PINs did not match. Create the new PIN again.';
      });
      return;
    }

    setState(() => _isBusy = true);
    try {
      await ref
          .read(vaultRepositoryProvider)
          .resetPinAfterEmailOtp(userId: _userId, newPin: _newPin);
      ref.read(sessionLockServiceProvider.notifier).unlock();
      ref.read(categoryRepositoryProvider).clearCache(_userId);
      ref.invalidate(categoriesProvider);
      ref.invalidate(storageUsageProvider);
      ref.invalidate(recentlyDeletedPhotosProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('PIN changed successfully.')),
      );
      context.go('/categories');
    } catch (error) {
      if (!mounted) return;
      HapticFeedback.heavyImpact();
      setState(() {
        _step = _PinResetStep.createPin;
        _digits = '';
        _newPin = '';
        _errorMessage = ErrorMapper.mapToUserMessage(error);
      });
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  void _handleBack() {
    if (_isBusy) return;
    switch (_step) {
      case _PinResetStep.confirmPin:
        setState(() {
          _step = _PinResetStep.createPin;
          _digits = '';
          _newPin = '';
          _errorMessage = null;
        });
        break;
      case _PinResetStep.verifyCode:
      case _PinResetStep.createPin:
        setState(() {
          _step = _PinResetStep.requestCode;
          _digits = '';
          _newPin = '';
          _errorMessage = null;
        });
        break;
      case _PinResetStep.requestCode:
        context.go('/unlock');
        break;
    }
  }

  String get _title {
    switch (_step) {
      case _PinResetStep.requestCode:
        return 'Reset Your PIN';
      case _PinResetStep.verifyCode:
        return 'Enter Gmail Code';
      case _PinResetStep.createPin:
        return 'Create New PIN';
      case _PinResetStep.confirmPin:
        return 'Confirm New PIN';
    }
  }

  String get _subtitle {
    if (_errorMessage != null) return _errorMessage!;
    switch (_step) {
      case _PinResetStep.requestCode:
        return 'Privora will send a 6-digit verification code to $_maskedEmail.';
      case _PinResetStep.verifyCode:
        return 'Enter the 6-digit code sent to $_maskedEmail.';
      case _PinResetStep.createPin:
        return 'Choose a new 6-digit PIN for this Google account.';
      case _PinResetStep.confirmPin:
        return 'Enter the same new PIN one more time.';
    }
  }

  @override
  Widget build(BuildContext context) {
    final showKeypad = _step != _PinResetStep.requestCode;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _handleBack();
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          title: const Text('Gmail PIN Reset'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
            tooltip: 'Back',
            onPressed: _isBusy ? null : _handleBack,
          ),
        ),
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                physics: const ClampingScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: IntrinsicHeight(
                    child: PrivoraFadeIn(
                      child: Column(
                        children: [
                          const Spacer(),
                          const PrivoraLogo(size: 68),
                          const SizedBox(height: 22),
                          Text(
                            _title,
                            style: AppTypography.displayMedium,
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 10),
                          Text(
                            _subtitle,
                            style: AppTypography.bodyMedium.copyWith(
                              color: _errorMessage == null
                                  ? AppColors.secondaryTextColor
                                  : AppColors.errorDestructive,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 28),
                          if (_step == _PinResetStep.requestCode) ...[
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: AppColors.cardSurface,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: AppColors.borderDivider,
                                ),
                              ),
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.mark_email_read_outlined,
                                    color: AppColors.primaryActionBlue,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      _maskedEmail,
                                      style: AppTypography.bodyMedium.copyWith(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 20),
                            PrivoraButton(
                              text: 'Send 6-Digit Code',
                              leadingIcon: Icons.mail_outline_rounded,
                              isLoading: _isBusy,
                              onPressed: _resendSeconds == 0 ? _sendCode : null,
                            ),
                          ] else ...[
                            if (_isBusy)
                              const SizedBox(
                                width: 32,
                                height: 32,
                                child: CircularProgressIndicator(
                                  strokeWidth: 3,
                                ),
                              )
                            else
                              PinDots(
                                length: _digits.length,
                                hasError: _errorMessage != null,
                              ),
                          ],
                          const Spacer(flex: 2),
                          if (showKeypad) ...[
                            PinKeypad(
                              enabled: !_isBusy,
                              onDigitPressed: _onDigitPressed,
                              onDeletePressed: _onDeletePressed,
                            ),
                            if (_step == _PinResetStep.verifyCode)
                              TextButton(
                                onPressed: _isBusy || _resendSeconds > 0
                                    ? null
                                    : _sendCode,
                                child: Text(
                                  _resendSeconds > 0
                                      ? 'Resend code in ${_resendSeconds}s'
                                      : 'Resend Gmail code',
                                ),
                              )
                            else
                              const SizedBox(height: 12),
                          ],
                          const SizedBox(height: 16),
                        ],
                      ),
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
