import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_typography.dart';

enum PrivoraButtonVariant { primary, secondary, danger, text }

/// Premium custom button conforming to Material 3 and Privora design guidelines.
class PrivoraButton extends StatelessWidget {
  final String text;
  final VoidCallback? onPressed;
  final PrivoraButtonVariant variant;
  final bool isLoading;
  final IconData? leadingIcon;
  final IconData? trailingIcon;
  final double? width;
  final double height;

  const PrivoraButton({
    super.key,
    required this.text,
    required this.onPressed,
    this.variant = PrivoraButtonVariant.primary,
    this.isLoading = false,
    this.leadingIcon,
    this.trailingIcon,
    this.width,
    this.height = 52,
  });

  @override
  Widget build(BuildContext context) {
    Color backgroundColor;
    Color foregroundColor;
    BorderSide? borderSide;

    switch (variant) {
      case PrivoraButtonVariant.primary:
        backgroundColor = AppColors.primaryAccent;
        foregroundColor = AppColors.background;
        break;
      case PrivoraButtonVariant.secondary:
        backgroundColor = AppColors.elevatedSurface;
        foregroundColor = AppColors.mainText;
        borderSide = const BorderSide(color: AppColors.border, width: 1);
        break;
      case PrivoraButtonVariant.danger:
        backgroundColor = AppColors.danger.withValues(alpha: 0.15);
        foregroundColor = AppColors.danger;
        borderSide = BorderSide(
          color: AppColors.danger.withValues(alpha: 0.4),
          width: 1,
        );
        break;
      case PrivoraButtonVariant.text:
        backgroundColor = Colors.transparent;
        foregroundColor = AppColors.primaryAccent;
        break;
    }

    final isInteractive = onPressed != null && !isLoading;

    return SizedBox(
      width: width ?? double.infinity,
      height: height,
      child: Material(
        color: isInteractive
            ? backgroundColor
            : backgroundColor.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: isInteractive ? onPressed : null,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: borderSide != null
                  ? Border.fromBorderSide(borderSide)
                  : null,
            ),
            child: Center(
              child: isLoading
                  ? SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          foregroundColor,
                        ),
                      ),
                    )
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (leadingIcon != null) ...[
                          Icon(leadingIcon, size: 20, color: foregroundColor),
                          const SizedBox(width: 10),
                        ],
                        Flexible(
                          child: Text(
                            text,
                            style: AppTypography.labelLarge.copyWith(
                              color: foregroundColor,
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (trailingIcon != null) ...[
                          const SizedBox(width: 10),
                          Icon(trailingIcon, size: 20, color: foregroundColor),
                        ],
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
