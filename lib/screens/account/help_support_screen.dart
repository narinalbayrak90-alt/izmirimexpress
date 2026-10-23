import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../providers/app_providers.dart';
import '../../services/api_exception.dart';
import '../../services/support_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../widgets/app_loader.dart';
import '../../widgets/primary_button.dart';

/// Help & Support screen (project.txt Module 14) — the admin's contact
/// details (App Setting > App Contact Us) plus a message form that emails
/// the admin directly (`POST /support/contact`, delivered through the
/// admin-configured SMTP settings).
class HelpSupportScreen extends ConsumerStatefulWidget {
  const HelpSupportScreen({super.key});

  @override
  ConsumerState<HelpSupportScreen> createState() => _HelpSupportScreenState();
}

class _HelpSupportScreenState extends ConsumerState<HelpSupportScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _messageController = TextEditingController();

  SupportContactInfo? _contactInfo;
  bool _isLoadingContactInfo = true;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _loadContactInfo();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _loadContactInfo() async {
    try {
      final info = await ref.read(supportServiceProvider).getContactInfo();
      if (!mounted) return;
      setState(() {
        _contactInfo = info;
        _isLoadingContactInfo = false;
      });
    } on ApiException {
      if (!mounted) return;
      setState(() => _isLoadingContactInfo = false);
    }
  }

  Future<void> _openEmail(String email) => launchUrl(Uri(scheme: 'mailto', path: email));

  Future<void> _openPhone(String phone) => launchUrl(Uri(scheme: 'tel', path: phone));

  Future<void> _openWhatsapp(String whatsapp) {
    final digits = whatsapp.replaceAll(RegExp(r'[^0-9]'), '');
    return launchUrl(Uri.parse('https://wa.me/$digits'), mode: LaunchMode.externalApplication);
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
      setState(() {
        _isSubmitting = false;
        _messageController.clear();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('support.message_sent'.tr()),
          backgroundColor: AppColors.success,
        ),
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
      appBar: AppBar(title: Text('account.help_support'.tr())),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_isLoadingContactInfo)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
                  child: Center(child: AppLoader(size: 32)),
                )
              else if (_contactInfo != null && _contactInfo!.hasAnyContact)
                _ContactInfoCard(info: _contactInfo!, onEmail: _openEmail, onPhone: _openPhone, onWhatsapp: _openWhatsapp),
              const SizedBox(height: AppSpacing.xl),
              Text('support.send_message'.tr(), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
              const SizedBox(height: AppSpacing.sm),
              Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextFormField(
                      controller: _nameController,
                      textCapitalization: TextCapitalization.words,
                      textInputAction: TextInputAction.next,
                      decoration: InputDecoration(hintText: 'support.your_name'.tr(), prefixIcon: const Icon(Icons.badge_outlined)),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) return 'support.enter_your_name'.tr();
                        return null;
                      },
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    TextFormField(
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      decoration: InputDecoration(hintText: 'support.your_email'.tr(), prefixIcon: const Icon(Icons.mail_outline_rounded)),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) return 'support.enter_your_email'.tr();
                        if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(value.trim())) {
                          return 'support.enter_valid_email'.tr();
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    TextFormField(
                      controller: _messageController,
                      maxLines: 5,
                      textInputAction: TextInputAction.newline,
                      decoration: InputDecoration(hintText: 'support.how_can_we_help'.tr()),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) return 'support.enter_your_message'.tr();
                        return null;
                      },
                    ),
                    const SizedBox(height: AppSpacing.md),
                    PrimaryButton(label: 'support.send_message_button'.tr(), onPressed: _submit, isLoading: _isSubmitting),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.md),
            ],
          ),
        ),
      ),
    );
  }
}

class _ContactInfoCard extends StatelessWidget {
  const _ContactInfoCard({required this.info, required this.onEmail, required this.onPhone, required this.onWhatsapp});

  final SupportContactInfo info;
  final ValueChanged<String> onEmail;
  final ValueChanged<String> onPhone;
  final ValueChanged<String> onWhatsapp;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          if (info.email != null && info.email!.isNotEmpty)
            _ContactRow(
              icon: Icons.mail_outline_rounded,
              iconColor: AppColors.accent,
              iconBackground: AppColors.infoBackground,
              label: 'support.email'.tr(),
              value: info.email!,
              onTap: () => onEmail(info.email!),
            ),
          if (info.phone != null && info.phone!.isNotEmpty) ...[
            if (info.email != null && info.email!.isNotEmpty) const Divider(height: 1, color: AppColors.divider),
            _ContactRow(
              icon: Icons.call_outlined,
              iconColor: AppColors.primaryDark,
              iconBackground: AppColors.heroBackground,
              label: 'support.phone'.tr(),
              value: info.phone!,
              onTap: () => onPhone(info.phone!),
            ),
          ],
          if (info.whatsapp != null && info.whatsapp!.isNotEmpty) ...[
            if ((info.email != null && info.email!.isNotEmpty) || (info.phone != null && info.phone!.isNotEmpty))
              const Divider(height: 1, color: AppColors.divider),
            _ContactRow(
              icon: Icons.chat_outlined,
              iconColor: AppColors.success,
              iconBackground: AppColors.successBackground,
              label: 'support.whatsapp'.tr(),
              value: info.whatsapp!,
              onTap: () => onWhatsapp(info.whatsapp!),
            ),
          ],
        ],
      ),
    );
  }
}

class _ContactRow extends StatelessWidget {
  const _ContactRow({
    required this.icon,
    required this.iconColor,
    required this.iconBackground,
    required this.label,
    required this.value,
    required this.onTap,
  });

  final IconData icon;
  final Color iconColor;
  final Color iconBackground;
  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm, horizontal: AppSpacing.md),
        child: Row(
          children: [
            Container(
              height: 36,
              width: 36,
              decoration: BoxDecoration(color: iconBackground, borderRadius: BorderRadius.circular(10)),
              child: Icon(icon, size: 18, color: iconColor),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: const TextStyle(fontSize: 11.5, color: AppColors.textSecondary)),
                  Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, size: 20, color: AppColors.textSecondary),
          ],
        ),
      ),
    );
  }
}
