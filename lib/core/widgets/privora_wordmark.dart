import 'package:flutter/material.dart';
import '../constants/app_constants.dart';
import '../theme/app_colors.dart';

/// Clean branded Privora wordmark widget displaying the authentic brand
/// typography artwork with exact proportions and theme tinting.
class PrivoraWordmark extends StatelessWidget {
  final double height;
  final Color? color;
  final Key? wordmarkKey;

  const PrivoraWordmark({
    super.key,
    this.height = 28,
    this.color = AppColors.primaryText,
    this.wordmarkKey = const Key('privora_brand_wordmark'),
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      header: true,
      label: AppConstants.appName,
      child: Image.asset(
        'assets/branding/privora_wordmark.png',
        key: wordmarkKey,
        height: height,
        fit: BoxFit.contain,
        color: color,
        filterQuality: FilterQuality.high,
      ),
    );
  }
}
