import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/app_providers.dart';
import '../../services/api_exception.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../widgets/app_loader.dart';

/// Account-deletion confirmation — current password plus typing the
/// literal word "delete", the same double-gate pattern as most "this is
/// permanent" flows elsewhere. Pops `true` only once
/// RiderAuthService.deleteAccount has actually succeeded server-side, so
/// the caller (AccountScreen) knows it's safe to clear the local
/// session and navigate away; `false`/`null` otherwise.
class DeleteAccountDialog extends ConsumerStatefulWidget {
  const DeleteAccountDialog({super.key});

  @override
  ConsumerState<DeleteAccountDialog> createState() => _DeleteAccountDialogState();
}

class _DeleteAccountDialogState extends ConsumerState<DeleteAccountDialog> {
  final _formKey = GlobalKey<FormState>();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _obscurePassword = true;
  bool _isSubmitting = false;

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSubmitting = true);
    try {
      await ref.read(riderAuthServiceProvider).deleteAccount(currentPassword: _passwordController.text);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('account.delete_dialog_title'.tr()),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'account.delete_dialog_warning'.tr(),
              style: const TextStyle(fontSize: 13, color: AppColors.textSecondary, height: 1.4),
            ),
            const SizedBox(height: AppSpacing.md),
            Text('auth.password_label'.tr(), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
            const SizedBox(height: 8),
            TextFormField(
              controller: _passwordController,
              obscureText: _obscurePassword,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.lock_outline_rounded),
                suffixIcon: IconButton(
                  icon: Icon(_obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined, color: AppColors.textSecondary),
                  onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                ),
              ),
              validator: (value) => (value == null || value.isEmpty) ? 'auth.password_error'.tr() : null,
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              'account.delete_dialog_type_confirm'.tr(),
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _confirmController,
              decoration: const InputDecoration(prefixIcon: Icon(Icons.warning_amber_rounded)),
              validator: (value) {
                if (!const {'delete', 'sil'}.contains(value?.trim().toLowerCase())) return 'account.delete_dialog_confirm_error'.tr();
                return null;
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(false),
          child: Text('common.cancel'.tr()),
        ),
        ElevatedButton(
          // Reset the app-wide full-width ElevatedButton theme (see
          // AppTheme) so this dialog action sizes to its content instead
          // of stretching edge to edge.
          style: ElevatedButton.styleFrom(minimumSize: const Size(64, 40), backgroundColor: AppColors.error),
          onPressed: _isSubmitting ? null : _submit,
          child: _isSubmitting
              ? const SizedBox(height: 20, width: 20, child: AppLoader(size: 18, color: Colors.white))
              : Text('account.delete_confirm'.tr(), style: const TextStyle(color: Colors.white)),
        ),
      ],
    );
  }
}
