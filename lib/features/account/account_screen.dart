import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../app/providers.dart';
import '../../core/constants/app_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/confirmation_dialog.dart';
import '../../core/widgets/privora_button.dart';

/// Screen managing user profile, security settings, storage usage, and account lifecycle.
class AccountScreen extends ConsumerStatefulWidget {
  const AccountScreen({super.key});

  @override
  ConsumerState<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends ConsumerState<AccountScreen> {
  bool _isDeleting = false;

  Future<void> _handleSignOut() async {
    final confirmed = await ConfirmationDialog.show(
      context: context,
      title: 'Sign Out?',
      message:
          'You will need to sign in again with Google and enter your 6-digit PIN to access your private vault.',
      confirmText: 'Sign Out',
      icon: Icons.logout_rounded,
    );

    if (confirmed == true && mounted) {
      await ref.read(authRepositoryProvider).signOut();
      ref.invalidate(currentUserProvider);
      ref.invalidate(categoriesProvider);
      ref.invalidate(recentlyDeletedPhotosProvider);
      ref.invalidate(storageUsageProvider);
      if (mounted) {
        context.go('/login');
      }
    }
  }

  Future<void> _handleDeleteAccount() async {
    final confirmed = await ConfirmationDialog.show(
      context: context,
      title: 'Permanently Delete Account?',
      message:
          'CRITICAL WARNING: This will permanently delete ALL encrypted photos in your cloud vault, categories, and account records. This action cannot be reversed.',
      confirmText: 'Permanently Delete',
      isDestructive: true,
      icon: Icons.warning_amber_rounded,
    );

    if (confirmed != true || !mounted) return;

    setState(() => _isDeleting = true);

    try {
      await ref.read(authRepositoryProvider).deleteAccount();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Account and all vault data permanently erased.'),
          ),
        );
        context.go('/login');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isDeleting = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to delete account: $e')));
      }
    }
  }

  Widget _buildOptionTile({
    required IconData icon,
    required String title,
    String? subtitle,
    required VoidCallback onTap,
    Color? iconColor,
  }) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: AppColors.elevatedSurface,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(
          icon,
          color: iconColor ?? AppColors.primaryAccent,
          size: 20,
        ),
      ),
      title: Text(title, style: AppTypography.bodyLarge),
      subtitle: subtitle != null
          ? Text(subtitle, style: AppTypography.bodySmall)
          : null,
      trailing: const Icon(
        Icons.arrow_forward_ios_rounded,
        size: 14,
        color: AppColors.secondaryText,
      ),
      onTap: onTap,
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    final storageAsync = ref.watch(storageUsageProvider);

    final email = user?.email ?? 'Unknown User';
    final name =
        user?.userMetadata?['display_name'] as String? ??
        user?.userMetadata?['full_name'] as String? ??
        'Privora Member';

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Account & Vault')),
      body: _isDeleting
          ? const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(AppColors.danger),
                  ),
                  SizedBox(height: 20),
                  Text(
                    'Securely erasing vault data...',
                    style: AppTypography.bodyMedium,
                  ),
                ],
              ),
            )
          : ListView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              children: [
                // Profile header card
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          color: AppColors.elevatedSurface,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: AppColors.primaryAccent.withValues(
                              alpha: 0.5,
                            ),
                          ),
                        ),
                        child: Center(
                          child: Text(
                            name.isNotEmpty ? name[0].toUpperCase() : 'P',
                            style: AppTypography.titleLarge.copyWith(
                              color: AppColors.primaryAccent,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(name, style: AppTypography.titleMedium),
                            const SizedBox(height: 4),
                            Text(
                              Formatters.maskEmail(email),
                              style: AppTypography.bodySmall,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // Vault Storage Card
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              const Icon(
                                Icons.cloud_outlined,
                                color: AppColors.primaryAccent,
                                size: 20,
                              ),
                              const SizedBox(width: 10),
                              Text(
                                'Encrypted Storage',
                                style: AppTypography.titleSmall,
                              ),
                            ],
                          ),
                          storageAsync.maybeWhen(
                            data: (bytes) => Text(
                              Formatters.formatBytes(bytes),
                              style: AppTypography.titleSmall.copyWith(
                                color: AppColors.primaryAccent,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            orElse: () => const Text(
                              '--',
                              style: AppTypography.titleSmall,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      PrivoraButton(
                        text: 'View Storage Breakdown',
                        variant: PrivoraButtonVariant.secondary,
                        height: 42,
                        onPressed: () => context.push('/storage-usage'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                const Text(
                  'Security & Access',
                  style: AppTypography.labelMedium,
                ),
                const SizedBox(height: 8),
                Container(
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Column(
                    children: [
                      _buildOptionTile(
                        icon: Icons.pin_outlined,
                        title: 'Change 6-Digit PIN',
                        subtitle: 'Update application access code',
                        onTap: () => context.push('/change-pin'),
                      ),
                      const Divider(height: 1),
                      _buildOptionTile(
                        icon: Icons.shield_outlined,
                        title: 'Security & Privacy',
                        subtitle: 'Encryption and device isolation',
                        onTap: () => context.push('/security-settings'),
                      ),
                      const Divider(height: 1),
                      _buildOptionTile(
                        icon: Icons.restore_page_outlined,
                        title: 'Vault Recovery Code',
                        subtitle: 'Recovery process details',
                        onTap: () => context.push('/recover-vault'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                const Text(
                  'Session & Identity',
                  style: AppTypography.labelMedium,
                ),
                const SizedBox(height: 8),
                Container(
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Column(
                    children: [
                      _buildOptionTile(
                        icon: Icons.logout_rounded,
                        title: 'Sign Out',
                        subtitle: 'Lock vault and sign out of session',
                        iconColor: AppColors.secondaryText,
                        onTap: _handleSignOut,
                      ),
                      const Divider(height: 1),
                      _buildOptionTile(
                        icon: Icons.delete_forever_rounded,
                        title: 'Delete Account',
                        subtitle: 'Permanently erase all cloud photos and data',
                        iconColor: AppColors.danger,
                        onTap: _handleDeleteAccount,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),
                Center(
                  child: Text(
                    '${AppConstants.appName} v1.0.0\n${AppConstants.appTagline}',
                    style: AppTypography.labelSmall.copyWith(
                      color: AppColors.secondaryText.withValues(alpha: 0.6),
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
    );
  }
}
