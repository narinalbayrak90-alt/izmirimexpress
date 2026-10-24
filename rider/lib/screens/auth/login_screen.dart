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

/// Rider App login: identifier (email or phone) + password, wired to
/// `POST /rider/auth/login`. Anything other than an approved account is
/// rejected by the backend with a 403 (see RiderAuthController::login) —
/// that hands off to [VerificationStatusScreen] so the rider sees exactly
/// where their application stands and can re-check, rather than getting a
/// one-line snackbar. Every other failure (bad credentials, network) is
/// still a plain snackbar.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _identifierController = TextEditingController(text: '');
  final _passwordController = TextEditingController(text: '');
  bool _obscurePassword = true;
  bool _isSubmitting = false;

  @override
  void dispose() {
    _identifierController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSubmitting = true);
    try {
      final result = await ref.read(riderAuthServiceProvider).login(
            identifier: _identifierController.text.trim(),
            password: _passwordController.text,
          );
      if (!mounted) return;

      await ref.read(secureStorageProvider).saveToken(result.token!);
      ref.read(isLoggedInProvider.notifier).state = true;
      ref.read(oneSignalServiceProvider).tagRiderId(result.rider.id);
      ref.read(oneSignalServiceProvider).requestPermission();
      if (!mounted) return;
      context.go('/home');
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _isSubmitting = false);

      // 403 = valid credentials, but the account isn't approved
      // (pending/rejected/blocked). Hand off to the status screen with
      // the same credentials so it can show — and re-check — where the
      // application stands.
      if (e.statusCode == 403) {
        context.push('/verification-status', extra: {
          'identifier': _identifierController.text.trim(),
          'password': _passwordController.text,
        });
        return;
      }

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
                const AuthBadge(icon: Icons.two_wheeler_rounded),
                const SizedBox(height: AppSpacing.lg),
                Text('auth.login.title'.tr(), style: Theme.of(context).textTheme.headlineMedium),
                const SizedBox(height: 8),
                Text(
                  'auth.login.subtitle'.tr(),
                  style: const TextStyle(fontSize: 15, color: AppColors.textSecondary, height: 1.4),
                ),
                const SizedBox(height: AppSpacing.xl),
                _FieldLabel('auth.email_or_phone_label'.tr()),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _identifierController,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(
                    hintText: 'auth.email_or_phone_hint'.tr(),
                    prefixIcon: const Icon(Icons.person_outline_rounded),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) return 'auth.email_or_phone_error'.tr();
                    return null;
                  },
                ),
                const SizedBox(height: AppSpacing.md),
                _FieldLabel('auth.password_label'.tr()),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _passwordController,
                  obscureText: _obscurePassword,
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _submit(),
                  decoration: InputDecoration(
                    hintText: 'auth.login.password_hint'.tr(),
                    prefixIcon: const Icon(Icons.lock_outline_rounded),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                        color: AppColors.textSecondary,
                      ),
                      onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) return 'auth.password_error'.tr();
                    return null;
                  },
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => context.push('/forgot-password'),
                    style: TextButton.styleFrom(foregroundColor: AppColors.primaryDark),
                    child: Text('auth.login.forgot_password'.tr(), style: const TextStyle(fontWeight: FontWeight.w600)),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                PrimaryButton(label: 'auth.login.submit'.tr(), onPressed: _submit, isLoading: _isSubmitting),
                const SizedBox(height: AppSpacing.xl),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('auth.login.no_account'.tr(), style: const TextStyle(color: AppColors.textSecondary)),
                    TextButton(
                      onPressed: () => context.push('/signup'),
                      style: TextButton.styleFrom(foregroundColor: AppColors.primaryDark),
                      child: Text('auth.sign_up'.tr(), style: const TextStyle(fontWeight: FontWeight.w700)),
                    ),
                  ],
                ),
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
