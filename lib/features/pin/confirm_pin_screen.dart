import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../app/providers.dart';
import '../../core/constants/app_constants.dart';
import '../../core/errors/error_mapper.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/privora_logo.dart';
import 'widgets/pin_keyboard.dart';

/// Screen where the user confirms their chosen 6-digit PIN and completes vault encryption setup.
class ConfirmPinScreen extends ConsumerStatefulWidget {
  final String originalPin;

  const ConfirmPinScreen({super.key, required this.originalPin});

  @override
  ConsumerState<ConfirmPinScreen> createState() => _ConfirmPinScreenState();
}

class _ConfirmPinScreenState extends ConsumerState<ConfirmPinScreen> {
  String _enteredPin = '';
  bool _hasError = false;
  String? _errorMessage;
  bool _isInitializing = false;

  void _onDigitPressed(String digit) {
    if (_enteredPin.length < AppConstants.pinLength && !_isInitializing) {
      setState(() {
        _hasError = false;
        _errorMessage = null;
        _enteredPin += digit;
      });

      if (_enteredPin.length == AppConstants.pinLength) {
        _verifyAndComplete();
      }
    }
  }

  void _onDeletePressed() {
    if (_enteredPin.isNotEmpty && !_isInitializing) {
      setState(() {
        _hasError = false;
        _errorMessage = null;
        _enteredPin = _enteredPin.substring(0, _enteredPin.length - 1);
      });
    }
  }

  Future<void> _verifyAndComplete() async {
    if (_enteredPin != widget.originalPin) {
      HapticFeedback.heavyImpact();
      setState(() {
        _hasError = true;
        _errorMessage = 'PINs do not match. Please try again.';
        _enteredPin = '';
      });
      return;
    }

    // PIN matches! Proceed to generate and wrap master key
    setState(() {
      _isInitializing = true;
    });

    try {
      final user = ref.read(currentUserProvider);
      if (user == null) {
        throw Exception('User session not found.');
      }

      final vaultRepo = ref.read(vaultRepositoryProvider);
      await vaultRepo.initializeNewVault(userId: user.id, pin: _enteredPin);

      ref.read(sessionLockServiceProvider.notifier).unlock();

      if (!mounted) return;
      context.go('/categories');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _hasError = true;
        _errorMessage = ErrorMapper.mapToUserMessage(e);
        _enteredPin = '';
        _isInitializing = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_isInitializing,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) {
          setState(() {
            _enteredPin = '';
          });
        }
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          leading: SizedBox(
            width: 48,
            height: 48,
            child: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
              tooltip: 'Back to Create PIN',
              onPressed: _isInitializing ? null : () => context.pop(),
            ),
          ),
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
                        const PrivoraLogo(size: 72),
                        const SizedBox(height: 24),
                        const Text(
                          'Confirm Your PIN',
                          style: AppTypography.displayMedium,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 40),
                          child: Text(
                            _errorMessage ??
                                'Re-enter the 6-digit PIN to confirm.',
                            style: AppTypography.bodyMedium.copyWith(
                              color: _hasError
                                  ? AppColors.danger
                                  : AppColors.secondaryText,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                        const SizedBox(height: 36),
                        if (_isInitializing) ...[
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
                          const SizedBox(height: 16),
                          Text(
                            'Generating 256-bit vault keys...',
                            style: AppTypography.bodySmall.copyWith(
                              color: AppColors.primaryAccent,
                            ),
                          ),
                        ] else ...[
                          PinDots(
                            length: _enteredPin.length,
                            hasError: _hasError,
                          ),
                        ],
                        const Spacer(flex: 2),
                        PinKeypad(
                          enabled: !_isInitializing,
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
