import 'package:flutter/material.dart';

/// Motion specifications and reusable micro-interaction widgets for Privora.
/// Strictly respects accessibility reduced-motion preferences.
class AppMotion {
  AppMotion._();

  // Durations aligned with the design specification
  static const Duration pressDuration = Duration(milliseconds: 100);
  static const Duration contentFadeDuration = Duration(milliseconds: 200);
  static const Duration navTransitionDuration = Duration(milliseconds: 200);
  static const Duration sheetSlideDuration = Duration(milliseconds: 240);
  static const Duration thumbnailFadeDuration = Duration(milliseconds: 140);
  static const Duration photoOpenDuration = Duration(milliseconds: 220);
  static const Duration pinIndicatorDuration = Duration(milliseconds: 120);
  static const Duration progressDuration = Duration(milliseconds: 160);
  static const Duration successConfirmationDuration = Duration(
    milliseconds: 180,
  );

  // Curves
  static const Curve standardCurve = Curves.easeOutCubic;
  static const Curve enterCurve = Curves.easeOutQuart;
  static const Curve exitCurve = Curves.easeInCubic;

  /// Checks if the user or device has requested reduced motion.
  static bool isReducedMotion(BuildContext context) {
    return MediaQuery.maybeDisableAnimationsOf(context) ?? false;
  }
}

/// Reusable interactive widget that scales to ~0.985 on press over 100ms.
/// Respects accessibility reduced-motion settings.
class PrivoraPressable extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final double scaleFactor;
  final HitTestBehavior behavior;

  const PrivoraPressable({
    super.key,
    required this.child,
    this.onTap,
    this.scaleFactor = 0.985,
    this.behavior = HitTestBehavior.opaque,
  });

  @override
  State<PrivoraPressable> createState() => _PrivoraPressableState();
}

class _PrivoraPressableState extends State<PrivoraPressable> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final reduced = AppMotion.isReducedMotion(context);
    final targetScale = (widget.onTap != null && _isPressed && !reduced)
        ? widget.scaleFactor
        : 1.0;

    return GestureDetector(
      behavior: widget.behavior,
      onTapDown: widget.onTap != null
          ? (_) => setState(() => _isPressed = true)
          : null,
      onTapUp: widget.onTap != null
          ? (_) => setState(() => _isPressed = false)
          : null,
      onTapCancel: widget.onTap != null
          ? () => setState(() => _isPressed = false)
          : null,
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: targetScale,
        duration: AppMotion.pressDuration,
        curve: AppMotion.standardCurve,
        child: widget.child,
      ),
    );
  }
}

/// Subtle entrance animation: fades in with <= 8-pixel upward movement over 200 ms.
/// Plays once on mount, does NOT replay on subsequent scroll or rebuild.
/// Instantly displays static content if reduced motion is enabled.
class PrivoraFadeIn extends StatefulWidget {
  final Widget child;
  final Duration delay;
  final double slideDistance;

  const PrivoraFadeIn({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.slideDistance = 8.0,
  });

  @override
  State<PrivoraFadeIn> createState() => _PrivoraFadeInState();
}

class _PrivoraFadeInState extends State<PrivoraFadeIn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fadeAnimation;
  late final Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: AppMotion.contentFadeDuration,
    );

    _fadeAnimation = CurvedAnimation(
      parent: _controller,
      curve: AppMotion.enterCurve,
    );

    _slideAnimation =
        Tween<Offset>(
          begin: Offset(0, widget.slideDistance / 100),
          end: Offset.zero,
        ).animate(
          CurvedAnimation(parent: _controller, curve: AppMotion.enterCurve),
        );

    if (widget.delay == Duration.zero) {
      _controller.forward();
    } else {
      Future.delayed(widget.delay, () {
        if (mounted) _controller.forward();
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (AppMotion.isReducedMotion(context)) {
      return widget.child;
    }

    return FadeTransition(
      opacity: _fadeAnimation,
      child: SlideTransition(position: _slideAnimation, child: widget.child),
    );
  }
}
