import '../../core/widgets/privora_wordmark.dart';
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

  String? _errorMessage;
  bool _isChecking = false;

  Future<void> _checkInitialRoute() async {
    if (_isChecking) return;
    setState(() {
      _isChecking = true;
      _errorMessage = null;
    });

    try {
      // 1. Startup disk hygiene: clean any leftover unencrypted files
      await ref.read(temporaryFileCleanerProvider).cleanTemporaryFiles();

      // Minimal tick for smooth frame initialization without artificial delay
      await Future.delayed(const Duration(milliseconds: 100));
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

      // Clean any legacy un-namespaced keys from older versions to enforce multi-account isolation
      try {
        await ref.read(secureKeyServiceProvider).cleanLegacySharedKeys();
      } catch (_) {}

      // Verify vault setup from server record with bounded wait (10 seconds)
      Map<String, dynamic>? serverVault;
      bool lookupFailed = false;
      try {
        serverVault = await vaultRepo
            .getServerVaultData(user.id)
            .timeout(const Duration(seconds: 10));
      } catch (e) {
        debugPrint('Splash vault lookup failed or offline: $e');
        lookupFailed = true;
      }
      if (!mounted) return;

      final hasLocal = await vaultRepo.hasCompletedSetup(user.id);
      if (!mounted) return;

      if (lookupFailed) {
        // Offline / network failure: allow unlock if local keys exist; never create replacement key
        if (hasLocal) {
          context.go('/unlock');
        } else {
          setState(() {
            _errorMessage =
                'Unable to connect to your vault. Please check your connection and retry.';
          });
        }
        return;
      }

      // 1. If this device has completed PIN setup for this user, unlock or enter PIN
      if (hasLocal) {
        if (!isLocked && vaultRepo.hasActiveKey) {
          context.go('/categories');
        } else {
          context.go('/unlock');
        }
        return;
      }

      // 2. Returning users on a new device restore the encrypted server PIN
      // envelope and enter their existing PIN. This fixes the false
      // "PIN has not been set" state caused by checking only local storage.
      final synced = await vaultRepo.syncServerPinEnvelopeIfMissing(
        user.id,
        serverVault: serverVault,
      );
      if (!mounted) return;
      if (synced) {
        context.go('/unlock');
        return;
      }

      if (serverVault == null) {
        // Brand-new Google account.
        context.go('/create-pin');
      } else {
        // Never overwrite an older/partial vault. Verify Gmail and reset PIN.
        context.go('/forgot-pin');
      }
    } catch (error) {
      debugPrint('Startup routing error: $error');
      if (mounted) {
        setState(() {
          _errorMessage =
              'Privora could not verify this account yet. Check your connection and retry.';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isChecking = false;
        });
      }
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
              const PrivoraWordmark(
                height: 38,
                wordmarkKey: Key('privora_brand_wordmark'),
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
              if (_errorMessage != null) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Text(
                    _errorMessage!,
                    style: AppTypography.bodySmall.copyWith(
                      color: AppColors.errorDestructive,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextButton(
                      onPressed: () => context.go('/login'),
                      style: TextButton.styleFrom(
                        minimumSize: const Size(48, 48),
                        foregroundColor: AppColors.secondaryTextColor,
                      ),
                      child: const Text('Back to Login'),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton(
                      onPressed: _checkInitialRoute,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primaryActionBlue,
                        foregroundColor: Colors.white,
                        minimumSize: const Size(100, 48),
                      ),
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ] else
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
