import 'dart:typed_data';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../providers/app_providers.dart';
import '../../services/api_exception.dart';
import '../../services/app_settings.dart';
import '../../services/auth_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../widgets/app_loader.dart';
import '../../widgets/country_code_picker.dart';
import '../../widgets/primary_button.dart';
import '../home/home_provider.dart';

/// Route entry for [PersonalInformationScreen]. The Account screen passes
/// the profile it already has; when there's none — the web page was
/// refreshed, or the URL opened directly, which drops GoRouter's `extra` —
/// the profile is fetched here instead of failing the cast into a blank
/// grey screen.
class PersonalInformationRoute extends ConsumerStatefulWidget {
  const PersonalInformationRoute({super.key, this.profile});

  final CustomerProfile? profile;

  @override
  ConsumerState<PersonalInformationRoute> createState() => _PersonalInformationRouteState();
}

class _PersonalInformationRouteState extends ConsumerState<PersonalInformationRoute> {
  late Future<CustomerProfile> _profile = _load();

  Future<CustomerProfile> _load() =>
      widget.profile != null ? Future.value(widget.profile) : ref.read(authServiceProvider).getProfile();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<CustomerProfile>(
      future: _profile,
      builder: (context, snapshot) {
        final profile = snapshot.data;
        if (profile != null) return PersonalInformationScreen(initialProfile: profile);
        return Scaffold(
          appBar: AppBar(title: Text('account.personal_information'.tr())),
          body: Center(
            child: snapshot.hasError
                ? TextButton(
                    onPressed: () => setState(() => _profile = _load()),
                    child: Text('common.retry'.tr()),
                  )
                : const AppLoader(),
          ),
        );
      },
    );
  }
}

/// Personal Information / Account Setting screen (project.txt Module 14) —
/// edits the same fields collected at signup (name, email, country code +
/// phone), plus an optional password change and profile photo update, all
/// in one `POST /me/update` call.
///
/// Reached by tapping the Personal Information row, the avatar, or its
/// camera badge on the Account screen; [initialProfile] prefills the form
/// instantly since the Account screen already has it loaded.
class PersonalInformationScreen extends ConsumerStatefulWidget {
  const PersonalInformationScreen({super.key, required this.initialProfile});

  final CustomerProfile initialProfile;

  @override
  ConsumerState<PersonalInformationScreen> createState() => _PersonalInformationScreenState();
}

