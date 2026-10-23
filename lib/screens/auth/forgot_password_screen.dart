import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../providers/app_providers.dart';
import '../../services/api_exception.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../widgets/auth_badge.dart';
import '../../widgets/primary_button.dart';

/// Forgot password screen (project.txt Module 2: "email link or OTP based
/// reset"). Calls `POST /auth/forgot-password`, which always delivers the
/// OTP over email regardless of the admin's `signup_verification` setting
/// (the one channel every customer always has), then hands off to
/// [OtpVerificationScreen] to enter the code and a new password.
class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  ConsumerState<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _identifierController = TextEditingController();
  bool _isSubmitting = false;

  @override
  void dispose() {
    _identifierController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSubmitting = true);
    try {
      final customerId = await ref.read(authServiceProvider).forgotPassword(
            identifier: _identifierController.text.trim(),
          );
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      context.push(
        '/otp-verify',
        extra: {
          'customerId': customerId,
          'identifier': _identifierController.text.trim(),
          'purpose': 'reset',
        },
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: AppSpacing.sm),
                const AuthBadge(icon: Icons.lock_reset_rounded),
                const SizedBox(height: AppSpacing.lg),
                Text(
                  'auth.forgot_password.title'.tr(),
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  'auth.forgot_password.subtitle'.tr(),
                  style: const TextStyle(fontSize: 15, color: AppColors.textSecondary, height: 1.4),
                ),
                const SizedBox(height: AppSpacing.xl),
                _FieldLabel('auth.email_or_phone_label'.tr()),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _identifierController,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _submit(),
                  decoration: InputDecoration(
                    hintText: 'auth.email_or_phone_hint'.tr(),
                    prefixIcon: const Icon(Icons.person_outline_rounded),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'auth.email_or_phone_error'.tr();
                    }
                    return null;
                  },
                ),
                const SizedBox(height: AppSpacing.xl),
                PrimaryButton(label: 'auth.forgot_password.submit'.tr(), onPressed: _submit, isLoading: _isSubmitting),
                const SizedBox(height: AppSpacing.md),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
    );
  }
}
