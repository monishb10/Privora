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
import '../../core/widgets/privora_button.dart';

/// Screen displaying the user's unique account recovery code,
/// allowing secure viewing, copying, replacing, and using it for PIN change / recovery.
class RecoveryCodeScreen extends ConsumerStatefulWidget {
  const RecoveryCodeScreen({super.key});

  @override
  ConsumerState<RecoveryCodeScreen> createState() => _RecoveryCodeScreenState();
}

class _RecoveryCodeScreenState extends ConsumerState<RecoveryCodeScreen> {
  bool _isLoading = true;
  String? _recoveryCode;
  bool _hasCloudEnvelope = false;
  bool _isObscured = true;
  bool _isActionInProgress = false;

  @override
  void initState() {
    super.initState();
    _loadRecoveryCode();
  }

  Future<void> _loadRecoveryCode() async {
    final user =
        ref.read(currentUserProvider) ??
        SupabaseConfig.client?.auth.currentUser;
    if (user == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    final vaultRepo = ref.read(vaultRepositoryProvider);
    final code = await vaultRepo.getRecoveryCode(user.id);
    final hasEnvelope = await vaultRepo.hasRecoveryCode(user.id);

    if (mounted) {
      setState(() {
        _recoveryCode = code;
        _hasCloudEnvelope = hasEnvelope;
        _isLoading = false;
      });
    }
  }

  void _copyToClipboard() {
    if (_recoveryCode == null || _recoveryCode!.isEmpty) return;
    Clipboard.setData(ClipboardData(text: _recoveryCode!));
    HapticFeedback.lightImpact();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Recovery code copied to clipboard'),
        behavior: SnackBarBehavior.floating,
      ),
    );
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
                'Confirm Your Current PIN',
                style: AppTypography.titleLarge,
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Enter your current 6-digit PIN to authorize generating a new recovery code.',
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

