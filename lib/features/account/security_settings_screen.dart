import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';

/// Screen detailing Privora's security architecture and privacy controls.
class SecuritySettingsScreen extends StatelessWidget {
  const SecuritySettingsScreen({super.key});

  Widget _buildSecurityCard({
    required IconData icon,
    required String title,
    required String description,
    required String status,
    Color statusColor = AppColors.success,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.elevatedSurface,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: AppColors.primaryAccent, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(title, style: AppTypography.titleMedium),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        status,
                        style: AppTypography.labelSmall.copyWith(
                          color: statusColor,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(description, style: AppTypography.bodySmall),
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
      appBar: AppBar(
        title: const Text('Security & Privacy'),
        leading: SizedBox(
          width: 48,
          height: 48,
          child: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
            tooltip: 'Back',
            onPressed: () {
              if (context.canPop()) {
                context.pop();
              } else {
                context.go('/account');
              }
            },
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        children: [
          _buildSecurityCard(
            icon: Icons.enhanced_encryption_rounded,
            title: 'End-to-End Encryption',
            description:
                'All photos and previews are encrypted with AES-256-GCM before uploading to cloud storage.',
            status: 'AES-256-GCM',
          ),
          _buildSecurityCard(
            icon: Icons.key_rounded,
            title: 'Key Derivation',
            description:
                'Master keys and PIN verifiers are derived using PBKDF2 with HMAC-SHA256 and 100,000 iterations.',
            status: 'PBKDF2',
          ),
          _buildSecurityCard(
            icon: Icons.screen_lock_portrait_rounded,
            title: 'Screenshot Blocking',
            description:
                'Android FLAG_SECURE prevents screenshots, screen recording, and masks recent app switchers.',
            status: 'Enforced',
          ),
          _buildSecurityCard(
            icon: Icons.fingerprint_rounded,
            title: 'Biometrics Disabled',
            description:
                'Biometric unlock is strictly disabled by design to eliminate biometric coercion vectors.',
            status: 'PIN Only',
            statusColor: AppColors.primaryAccent,
          ),
          _buildSecurityCard(
            icon: Icons.memory_rounded,
            title: 'RAM-Only Decryption',
            description:
                'Decrypted images exist solely in memory. Decrypted caches are wiped whenever the app locks.',
            status: 'Zero Disk',
          ),
          _buildSecurityCard(
            icon: Icons.timer_outlined,
            title: 'Anti-Bruteforce Lockout',
            description:
                'Progressive time delay penalties are enforced after 5 consecutive incorrect PIN entries.',
            status: 'Active',
          ),
          const SizedBox(height: 16),
          ListTile(
            tileColor: AppColors.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: const BorderSide(color: AppColors.border),
            ),
            leading: const Icon(
              Icons.password_rounded,
              color: AppColors.primaryAccent,
            ),
            title: const Text(
              'Change 6-Digit PIN',
              style: AppTypography.bodyLarge,
            ),
            trailing: const Icon(
              Icons.arrow_forward_ios_rounded,
              size: 14,
              color: AppColors.secondaryText,
            ),
            onTap: () => context.push('/change-pin'),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}
