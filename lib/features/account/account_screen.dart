import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkAndSyncGooglePhoto();
    });
  }

  Future<void> _checkAndSyncGooglePhoto() async {
    try {
      final user = ref.read(currentUserProvider);
      final existing =
          user?.userMetadata?['avatar_url'] as String? ??
          user?.userMetadata?['picture'] as String?;
      if (existing == null || existing.isEmpty) {
        final googlePhoto = ref.read(authRepositoryProvider).googlePhotoUrl;
        if (googlePhoto != null && googlePhoto.isNotEmpty) {
          await ref.read(authRepositoryProvider).updateUserMetadata({
            'avatar_url': googlePhoto,
            'picture': googlePhoto,
          });
          if (mounted) {
            ref.invalidate(currentUserProvider);
          }
        }
      }
    } catch (_) {}
  }

  Future<void> _showProfilePhotoOptions() async {
    final googlePhoto = ref.read(authRepositoryProvider).googlePhotoUrl;
    final user = ref.read(currentUserProvider);
    final currentAvatar =
        user?.userMetadata?['avatar_url'] as String? ??
        user?.userMetadata?['picture'] as String?;

    await showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.cardSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.borderDivider,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              const Text('Profile Picture', style: AppTypography.titleMedium),
              const SizedBox(height: 16),
              if (googlePhoto != null && googlePhoto.isNotEmpty)
                ListTile(
                  leading: const Icon(
                    Icons.account_circle_outlined,
                    color: AppColors.primaryActionBlue,
                  ),
                  title: const Text('Use Google Account Photo'),
                  subtitle: const Text(
                    'Sync avatar from your linked Google account',
                  ),
                  onTap: () async {
                    Navigator.of(sheetContext).pop();
                    await _updateAvatar(googlePhoto);
                  },
                ),
              ListTile(
                leading: const Icon(
                  Icons.photo_library_outlined,
                  color: AppColors.primaryActionBlue,
                ),
                title: const Text('Choose from Gallery'),
                subtitle: const Text('Upload a custom profile photo'),
                onTap: () async {
                  Navigator.of(sheetContext).pop();
                  await _pickAndUploadProfilePhoto();
                },
              ),
              if (currentAvatar != null && currentAvatar.isNotEmpty)
                ListTile(
                  leading: const Icon(
                    Icons.delete_outline_rounded,
                    color: AppColors.errorDestructive,
                  ),
                  title: const Text(
                    'Remove Photo',
                    style: TextStyle(color: AppColors.errorDestructive),
                  ),
                  onTap: () async {
                    Navigator.of(sheetContext).pop();
                    await _updateAvatar('');
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickAndUploadProfilePhoto() async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 256,
        maxHeight: 256,
        imageQuality: 75,
      );
      if (picked == null) return;

      final bytes = await picked.readAsBytes();
      final base64String = base64Encode(bytes);
      final dataUri = 'data:image/jpeg;base64,$base64String';

      await _updateAvatar(dataUri);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to update photo: $e')));
      }
    }
  }

  Future<void> _updateAvatar(String? url) async {
    try {
      await ref.read(authRepositoryProvider).updateUserMetadata({
        'avatar_url': url ?? '',
        'picture': url ?? '',
      });
      ref.invalidate(currentUserProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Profile picture updated successfully.'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update profile picture: $e')),
        );
      }
    }
  }

  Widget _buildProfileAvatar(String? avatarUrl, String name) {
    Widget imageContent;

    if (avatarUrl != null && avatarUrl.isNotEmpty) {
      if (avatarUrl.startsWith('data:image')) {
        try {
          final base64String = avatarUrl.split(',').last;
          final bytes = base64Decode(base64String);
          imageContent = Image.memory(
            bytes,
            width: 56,
            height: 56,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) =>
                _buildFallbackInitial(name),
          );
        } catch (_) {
          imageContent = _buildFallbackInitial(name);
        }
      } else {
        imageContent = Image.network(
          avatarUrl,
          width: 56,
          height: 56,
          fit: BoxFit.cover,
          loadingBuilder: (context, child, loadingProgress) {
            if (loadingProgress == null) return child;
            return const Center(
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    AppColors.primaryActionBlue,
                  ),
                ),
              ),
            );
          },
          errorBuilder: (context, error, stackTrace) =>
              _buildFallbackInitial(name),
        );
      }
    } else {
      imageContent = _buildFallbackInitial(name);
    }

    return Stack(
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: AppColors.softBlueSurface,
            shape: BoxShape.circle,
            border: Border.all(
              color: AppColors.primaryActionBlue.withValues(alpha: 0.3),
            ),
          ),
          child: ClipOval(child: imageContent),
        ),
        Positioned(
          bottom: 0,
          right: 0,
          child: Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              color: AppColors.primaryActionBlue,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 1.5),
            ),
            child: const Icon(
              Icons.camera_alt_rounded,
              size: 11,
              color: Colors.white,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFallbackInitial(String name) {
    return Center(
      child: Text(
        name.isNotEmpty ? name[0].toUpperCase() : 'P',
        style: AppTypography.titleLarge.copyWith(
          color: AppColors.primaryActionBlue,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

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
      final authRepo = ref.read(authRepositoryProvider);
      final catRepo = ref.read(categoryRepositoryProvider);
      catRepo.clearCache();
      ref.invalidate(currentUserProvider);
      ref.invalidate(categoriesProvider);
      ref.invalidate(recentlyDeletedPhotosProvider);
      ref.invalidate(storageUsageProvider);
      await authRepo.signOut();
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
    return Material(
      color: Colors.transparent,
      child: ListTile(
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
      ),
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
    final avatarUrl =
        user?.userMetadata?['avatar_url'] as String? ??
        user?.userMetadata?['picture'] as String? ??
        ref.watch(authRepositoryProvider).googlePhotoUrl;

    return Scaffold(
      backgroundColor: AppColors.mainBackground,
      appBar: AppBar(
        title: const Text('Account & Vault'),
        leading: SizedBox(
          width: 48,
          height: 48,
          child: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
            tooltip: 'Categories',
            onPressed: () => context.go('/categories'),
          ),
        ),
      ),
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
                      GestureDetector(
                        onTap: _showProfilePhotoOptions,
                        child: _buildProfileAvatar(avatarUrl, name),
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
                        icon: Icons.vpn_key_outlined,
                        title: 'Vault Recovery Code',
                        subtitle: 'View your unique recovery code',
                        onTap: () => context.push('/recovery-code'),
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
