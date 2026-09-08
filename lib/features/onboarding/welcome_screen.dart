import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/constants/app_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/privora_button.dart';
import '../../core/widgets/privora_logo.dart';

/// Onboarding Welcome screen for first-time visitors.
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  Widget _buildFeatureRow(IconData icon, String title, String subtitle) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.elevatedSurface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: Icon(icon, color: AppColors.primaryAccent, size: 22),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppTypography.titleMedium),
                const SizedBox(height: 4),
                Text(subtitle, style: AppTypography.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 16),
              // App Logo & Header
              Row(
                children: [
                  const PrivoraLogo(size: 42, showShadow: false),
                  const SizedBox(width: 12),
                  const Text(
                    AppConstants.appName,
                    style: AppTypography.brandTitle,
                  ),
                ],
              ),
              const Spacer(flex: 1),

              // Hero Headline
              const Text(
                'Private.\nEncrypted.\nUntraceable.',
                style: AppTypography.displayLarge,
              ),
              const SizedBox(height: 12),
              const Text(
                AppConstants.appTagline,
                style: AppTypography.titleSmall,
              ),

              const Spacer(flex: 2),

              // Highlights
              _buildFeatureRow(
                Icons.lock_outline_rounded,
                'Zero Device Footprint',
                'Photos never enter your phone gallery. Decrypted in RAM only.',
              ),
              _buildFeatureRow(
                Icons.enhanced_encryption_outlined,
                'Client-Side AES-256-GCM',
                'Encrypted on your device before touching Supabase Cloud Storage.',
              ),
              _buildFeatureRow(
                Icons.pin_outlined,
                '6-Digit PIN Isolation',
                'Your master vault key is protected by your PIN with zero biometric backdoors.',
              ),

              const Spacer(flex: 2),

              // Action buttons
              PrivoraButton(
                text: 'Create Account',
                variant: PrivoraButtonVariant.primary,
                onPressed: () => context.go('/register'),
              ),
              const SizedBox(height: 12),
              PrivoraButton(
                text: 'Sign In',
                variant: PrivoraButtonVariant.secondary,
                onPressed: () => context.go('/login'),
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }
}
