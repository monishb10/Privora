import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';

/// 6 Animated dots visualizing entered PIN digits.
class PinDots extends StatelessWidget {
  final int length;
  final int totalDigits;
  final bool hasError;

  const PinDots({
    super.key,
    required this.length,
    this.totalDigits = AppConstants.pinLength,
    this.hasError = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(totalDigits, (index) {
        final isFilled = index < length;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          margin: const EdgeInsets.symmetric(horizontal: 10),
          width: isFilled ? 18 : 14,
          height: isFilled ? 18 : 14,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: hasError
                ? AppColors.errorDestructive
                : isFilled
                ? AppColors.primaryActionBlue
                : Colors.transparent,
            border: Border.all(
              color: hasError
                  ? AppColors.errorDestructive
                  : isFilled
                  ? AppColors.primaryActionBlue
                  : AppColors.borderDivider,
              width: 1.5,
            ),
            boxShadow: isFilled && !hasError
                ? [
                    BoxShadow(
                      color: AppColors.primaryActionBlue.withValues(
                        alpha: 0.15,
                      ),
                      blurRadius: 4,
                      offset: const Offset(0, 1),
                    ),
                  ]
                : null,
          ),
        );
      }),
    );
  }
}

/// Secure custom numeric keypad for PIN entry.
/// Strictly numeric: No biometrics, no alphanumeric keys.
class PinKeypad extends StatelessWidget {
  final ValueChanged<String> onDigitPressed;
  final VoidCallback onDeletePressed;
  final Widget? leftActionWidget;
  final bool enabled;

  const PinKeypad({
    super.key,
    required this.onDigitPressed,
    required this.onDeletePressed,
    this.leftActionWidget,
    this.enabled = true,
  });

  Widget _buildKey(String digit) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: SizedBox(
          height: 64,
          child: Material(
            color: Colors.transparent,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: enabled
                  ? () {
                      HapticFeedback.lightImpact();
                      onDigitPressed(digit);
                    }
                  : null,
              child: Center(
                child: Text(
                  digit,
                  style: AppTypography.pinDigit.copyWith(
                    color: enabled
                        ? AppColors.mainText
                        : AppColors.secondaryText.withValues(alpha: 0.3),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      constraints: const BoxConstraints(maxWidth: 360),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(children: [_buildKey('1'), _buildKey('2'), _buildKey('3')]),
          Row(children: [_buildKey('4'), _buildKey('5'), _buildKey('6')]),
          Row(children: [_buildKey('7'), _buildKey('8'), _buildKey('9')]),
          Row(
            children: [
              Expanded(
                child: Center(child: leftActionWidget ?? const SizedBox()),
              ),
              _buildKey('0'),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  child: SizedBox(
                    height: 64,
                    child: Material(
                      color: Colors.transparent,
                      shape: const CircleBorder(),
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: enabled
                            ? () {
                                HapticFeedback.selectionClick();
                                onDeletePressed();
                              }
                            : null,
                        child: Center(
                          child: Icon(
                            Icons.backspace_outlined,
                            size: 24,
                            color: enabled
                                ? AppColors.mainText
                                : AppColors.secondaryText.withValues(
                                    alpha: 0.3,
                                  ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
