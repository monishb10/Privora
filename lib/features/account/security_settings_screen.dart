import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../app/providers.dart';
import '../../core/config/supabase_config.dart';
import '../../core/errors/error_mapper.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/utils/validators.dart';
import 'widgets/recovery_code_modal.dart';

/// Screen detailing Privora's security architecture and privacy controls,
/// including interactive recovery code generation and management.
class SecuritySettingsScreen extends ConsumerStatefulWidget {
  const SecuritySettingsScreen({super.key});

  @override
  ConsumerState<SecuritySettingsScreen> createState() =>
      _SecuritySettingsScreenState();
}

class _SecuritySettingsScreenState
    extends ConsumerState<SecuritySettingsScreen> {
  bool _isLoadingRecoveryStatus = true;
  bool _hasRecoveryCode = false;
  String? _currentRecoveryCode;
  bool _isRecoveryCodeObscured = true;
  bool _isActionInProgress = false;

  @override
  void initState() {
    super.initState();
    _loadRecoveryStatus();
  }

  Future<void> _loadRecoveryStatus() async {
    final user =
        ref.read(currentUserProvider) ??
        SupabaseConfig.client?.auth.currentUser;
    if (user != null) {
      final vaultRepo = ref.read(vaultRepositoryProvider);
      final hasCode = await vaultRepo.hasRecoveryCode(user.id);
      final code = await vaultRepo.getRecoveryCode(user.id);
      if (mounted) {
        setState(() {
          _hasRecoveryCode = hasCode || (code != null && code.isNotEmpty);
          _currentRecoveryCode = code;
          _isLoadingRecoveryStatus = false;
        });
      }
    } else {
      if (mounted) {
        setState(() {
          _isLoadingRecoveryStatus = false;
        });
      }
    }
  }

  Future<String?> _promptCurrentPin() async {
    final pinController = TextEditingController();
    String? localError;

    return showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: AppColors.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              title: const Text(
                'Confirm Your PIN',
                style: AppTypography.titleLarge,
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Enter your current 6-digit PIN to authorize recovery code generation.',
                    style: AppTypography.bodySmall,
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: pinController,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    obscureText: true,
                    autofocus: true,
                    decoration: InputDecoration(
                      labelText: '6-Digit PIN',
                      errorText: localError,
                      counterText: '',
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(null),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () {
                    final entered = pinController.text.trim();
                    if (!Validators.isSixDigitPin(entered)) {
                      setDialogState(() {
                        localError = 'Enter a valid 6-digit PIN';
                      });
                      return;
                    }
                    Navigator.of(dialogContext).pop(entered);
                  },
                  child: const Text('Confirm'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _handleGenerateOrReplaceRecoveryCode() async {
    if (_isActionInProgress) return;

    final pin = await _promptCurrentPin();
    if (pin == null || !mounted) return;

    setState(() => _isActionInProgress = true);

    try {
      final user =
          ref.read(currentUserProvider) ??
          SupabaseConfig.client?.auth.currentUser;
      if (user == null) {
        throw Exception('User session not found. Please log in again.');
      }

      final vaultRepo = ref.read(vaultRepositoryProvider);
      final recoveryCode = await vaultRepo.generateOrReplaceRecoveryCode(
        userId: user.id,
        currentPin: pin,
      );

      if (!mounted) return;

      setState(() {
        _hasRecoveryCode = true;
        _currentRecoveryCode = recoveryCode;
        _isRecoveryCodeObscured = true;
        _isActionInProgress = false;
      });

      await RecoveryCodeModal.show(context, recoveryCode);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isActionInProgress = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(ErrorMapper.mapToUserMessage(e)),
          backgroundColor: AppColors.errorDestructive,
        ),
      );
    }
  }

  Widget _buildSecurityCard({
    required IconData icon,
    required String title,
    required String description,
    required String status,
    Color statusColor = AppColors.success,
    Widget? trailingAction,
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
          // Fixed size icon container
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
                    final isNarrow =
                        constraints.maxWidth < 220 ||
                        MediaQuery.textScalerOf(context).scale(14) > 17;

                    final badgeWidget = Container(
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
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    );

                    if (isNarrow) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(title, style: AppTypography.titleMedium),
                          const SizedBox(height: 6),
                          badgeWidget,
                        ],
                      );
                    }

                    return Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: Text(title, style: AppTypography.titleMedium),
                        ),
                        const SizedBox(width: 8),
                        badgeWidget,
                      ],
                    );
                  },
                ),
                const SizedBox(height: 6),
                Text(
                  description,
                  style: AppTypography.bodySmall,
                  softWrap: true,
                ),
                if (trailingAction != null) ...[
                  const SizedBox(height: 12),
                  trailingAction,
                ],
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
      body: SafeArea(
        child: ListView(
          padding: EdgeInsets.fromLTRB(20, 16, 20, 24 + bottomPadding),
          children: [
            // Interactive Recovery Code Card
            _buildSecurityCard(
              icon: Icons.vpn_key_rounded,
              title: 'Recovery Code',
              description: _hasRecoveryCode
                  ? 'Your unique recovery code is active. Use it strictly to change your PIN or recover your vault if you ever forget your PIN.'
                  : 'Optional backup code to regain vault access if you ever forget your PIN. Store it securely offline.',
              status: _isLoadingRecoveryStatus
                  ? 'Checking...'
                  : (_hasRecoveryCode
                        ? 'Recovery code ready'
                        : 'Not generated'),
              statusColor: _hasRecoveryCode
                  ? AppColors.success
                  : AppColors.secondaryTextColor,
              trailingAction: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_currentRecoveryCode != null &&
                      _currentRecoveryCode!.isNotEmpty) ...[
                    Container(
                      margin: const EdgeInsets.only(top: 4, bottom: 8),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.elevatedSurface,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              _isRecoveryCodeObscured
                                  ? (_currentRecoveryCode!.startsWith('PRIV-')
                                        ? 'PRIV-••••-••••-••••-••••'
                                        : '••••-••••-••••-••••')
                                  : _currentRecoveryCode!,
                              style: AppTypography.labelMedium.copyWith(
                                fontFamily: 'monospace',
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          IconButton(
                            icon: Icon(
                              _isRecoveryCodeObscured
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                              size: 18,
                              color: AppColors.primaryActionBlue,
                            ),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                              minWidth: 28,
                              minHeight: 28,
                            ),
                            onPressed: () {
                              setState(() {
                                _isRecoveryCodeObscured =
                                    !_isRecoveryCodeObscured;
                              });
                            },
                            tooltip: _isRecoveryCodeObscured
                                ? 'Reveal'
                                : 'Hide',
                          ),
                          IconButton(
                            icon: const Icon(
                              Icons.copy_rounded,
                              size: 18,
                              color: AppColors.primaryActionBlue,
                            ),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                              minWidth: 28,
                              minHeight: 28,
                            ),
                            onPressed: () {
                              Clipboard.setData(
                                ClipboardData(text: _currentRecoveryCode!),
                              );
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Recovery code copied to clipboard',
                                  ),
                                  behavior: SnackBarBehavior.floating,
                                ),
                              );
                            },
                            tooltip: 'Copy',
                          ),
                        ],
                      ),
                    ),
                  ],
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: _isActionInProgress
                            ? null
                            : _handleGenerateOrReplaceRecoveryCode,
                        icon: Icon(
                          _hasRecoveryCode
                              ? Icons.sync_rounded
                              : Icons.add_moderator_rounded,
                          size: 15,
                          color: AppColors.primaryActionBlue,
                        ),
                        label: Text(
                          _hasRecoveryCode
                              ? 'Replace recovery code'
                              : 'Generate recovery code',
                          style: AppTypography.labelSmall.copyWith(
                            color: AppColors.primaryActionBlue,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          side: const BorderSide(
                            color: AppColors.primaryActionBlue,
                            width: 1.1,
                          ),
                        ),
                      ),
                      TextButton.icon(
                        onPressed: () => context.push('/recovery-code'),
                        icon: const Icon(
                          Icons.open_in_new_rounded,
                          size: 15,
                          color: AppColors.primaryActionBlue,
                        ),
                        label: Text(
                          'View full page',
                          style: AppTypography.labelSmall.copyWith(
                            color: AppColors.primaryActionBlue,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

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
      ),
    );
  }
}
