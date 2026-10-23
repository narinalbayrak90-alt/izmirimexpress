import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../providers/app_providers.dart';
import '../../services/api_exception.dart';
import '../../services/auth_service.dart';
import '../../services/pwa_install.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../widgets/app_bottom_nav.dart';
import '../../widgets/app_loader.dart';
import '../../widgets/install_app.dart';

const _languages = {'tr': 'Türkçe', 'en': 'English', 'es': 'Español', 'ar': 'العربية'};

/// Account screen (project.txt Module 14) — profile summary with real
/// stats (wallet balance, order counts, verification status), a Quick
/// Actions grid, and an Account Settings menu.
///
/// Change Language and Delete Account are fully wired (the localization
/// infra and a soft-delete endpoint already exist). Everything else in the
/// menu links to screens from later Module 10/11/14 work that isn't built
/// yet, so those rows show a "coming soon" notice rather than a dead 404.
class AccountScreen extends ConsumerStatefulWidget {
  const AccountScreen({super.key});

  @override
  ConsumerState<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends ConsumerState<AccountScreen> {
  CustomerProfile? _profile;
  String? _loadError;
  bool _isLoggingOut = false;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    setState(() => _loadError = null);
    try {
      final profile = await ref.read(authServiceProvider).getProfile();
      if (!mounted) return;
      setState(() => _profile = profile);
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.statusCode == 401) {
        // Stale/expired token — clear it and drop back to the guest home
        // screen instead of showing a dead-end error the customer can't
        // act on.
        await ref.read(secureStorageProvider).clearToken();
        if (!mounted) return;
        context.go('/home');
        return;
      }
      setState(() => _loadError = e.message);
    }
  }

  Future<void> _confirmLogout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('account.logout_confirm_title'.tr()),
        content: Text('account.logout_confirm_body'.tr()),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text('common.cancel'.tr()),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: Text('account.logout'.tr()),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _logout();
  }

  Future<void> _logout() async {
    setState(() => _isLoggingOut = true);
    try {
      await ref.read(authServiceProvider).logout();
    } on ApiException {
      // Best-effort server-side token revoke — clear the local token and
      // log the customer out either way rather than stranding them.
    }
    await ref.read(secureStorageProvider).clearToken();
    // So a shared/reused device stops receiving this customer's
    // personalised push notifications once they've signed out.
    ref.read(oneSignalServiceProvider).clearUserTag();
    if (!mounted) return;
    context.go('/home');
  }

  Future<void> _openPersonalInformation() async {
    final profile = _profile;
    if (profile == null) return;
    final result = await context.push('/account/personal-information', extra: profile);
    if (!mounted || result is! CustomerProfile) return;
    setState(() => _profile = result);
  }

  Future<void> _showLanguagePicker() async {
    await showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'account.change_language'.tr(),
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              for (final entry in _languages.entries)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(entry.value),
                  trailing: sheetContext.locale.languageCode == entry.key
                      ? const Icon(
                          Icons.check_circle_rounded,
                          color: AppColors.success,
                        )
                      : null,
                  onTap: () async {
                    await sheetContext.setLocale(Locale(entry.key));
                    await ref.read(settingsStorageProvider).setManuallyChosenLanguage();
                    if (sheetContext.mounted) Navigator.of(sheetContext).pop();
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmDeleteAccount() async {
    final deleted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => const _DeleteAccountDialog(),
    );
    if (deleted != true) return;

    await ref.read(secureStorageProvider).clearToken();
    ref.read(oneSignalServiceProvider).clearUserTag();
    if (!mounted) return;
    context.go('/home');
  }

  @override
  Widget build(BuildContext context) {
    final profile = _profile;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.md,
            AppSpacing.md,
            AppSpacing.xl,
          ),
          children: [
            const _AccountHeader(),
            const SizedBox(height: AppSpacing.lg),
            if (profile == null)
              _buildLoadingOrError()
            else ...[
              _ProfileCard(
                profile: profile,
                onTap: _openPersonalInformation,
              ),
              const SizedBox(height: AppSpacing.xl),
              Text(
                'account.quick_actions'.tr(),
                style: Theme.of(
                  context,
                ).textTheme.headlineMedium?.copyWith(fontSize: 18),
              ),
              const SizedBox(height: AppSpacing.md),
              _QuickActionsGrid(
                onMyOrdersTap: () => context.push('/orders'),
                onSavedAddressesTap: () => context.push('/account/saved-addresses'),
                onWalletTap: () => context.push('/account/wallet'),
              ),
              const SizedBox(height: AppSpacing.xl),
              Text(
                'account.account_settings'.tr(),
                style: Theme.of(
                  context,
                ).textTheme.headlineMedium?.copyWith(fontSize: 18),
              ),
              const SizedBox(height: AppSpacing.md),
              _SettingsCard(
                rows: [
                  _MenuRowData(
                    icon: Icons.person_outline_rounded,
                    iconColor: AppColors.accent,
                    iconBackground: AppColors.infoBackground,
                    label: 'account.personal_information'.tr(),
                    onTap: _openPersonalInformation,
                  ),
                  _MenuRowData(
                    icon: Icons.notifications_none_rounded,
                    iconColor: AppColors.primaryDark,
                    iconBackground: AppColors.heroBackground,
                    label: 'account.notifications'.tr(),
                    onTap: () => context.push('/notifications'),
                  ),
                  _MenuRowData(
                    icon: Icons.language_rounded,
                    iconColor: AppColors.accent,
                    iconBackground: AppColors.infoBackground,
                    label: 'account.change_language'.tr(),
                    onTap: _showLanguagePicker,
                  ),
                  if (PwaInstall.isAvailable)
                    _MenuRowData(
                      icon: Icons.install_mobile_rounded,
                      iconColor: AppColors.accent,
                      iconBackground: AppColors.infoBackground,
                      label: 'pwa.account_row'.tr(),
                      onTap: () => installApp(context),
                    ),
                  _MenuRowData(
                    icon: Icons.headset_mic_outlined,
                    iconColor: AppColors.accent,
                    iconBackground: AppColors.infoBackground,
                    label: 'account.help_support'.tr(),
                    onTap: () => context.push('/account/help-support'),
                  ),
                  _MenuRowData(
                    icon: Icons.card_giftcard_rounded,
                    iconColor: AppColors.error,
                    iconBackground: AppColors.errorBackground,
                    label: 'account.invite_earn'.tr(),
                    onTap: () => context.push('/account/invite-earn'),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              _SettingsCard(
                rows: [
                  _MenuRowData(
                    icon: Icons.delete_outline_rounded,
                    iconColor: AppColors.error,
                    iconBackground: AppColors.errorBackground,
                    label: 'account.delete_account'.tr(),
                    isDestructive: true,
                    onTap: _confirmDeleteAccount,
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              _SettingsCard(
                rows: [
                  _MenuRowData(
                    icon: Icons.logout_rounded,
                    iconColor: AppColors.error,
                    iconBackground: AppColors.errorBackground,
                    label: 'account.logout'.tr(),
                    isDestructive: true,
                    onTap: _isLoggingOut ? null : _confirmLogout,
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
      bottomNavigationBar: const AppBottomNav(activeTab: AppTab.account),
    );
  }

  Widget _buildLoadingOrError() {
    if (_loadError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.error_outline_rounded,
                color: AppColors.error,
                size: 40,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                _loadError!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.textSecondary),
              ),
              const SizedBox(height: AppSpacing.md),
              OutlinedButton(
                onPressed: _loadProfile,
                child: Text('common.retry'.tr()),
              ),
            ],
          ),
        ),
      );
    }
    return const Padding(
      padding: EdgeInsets.only(top: AppSpacing.xl),
      child: Center(child: AppLoader()),
    );
  }
}

class _AccountHeader extends StatelessWidget {
  const _AccountHeader();

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => Navigator.of(context).maybePop(),
          borderRadius: BorderRadius.circular(21),
          child: const SizedBox(
            height: 42,
            width: 42,
            child: Icon(Icons.arrow_back_rounded, color: AppColors.textPrimary, size: 24),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'account.my_account'.tr(),
                style: Theme.of(
                  context,
                ).textTheme.headlineMedium?.copyWith(fontSize: 26),
              ),
              const SizedBox(height: 4),
              Text(
                'account.header_subtitle'.tr(),
                style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        InkWell(
          onTap: () => context.push('/notifications'),
          borderRadius: BorderRadius.circular(21),
          child: const SizedBox(
            height: 42,
            width: 42,
            child: Icon(Icons.notifications_none_rounded, color: AppColors.textPrimary, size: 24),
          ),
        ),
      ],
    );
  }
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({required this.profile, required this.onTap});

  final CustomerProfile profile;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.heroBackground,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                CircleAvatar(
                  radius: 36,
                  backgroundColor: AppColors.primary.withValues(alpha: 0.2),
                  backgroundImage:
                      (profile.photoUrl != null && profile.photoUrl!.isNotEmpty)
                      ? NetworkImage(profile.photoUrl!)
                      : null,
                  child: (profile.photoUrl == null || profile.photoUrl!.isEmpty)
                      ? const Icon(
                          Icons.person_rounded,
                          size: 34,
                          color: AppColors.primaryDark,
                        )
                      : null,
                ),
                Positioned(
                  bottom: -2,
                  right: -2,
                  child: Container(
                    height: 24,
                    width: 24,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.border),
                    ),
                    child: const Icon(
                      Icons.camera_alt_rounded,
                      size: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          profile.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                      if (profile.isVerified) ...[
                        const SizedBox(width: 6),
                        const _VerifiedBadge(),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    profile.email,
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  Text(
                    '+${profile.countryCode} ${profile.phone}',
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              color: AppColors.textSecondary,
            ),
          ],
        ),
      ),
    );
  }
}

