import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../app/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_motion.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/google_icon.dart';
import '../../core/widgets/privora_button.dart';
import '../../core/widgets/privora_logo.dart';
import '../../core/widgets/privora_wordmark.dart';

/// Clean Google-only Authentication Screen for Privora.
/// Replaces visible email/password inputs with a single "Continue with Google" action,
/// adhering to Privora's modern blue-and-white design system.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  bool _isLoading = false;
  String? _errorMessage;

  Future<void> _handleGoogleSignIn() async {
    if (_isLoading) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final authRepo = ref.read(authRepositoryProvider);
      final response = await authRepo.signInWithGoogle();

      // If user cancelled the Google account chooser, stay on Login quietly without large error banner
      if (response == null) {
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
        return;
      }

      final user = response.user ?? authRepo.currentUser;
      if (user == null) {
        if (mounted) {
          setState(() {
            _isLoading = false;
            _errorMessage =
                'Authentication completed but no user profile found.';
          });
        }
        return;
      }

      // Check local and server vault status for this user
      final vaultRepo = ref.read(vaultRepositoryProvider);
      // Clear previous in-memory caches and invalidate providers for this account
      ref.read(categoryRepositoryProvider).clearCache(user.id);
      ref.invalidate(categoriesProvider);
      ref.invalidate(storageUsageProvider);
      ref.invalidate(recentlyDeletedPhotosProvider);

      final hasLocalKeys = await vaultRepo.hasCompletedSetup(user.id);
      if (!mounted) return;

      if (hasLocalKeys) {
        // Returning user on this device.
        context.go('/unlock');
      } else {
        // A returning user on a new device receives the encrypted PIN envelope
        // from Supabase, then unlocks it using the same six-digit PIN.
        final synced = await vaultRepo.syncServerPinEnvelopeIfMissing(user.id);
        if (!mounted) return;

        if (synced) {
          context.go('/unlock');
        } else {
          final serverVault = await vaultRepo.getServerVaultData(user.id);
          if (!mounted) return;
          if (serverVault == null) {
            context.go('/create-pin');
          } else {
            // An older or partially migrated vault must never be overwritten.
            // Gmail OTP is the only reset path in the current application.
            context.go('/forgot-pin');
          }
        }
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e
            .toString()
            .replaceFirst('Exception: ', '')
            .replaceFirst('AuthException: ', '');
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.mainBackground,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
            child: PrivoraFadeIn(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const SizedBox(height: 24),

                  // Privora Logo with subtle static blue wash
                  Stack(
                    alignment: Alignment.center,
                    children: [
                      Container(
                        width: 140,
                        height: 140,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: RadialGradient(
                            colors: [
                              AppColors.softBlueSurface,
                              AppColors.softBlueSurface.withValues(alpha: 0.0),
                            ],
                            stops: const [0.45, 1.0],
                          ),
                        ),
                      ),
                      const PrivoraLogo(size: 92, showShadow: true),
                    ],
                  ),
                  const SizedBox(height: 28),

                  // App Title (Brand Wordmark matching main page)
                  const PrivoraWordmark(
                    height: 38,
                    wordmarkKey: Key('privora_brand_wordmark'),
                  ),
                  const SizedBox(height: 10),

                  // Subtitle
                  Text(
                    'Your private cloud gallery',
                    style: AppTypography.titleSmall.copyWith(
                      color: AppColors.secondaryTextColor,
                      fontWeight: FontWeight.w500,
                    ),
                    textAlign: TextAlign.center,
                  ),

                  const SizedBox(height: 52),

                  // Error message banner
                  if (_errorMessage != null) ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.errorDestructive.withValues(
                          alpha: 0.08,
                        ),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: AppColors.errorDestructive.withValues(
                            alpha: 0.3,
                          ),
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            Icons.error_outline_rounded,
                            color: AppColors.errorDestructive,
                            size: 20,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _errorMessage!,
                              style: AppTypography.bodySmall.copyWith(
                                color: AppColors.errorDestructive,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],

                  // Single "Continue with Google" Action Button
                  Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.primaryActionBlue.withValues(
                            alpha: 0.08,
                          ),
                          blurRadius: 14,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: PrivoraButton(
                      text: 'Continue with Google',
                      variant: PrivoraButtonVariant.secondary,
                      leadingWidget: const GoogleIcon(size: 22),
                      isLoading: _isLoading,
                      minHeight: 54,
                      onPressed: _isLoading ? null : _handleGoogleSignIn,
                    ),
                  ),

                  const SizedBox(height: 40),

                  // Privacy assurance note
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.shield_outlined,
                        size: 16,
                        color: AppColors.secondaryTextColor,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Client-side encrypted with AES-256-GCM',
                        style: AppTypography.labelSmall.copyWith(
                          color: AppColors.secondaryTextColor,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
