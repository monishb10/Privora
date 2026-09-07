import 'package:flutter/material.dart';

/// Clean branded Privora logo widget displaying the authentic artwork
/// with exact proportions, transparent background, and high filter quality.
class PrivoraLogo extends StatelessWidget {
  final double size;
  final bool showShadow;

  const PrivoraLogo({super.key, this.size = 64, this.showShadow = false});

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/branding/privora_logo.png',
      width: size,
      height: size,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
    );
  }
}
