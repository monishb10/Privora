import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/providers.dart';
import '../../core/constants/app_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import 'widgets/pin_keyboard.dart';

enum ChangePinStep { enterCurrent, enterNew, confirmNew }

/// Screen allowing users to update their PIN, requiring current PIN verification.
class ChangePinScreen extends ConsumerStatefulWidget {
  const ChangePinScreen({super.key});

  @override
  ConsumerState<ChangePinScreen> createState() => _ChangePinScreenState();
}

class _ChangePinScreenState extends ConsumerState<ChangePinScreen> {
  ChangePinStep _step = ChangePinStep.enterCurrent;
  String _currentPin = '';
  String _newPin = '';
  String _confirmPin = '';
  String _activeDigits = '';

  bool _hasError = false;
  String? _errorMessage;
  bool _isLoading = false;

  void _onDigitPressed(String digit) {
    if (_activeDigits.length < AppConstants.pinLength && !_isLoading) {
      setState(() {
        _hasError = false;
        _errorMessage = null;
        _activeDigits += digit;
      });

      if (_activeDigits.length == AppConstants.pinLength) {
        _advanceStep();
      }
    }
  }

  void _onDeletePressed() {
    if (_activeDigits.isNotEmpty && !_isLoading) {
      setState(() {
        _hasError = false;
        _errorMessage = null;
        _activeDigits = _activeDigits.substring(0, _activeDigits.length - 1);
      });
    }
  }

  Future<void> _advanceStep() async {
    switch (_step) {
      case ChangePinStep.enterCurrent:
        _currentPin = _activeDigits;
        setState(() {
          _step = ChangePinStep.enterNew;
          _activeDigits = '';
        });
        break;

      case ChangePinStep.enterNew:
        _newPin = _activeDigits;
        setState(() {
          _step = ChangePinStep.confirmNew;
          _activeDigits = '';
        });
        break;

      case ChangePinStep.confirmNew:
        _confirmPin = _activeDigits;
        if (_newPin != _confirmPin) {
          HapticFeedback.heavyImpact();
          setState(() {
            _hasError = true;
            _errorMessage = 'New PINs do not match. Please re-enter.';
            _activeDigits = '';
            _step = ChangePinStep.enterNew;
          });
          return;
        }

        // Execute PIN change
        setState(() => _isLoading = true);
        try {
          final vaultRepo = ref.read(vaultRepositoryProvider);
          await vaultRepo.changePin(currentPin: _currentPin, newPin: _newPin);

          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('PIN updated successfully.')),
          );
          Navigator.of(context).pop();
        } catch (e) {
          if (!mounted) return;
          HapticFeedback.heavyImpact();
          setState(() {
            _hasError = true;
            _errorMessage = e.toString();
            _activeDigits = '';
            _step = ChangePinStep.enterCurrent;
            _isLoading = false;
          });
        }
        break;
    }
  }

  String get _title {
    switch (_step) {
      case ChangePinStep.enterCurrent:
        return 'Enter Current PIN';
      case ChangePinStep.enterNew:
        return 'Enter New PIN';
      case ChangePinStep.confirmNew:
        return 'Confirm New PIN';
    }
  }

  String get _subtitle {
    if (_errorMessage != null) return _errorMessage!;
    switch (_step) {
      case ChangePinStep.enterCurrent:
        return 'Verify your identity by entering your current 6-digit PIN.';
      case ChangePinStep.enterNew:
        return 'Choose your new 6-digit PIN.';
      case ChangePinStep.confirmNew:
        return 'Re-enter your new 6-digit PIN to confirm.';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Change PIN')),
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
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          color: AppColors.elevatedSurface,
                          shape: BoxShape.circle,
                          border: Border.all(color: AppColors.border),
                        ),
                        child: const Icon(
                          Icons.password_rounded,
                          size: 30,
                          color: AppColors.primaryAccent,
                        ),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        _title,
                        style: AppTypography.displayMedium,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 40),
                        child: Text(
                          _subtitle,
                          style: AppTypography.bodyMedium.copyWith(
                            color: _hasError
                                ? AppColors.danger
                                : AppColors.secondaryText,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      const SizedBox(height: 36),
                      if (_isLoading) ...[
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
                          length: _activeDigits.length,
                          hasError: _hasError,
                        ),
                      ],
                      const Spacer(flex: 2),
                      PinKeypad(
                        enabled: !_isLoading,
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
    );
  }
}
