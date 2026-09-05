import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../app/providers.dart';
import '../../core/constants/app_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';

/// App launch splash screen.
/// Validates Supabase authentication session and routes to Welcome, Unlock, or PIN setup.
class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _fadeAnim;
  late Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    _fadeAnim = CurvedAnimation(parent: _animController, curve: Curves.easeIn);
    _scaleAnim = Tween<double>(begin: 0.9, end: 1.0).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOutCubic),
    );

    _animController.forward();
    _checkInitialRoute();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  Future<void> _checkInitialRoute() async {
    // 1. Startup disk hygiene: clean any leftover unencrypted files
    await ref.read(temporaryFileCleanerProvider).cleanTemporaryFiles();

    // Small delay to allow branding presentation
    await Future.delayed(const Duration(milliseconds: 1200));
    if (!mounted) return;

    final authRepo = ref.read(authRepositoryProvider);
    final vaultRepo = ref.read(vaultRepositoryProvider);
    final user = authRepo.currentUser;

    if (user == null) {
      // First installation or logged out
      context.go('/welcome');
      return;
    }

    // Clean expired trash for authenticated user
    ref.read(photoRepositoryProvider).cleanExpiredTrash(user.id);

    final hasSetup = await vaultRepo.hasCompletedSetup();
    if (!mounted) return;

    if (hasSetup) {
      // Returning user on the same device -> Proceed directly to 6-digit PIN screen
      context.go('/unlock');
    } else {
      // Authenticated but hasn't created local vault PIN yet
      context.go('/create-pin');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: FadeTransition(
          opacity: _fadeAnim,
          child: ScaleTransition(
            scale: _scaleAnim,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 88,
                  height: 88,
                  decoration: BoxDecoration(
                    color: AppColors.elevatedSurface,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: AppColors.border, width: 1.5),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primaryAccent.withValues(alpha: 0.15),
                        blurRadius: 30,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: const Center(
                    child: Icon(
                      Icons.shield_outlined,
                      size: 44,
                      color: AppColors.primaryAccent,
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  AppConstants.appName,
                  style: AppTypography.displayLarge,
                ),
                const SizedBox(height: 8),
                const Text(
                  AppConstants.appTagline,
                  style: AppTypography.titleSmall,
                ),
                const SizedBox(height: 48),
                const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      AppColors.primaryAccent,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
