import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../app/providers.dart';
import '../../core/constants/app_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/privora_logo.dart';

/// App launch splash screen.
/// Minimal appearance with #F7FCFF background, centered Privora logo,
/// app name, and official tagline. Validates Supabase session and routes cleanly.
class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _fadeAnim = CurvedAnimation(parent: _animController, curve: Curves.easeIn);

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

    // Minimal delay for smooth brand presentation without artificial wait
    await Future.delayed(const Duration(milliseconds: 700));
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
      backgroundColor: AppColors.mainBackground,
      body: Center(
        child: FadeTransition(
          opacity: _fadeAnim,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const PrivoraLogo(size: 96),
              const SizedBox(height: 20),
              const Text(
                AppConstants.appName,
                style: AppTypography.displayLarge,
              ),
              const SizedBox(height: 8),
              Text(
                AppConstants.appTagline,
                style: AppTypography.titleSmall.copyWith(
                  color: AppColors.secondaryTextColor,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 40),
              const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.2,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    AppColors.primaryActionBlue,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
