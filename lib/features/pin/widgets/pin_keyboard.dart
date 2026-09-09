import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_motion.dart';
import '../../../core/theme/app_typography.dart';

/// 6 Animated dots visualizing entered PIN digits.
/// Employs a small fill/scale micro-transition over 120 ms.
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
          duration: AppMotion.pinIndicatorDuration,
          curve: AppMotion.standardCurve,
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
                        alpha: 0.18,
                      ),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
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
/// Comfortably spaced with scale-on-press micro-interactions.
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
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: SizedBox(
          height: 64,
          child: PrivoraPressable(
            onTap: enabled
                ? () {
                    HapticFeedback.lightImpact();
                    onDigitPressed(digit);
                  }
                : null,
            child: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.cardSurface,
                border: Border.all(color: AppColors.borderDivider, width: 1),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.cardShadow,
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
              child: Center(
                child: Text(
                  digit,
                  style: AppTypography.pinDigit.copyWith(
                    color: enabled
                        ? AppColors.primaryText
                        : AppColors.secondaryTextColor.withValues(alpha: 0.3),
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
          const SizedBox(height: 4),
          Row(children: [_buildKey('4'), _buildKey('5'), _buildKey('6')]),
          const SizedBox(height: 4),
          Row(children: [_buildKey('7'), _buildKey('8'), _buildKey('9')]),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: Center(child: leftActionWidget ?? const SizedBox()),
              ),
              _buildKey('0'),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  child: SizedBox(
                    height: 64,
                    child: PrivoraPressable(
                      onTap: enabled
                          ? () {
                              HapticFeedback.selectionClick();
                              onDeletePressed();
                            }
                          : null,
                      child: Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppColors.cardSurface,
                          border: Border.all(
                            color: AppColors.borderDivider,
                            width: 1,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.cardShadow,
                              blurRadius: 4,
                              offset: const Offset(0, 1),
                            ),
                          ],
                        ),
                        child: Center(
                          child: Icon(
                            Icons.backspace_outlined,
                            size: 22,
                            color: enabled
                                ? AppColors.primaryText
                                : AppColors.secondaryTextColor.withValues(
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
