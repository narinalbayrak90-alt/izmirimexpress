import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../providers/app_providers.dart';
import '../../services/api_exception.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../widgets/auth_badge.dart';
import '../../widgets/document_picker.dart';
import '../../widgets/primary_button.dart';
import '../welcome/welcome_provider.dart';
import '../../utils/iban.dart';
import '../account/iban_sheet.dart';

/// Rider App signup: name/email/phone/password, vehicle type + number, and
/// optional photo/driving-license/ID-proof uploads — everything
/// `POST /rider/auth/register` accepts. Unlike the User App's signup there
/// is no OTP step and no token on success: a new rider's account starts
/// `pending` and can't log in until an admin approves it (see
/// RiderAuthService.register), so a successful submit hands off to
/// [VerificationStatusScreen] — the "under review, check back" state —
/// rather than continuing into the app.
class SignupScreen extends ConsumerStatefulWidget {
  const SignupScreen({super.key});

  @override
  ConsumerState<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends ConsumerState<SignupScreen> {
  static const _vehicleTypes = ['bike', 'car', 'van', 'truck'];

  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _vehicleNumberController = TextEditingController();
  final _ibanController = TextEditingController();
  final _ibanHolderController = TextEditingController();

  String? _vehicleType;
  File? _photo;
  File? _drivingLicense;
  File? _idProof;
  bool _obscurePassword = true;
  bool _isSubmitting = false;
  bool _agreedToTerms = false;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    _vehicleNumberController.dispose();
    _ibanController.dispose();
    _ibanHolderController.dispose();
    super.dispose();
  }

  Future<void> _pickInto(void Function(File file) assign) async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: AppSpacing.sm),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined, color: AppColors.primaryDark),
              title: Text('upload.take_photo'.tr()),
              onTap: () => Navigator.of(sheetContext).pop(ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined, color: AppColors.primaryDark),
              title: Text('upload.choose_from_gallery'.tr()),
              onTap: () => Navigator.of(sheetContext).pop(ImageSource.gallery),
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
        ),
      ),
    );
    if (source == null) return;

    final picked = await ImagePicker().pickImage(source: source, maxWidth: 1600, imageQuality: 85);
    if (picked == null) return;
    setState(() => assign(File(picked.path)));
  }

  /// No-op if [url] is empty/unset (admin hasn't configured it yet) or
  /// can't be launched — same graceful-fallback shape as [_call] on the
  /// order detail screen.
  Future<void> _openUrl(String? url) async {
    if (url == null || url.isEmpty) return;
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    if (!_agreedToTerms) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('auth.signup.agree_terms_error'.tr())),
      );
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      final email = _emailController.text.trim();
      await ref.read(riderAuthServiceProvider).register(
            name: _nameController.text.trim(),
            email: email,
            phone: _phoneController.text.trim(),
            password: _passwordController.text,
            vehicleType: _vehicleType!,
            vehicleNumber: _vehicleNumberController.text.trim(),
            iban: normalizeIban(_ibanController.text),
            ibanHolder: _ibanHolderController.text.trim(),
            photoPath: _photo?.path,
            drivingLicensePath: _drivingLicense?.path,
            idProofPath: _idProof?.path,
          );
      if (!mounted) return;
      // A new rider can't sign in until an admin approves them — send
      // them to the status screen (with the credentials they just chose,
      // so it can check and re-check) rather than into the app.
      context.go('/verification-status', extra: {'identifier': email, 'password': _passwordController.text});
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    // Watched (not just read on tap) so it's already resolved by the
    // time the rider reaches the checkbox — proactively fetching here
    // covers the rare case of landing on Signup without passing through
    // Welcome first, which already triggers the same shared provider.
    ref.watch(welcomeInfoProvider);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          // Always Welcome specifically, not just "pop" — Signup can be
          // reached either from Welcome directly or via Login's "Sign Up"
          // link, and a rider tapping back expects to land on Welcome
          // either way, not back on Login.
          onPressed: () => context.go('/'),
        ),
      ),
      body: SafeArea(
        top: false,
        child: _buildForm(context),
      ),
    );
  }

  Widget _buildForm(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: AppSpacing.sm),
            const AuthBadge(icon: Icons.two_wheeler_rounded),
            const SizedBox(height: AppSpacing.lg),
            Text('auth.signup.title'.tr(), style: Theme.of(context).textTheme.headlineMedium),
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
                hintText: 'auth.email_hint'.tr(),
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
            TextFormField(
              controller: _phoneController,
              keyboardType: TextInputType.phone,
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(
                hintText: 'auth.signup.phone_hint'.tr(),
                prefixIcon: const Icon(Icons.phone_outlined),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) return 'auth.signup.phone_error'.tr();
                return null;
              },
            ),
            const SizedBox(height: AppSpacing.md),
            _FieldLabel('auth.password_label'.tr()),
            const SizedBox(height: 8),
            TextFormField(
              controller: _passwordController,
              obscureText: _obscurePassword,
              textInputAction: TextInputAction.next,
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
            _FieldLabel('auth.signup.vehicle_type_label'.tr()),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: _vehicleType,
              icon: const Icon(Icons.keyboard_arrow_down_rounded),
              decoration: InputDecoration(
                hintText: 'auth.signup.vehicle_type_hint'.tr(),
                prefixIcon: const Icon(Icons.two_wheeler_outlined),
              ),
              items: _vehicleTypes
                  .map((type) => DropdownMenuItem(value: type, child: Text('vehicle_types.$type'.tr())))
                  .toList(),
              onChanged: (value) => setState(() => _vehicleType = value),
              validator: (value) => value == null ? 'auth.signup.vehicle_type_error'.tr() : null,
            ),
            const SizedBox(height: AppSpacing.md),
            _FieldLabel('auth.signup.vehicle_number_label'.tr()),
            const SizedBox(height: 8),
            TextFormField(
              controller: _vehicleNumberController,
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(
                hintText: 'auth.signup.vehicle_number_hint'.tr(),
                prefixIcon: const Icon(Icons.directions_car_filled_outlined),
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            Text(
              'iban.title'.tr(),
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontSize: 18),
            ),
            const SizedBox(height: 4),
            Text(
              'iban.subtitle'.tr(),
              style: const TextStyle(fontSize: 13, color: AppColors.textSecondary, height: 1.4),
            ),
            const SizedBox(height: AppSpacing.md),
            IbanFields(ibanController: _ibanController, holderController: _ibanHolderController, required: true),
            const SizedBox(height: AppSpacing.xl),
            Text(
              'auth.signup.documents_title'.tr(),
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontSize: 18),
            ),
            const SizedBox(height: 4),
            Text(
              'auth.signup.documents_subtitle'.tr(),
              style: const TextStyle(fontSize: 13, color: AppColors.textSecondary, height: 1.4),
            ),
            const SizedBox(height: AppSpacing.md),
            DocumentPicker(
              label: 'auth.signup.photo_label'.tr(),
              file: _photo,
              onPick: () => _pickInto((file) => _photo = file),
              onRemove: () => setState(() => _photo = null),
            ),
            const SizedBox(height: AppSpacing.sm),
            DocumentPicker(
              label: 'auth.signup.driving_license_label'.tr(),
              file: _drivingLicense,
              onPick: () => _pickInto((file) => _drivingLicense = file),
              onRemove: () => setState(() => _drivingLicense = null),
            ),
            const SizedBox(height: AppSpacing.sm),
            DocumentPicker(
              label: 'auth.signup.id_proof_label'.tr(),
              file: _idProof,
              onPick: () => _pickInto((file) => _idProof = file),
              onRemove: () => setState(() => _idProof = null),
            ),
            const SizedBox(height: AppSpacing.lg),
            _AgreeToTermsRow(
              agreed: _agreedToTerms,
              onChanged: (value) => setState(() => _agreedToTerms = value),
              onTapPrivacyPolicy: () => _openUrl(ref.read(welcomeInfoProvider).valueOrNull?.privacyPolicyUrl),
              onTapTerms: () => _openUrl(ref.read(welcomeInfoProvider).valueOrNull?.termsUrl),
            ),
            const SizedBox(height: AppSpacing.lg),
            PrimaryButton(
              label: 'auth.signup.submit'.tr(),
              onPressed: _submit,
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
    );
  }

}

