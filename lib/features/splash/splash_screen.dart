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
/// app name, and official tagline. Validates Supabase session and routes cleanly
/// through the guarded startup flow:
/// Loading session -> Google Login -> Create/Enter PIN -> Categories.
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
    final isLocked = ref.read(sessionLockServiceProvider);
    final user = authRepo.currentUser;

    if (user == null) {
      // Rule: No Supabase session -> Google Login
      context.go('/login');
      return;
    }

    // Clean expired trash for authenticated user
    try {
      ref.read(photoRepositoryProvider).cleanExpiredTrash(user.id);
    } catch (_) {}

    // Verify vault setup from server record
    final serverVault = await vaultRepo.getServerVaultData(user.id);
    if (!mounted) return;

    if (serverVault == null) {
      // Rule: Authenticated user with no PIN/vault setup -> Create PIN
      context.go('/create-pin');
      return;
    }

    // Server vault exists: check if local key material is present
    final hasLocal = await vaultRepo.hasCompletedSetup(user.id);
    if (!mounted) return;

    if (!hasLocal) {
      // Required local key material missing on this device -> Recovery flow
      context.go('/recover-vault');
      return;
    }

    if (!mounted) return;

    // Rule: Authenticated and unlocked user -> Categories; otherwise Enter PIN
    if (!isLocked && vaultRepo.hasActiveKey) {
      context.go('/categories');
    } else {
      context.go('/unlock');
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
