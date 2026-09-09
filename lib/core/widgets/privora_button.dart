import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_motion.dart';
import '../theme/app_typography.dart';

enum PrivoraButtonVariant { primary, secondary, danger, text }

/// Custom button conforming to the design specification:
/// 16px radius, >= 52px height (grows with text scale), white text on primary,
/// scale to 0.985 on press over 100ms, and accessible touch target.
class PrivoraButton extends StatefulWidget {
  final String text;
  final VoidCallback? onPressed;
  final PrivoraButtonVariant variant;
  final bool isLoading;
  final IconData? leadingIcon;
  final Widget? leadingWidget;
  final IconData? trailingIcon;
  final double? width;
  final double? height;
  final double minHeight;

  const PrivoraButton({
    super.key,
    required this.text,
    required this.onPressed,
    this.variant = PrivoraButtonVariant.primary,
    this.isLoading = false,
    this.leadingIcon,
    this.leadingWidget,
    this.trailingIcon,
    this.width,
    this.height,
    this.minHeight = 52.0,
  });

  @override
  State<PrivoraButton> createState() => _PrivoraButtonState();
}

class _PrivoraButtonState extends State<PrivoraButton> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    Color backgroundColor;
    Color foregroundColor;
    BorderSide? borderSide;

    switch (widget.variant) {
      case PrivoraButtonVariant.primary:
        backgroundColor = _isPressed
            ? AppColors.pressedPrimary
            : AppColors.primaryActionBlue;
        foregroundColor = Colors.white;
        break;
      case PrivoraButtonVariant.secondary:
        backgroundColor = _isPressed
            ? AppColors.borderDivider.withValues(alpha: 0.6)
            : AppColors.softBlueSurface;
        foregroundColor = AppColors.primaryActionBlue;
        borderSide = const BorderSide(color: AppColors.borderDivider, width: 1);
        break;
      case PrivoraButtonVariant.danger:
        backgroundColor = _isPressed
            ? AppColors.errorDestructive.withValues(alpha: 0.18)
            : AppColors.errorDestructive.withValues(alpha: 0.08);
        foregroundColor = AppColors.errorDestructive;
        borderSide = BorderSide(
          color: AppColors.errorDestructive.withValues(alpha: 0.3),
          width: 1,
        );
        break;
      case PrivoraButtonVariant.text:
        backgroundColor = Colors.transparent;
        foregroundColor = AppColors.primaryActionBlue;
        break;
    }

    final isInteractive = widget.onPressed != null && !widget.isLoading;
    final reduced = AppMotion.isReducedMotion(context);
    final targetScale = (isInteractive && _isPressed && !reduced) ? 0.985 : 1.0;

    return AnimatedScale(
      scale: targetScale,
      duration: AppMotion.pressDuration,
      curve: AppMotion.standardCurve,
      child: Container(
        width: widget.width ?? double.infinity,
        constraints: BoxConstraints(
          minHeight: widget.height ?? widget.minHeight,
        ),
        decoration: BoxDecoration(
          color: isInteractive
              ? backgroundColor
              : backgroundColor.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(16),
          border: borderSide != null ? Border.fromBorderSide(borderSide) : null,
          boxShadow:
              (widget.variant == PrivoraButtonVariant.primary &&
                  isInteractive &&
                  !_isPressed)
              ? [
                  BoxShadow(
                    color: AppColors.primaryActionBlue.withValues(alpha: 0.16),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ]
              : null,
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: isInteractive ? widget.onPressed : null,
            onTapDown: isInteractive
                ? (_) => setState(() => _isPressed = true)
                : null,
            onTapUp: isInteractive
                ? (_) => setState(() => _isPressed = false)
                : null,
            onTapCancel: isInteractive
                ? () => setState(() => _isPressed = false)
                : null,
            borderRadius: BorderRadius.circular(16),
            splashColor: widget.variant == PrivoraButtonVariant.primary
                ? Colors.white.withValues(alpha: 0.12)
                : AppColors.primaryActionBlue.withValues(alpha: 0.08),
            highlightColor: Colors.transparent,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              child: Center(
                child: widget.isLoading
                    ? SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.2,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            foregroundColor,
                          ),
                        ),
                      )
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (widget.leadingWidget != null) ...[
                            widget.leadingWidget!,
                            const SizedBox(width: 12),
                          ] else if (widget.leadingIcon != null) ...[
                            Icon(
                              widget.leadingIcon,
                              size: 20,
                              color: foregroundColor,
                            ),
                            const SizedBox(width: 10),
                          ],
                          Flexible(
                            child: Text(
                              widget.text,
                              style: AppTypography.buttonText.copyWith(
                                color: foregroundColor,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                          if (widget.trailingIcon != null) ...[
                            const SizedBox(width: 10),
                            Icon(
                              widget.trailingIcon,
                              size: 20,
                              color: foregroundColor,
                            ),
                          ],
                        ],
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