/// Required before [SignupScreen] will submit — see [_SignupScreenState._submit].
/// [onTapPrivacyPolicy]/[onTapTerms] no-op silently if the admin hasn't
/// configured that URL yet (App Setting > Welcome Page > Legal), same
/// "don't fail loudly on optional admin config" shape used elsewhere.
class _AgreeToTermsRow extends StatelessWidget {
  const _AgreeToTermsRow({
    required this.agreed,
    required this.onChanged,
    required this.onTapPrivacyPolicy,
    required this.onTapTerms,
  });

  final bool agreed;
  final ValueChanged<bool> onChanged;
  final VoidCallback onTapPrivacyPolicy;
  final VoidCallback onTapTerms;

  @override
  Widget build(BuildContext context) {
    const linkStyle = TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w700,
      color: AppColors.primaryDark,
      decoration: TextDecoration.underline,
    );
    const textStyle = TextStyle(fontSize: 13, color: AppColors.textSecondary);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 24,
          width: 24,
          child: Checkbox(
            value: agreed,
            onChanged: (value) => onChanged(value ?? false),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text('auth.signup.agree_prefix'.tr(), style: textStyle),
                GestureDetector(onTap: onTapPrivacyPolicy, child: Text('auth.signup.privacy_policy'.tr(), style: linkStyle)),
                Text('auth.signup.and'.tr(), style: textStyle),
                GestureDetector(onTap: onTapTerms, child: Text('auth.signup.terms_conditions'.tr(), style: linkStyle)),
                Text('auth.signup.agree_suffix'.tr(), style: textStyle),
              ],
            ),
          ),
        ),
      ],
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
