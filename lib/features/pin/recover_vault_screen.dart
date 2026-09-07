import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../app/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/utils/validators.dart';
import '../../core/widgets/privora_button.dart';
import '../../core/widgets/privora_logo.dart';

/// Screen allowing recovery of encrypted vault master key using the single-use recovery code.
class RecoverVaultScreen extends ConsumerStatefulWidget {
  const RecoverVaultScreen({super.key});

  @override
  ConsumerState<RecoverVaultScreen> createState() => _RecoverVaultScreenState();
}

class _RecoverVaultScreenState extends ConsumerState<RecoverVaultScreen> {
  final _formKey = GlobalKey<FormState>();
  final _codeController = TextEditingController();
  final _newPinController = TextEditingController();
  final _confirmPinController = TextEditingController();

  bool _isLoading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _codeController.dispose();
    _newPinController.dispose();
    _confirmPinController.dispose();
    super.dispose();
  }

  Future<void> _handleRecovery() async {
    if (!_formKey.currentState!.validate()) return;

    if (_newPinController.text != _confirmPinController.text) {
      setState(() {
        _errorMessage = 'New PINs do not match. Please re-enter.';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final user = ref.read(currentUserProvider);
      if (user == null) {
        throw Exception('Please sign in with your email account first.');
      }

      final vaultRepo = ref.read(vaultRepositoryProvider);
      await vaultRepo.recoverVault(
        userId: user.id,
        recoveryCode: _codeController.text.trim(),
        newPin: _newPinController.text.trim(),
      );

      ref.read(sessionLockServiceProvider.notifier).unlock();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vault restored successfully.')),
      );
      context.go('/categories');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Recover Vault')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const PrivoraLogo(size: 56),
                const SizedBox(height: 20),
                const Text('Vault Recovery', style: AppTypography.displayLarge),
                const SizedBox(height: 8),
                Text(
                  'Enter the 24-character recovery code generated when you first created your vault. This will unwrap your master key and allow you to set a new PIN.',
                  style: AppTypography.bodyMedium.copyWith(
                    color: AppColors.secondaryText,
                  ),
                ),
                const SizedBox(height: 28),

                if (_errorMessage != null) ...[
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppColors.danger.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: AppColors.danger.withValues(alpha: 0.4),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.error_outline_rounded,
                          color: AppColors.danger,
                          size: 20,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            _errorMessage!,
                            style: AppTypography.bodySmall.copyWith(
                              color: AppColors.danger,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                ],

                TextFormField(
                  controller: _codeController,
                  textCapitalization: TextCapitalization.characters,
                  style: AppTypography.bodyLarge.copyWith(
                    letterSpacing: 1.2,
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.w600,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Recovery Code (e.g. PRIV-XXXX-XXXX-XXXX-XXXX)',
                    prefixIcon: Icon(
                      Icons.vpn_key_outlined,
                      color: AppColors.secondaryText,
                    ),
                  ),
                  validator: (val) {
                    if (val == null || val.trim().isEmpty) {
                      return 'Recovery code is required.';
                    }
                    if (val.trim().length < 16) {
                      return 'Please enter a valid recovery code.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                TextFormField(
                  controller: _newPinController,
                  keyboardType: TextInputType.number,
                  obscureText: true,
                  maxLength: 6,
                  style: AppTypography.bodyLarge,
                  decoration: const InputDecoration(
                    labelText: 'New 6-Digit PIN',
                    prefixIcon: Icon(
                      Icons.pin_outlined,
                      color: AppColors.secondaryText,
                    ),
                    counterText: '',
                  ),
                  validator: Validators.validatePin,
                ),
                const SizedBox(height: 16),

                TextFormField(
                  controller: _confirmPinController,
                  keyboardType: TextInputType.number,
                  obscureText: true,
                  maxLength: 6,
                  style: AppTypography.bodyLarge,
                  decoration: const InputDecoration(
                    labelText: 'Confirm New 6-Digit PIN',
                    prefixIcon: Icon(
                      Icons.check_circle_outline_rounded,
                      color: AppColors.secondaryText,
                    ),
                    counterText: '',
                  ),
                  validator: Validators.validatePin,
                ),
                const SizedBox(height: 28),

                PrivoraButton(
                  text: 'Restore Vault Access',
                  isLoading: _isLoading,
                  onPressed: _handleRecovery,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
