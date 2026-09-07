import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/constants/app_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/privora_logo.dart';
import 'widgets/pin_keyboard.dart';

/// Screen where the user initiates setting up a new 6-digit PIN.
class CreatePinScreen extends StatefulWidget {
  const CreatePinScreen({super.key});

  @override
  State<CreatePinScreen> createState() => _CreatePinScreenState();
}

class _CreatePinScreenState extends State<CreatePinScreen> {
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
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
                      const PrivoraLogo(size: 72),
                      const SizedBox(height: 24),
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
                            color: AppColors.secondaryText,
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
    );
  }
}
