import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/privora_button.dart';
import '../../data/models/vault_photo.dart';

/// Modal bottom sheet displaying metadata for a selected photo.
class PhotoDetailsSheet extends ConsumerWidget {
  final VaultPhoto photo;
  final VoidCallback onRenameRequested;
  final VoidCallback onSetCoverRequested;

  const PhotoDetailsSheet({
    super.key,
    required this.photo,
    required this.onRenameRequested,
    required this.onSetCoverRequested,
  });

  static Future<void> show({
    required BuildContext context,
    required VaultPhoto photo,
    required VoidCallback onRenameRequested,
    required VoidCallback onSetCoverRequested,
  }) {
    return showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      barrierColor: Colors.black54,
      backgroundColor: AppColors.surface,
      builder: (context) => PhotoDetailsSheet(
        photo: photo,
        onRenameRequested: onRenameRequested,
        onSetCoverRequested: onSetCoverRequested,
      ),
    );
  }

  Widget _buildRow(String label, String value, [IconData? icon]) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 18, color: AppColors.secondaryText),
            const SizedBox(width: 12),
          ],
          SizedBox(
            width: 120,
            child: Text(label, style: AppTypography.bodySmall),
          ),
          Expanded(
            child: Text(
              value,
              style: AppTypography.bodyMedium.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Photo Details', style: AppTypography.titleLarge),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 48,
                    height: 48,
                    child: IconButton(
                      icon: const Icon(
                        Icons.edit_outlined,
                        size: 20,
                        color: AppColors.primaryAccent,
                      ),
                      tooltip: 'Rename Photo',
                      onPressed: () {
                        Navigator.of(context).pop();
                        onRenameRequested();
                      },
                    ),
                  ),
                  SizedBox(
                    width: 48,
                    height: 48,
                    child: IconButton(
                      icon: const Icon(Icons.close_rounded, size: 22),
                      tooltip: 'Close',
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildRow('Name', photo.displayName, Icons.label_outline_rounded),
          _buildRow(
            'Encrypted Size',
            Formatters.formatBytes(photo.encryptedSize),
            Icons.lock_outline_rounded,
          ),
          if (photo.width != null && photo.height != null)
            _buildRow(
              'Dimensions',
              '${photo.width} × ${photo.height}',
              Icons.aspect_ratio_rounded,
            ),
          _buildRow('Format', photo.mimeType, Icons.image_outlined),
          _buildRow(
            'Added',
            Formatters.formatDate(photo.createdAt),
            Icons.calendar_today_outlined,
          ),
          const SizedBox(height: 20),
          PrivoraButton(
            text: 'Set as Category Cover',
            variant: PrivoraButtonVariant.secondary,
            leadingIcon: Icons.wallpaper_rounded,
            height: 46,
            onPressed: () {
              Navigator.of(context).pop();
              onSetCoverRequested();
            },
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}
