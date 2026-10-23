import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../providers/app_providers.dart';
import '../../services/api_exception.dart';
import '../../services/app_settings.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../widgets/auth_badge.dart';
import '../../widgets/country_code_picker.dart';
import '../../widgets/primary_button.dart';
import '../booking/booking_providers.dart';
import '../home/home_provider.dart';

/// Signup screen (project.txt Module 2): name, email, country code + phone,
/// password. Calls `POST /auth/register`; if the admin's
/// `signup_verification` setting isn't "none" this hands off to
/// [OtpVerificationScreen], otherwise the returned token logs the customer
/// in immediately.
class SignupScreen extends ConsumerStatefulWidget {
  const SignupScreen({super.key});

  @override
  ConsumerState<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends ConsumerState<SignupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _isSubmitting = false;
  String? _countryCode;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit(List<String> countryCodes) async {
    if (!_formKey.currentState!.validate()) return;
    final countryCode = _countryCode ?? countryCodes.first;

    setState(() => _isSubmitting = true);
    try {
      final result = await ref.read(authServiceProvider).register(
            name: _nameController.text.trim(),
            email: _emailController.text.trim(),
            countryCode: countryCode,
            phone: _phoneController.text.trim(),
            password: _passwordController.text,
          );
      if (!mounted) return;

      if (result.requiresVerification) {
        setState(() => _isSubmitting = false);
        context.push(
          '/otp-verify',
          extra: {
            'customerId': result.customerId,
            'identifier': result.verificationChannel == 'email'
                ? _emailController.text.trim()
                : '+$countryCode ${_phoneController.text.trim()}',
            'purpose': 'signup',
          },
        );
        return;
      }

      await completeAuthSession(ref, token: result.token!, customerId: result.customerId);
      if (!mounted) return;
      context.go(postAuthRoute(ref));
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  void _pickCountryCode(List<String> countryCodes) {
    pickCountryCode(
      context,
      countryCodes: countryCodes,
      selected: _countryCode ?? countryCodes.first,
      onSelect: (code) => setState(() => _countryCode = code),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(appSettingsProvider).valueOrNull ?? const AppSettings.fallback();
    final countryCodes = settings.countryCodes;
    final selectedCode = _countryCode ?? countryCodes.first;

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
                const AuthBadge(icon: Icons.person_add_alt_1_rounded),
                const SizedBox(height: AppSpacing.lg),
                Text(
                  'auth.signup.title'.tr(),
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  'auth.signup.subtitle'.tr(),
                  style: const TextStyle(fontSize: 15, color: AppColors.textSecondary, height: 1.4),
                ),
                const SizedBox(height: AppSpacing.xl),
                _FieldLabel('auth.signup.full_name_label'.tr()),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _nameController,
                  textInputAction: TextInputAction.next,
                  textCapitalization: TextCapitalization.words,
                  decoration: InputDecoration(
                    hintText: 'auth.signup.full_name_hint'.tr(),
                    prefixIcon: const Icon(Icons.badge_outlined),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) return 'auth.signup.full_name_error'.tr();
                    return null;
                  },
                ),
                const SizedBox(height: AppSpacing.md),
                _FieldLabel('auth.email_label'.tr()),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(
                    hintText: 'auth.email_or_phone_hint'.tr(),
                    prefixIcon: const Icon(Icons.mail_outline_rounded),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) return 'auth.email_error'.tr();
                    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(value.trim())) {
                      return 'auth.email_invalid_error'.tr();
                    }
                    return null;
                  },
                ),
                const SizedBox(height: AppSpacing.md),
                _FieldLabel('auth.signup.phone_label'.tr()),
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CountryCodeField(
                      code: selectedCode,
                      onTap: () => _pickCountryCode(countryCodes),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: TextFormField(
                        controller: _phoneController,
                        keyboardType: TextInputType.phone,
                        textInputAction: TextInputAction.next,
                        decoration: InputDecoration(hintText: 'auth.signup.phone_hint'.tr()),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'auth.signup.phone_error'.tr();
                          }
                          return null;
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                _FieldLabel('auth.password_label'.tr()),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _passwordController,
                  obscureText: _obscurePassword,
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _submit(countryCodes),
                  decoration: InputDecoration(
                    hintText: 'auth.signup.password_hint'.tr(),
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
                    if (value == null || value.isEmpty) return 'auth.signup.password_hint'.tr();
                    if (value.length < 6) return 'auth.password_length_error'.tr();
                    return null;
                  },
                ),
                const SizedBox(height: AppSpacing.xl),
                PrimaryButton(
                  label: 'auth.signup.submit'.tr(),
                  onPressed: () => _submit(countryCodes),
                  isLoading: _isSubmitting,
                ),
                const SizedBox(height: AppSpacing.xl),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('auth.signup.have_account'.tr(), style: const TextStyle(color: AppColors.textSecondary)),
                    TextButton(
                      onPressed: () => Navigator.of(context).maybePop(),
                      style: TextButton.styleFrom(foregroundColor: AppColors.primaryDark),
                      child: Text('auth.login.submit'.tr(), style: const TextStyle(fontWeight: FontWeight.w700)),
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