class _VerifiedBadge extends StatelessWidget {
  const _VerifiedBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.check_circle_rounded,
            size: 12,
            color: AppColors.primaryDark,
          ),
          const SizedBox(width: 3),
          Text(
            'account.verified'.tr(),
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: AppColors.primaryDark,
            ),
          ),
        ],
      ),
    );
  }
}


class _QuickActionsGrid extends StatelessWidget {
  const _QuickActionsGrid({
    required this.onMyOrdersTap,
    required this.onSavedAddressesTap,
    required this.onWalletTap,
  });

  final VoidCallback onMyOrdersTap;
  final VoidCallback onSavedAddressesTap;
  final VoidCallback onWalletTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _QuickActionTile(
            icon: Icons.local_shipping_outlined,
            iconColor: AppColors.primaryDark,
            iconBackground: AppColors.heroBackground,
            label: 'orders.title'.tr(),
            onTap: onMyOrdersTap,
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: _QuickActionTile(
            icon: Icons.location_on_outlined,
            iconColor: AppColors.accent,
            iconBackground: AppColors.infoBackground,
            label: 'account.saved_addresses'.tr(),
            onTap: onSavedAddressesTap,
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: _QuickActionTile(
            icon: Icons.account_balance_wallet_outlined,
            iconColor: AppColors.success,
            iconBackground: AppColors.successBackground,
            label: 'account.wallet'.tr(),
            onTap: onWalletTap,
          ),
        ),
      ],
    );
  }
}

