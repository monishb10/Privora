import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../app/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/error_view.dart';

/// Screen displaying the user's encrypted cloud storage usage.
class StorageUsageScreen extends ConsumerWidget {
  const StorageUsageScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final storageAsync = ref.watch(storageUsageProvider);
    final categoriesAsync = ref.watch(categoriesProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Cloud Storage'),
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
      body: storageAsync.when(
        data: (totalBytes) {
          int totalPhotos = 0;
          categoriesAsync.whenData((cats) {
            for (final c in cats) {
              totalPhotos += c.photoCount;
            }
          });

          return SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Summary Card
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Column(
                    children: [
                      Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          color: AppColors.primaryAccent.withValues(
                            alpha: 0.12,
                          ),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.cloud_outlined,
                          size: 32,
                          color: AppColors.primaryAccent,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        Formatters.formatBytes(totalBytes),
                        style: AppTypography.displayLarge.copyWith(
                          color: AppColors.primaryAccent,
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Total Encrypted Cloud Storage',
                        style: AppTypography.bodySmall,
                      ),
                      const SizedBox(height: 20),
                      const Divider(),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          Column(
                            children: [
                              Text(
                                '$totalPhotos',
                                style: AppTypography.titleLarge,
                              ),
                              const SizedBox(height: 4),
                              const Text(
                                'Total Photos',
                                style: AppTypography.bodySmall,
                              ),
                            ],
                          ),
                          Container(
                            width: 1,
                            height: 32,
                            color: AppColors.border,
                          ),
                          Column(
                            children: [
                              const Text(
                                '0 B',
                                style: AppTypography.titleLarge,
                              ),
                              const SizedBox(height: 4),
                              const Text(
                                'Phone Storage Used',
                                style: AppTypography.bodySmall,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 28),

                const Text(
                  'Storage Architecture',
                  style: AppTypography.titleMedium,
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Column(
                    children: [
                      _buildArchRow(
                        Icons.smartphone_rounded,
                        'Zero Device Footprint',
                        'Decrypted images are loaded into RAM only and purged upon lock or exit.',
                      ),
                      const Divider(height: 24),
                      _buildArchRow(
                        Icons.lock_clock_outlined,
                        'Client Encrypted Blobs',
                        'Files uploaded to Supabase Storage are strictly AES-256-GCM ciphertexts.',
                      ),
                      const Divider(height: 24),
                      _buildArchRow(
                        Icons.auto_delete_outlined,
                        'Trash Reclamation',
                        'Permanently deleted photos free up cloud storage immediately.',
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
        loading: () => const Center(
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(AppColors.primaryAccent),
          ),
        ),
        error: (err, _) => ErrorView(
          message: err.toString(),
          onRetry: () => ref.invalidate(storageUsageProvider),
        ),
      ),
    );
  }

  Widget _buildArchRow(IconData icon, String title, String subtitle) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 22, color: AppColors.primaryAccent),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: AppTypography.titleSmall.copyWith(
                  color: AppColors.mainText,
                ),
              ),
              const SizedBox(height: 4),
              Text(subtitle, style: AppTypography.bodySmall),
            ],
          ),
        ),
      ],
    );
  }
}
