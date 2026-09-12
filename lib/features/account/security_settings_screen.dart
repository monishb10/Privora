import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_motion.dart';
import '../../core/theme/app_typography.dart';

/// Readable security summary. User-managed recovery codes have been removed;
/// forgotten PINs are reset only after verification through the signed-in
/// Google account's Gmail address.
class SecuritySettingsScreen extends StatelessWidget {
  const SecuritySettingsScreen({super.key});

  Widget _securityCard({
    required IconData icon,
    required String title,
    required String description,
    required String status,
    Color statusColor = AppColors.success,
    Widget? action,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: AppColors.cardShadow,
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            alignment: Alignment.center,
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
                LayoutBuilder(
                  builder: (context, constraints) {
                    final badge = Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        status,
                        style: AppTypography.labelSmall.copyWith(
                          color: statusColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    );

                    final textScale = MediaQuery.textScalerOf(
                      context,
                    ).scale(1.0);
                    if (constraints.maxWidth < 230 || textScale > 1.4) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(title, style: AppTypography.titleMedium),
                          const SizedBox(height: 6),
                          badge,
                        ],
                      );
                    }
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(title, style: AppTypography.titleMedium),
                        ),
                        const SizedBox(width: 8),
                        badge,
                      ],
                    );
                  },
                ),
                const SizedBox(height: 6),
                Text(description, style: AppTypography.bodySmall),
                if (action != null) ...[const SizedBox(height: 12), action],
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.paddingOf(context).bottom;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Security & Privacy'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          tooltip: 'Back',
          onPressed: () =>
              context.canPop() ? context.pop() : context.go('/account'),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: EdgeInsets.fromLTRB(20, 16, 20, 24 + bottomPadding),
          children: [
            PrivoraFadeIn(
              child: _securityCard(
                icon: Icons.mark_email_read_outlined,
                title: 'Gmail PIN Reset',
                description:
                    'If you forget your PIN, Privora sends a one-time 6-digit code only to the Gmail address connected to this vault.',
                status: 'OTP Protected',
                action: Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    onPressed: () => context.push('/forgot-pin'),
                    icon: const Icon(Icons.password_rounded, size: 18),
                    label: const Text('Reset PIN with Gmail'),
                  ),
                ),
              ),
            ),
            PrivoraFadeIn(
              delay: const Duration(milliseconds: 40),
              child: _securityCard(
                icon: Icons.enhanced_encryption_rounded,
                title: 'On-Device Encryption',
                description:
                    'Photos and previews are encrypted with AES-256-GCM before they are uploaded to Cloudinary.',
                status: 'AES-256-GCM',
              ),
            ),
            PrivoraFadeIn(
              delay: const Duration(milliseconds: 80),
              child: _securityCard(
                icon: Icons.key_rounded,
                title: 'PIN Key Derivation',
                description:
                    'The vault key and PIN verifier are protected using PBKDF2 with HMAC-SHA256 and 100,000 iterations.',
                status: 'PBKDF2',
              ),
            ),
            PrivoraFadeIn(
              delay: const Duration(milliseconds: 120),
              child: _securityCard(
                icon: Icons.cloud_done_outlined,
                title: 'Encrypted Reset Backup',
                description:
                    'A server-encrypted copy of the vault key allows the original photos to remain readable after a verified Gmail PIN reset.',
                status: 'Private',
              ),
            ),
            PrivoraFadeIn(
              delay: const Duration(milliseconds: 160),
              child: _securityCard(
                icon: Icons.screen_lock_portrait_rounded,
                title: 'Screenshot Blocking',
                description:
                    'Android secure-window protection blocks screenshots, screen recording, and recent-app previews.',
                status: 'Enforced',
              ),
            ),
            PrivoraFadeIn(
              delay: const Duration(milliseconds: 200),
              child: _securityCard(
                icon: Icons.memory_rounded,
                title: 'RAM-Only Decryption',
                description:
                    'Decrypted images are kept in memory and temporary data is cleared when the vault locks.',
                status: 'Zero Gallery',
              ),
            ),
            PrivoraFadeIn(
              delay: const Duration(milliseconds: 240),
              child: _securityCard(
                icon: Icons.timer_outlined,
                title: 'Attempt Lockout',
                description:
                    'Progressive delays are enforced after repeated incorrect PIN attempts.',
                status: 'Active',
              ),
            ),
            const SizedBox(height: 2),
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
              subtitle: const Text('Use your current PIN to choose a new one.'),
              trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 14),
              onTap: () => context.push('/change-pin'),
            ),
          ],
        ),
      ),
    );
  }
}
