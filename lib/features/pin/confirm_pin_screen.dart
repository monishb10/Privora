import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../app/providers.dart';
import '../../core/constants/app_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/privora_button.dart';
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
      final recoveryCode = await vaultRepo.initializeNewVault(
        userId: user.id,
        pin: _enteredPin,
      );

      ref.read(sessionLockServiceProvider.notifier).unlock();

      if (!mounted) return;
      _showRecoveryCodeDialog(recoveryCode);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _hasError = true;
        _errorMessage = e.toString();
        _enteredPin = '';
        _isInitializing = false;
      });
    }
  }

  void _showRecoveryCodeDialog(String recoveryCode) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return _RecoveryCodeDialog(
          recoveryCode: recoveryCode,
          onConfirmed: () {
            Navigator.of(context).pop();
            context.go('/categories');
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: _isInitializing ? null : () => context.pop(),
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
                      Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          color: AppColors.elevatedSurface,
                          shape: BoxShape.circle,
                          border: Border.all(color: AppColors.border),
                        ),
                        child: const Icon(
                          Icons.check_circle_outline_rounded,
                          size: 32,
                          color: AppColors.primaryAccent,
                        ),
                      ),
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
    );
  }
}

class _RecoveryCodeDialog extends StatefulWidget {
  final String recoveryCode;
  final VoidCallback onConfirmed;

  const _RecoveryCodeDialog({
    required this.recoveryCode,
    required this.onConfirmed,
  });

  @override
  State<_RecoveryCodeDialog> createState() => _RecoveryCodeDialogState();
}

class _RecoveryCodeDialogState extends State<_RecoveryCodeDialog> {
  bool _hasSaved = false;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: AppColors.border),
        ),
        contentPadding: const EdgeInsets.all(24),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.primaryAccent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.vpn_key_outlined,
                    color: AppColors.primaryAccent,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Save Recovery Code',
                    style: AppTypography.titleLarge,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Text(
              'This single-use recovery code is the ONLY way to recover your encrypted photos if you lose your phone or forget your PIN.',
              style: AppTypography.bodySmall,
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: AppColors.elevatedSurface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppColors.primaryAccent.withValues(alpha: 0.4),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: SelectableText(
                      widget.recoveryCode,
                      style: AppTypography.titleMedium.copyWith(
                        fontFamily: 'monospace',
                        color: AppColors.primaryAccent,
                        letterSpacing: 1.2,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(
                      Icons.copy_rounded,
                      color: AppColors.primaryAccent,
                      size: 20,
                    ),
                    tooltip: 'Copy Code',
                    onPressed: () {
                      Clipboard.setData(
                        ClipboardData(text: widget.recoveryCode),
                      );
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Recovery code copied to clipboard.'),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Checkbox(
                  value: _hasSaved,
                  activeColor: AppColors.primaryAccent,
                  checkColor: AppColors.background,
                  onChanged: (val) {
                    setState(() {
                      _hasSaved = val ?? false;
                    });
                  },
                ),
                Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _hasSaved = !_hasSaved),
                    child: Padding(
                      padding: const EdgeInsets.only(top: 8.0),
                      child: Text(
                        'I have securely written down or saved this recovery code.',
                        style: AppTypography.bodySmall.copyWith(
                          color: AppColors.mainText,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            PrivoraButton(
              text: 'Open My Vault',
              onPressed: _hasSaved ? widget.onConfirmed : null,
            ),
          ],
        ),
      ),
    );
  }
}
