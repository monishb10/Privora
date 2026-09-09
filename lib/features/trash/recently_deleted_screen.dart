import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../app/providers.dart';
import '../../core/constants/app_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_motion.dart';
import '../../core/theme/app_typography.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/confirmation_dialog.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/error_view.dart';
import '../../data/models/vault_photo.dart';
import '../pin/widgets/pin_keyboard.dart';

/// Screen managing soft-deleted photos scheduled for auto-expiration in 30 days.
/// Permanent deletion strictly requires PIN verification.
class RecentlyDeletedScreen extends ConsumerStatefulWidget {
  const RecentlyDeletedScreen({super.key});

  @override
  ConsumerState<RecentlyDeletedScreen> createState() =>
      _RecentlyDeletedScreenState();
}

class _RecentlyDeletedScreenState extends ConsumerState<RecentlyDeletedScreen> {
  Future<bool> _verifyPinForPermanentDeletion() async {
    final verified = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => const _PinVerificationDialog(
        title: 'Confirm Permanent Deletion',
        message:
            'Enter your 6-digit PIN to permanently erase items from cloud storage.',
      ),
    );
    return verified == true;
  }

  Future<void> _handleRestore(VaultPhoto photo) async {
    final user = ref.read(currentUserProvider);
    if (user == null) return;

    try {
      await ref.read(photoRepositoryProvider).restorePhoto(photo.id, user.id);
      ref.invalidate(recentlyDeletedPhotosProvider);
      ref.invalidate(categoriesProvider);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Restored "${photo.displayName}".')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to restore: $e')));
      }
    }
  }

  Future<void> _handlePermanentDelete(VaultPhoto photo) async {
    final isPinValid = await _verifyPinForPermanentDeletion();
    if (!isPinValid || !mounted) return;

    final user = ref.read(currentUserProvider);
    if (user == null) return;

    try {
      await ref
          .read(photoRepositoryProvider)
          .permanentlyDeletePhoto(photo, user.id);
      ref.invalidate(recentlyDeletedPhotosProvider);
      ref.invalidate(storageUsageProvider);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Permanently deleted "${photo.displayName}".'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to permanently delete: $e')),
        );
      }
    }
  }

  Future<void> _handleEmptyTrash(List<VaultPhoto> photos) async {
    final confirmed = await ConfirmationDialog.show(
      context: context,
      title: 'Empty Recently Deleted?',
      message:
          'All ${photos.length} photos will be permanently deleted from cloud storage immediately. This action cannot be undone.',
      confirmText: 'Continue',
      isDestructive: true,
      icon: Icons.delete_forever_rounded,
    );

    if (confirmed != true || !mounted) return;

    final isPinValid = await _verifyPinForPermanentDeletion();
    if (!isPinValid || !mounted) return;

    final user = ref.read(currentUserProvider);
    if (user == null) return;

    try {
      await ref.read(photoRepositoryProvider).emptyTrash(user.id);
      ref.invalidate(recentlyDeletedPhotosProvider);
      ref.invalidate(storageUsageProvider);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Recently Deleted emptied.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to empty trash: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final trashAsync = ref.watch(recentlyDeletedPhotosProvider);
    final masterKey = ref.watch(vaultRepositoryProvider).activeMasterKey;

    return Scaffold(
      backgroundColor: AppColors.mainBackground,
      appBar: AppBar(
        title: const Text('Recently Deleted'),
        leading: SizedBox(
          width: 48,
          height: 48,
          child: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
            tooltip: 'Categories',
            onPressed: () => context.go('/categories'),
          ),
        ),
        actions: [
          trashAsync.maybeWhen(
            data: (photos) => photos.isNotEmpty
                ? TextButton(
                    onPressed: () => _handleEmptyTrash(photos),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.errorDestructive,
                    ),
                    child: const Text('Empty Trash'),
                  )
                : const SizedBox.shrink(),
            orElse: () => const SizedBox.shrink(),
          ),
        ],
      ),
      body: trashAsync.when(
        data: (photos) {
          if (photos.isEmpty) {
            return const EmptyState(
              icon: Icons.delete_outline_rounded,
              title: 'Trash is empty',
              subtitle:
                  'Photos you delete will appear here for 30 days before being permanently erased.',
            );
          }

          return Column(
            children: [
              // Retention policy notice
              Container(
                color: AppColors.softBlueSurface,
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 10,
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.info_outline_rounded,
                      size: 16,
                      color: AppColors.primaryActionBlue,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Items are permanently erased after 30 days.',
                        style: AppTypography.labelSmall.copyWith(
                          color: AppColors.primaryText,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.separated(
                  padding: EdgeInsets.only(
                    left: 20,
                    right: 20,
                    top: 14,
                    // Safe scrolling clearance for floating navigation capsule
                    bottom: 120 + MediaQuery.paddingOf(context).bottom,
                  ),
                  itemCount: photos.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final photo = photos[index];

                    return Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.cardSurface,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: AppColors.borderDivider,
                          width: 1.0,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.cardShadow,
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          // Thumbnail
                          ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: SizedBox(
                              width: 60,
                              height: 60,
                              child: masterKey == null
                                  ? Container(color: AppColors.softBlueSurface)
                                  : FutureBuilder<Uint8List>(
                                      future: ref
                                          .read(photoRepositoryProvider)
                                          .loadThumbnail(
                                            photo: photo,
                                            masterKey: masterKey,
                                          ),
                                      builder: (context, snapshot) {
                                        if (snapshot.hasData) {
                                          return TweenAnimationBuilder<double>(
                                            tween: Tween<double>(
                                              begin: 0.0,
                                              end: 1.0,
                                            ),
                                            duration:
                                                AppMotion.thumbnailFadeDuration,
                                            builder: (context, opacity, _) =>
                                                Opacity(
                                                  opacity: opacity,
                                                  child: Image.memory(
                                                    snapshot.data!,
                                                    fit: BoxFit.cover,
                                                  ),
                                                ),
                                          );
                                        }
                                        return Container(
                                          color: AppColors.softBlueSurface,
                                        );
                                      },
                                    ),
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  photo.displayName,
                                  style: AppTypography.bodyMedium.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    const Icon(
                                      Icons.timer_outlined,
                                      size: 14,
                                      color: AppColors.errorDestructive,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      Formatters.formatRemainingDays(
                                        photo.deleteAfter,
                                      ),
                                      style: AppTypography.bodySmall.copyWith(
                                        color: AppColors.errorDestructive,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(
                              Icons.restore_rounded,
                              color: AppColors.primaryActionBlue,
                            ),
                            tooltip: 'Restore Photo',
                            onPressed: () => _handleRestore(photo),
                          ),
                          IconButton(
                            icon: const Icon(
                              Icons.delete_forever_rounded,
                              color: AppColors.errorDestructive,
                            ),
                            tooltip: 'Permanently Delete',
                            onPressed: () => _handlePermanentDelete(photo),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
        loading: () => const Center(
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(
              AppColors.primaryActionBlue,
            ),
          ),
        ),
        error: (err, _) => ErrorView(
          message: err.toString(),
          onRetry: () => ref.invalidate(recentlyDeletedPhotosProvider),
        ),
      ),
    );
  }
}

/// PIN confirmation modal specifically required before permanent deletion.
class _PinVerificationDialog extends ConsumerStatefulWidget {
  final String title;
  final String message;

  const _PinVerificationDialog({required this.title, required this.message});

  @override
  ConsumerState<_PinVerificationDialog> createState() =>
      _PinVerificationDialogState();
}

class _PinVerificationDialogState
    extends ConsumerState<_PinVerificationDialog> {
  String _pin = '';
  bool _hasError = false;
  String? _errorMessage;
  bool _isVerifying = false;

  void _onDigit(String d) {
    if (_pin.length < AppConstants.pinLength && !_isVerifying) {
      setState(() {
        _hasError = false;
        _errorMessage = null;
        _pin += d;
      });

      if (_pin.length == AppConstants.pinLength) {
        _verify();
      }
    }
  }

  void _onDelete() {
    if (_pin.isNotEmpty && !_isVerifying) {
      setState(() {
        _hasError = false;
        _errorMessage = null;
        _pin = _pin.substring(0, _pin.length - 1);
      });
    }
  }

  Future<void> _verify() async {
    setState(() => _isVerifying = true);

    try {
      final isValid = await ref
          .read(vaultRepositoryProvider)
          .verifyAndUnlock(_pin);
      if (!mounted) return;

      if (isValid) {
        Navigator.of(context).pop(true);
      } else {
        setState(() {
          _hasError = true;
          _errorMessage = 'Incorrect PIN.';
          _pin = '';
          _isVerifying = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _hasError = true;
        _errorMessage = e.toString();
        _pin = '';
        _isVerifying = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.cardSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: AppColors.borderDivider),
      ),
      contentPadding: const EdgeInsets.all(20),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(widget.title, style: AppTypography.titleMedium),
              IconButton(
                icon: const Icon(Icons.close_rounded, size: 20),
                onPressed: () => Navigator.of(context).pop(false),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            widget.message,
            style: AppTypography.bodySmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          if (_errorMessage != null) ...[
            Text(
              _errorMessage!,
              style: const TextStyle(
                color: AppColors.errorDestructive,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 8),
          ],
          PinDots(length: _pin.length, hasError: _hasError),
          const SizedBox(height: 16),
          PinKeypad(
            onDigitPressed: _onDigit,
            onDeletePressed: _onDelete,
            enabled: !_isVerifying,
          ),
        ],
      ),
    );
  }
}