class _PersonalInformationScreenState extends ConsumerState<PersonalInformationScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _emailController;
  late final TextEditingController _phoneController;
  final _currentPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  late String _countryCode;
  XFile? _pickedPhoto;
  Uint8List? _pickedPhotoBytes;
  bool _changePassword = false;
  bool _obscureCurrent = true;
  bool _obscureNew = true;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initialProfile.name);
    _emailController = TextEditingController(text: widget.initialProfile.email);
    _phoneController = TextEditingController(text: widget.initialProfile.phone);
    _countryCode = widget.initialProfile.countryCode;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto() async {
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
              title: Text('account.take_photo'.tr()),
              onTap: () => Navigator.of(sheetContext).pop(ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined, color: AppColors.primaryDark),
              title: Text('account.choose_from_gallery'.tr()),
              onTap: () => Navigator.of(sheetContext).pop(ImageSource.gallery),
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
        ),
      ),
    );
    if (source == null) return;

    final picked = await ImagePicker().pickImage(source: source, maxWidth: 1024, imageQuality: 85);
    if (picked == null) return;
    // Bytes rather than a dart:io File so the preview and upload also work
    // in the web build, where picked images have no real file path.
    final bytes = await picked.readAsBytes();
    if (!mounted) return;
    setState(() {
      _pickedPhoto = picked;
      _pickedPhotoBytes = bytes;
    });
  }

  void _pickCountryCode(List<String> countryCodes) {
    pickCountryCode(
      context,
      countryCodes: countryCodes,
      selected: _countryCode,
      onSelect: (code) => setState(() => _countryCode = code),
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSubmitting = true);
    try {
      final profile = await ref.read(authServiceProvider).updateProfile(
            name: _nameController.text.trim(),
            email: _emailController.text.trim(),
            countryCode: _countryCode,
            phone: _phoneController.text.trim(),
            currentPassword: _changePassword ? _currentPasswordController.text : null,
            newPassword: _changePassword ? _newPasswordController.text : null,
            photo: _pickedPhoto,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('account.profile_updated'.tr())),
      );
      Navigator.of(context).pop(profile);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(appSettingsProvider).valueOrNull ?? const AppSettings.fallback();
    final countryCodes = settings.countryCodes;

    return Scaffold(
      appBar: AppBar(title: Text('account.personal_information'.tr())),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(child: _AvatarPicker(profile: widget.initialProfile, pickedPhoto: _pickedPhotoBytes, onTap: _pickPhoto)),
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
                    CountryCodeField(code: _countryCode, onTap: () => _pickCountryCode(countryCodes)),
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
                const SizedBox(height: AppSpacing.xl),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _changePassword,
                  activeThumbColor: AppColors.primaryDark,
                  title: Text(
                    'account.change_password'.tr(),
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                  ),
                  onChanged: (value) => setState(() => _changePassword = value),
                ),
                if (_changePassword) ...[
                  const SizedBox(height: AppSpacing.sm),
                  _FieldLabel('account.current_password_label'.tr()),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _currentPasswordController,
                    obscureText: _obscureCurrent,
                    textInputAction: TextInputAction.next,
                    decoration: InputDecoration(
                      hintText: 'account.current_password_hint'.tr(),
                      prefixIcon: const Icon(Icons.lock_outline_rounded),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscureCurrent ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                          color: AppColors.textSecondary,
                        ),
                        onPressed: () => setState(() => _obscureCurrent = !_obscureCurrent),
                      ),
                    ),
                    validator: (value) {
                      if (!_changePassword) return null;
                      if (value == null || value.isEmpty) return 'account.current_password_error'.tr();
                      return null;
                    },
                  ),
                  const SizedBox(height: AppSpacing.md),
                  _FieldLabel('account.new_password_label'.tr()),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _newPasswordController,
                    obscureText: _obscureNew,
                    textInputAction: TextInputAction.next,
                    decoration: InputDecoration(
                      hintText: 'account.new_password_hint'.tr(),
                      prefixIcon: const Icon(Icons.lock_outline_rounded),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscureNew ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                          color: AppColors.textSecondary,
                        ),
                        onPressed: () => setState(() => _obscureNew = !_obscureNew),
                      ),
                    ),
                    validator: (value) {
                      if (!_changePassword) return null;
                      if (value == null || value.isEmpty) return 'account.new_password_hint'.tr();
                      if (value.length < 6) return 'auth.password_length_error'.tr();
                      return null;
                    },
                  ),
                  const SizedBox(height: AppSpacing.md),
                  _FieldLabel('account.confirm_new_password_label'.tr()),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _confirmPasswordController,
                    obscureText: _obscureNew,
                    textInputAction: TextInputAction.done,
                    decoration: InputDecoration(hintText: 'account.confirm_new_password_hint'.tr()),
                    validator: (value) {
                      if (!_changePassword) return null;
                      if (value != _newPasswordController.text) return 'account.passwords_dont_match'.tr();
                      return null;
                    },
                  ),
                ],
                const SizedBox(height: AppSpacing.xl),
                PrimaryButton(label: 'account.save_changes'.tr(), onPressed: _submit, isLoading: _isSubmitting),
                const SizedBox(height: AppSpacing.md),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AvatarPicker extends StatelessWidget {
  const _AvatarPicker({required this.profile, required this.pickedPhoto, required this.onTap});

  final CustomerProfile profile;
  final Uint8List? pickedPhoto;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final hasNetworkPhoto = profile.photoUrl != null && profile.photoUrl!.isNotEmpty;

    return GestureDetector(
      onTap: onTap,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          CircleAvatar(
            radius: 48,
            backgroundColor: AppColors.primary.withValues(alpha: 0.2),
            backgroundImage: pickedPhoto != null
                ? MemoryImage(pickedPhoto!)
                : hasNetworkPhoto
                    ? NetworkImage(profile.photoUrl!) as ImageProvider
                    : null,
            child: (pickedPhoto == null && !hasNetworkPhoto)
                ? const Icon(Icons.person_rounded, size: 44, color: AppColors.primaryDark)
                : null,
          ),
          Positioned(
            bottom: -2,
            right: -2,
            child: Container(
              height: 32,
              width: 32,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.border),
              ),
              child: const Icon(Icons.camera_alt_rounded, size: 16, color: AppColors.textSecondary),
            ),
          ),
        ],
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
