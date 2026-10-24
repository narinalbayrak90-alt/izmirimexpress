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
import '../booking/booking_providers.dart';

/// OTP verification screen (project.txt Module 2).
///
/// Shared by the signup flow and the forgot-password flow — which one it's
/// for is passed in via `GoRouterState.extra` as `{'customerId': ...,
/// 'identifier': ..., 'purpose': 'signup' | 'reset'}`.
///
/// For `signup` (and login on an unverified account), entering the code
/// calls `POST /auth/verify-otp` and logs the customer in. For `reset`, a
/// "new password" field appears once the code is entered and the button
/// calls `POST /auth/reset-password`, which verifies the code and sets the
/// password in one step — also logging the customer in on success.
class OtpVerificationScreen extends ConsumerStatefulWidget {
  const OtpVerificationScreen({super.key, this.customerId, this.identifier, this.purpose = 'signup'});

  final int? customerId;
  final String? identifier;
  final String purpose;

  static const _codeLength = 6;

  @override
  ConsumerState<OtpVerificationScreen> createState() => _OtpVerificationScreenState();
}

class _OtpVerificationScreenState extends ConsumerState<OtpVerificationScreen> {
  late final List<TextEditingController> _controllers = List.generate(
    OtpVerificationScreen._codeLength,
    (_) => TextEditingController(),
  );
  late final List<FocusNode> _focusNodes = List.generate(
    OtpVerificationScreen._codeLength,
    (_) => FocusNode(),
  );
  final _newPasswordController = TextEditingController();

  bool _obscurePassword = true;
  bool _isVerifying = false;
  Timer? _resendTimer;
  int _resendSecondsLeft = 30;

  bool get _isReset => widget.purpose == 'reset';

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
    // A pasted or autofilled code arrives in one box: spread it over the
    // boxes. Typing into a filled box keeps only the new digit.
    if (value.length > 1) {
      final digits = value.length >= OtpVerificationScreen._codeLength ? value : value.substring(value.length - 1);
      if (digits.length == 1) {
        _controllers[index].text = digits;
      } else {
        for (var i = 0; i < OtpVerificationScreen._codeLength; i++) {
          _controllers[i].text = i < digits.length ? digits[i] : '';
        }
        _focusNodes[OtpVerificationScreen._codeLength - 1].requestFocus();
        setState(() {});
        return;
      }
      value = digits;
    }
    if (value.isNotEmpty && index < OtpVerificationScreen._codeLength - 1) {
      _focusNodes[index + 1].requestFocus();
    }
    if (value.isEmpty && index > 0) {
      _focusNodes[index - 1].requestFocus();
    }
    setState(() {});
  }

  Future<void> _verify() async {
    if (_code.length < OtpVerificationScreen._codeLength) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('auth.otp.incomplete_code_error'.tr())),
      );
      return;
    }

    final customerId = widget.customerId;
    if (customerId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('common.unexpected_error'.tr())),
      );
      return;
    }

    if (_isReset && _newPasswordController.text.length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('auth.otp.new_password_error'.tr())),
      );
      return;
    }

    setState(() => _isVerifying = true);
    try {
      final token = _isReset
          ? await ref.read(authServiceProvider).resetPassword(
                customerId: customerId,
                code: _code,
                password: _newPasswordController.text,
              )
          : await ref.read(authServiceProvider).verifyOtp(customerId: customerId, code: _code);

      await completeAuthSession(ref, token: token, customerId: customerId);
      if (!mounted) return;
      context.go(postAuthRoute(ref));
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _isVerifying = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _resend() async {
    if (_resendSecondsLeft > 0) return;

    final customerId = widget.customerId;
    if (customerId != null) {
      try {
        await ref.read(authServiceProvider).resendOtp(customerId: customerId, purpose: widget.purpose);
      } on ApiException catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
        return;
      }
    }

    for (final controller in _controllers) {
      controller.clear();
    }
    _focusNodes.first.requestFocus();
    _startResendTimer();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('auth.otp.resent'.tr())),
    );
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
              Text(
                'auth.otp.title'.tr(),
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 8),
              Text(
                // A reset code always goes by email, even when the customer typed their phone.
                _isReset && (identifier == null || !identifier.contains('@'))
                    ? 'auth.otp.subtitle_email'.tr()
                    : identifier == null || identifier.isEmpty
                    ? 'auth.otp.subtitle_generic'.tr()
                    : 'auth.otp.subtitle_with_identifier'.tr(namedArgs: {'identifier': identifier}),
                style: const TextStyle(fontSize: 15, color: AppColors.textSecondary, height: 1.4),
              ),
              const SizedBox(height: AppSpacing.xl),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: List.generate(
                  OtpVerificationScreen._codeLength,
                  (index) => _OtpDigitField(
                    controller: _controllers[index],
                    focusNode: _focusNodes[index],
                    onChanged: (value) => _onDigitChanged(index, value),
                  ),
                ),
              ),
              if (_isReset) ...[
                const SizedBox(height: AppSpacing.lg),
                Text(
                  'auth.otp.new_password_label'.tr(),
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _newPasswordController,
                  obscureText: _obscurePassword,
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _verify(),
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
              ],
              const SizedBox(height: AppSpacing.xl),
              PrimaryButton(
                label: _isReset ? 'auth.otp.reset_password_submit'.tr() : 'auth.otp.verify_submit'.tr(),
                onPressed: _verify,
                isLoading: _isVerifying,
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
        textAlignVertical: TextAlignVertical.center,
        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        // The theme's 16 px side padding leaves no room for a digit in a
        // box this narrow, so the boxes use none.
        decoration: const InputDecoration(contentPadding: EdgeInsets.zero),
      ),
    );
  }
}
