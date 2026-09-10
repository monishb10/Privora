import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../app/providers.dart';
import '../../core/constants/app_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/confirmation_dialog.dart';
import 'widgets/pin_keyboard.dart';

/// Screen where the user initiates setting up a new 6-digit PIN.
class CreatePinScreen extends ConsumerStatefulWidget {
  const CreatePinScreen({super.key});

  @override
  ConsumerState<CreatePinScreen> createState() => _CreatePinScreenState();
}

class _CreatePinScreenState extends ConsumerState<CreatePinScreen> {
  String _enteredPin = '';

  void _onDigitPressed(String digit) {
    if (_enteredPin.length < AppConstants.pinLength) {
      setState(() {
        _enteredPin += digit;
      });

      if (_enteredPin.length == AppConstants.pinLength) {
        final pinToConfirm = _enteredPin;
        Future.delayed(const Duration(milliseconds: 150), () {
          if (!mounted) return;
          context.push('/confirm-pin', extra: pinToConfirm);
          setState(() {
            _enteredPin = '';
          });
        });
      }
    }
  }

  void _onDeletePressed() {
    if (_enteredPin.isNotEmpty) {
      setState(() {
        _enteredPin = _enteredPin.substring(0, _enteredPin.length - 1);
      });
    }
  }

  Future<void> _handleBackToLogin() async {
    final confirmed = await ConfirmationDialog.show(
      context: context,
      title: 'Cancel Setup?',
      message:
          'Are you sure you want to return to Google Login? Your vault setup will be cancelled.',
      confirmText: 'Return to Login',
      icon: Icons.logout_rounded,
    );
    if (confirmed == true && mounted) {
      final authRepo = ref.read(authRepositoryProvider);
      ref.invalidate(currentUserProvider);
      ref.invalidate(categoriesProvider);
      await authRepo.signOut();
      if (mounted) {
        context.go('/login');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        await _handleBackToLogin();
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          leading: SizedBox(
            width: 48,
            height: 48,
            child: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
              tooltip: 'Back to Login',
              onPressed: _handleBackToLogin,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => context.push('/recover-vault'),
              child: const Text('Recover Vault'),
            ),
          ],
        ),
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
                        const Spacer(flex: 1),
                        Container(
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            color: AppColors.softBlueSurface,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: AppColors.borderDivider,
                              width: 1,
                            ),
                          ),
                          child: const Center(
                            child: Icon(
                              Icons.lock_outline_rounded,
                              size: 26,
                              color: AppColors.primaryActionBlue,
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                        const Text(
                          'Create 6-Digit PIN',
                          style: AppTypography.displayMedium,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 40),
                          child: Text(
                            'Choose a 6-digit PIN to secure your private vault on this device.',
                            style: AppTypography.bodyMedium.copyWith(
                              color: AppColors.secondaryTextColor,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                        const SizedBox(height: 36),
                        PinDots(length: _enteredPin.length),
                        const Spacer(flex: 2),
                        PinKeypad(
                          onDigitPressed: _onDigitPressed,
                          onDeletePressed: _onDeletePressed,
                        ),
                        const SizedBox(height: 24),
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