class _QuickActionTile extends StatelessWidget {
  const _QuickActionTile({
    required this.icon,
    required this.iconColor,
    required this.iconBackground,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final Color iconColor;
  final Color iconBackground;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(
          vertical: AppSpacing.md,
          horizontal: AppSpacing.xs,
        ),
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          children: [
            Container(
              height: 42,
              width: 42,
              decoration: BoxDecoration(
                color: iconBackground,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: iconColor, size: 20),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MenuRowData {
  const _MenuRowData({
    required this.icon,
    required this.iconColor,
    required this.iconBackground,
    required this.label,
    required this.onTap,
    this.isDestructive = false,
  });

  final IconData icon;
  final Color iconColor;
  final Color iconBackground;
  final String label;
  final VoidCallback? onTap;
  final bool isDestructive;
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({required this.rows});

  final List<_MenuRowData> rows;

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
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) const Divider(height: 1, color: AppColors.divider),
            _MenuRow(
              data: rows[i],
              isFirst: i == 0,
              isLast: i == rows.length - 1,
            ),
          ],
        ],
      ),
    );
  }
}

class _MenuRow extends StatelessWidget {
  const _MenuRow({
    required this.data,
    required this.isFirst,
    required this.isLast,
  });

  final _MenuRowData data;
  final bool isFirst;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: data.onTap,
      borderRadius: BorderRadius.vertical(
        top: isFirst ? const Radius.circular(16) : Radius.zero,
        bottom: isLast ? const Radius.circular(16) : Radius.zero,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          vertical: AppSpacing.sm,
          horizontal: AppSpacing.md,
        ),
        child: Row(
          children: [
            Container(
              height: 36,
              width: 36,
              decoration: BoxDecoration(
                color: data.iconBackground,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(data.icon, size: 18, color: data.iconColor),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                data.label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: data.isDestructive
                      ? AppColors.error
                      : AppColors.textPrimary,
                ),
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              size: 20,
              color: AppColors.textSecondary.withValues(
                alpha: data.onTap == null ? 0.4 : 1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Delete Account confirmation (project.txt Module 14) — requires the
/// current password (so a stolen/left-open session can't destroy the
/// account on its own) plus typing "DELETE" (so it can't be dismissed by
/// muscle memory), and performs the deletion itself so a wrong password
/// can be shown inline without the dialog closing.
class _DeleteAccountDialog extends ConsumerStatefulWidget {
  const _DeleteAccountDialog();

  @override
  ConsumerState<_DeleteAccountDialog> createState() => _DeleteAccountDialogState();
}

class _DeleteAccountDialogState extends ConsumerState<_DeleteAccountDialog> {
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _obscurePassword = true;
  bool _isSubmitting = false;
  String? _error;

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  bool get _canSubmit =>
      !_isSubmitting &&
      _passwordController.text.isNotEmpty &&
      _confirmController.text.trim().toUpperCase() == 'account.delete_confirm_word'.tr().toUpperCase();

  Future<void> _submit() async {
    setState(() {
      _isSubmitting = true;
      _error = null;
    });
    try {
      await ref.read(authServiceProvider).deleteAccount(currentPassword: _passwordController.text);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _error = e.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final confirmWord = 'account.delete_confirm_word'.tr();
    return AlertDialog(
      title: Text('account.delete_account_title'.tr()),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'account.delete_account_body'.tr(),
              style: const TextStyle(fontSize: 13, color: AppColors.textSecondary, height: 1.4),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _passwordController,
              obscureText: _obscurePassword,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: 'auth.password_label'.tr(),
                suffixIcon: IconButton(
                  icon: Icon(_obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                  onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Text.rich(
              TextSpan(
                style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
                children: [
                  TextSpan(text: 'account.delete_type_prefix'.tr()),
                  TextSpan(text: confirmWord, style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.error)),
                  TextSpan(text: 'account.delete_type_suffix'.tr()),
                ],
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _confirmController,
              textCapitalization: TextCapitalization.characters,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(hintText: confirmWord),
            ),
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(_error!, style: const TextStyle(fontSize: 12.5, color: AppColors.error)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(false),
          child: Text('common.cancel'.tr()),
        ),
        TextButton(
          onPressed: _canSubmit ? _submit : null,
          style: TextButton.styleFrom(foregroundColor: AppColors.error),
          child: _isSubmitting
              ? const SizedBox(height: 16, width: 16, child: AppLoader(size: 16, color: AppColors.error))
              : Text('common.delete'.tr()),
        ),
      ],
    );
  }
}
