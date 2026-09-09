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
/// Conforms to design specification:
/// - Real account details in readable groups
/// - Prominent, accessible Sign Out
/// - Zero fake meters, zero backend jargon (OAuth, JWT, Cloudinary)
/// - 20px card radii with #DCE5F2 border and safe navigation clearance
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
        Navigator.of(
          context,
          rootNavigator: true,
        ).popUntil((route) => route.isFirst);
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
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
      leading: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: AppColors.softBlueSurface,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(
          icon,
          color: iconColor ?? AppColors.primaryActionBlue,
          size: 20,
        ),
      ),
      title: Text(
        title,
        style: AppTypography.bodyMedium.copyWith(fontWeight: FontWeight.w600),
      ),
      subtitle: subtitle != null
          ? Text(subtitle, style: AppTypography.bodySmall)
          : null,
      trailing: const Icon(
        Icons.arrow_forward_ios_rounded,
        size: 14,
        color: AppColors.secondaryTextColor,
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
      backgroundColor: AppColors.mainBackground,
      appBar: AppBar(title: const Text('Account & Vault')),
      body: _isDeleting
          ? const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(
                      AppColors.errorDestructive,
                    ),
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
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 16,
                // Safe clearance so bottom floating navigation bar never obscures options
                bottom: 120 + MediaQuery.paddingOf(context).bottom,
              ),
              children: [
                // Profile header card
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: AppColors.cardSurface,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: AppColors.borderDivider,
                      width: 1.0,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.cardShadow,
                        blurRadius: 10,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          color: AppColors.softBlueSurface,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: AppColors.primaryActionBlue.withValues(
                              alpha: 0.3,
                            ),
                          ),
                        ),
                        child: Center(
                          child: Text(
                            name.isNotEmpty ? name[0].toUpperCase() : 'P',
                            style: AppTypography.titleLarge.copyWith(
                              color: AppColors.primaryActionBlue,
                              fontWeight: FontWeight.w700,
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

                // Vault Storage Card (Real usage, no fake meters)
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: AppColors.cardSurface,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: AppColors.borderDivider,
                      width: 1.0,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.cardShadow,
                        blurRadius: 10,
                        offset: const Offset(0, 2),
                      ),
                    ],
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
                                color: AppColors.primaryActionBlue,
                                size: 20,
                              ),
                              const SizedBox(width: 10),
                              Text(
                                'Encrypted Storage',
                                style: AppTypography.titleSmall.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.primaryText,
                                ),
                              ),
                            ],
                          ),
                          storageAsync.maybeWhen(
                            data: (bytes) => Text(
                              Formatters.formatBytes(bytes),
                              style: AppTypography.titleSmall.copyWith(
                                color: AppColors.primaryActionBlue,
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
                      const SizedBox(height: 14),
                      PrivoraButton(
                        text: 'View Storage Breakdown',
                        variant: PrivoraButtonVariant.secondary,
                        minHeight: 46,
                        onPressed: () => context.push('/storage-usage'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                const Text(
                  'Security & Access',
                  style: AppTypography.labelLarge,
                ),
                const SizedBox(height: 8),
                Container(
                  decoration: BoxDecoration(
                    color: AppColors.cardSurface,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: AppColors.borderDivider,
                      width: 1.0,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.cardShadow,
                        blurRadius: 10,
                        offset: const Offset(0, 2),
                      ),
                    ],
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
                        subtitle: 'Client-side encryption details',
                        onTap: () => context.push('/security-settings'),
                      ),
                      const Divider(height: 1),
                      _buildOptionTile(
                        icon: Icons.restore_page_outlined,
                        title: 'Vault Recovery Code',
                        subtitle: 'View recovery information',
                        onTap: () => context.push('/recover-vault'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                const Text(
                  'Session & Identity',
                  style: AppTypography.labelLarge,
                ),
                const SizedBox(height: 8),
                Container(
                  decoration: BoxDecoration(
                    color: AppColors.cardSurface,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: AppColors.borderDivider,
                      width: 1.0,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.cardShadow,
                        blurRadius: 10,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      _buildOptionTile(
                        icon: Icons.logout_rounded,
                        title: 'Sign Out',
                        subtitle: 'Lock vault and sign out of session',
                        iconColor: AppColors.primaryActionBlue,
                        onTap: _handleSignOut,
                      ),
                      const Divider(height: 1),
                      _buildOptionTile(
                        icon: Icons.delete_forever_rounded,
                        title: 'Delete Account',
                        subtitle: 'Permanently erase all cloud photos and data',
                        iconColor: AppColors.errorDestructive,
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
                      color: AppColors.secondaryTextColor.withValues(
                        alpha: 0.6,
                      ),
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