  Future<void> _handleReplaceRecoveryCode() async {
    if (_isActionInProgress) return;

    final pin = await _promptCurrentPin();
    if (pin == null || !mounted) return;

    setState(() => _isActionInProgress = true);

    try {
      final user =
          ref.read(currentUserProvider) ??
          SupabaseConfig.client?.auth.currentUser;
      if (user == null) {
        throw Exception('User session not found. Please sign in again.');
      }

      final vaultRepo = ref.read(vaultRepositoryProvider);
      final newCode = await vaultRepo.generateOrReplaceRecoveryCode(
        userId: user.id,
        currentPin: pin,
      );

      if (!mounted) return;

      setState(() {
        _recoveryCode = newCode;
        _hasCloudEnvelope = true;
        _isObscured = false;
        _isActionInProgress = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Recovery code replaced and saved successfully.'),
          backgroundColor: AppColors.success,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isActionInProgress = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(ErrorMapper.mapToUserMessage(e)),
          backgroundColor: AppColors.errorDestructive,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  String _maskedCode(String code) {
    // Keep prefix if present (e.g. PRIV-) and mask the rest with bullets
    if (code.startsWith('PRIV-')) {
      return 'PRIV-••••-••••-••••-••••';
    }
    return '••••-••••-••••-••••-••••';
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.paddingOf(context).bottom;

    return Scaffold(
      backgroundColor: AppColors.mainBackground,
      appBar: AppBar(
        title: const Text('Vault Recovery Code'),
        leading: SizedBox(
          width: 48,
          height: 48,
          child: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
            tooltip: 'Back',
            onPressed: () => context.pop(),
          ),
        ),
      ),
      body: SafeArea(
        child: _isLoading
            ? const Center(
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(
                    AppColors.primaryActionBlue,
                  ),
                ),
              )
            : ListView(
                padding: EdgeInsets.fromLTRB(20, 16, 20, 24 + bottomPadding),
                children: [
                  // Icon Header
                  Center(
                    child: Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        color: AppColors.softBlueSurface,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: AppColors.primaryActionBlue.withValues(
                            alpha: 0.3,
                          ),
                          width: 2,
                        ),
                      ),
                      child: const Icon(
                        Icons.vpn_key_rounded,
                        color: AppColors.primaryActionBlue,
                        size: 34,
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    'Unique Account Recovery Code',
                    style: AppTypography.displayMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      'This recovery code is unique to your Google account. It is strictly used to change your PIN or recover access to your encrypted vault if you ever forget your PIN.',
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.secondaryTextColor,
                        height: 1.45,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(height: 28),

                  // Recovery Code Box Card
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
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'YOUR RECOVERY CODE',
                              style: AppTypography.labelSmall.copyWith(
                                color: AppColors.secondaryTextColor,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1.1,
                              ),
                            ),
                            if (_recoveryCode != null)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.success.withValues(
                                    alpha: 0.15,
                                  ),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  'Active',
                                  style: AppTypography.labelSmall.copyWith(
                                    color: AppColors.success,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 14),

                        if (_recoveryCode != null &&
                            _recoveryCode!.isNotEmpty) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 14,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.softBlueSurface,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: AppColors.primaryActionBlue.withValues(
                                  alpha: 0.2,
                                ),
                              ),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: SelectableText(
                                    _isObscured
                                        ? _maskedCode(_recoveryCode!)
                                        : _recoveryCode!,
                                    style: AppTypography.titleMedium.copyWith(
                                      color: AppColors.primaryText,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 1.2,
                                      fontFamily: 'monospace',
                                    ),
                                  ),
                                ),
                                IconButton(
                                  icon: Icon(
                                    _isObscured
                                        ? Icons.visibility_outlined
                                        : Icons.visibility_off_outlined,
                                    color: AppColors.primaryActionBlue,
                                    size: 20,
                                  ),
                                  tooltip: _isObscured ? 'Reveal' : 'Hide',
                                  onPressed: () {
                                    setState(() {
                                      _isObscured = !_isObscured;
                                    });
                                  },
                                ),
                                IconButton(
                                  icon: const Icon(
                                    Icons.copy_rounded,
                                    color: AppColors.primaryActionBlue,
                                    size: 20,
                                  ),
                                  tooltip: 'Copy Code',
                                  onPressed: _copyToClipboard,
                                ),
                              ],
                            ),
                          ),
                        ] else ...[
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: AppColors.softBlueSurface,
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.info_outline_rounded,
                                  color: AppColors.primaryActionBlue,
                                  size: 22,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    _hasCloudEnvelope
                                        ? 'Recovery code is active on cloud. Tap "Replace Recovery Code" below to display and refresh your code on this device.'
                                        : 'No recovery code generated yet for this account.',
                                    style: AppTypography.bodySmall,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Guidance Card
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.softBlueSurface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: AppColors.primaryActionBlue.withValues(
                          alpha: 0.15,
                        ),
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.shield_outlined,
                          color: AppColors.primaryActionBlue,
                          size: 22,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'How to use this code',
                                style: AppTypography.titleSmall.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '• Forgot your PIN? Tap "Forgot PIN" on the unlock screen and enter this recovery code to set a new PIN.\n• Changing PIN? Use this code whenever you want to reset your PIN without entering the old one.\n• Store this code in a secure offline notebook or password manager.',
                                style: AppTypography.bodySmall.copyWith(
                                  color: AppColors.secondaryTextColor,
                                  height: 1.45,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 28),

                  // Action Buttons
                  if (_recoveryCode != null && _recoveryCode!.isNotEmpty) ...[
                    PrivoraButton(
                      text: 'Copy Recovery Code',
                      leadingIcon: Icons.copy_rounded,
                      onPressed: _copyToClipboard,
                    ),
                    const SizedBox(height: 14),
                  ],

                  PrivoraButton(
                    text: 'Change PIN with Recovery Code',
                    variant: PrivoraButtonVariant.secondary,
                    leadingIcon: Icons.lock_reset_rounded,
                    onPressed: () => context.push('/recover-vault'),
                  ),
                  const SizedBox(height: 14),

                  PrivoraButton(
                    text: _isActionInProgress
                        ? 'Generating...'
                        : 'Replace Recovery Code',
                    variant: PrivoraButtonVariant.text,
                    leadingIcon: Icons.sync_rounded,
                    isLoading: _isActionInProgress,
                    onPressed: _isActionInProgress
                        ? null
                        : _handleReplaceRecoveryCode,
                  ),
                ],
              ),
      ),
    );
  }
}
