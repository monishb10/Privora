import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/privora_button.dart';

/// Secure modal displaying the newly generated recovery code ONCE.
/// Wipes the plaintext code from memory as soon as the modal is dismissed.
class RecoveryCodeModal extends StatefulWidget {
  final String recoveryCode;

  const RecoveryCodeModal({super.key, required this.recoveryCode});

  static Future<void> show(BuildContext context, String recoveryCode) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (context) => RecoveryCodeModal(recoveryCode: recoveryCode),
    );
  }

  @override
  State<RecoveryCodeModal> createState() => _RecoveryCodeModalState();
}

class _RecoveryCodeModalState extends State<RecoveryCodeModal> {
  late String? _ephemeralCode;
  bool _copied = false;

  @override
  void initState() {
    super.initState();
    _ephemeralCode = widget.recoveryCode;
  }

  @override
  void dispose() {
    // Memory hygiene: zero out the ephemeral reference
    _ephemeralCode = null;
    super.dispose();
  }

  void _handleCopy() {
    if (_ephemeralCode == null) return;
    Clipboard.setData(ClipboardData(text: _ephemeralCode!));
    setState(() => _copied = true);

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Recovery code copied to clipboard'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.paddingOf(context).bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(24, 16, 24, 24 + bottomPadding),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Drag handle
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

          // Header Icon & Title
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.elevatedSurface,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.vpn_key_rounded,
                  color: AppColors.primaryAccent,
                  size: 24,
                ),
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Text(
                  'Your Recovery Code',
                  style: AppTypography.titleLarge,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          Text(
            'Save this recovery code in a secure password manager or offline location. It allows you to regain access to your vault if you ever forget your PIN.',
            style: AppTypography.bodySmall.copyWith(
              color: AppColors.secondaryTextColor,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 20),

          // Code display box
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
            decoration: BoxDecoration(
              color: AppColors.elevatedSurface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.border),
            ),
            child: Center(
              child: SelectableText(
                _ephemeralCode ?? '',
                style: AppTypography.bodyLarge.copyWith(
                  fontFamily: 'monospace',
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 2.0,
                  color: AppColors.primaryText,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
          const SizedBox(height: 14),

          // Critical Warning Banner
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.errorDestructive.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: AppColors.errorDestructive.withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.warning_amber_rounded,
                  color: AppColors.errorDestructive,
                  size: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'This code will NEVER be displayed again. If you close this screen without saving it, you will have to generate a replacement with your PIN.',
                    style: AppTypography.bodySmall.copyWith(
                      color: AppColors.errorDestructive,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Action Buttons
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _handleCopy,
                  icon: Icon(
                    _copied ? Icons.check_rounded : Icons.copy_rounded,
                    size: 18,
                  ),
                  label: Text(_copied ? 'Copied' : 'Copy code'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: PrivoraButton(
                  text: 'I saved it',
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
