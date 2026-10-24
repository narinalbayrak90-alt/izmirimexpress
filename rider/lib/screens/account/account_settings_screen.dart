import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../providers/app_providers.dart';
import '../../services/api_exception.dart';
import '../../services/rider_auth_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../widgets/app_loader.dart';
import '../../widgets/document_picker.dart';
import '../../widgets/primary_button.dart';
import '../home/home_provider.dart';

/// Edit-profile screen, pushed from the Account tab's "Account Setting"
/// menu item — name/contact/vehicle, optional document re-upload, and an
/// optional password change, all through the one `POST /rider/me/update`
/// call (see RiderAuthService.update). A password change only fires when
/// [_newPasswordController] is filled in; [_currentPasswordController] is
/// only required at that point, not for the rest of the form.
class AccountSettingsScreen extends ConsumerStatefulWidget {
  const AccountSettingsScreen({super.key});

  @override
  ConsumerState<AccountSettingsScreen> createState() => _AccountSettingsScreenState();
}

class _AccountSettingsScreenState extends ConsumerState<AccountSettingsScreen> {
  static const _vehicleTypes = ['bike', 'car', 'van', 'truck'];

  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _vehicleNumberController = TextEditingController();
  final _currentPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();

  String? _vehicleType;
  File? _photo;
  File? _drivingLicense;
  File? _idProof;
  bool _obscureCurrentPassword = true;
  bool _obscureNewPassword = true;
  bool _isSubmitting = false;
  bool _prefilled = false;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _vehicleNumberController.dispose();
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    super.dispose();
  }

  void _prefill(RiderProfile rider) {
    if (_prefilled) return;
    _prefilled = true;
    _nameController.text = rider.name;
    _emailController.text = rider.email;
    _phoneController.text = rider.phone;
    _vehicleNumberController.text = rider.vehicleNumber ?? '';
    _vehicleType = rider.vehicleType;
  }

  Future<void> _pickInto(void Function(File file) assign) async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
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

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final newPassword = _newPasswordController.text.trim();
    if (newPassword.isNotEmpty && _currentPasswordController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('account_settings.current_password_required_error'.tr())),
      );
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      await ref.read(riderAuthServiceProvider).update(
            name: _nameController.text.trim(),
            email: _emailController.text.trim(),
            phone: _phoneController.text.trim(),
            vehicleType: _vehicleType!,
            vehicleNumber: _vehicleNumberController.text.trim(),
            currentPassword: newPassword.isEmpty ? null : _currentPasswordController.text,
            newPassword: newPassword.isEmpty ? null : newPassword,
            photoPath: _photo?.path,
            drivingLicensePath: _drivingLicense?.path,
            idProofPath: _idProof?.path,
          );
      ref.invalidate(riderProfileProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('account_settings.success'.tr())),
      );
      Navigator.of(context).pop();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(riderProfileProvider);

    return Scaffold(
      appBar: AppBar(title: Text('account_settings.title'.tr())),
      body: SafeArea(
        top: false,
        child: profile.when(
          data: (rider) {
            _prefill(rider);
            return _buildForm(rider);
          },
          loading: () => const Center(child: AppLoader()),
          error: (_, _) => Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('common.error'.tr()),
                const SizedBox(height: AppSpacing.md),
                TextButton(onPressed: () => ref.invalidate(riderProfileProvider), child: Text('common.retry'.tr())),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildForm(RiderProfile rider) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _FieldLabel('auth.signup.full_name_label'.tr()),
            const SizedBox(height: 8),
            TextFormField(
              controller: _nameController,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(prefixIcon: Icon(Icons.badge_outlined)),
              validator: (value) => (value == null || value.trim().isEmpty) ? 'auth.signup.full_name_error'.tr() : null,
            ),
            const SizedBox(height: AppSpacing.md),
            _FieldLabel('auth.email_label'.tr()),
            const SizedBox(height: 8),
            TextFormField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(prefixIcon: Icon(Icons.mail_outline_rounded)),
              validator: (value) {
                if (value == null || value.trim().isEmpty) return 'auth.email_error'.tr();
                if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(value.trim())) return 'auth.email_invalid_error'.tr();
                return null;
              },
            ),
            const SizedBox(height: AppSpacing.md),
            _FieldLabel('auth.signup.phone_label'.tr()),
            const SizedBox(height: 8),
            TextFormField(
              controller: _phoneController,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(prefixIcon: Icon(Icons.phone_outlined)),
              validator: (value) => (value == null || value.trim().isEmpty) ? 'auth.signup.phone_error'.tr() : null,
            ),
            const SizedBox(height: AppSpacing.md),
            _FieldLabel('auth.signup.vehicle_type_label'.tr()),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: _vehicleType,
              icon: const Icon(Icons.keyboard_arrow_down_rounded),
              decoration: const InputDecoration(prefixIcon: Icon(Icons.two_wheeler_outlined)),
              items: _vehicleTypes.map((type) => DropdownMenuItem(value: type, child: Text('vehicle_types.$type'.tr()))).toList(),
              onChanged: (value) => setState(() => _vehicleType = value),
              validator: (value) => value == null ? 'auth.signup.vehicle_type_error'.tr() : null,
            ),
            const SizedBox(height: AppSpacing.md),
            _FieldLabel('auth.signup.vehicle_number_label'.tr()),
            const SizedBox(height: 8),
            TextFormField(
              controller: _vehicleNumberController,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(prefixIcon: Icon(Icons.directions_car_filled_outlined)),
            ),
            const SizedBox(height: AppSpacing.xl),
            Text('auth.signup.documents_title'.tr(), style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontSize: 18)),
            const SizedBox(height: 4),
            Text(
              'account_settings.documents_subtitle'.tr(),
              style: const TextStyle(fontSize: 13, color: AppColors.textSecondary, height: 1.4),
            ),
            const SizedBox(height: AppSpacing.md),
            DocumentPicker(
              label: 'auth.signup.photo_label'.tr(),
              file: _photo,
              existingImageUrl: rider.photoUrl,
              onPick: () => _pickInto((file) => _photo = file),
              onRemove: () => setState(() => _photo = null),
            ),
            const SizedBox(height: AppSpacing.sm),
            DocumentPicker(
              label: 'auth.signup.driving_license_label'.tr(),
              file: _drivingLicense,
              existingImageUrl: rider.drivingLicenseUrl,
              onPick: () => _pickInto((file) => _drivingLicense = file),
              onRemove: () => setState(() => _drivingLicense = null),
            ),
            const SizedBox(height: AppSpacing.sm),
            DocumentPicker(
              label: 'auth.signup.id_proof_label'.tr(),
              file: _idProof,
              existingImageUrl: rider.idProofUrl,
              onPick: () => _pickInto((file) => _idProof = file),
              onRemove: () => setState(() => _idProof = null),
            ),
            const SizedBox(height: AppSpacing.xl),
            Text('account_settings.change_password_title'.tr(), style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontSize: 18)),
            const SizedBox(height: 4),
            Text(
              'account_settings.change_password_subtitle'.tr(),
              style: const TextStyle(fontSize: 13, color: AppColors.textSecondary, height: 1.4),
            ),
            const SizedBox(height: AppSpacing.md),
            _FieldLabel('account_settings.current_password_label'.tr()),
            const SizedBox(height: 8),
            TextFormField(
              controller: _currentPasswordController,
              obscureText: _obscureCurrentPassword,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.lock_outline_rounded),
                suffixIcon: IconButton(
                  icon: Icon(_obscureCurrentPassword ? Icons.visibility_outlined : Icons.visibility_off_outlined, color: AppColors.textSecondary),
                  onPressed: () => setState(() => _obscureCurrentPassword = !_obscureCurrentPassword),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            _FieldLabel('account_settings.new_password_label'.tr()),
            const SizedBox(height: 8),
            TextFormField(
              controller: _newPasswordController,
              obscureText: _obscureNewPassword,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.lock_reset_rounded),
                suffixIcon: IconButton(
                  icon: Icon(_obscureNewPassword ? Icons.visibility_outlined : Icons.visibility_off_outlined, color: AppColors.textSecondary),
                  onPressed: () => setState(() => _obscureNewPassword = !_obscureNewPassword),
                ),
              ),
              validator: (value) {
                if (value == null || value.isEmpty) return null;
                if (value.length < 6) return 'auth.password_length_error'.tr();
                return null;
              },
            ),
            const SizedBox(height: AppSpacing.xl),
            PrimaryButton(
              label: 'account_settings.save'.tr(),
              onPressed: _submit,
              isLoading: _isSubmitting,
            ),
            const SizedBox(height: AppSpacing.md),
          ],
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
    return Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary));
  }
}
