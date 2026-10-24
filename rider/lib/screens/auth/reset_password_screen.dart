import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../providers/app_providers.dart';
import '../../services/api_exception.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../widgets/auth_badge.dart';
import '../../widgets/primary_button.dart';

/// Enter the reset OTP (always emailed — see [ForgotPasswordScreen]) plus
/// a new password, wired to `POST /rider/auth/reset-password`.
///
/// Unlike the User App's equivalent OTP screen, this only ever handles the
/// "reset" case (rider signup has no OTP step at all), and a successful
/// reset doesn't always mean a token comes back: an account that's still
/// pending/rejected/blocked gets its password changed but is sent back to
/// Login rather than into the app, same gate `POST /rider/auth/login`
/// itself enforces.
class ResetPasswordScreen extends ConsumerStatefulWidget {
  const ResetPasswordScreen({super.key, required this.riderId, this.identifier});

  final int riderId;
  final String? identifier;

  static const _codeLength = 6;

  @override
  ConsumerState<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends ConsumerState<ResetPasswordScreen> {
  late final List<TextEditingController> _controllers = List.generate(
    ResetPasswordScreen._codeLength,
    (_) => TextEditingController(),
  );
  late final List<FocusNode> _focusNodes = List.generate(
    ResetPasswordScreen._codeLength,
    (_) => FocusNode(),
  );
  final _newPasswordController = TextEditingController();

  bool _obscurePassword = true;
  bool _isSubmitting = false;
  Timer? _resendTimer;
  int _resendSecondsLeft = 30;

  @override
  void initState() {
    super.initState();
    _startResendTimer();
  }

  @override
  void dispose() {
    _resendTimer?.cancel();
    for (final controller in _controllers) {
      controller.dispose();
    }
    for (final node in _focusNodes) {
      node.dispose();
    }
    _newPasswordController.dispose();
    super.dispose();
  }

  void _startResendTimer() {
    _resendTimer?.cancel();
    setState(() => _resendSecondsLeft = 30);
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_resendSecondsLeft <= 1) {
        timer.cancel();
        setState(() => _resendSecondsLeft = 0);
        return;
      }
      setState(() => _resendSecondsLeft -= 1);
    });
  }

  String get _code => _controllers.map((c) => c.text).join();

  void _onDigitChanged(int index, String value) {
    if (value.isNotEmpty && index < ResetPasswordScreen._codeLength - 1) {
      _focusNodes[index + 1].requestFocus();
    }
    if (value.isEmpty && index > 0) {
      _focusNodes[index - 1].requestFocus();
    }
    setState(() {});
  }

  String? _statusMessage(String status) {
    switch (status) {
      case 'pending':
        return 'auth.reset_password.status_pending'.tr();
      case 'rejected':
        return 'auth.reset_password.status_rejected'.tr();
      case 'blocked':
        return 'auth.reset_password.status_blocked'.tr();
      default:
        return null;
    }
  }

  Future<void> _submit() async {
    if (_code.length < ResetPasswordScreen._codeLength) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('auth.otp.incomplete_code_error'.tr())),
      );
      return;
    }
    if (_newPasswordController.text.length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('auth.password_length_error'.tr())),
      );
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      final result = await ref.read(riderAuthServiceProvider).resetPassword(
            riderId: widget.riderId,
            code: _code,
            password: _newPasswordController.text,
          );
      if (!mounted) return;

      final token = result.token;
      if (token == null) {
        setState(() => _isSubmitting = false);
        final message = _statusMessage(result.rider.status) ?? 'auth.reset_password.success'.tr();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
        context.go('/login');
        return;
      }

      await ref.read(secureStorageProvider).saveToken(token);
      ref.read(isLoggedInProvider.notifier).state = true;
      ref.read(oneSignalServiceProvider).tagRiderId(result.rider.id);
      ref.read(oneSignalServiceProvider).requestPermission();
      if (!mounted) return;
      context.go('/home');
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _resend() async {
    if (_resendSecondsLeft > 0) return;

    try {
      await ref.read(riderAuthServiceProvider).forgotPassword(identifier: widget.identifier ?? '');
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      return;
    }

    for (final controller in _controllers) {
      controller.clear();
    }
    _focusNodes.first.requestFocus();
    _startResendTimer();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('auth.otp.resent'.tr())));
  }

  @override
  Widget build(BuildContext context) {
    final identifier = widget.identifier;

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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: AppSpacing.sm),
              const AuthBadge(icon: Icons.mark_email_read_outlined),
              const SizedBox(height: AppSpacing.lg),
              Text('auth.otp.title'.tr(), style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 8),
              Text(
                identifier == null || identifier.isEmpty
                    ? 'auth.otp.subtitle_generic'.tr()
                    : 'auth.otp.subtitle_with_identifier'.tr(namedArgs: {'identifier': identifier}),
                style: const TextStyle(fontSize: 15, color: AppColors.textSecondary, height: 1.4),
              ),
              const SizedBox(height: AppSpacing.xl),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: List.generate(
                  ResetPasswordScreen._codeLength,
                  (index) => _OtpDigitField(
                    controller: _controllers[index],
                    focusNode: _focusNodes[index],
                    onChanged: (value) => _onDigitChanged(index, value),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Text('auth.otp.new_password_label'.tr(), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
              const SizedBox(height: 8),
              TextFormField(
                controller: _newPasswordController,
                obscureText: _obscurePassword,
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) => _submit(),
                decoration: InputDecoration(
                  hintText: 'auth.otp.new_password_hint'.tr(),
                  prefixIcon: const Icon(Icons.lock_outline_rounded),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                      color: AppColors.textSecondary,
                    ),
                    onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              PrimaryButton(
                label: 'auth.otp.reset_password_submit'.tr(),
                onPressed: _submit,
                isLoading: _isSubmitting,
              ),
              const SizedBox(height: AppSpacing.lg),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('auth.otp.no_code'.tr(), style: const TextStyle(color: AppColors.textSecondary)),
                  TextButton(
                    onPressed: _resendSecondsLeft > 0 ? null : _resend,
                    style: TextButton.styleFrom(foregroundColor: AppColors.primaryDark),
                    child: Text(
                      _resendSecondsLeft > 0
                          ? 'auth.otp.resend_in'.tr(namedArgs: {'seconds': '$_resendSecondsLeft'})
                          : 'auth.otp.resend'.tr(),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
            ],
          ),
        ),
      ),
    );
  }
}

class _OtpDigitField extends StatelessWidget {
  const _OtpDigitField({required this.controller, required this.focusNode, required this.onChanged});

  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 44,
      height: 52,
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        onChanged: onChanged,
        textAlign: TextAlign.center,
        keyboardType: TextInputType.number,
        maxLength: 1,
        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: const InputDecoration(counterText: ''),
      ),
    );
  }
}
