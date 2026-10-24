import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../providers/app_providers.dart';
import '../../services/api_exception.dart';
import '../../services/rider_auth_service.dart';
import '../../services/support_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../widgets/app_loader.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/primary_button.dart';
import '../home/home_provider.dart';
import 'support_provider.dart';

/// Help & Support screen, pushed from the Account tab's menu — admin's
/// contact details (App Setting > App Contact Us) up top, then a
/// contact-us form that emails the admin directly (see SupportService).
/// Shared backend endpoints with the User App — see SupportController's
/// own class-level context — so this screen only tags its submissions
/// `source: 'rider_app'`, nothing else about it is rider-specific.
class SupportScreen extends ConsumerStatefulWidget {
  const SupportScreen({super.key});

  @override
  ConsumerState<SupportScreen> createState() => _SupportScreenState();
}

class _SupportScreenState extends ConsumerState<SupportScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _messageController = TextEditingController();
  bool _isSubmitting = false;
  bool _prefilled = false;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  void _prefill(RiderProfile rider) {
    if (_prefilled) return;
    _prefilled = true;
    _nameController.text = rider.name;
    _emailController.text = rider.email;
  }

  Future<void> _launch(Uri uri) async {
    // canLaunchUrl() can wrongly answer false on newer Android, so the
    // dialer/mail app is opened directly.
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSubmitting = true);
    try {
      await ref.read(supportServiceProvider).sendContactForm(
            name: _nameController.text.trim(),
            email: _emailController.text.trim(),
            message: _messageController.text.trim(),
          );
      if (!mounted) return;
      _messageController.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('support.form_success'.tr())),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final contactInfo = ref.watch(supportContactInfoProvider);
    final profile = ref.watch(riderProfileProvider);

    profile.whenData(_prefill);

    return Scaffold(
      appBar: AppBar(title: Text('support.title'.tr())),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              contactInfo.when(
                data: (info) => _ContactInfoCard(info: info, onLaunch: _launch),
                loading: () => const Padding(
                  padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
                  child: Center(child: AppLoader(size: 28)),
                ),
                error: (_, _) => EmptyState(message: 'common.error'.tr()),
              ),
              const SizedBox(height: AppSpacing.xl),
              Text('support.form_title'.tr(), style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontSize: 18)),
              const SizedBox(height: 4),
              Text(
                'support.form_subtitle'.tr(),
                style: const TextStyle(fontSize: 13, color: AppColors.textSecondary, height: 1.4),
              ),
              const SizedBox(height: AppSpacing.md),
              Form(
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
                    _FieldLabel('support.message_label'.tr()),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _messageController,
                      maxLines: 5,
                      decoration: InputDecoration(hintText: 'support.message_hint'.tr()),
                      validator: (value) => (value == null || value.trim().isEmpty) ? 'support.message_error'.tr() : null,
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    PrimaryButton(
                      label: 'support.form_submit'.tr(),
                      onPressed: _submit,
                      isLoading: _isSubmitting,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ContactInfoCard extends StatelessWidget {
  const _ContactInfoCard({required this.info, required this.onLaunch});

  final SupportContactInfo info;
  final Future<void> Function(Uri uri) onLaunch;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];

    if (info.email != null && info.email!.isNotEmpty) {
      rows.add(_ContactRow(
        icon: Icons.mail_outline_rounded,
        label: info.email!,
        onTap: () => onLaunch(Uri(scheme: 'mailto', path: info.email)),
      ));
    }
    if (info.phone != null && info.phone!.isNotEmpty) {
      rows.add(_ContactRow(
        icon: Icons.phone_outlined,
        label: info.phone!,
        onTap: () => onLaunch(Uri(scheme: 'tel', path: info.phone)),
      ));
    }
    if (info.whatsapp != null && info.whatsapp!.isNotEmpty) {
      rows.add(_ContactRow(
        icon: Icons.chat_outlined,
        label: info.whatsapp!,
        onTap: () => onLaunch(Uri.parse('https://wa.me/${info.whatsapp!.replaceAll(RegExp(r'[^0-9]'), '')}')),
      ));
    }

    if (rows.isEmpty) {
      return EmptyState(message: 'support.no_contact_info'.tr());
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      decoration: BoxDecoration(color: AppColors.surfaceMuted, borderRadius: BorderRadius.circular(14)),
      child: Column(children: rows),
    );
  }
}

class _ContactRow extends StatelessWidget {
  const _ContactRow({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
        child: Row(
          children: [
            Icon(icon, size: 20, color: AppColors.primaryDark),
            const SizedBox(width: AppSpacing.sm),
            Expanded(child: Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600))),
            const Icon(Icons.chevron_right_rounded, color: AppColors.textSecondary),
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
