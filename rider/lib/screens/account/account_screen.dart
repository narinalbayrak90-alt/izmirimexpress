import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../providers/app_providers.dart';
import '../../services/rider_auth_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../widgets/app_loader.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/primary_button.dart';
import '../home/home_provider.dart';
import 'delete_account_dialog.dart';
import 'language_picker.dart';
import 'iban_sheet.dart';

/// Account tab: the rider's own name/email/phone, a menu into Account
/// Setting/Earning/History, and the two account-ending actions — Delete
/// My Account and Log Out — the bottom nav's fourth destination (see
/// HomeScreen). Logout lives here rather than on the Home tab's app bar
/// now that there's a dedicated place for it.
class AccountScreen extends ConsumerStatefulWidget {
  const AccountScreen({super.key});

  @override
  ConsumerState<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends ConsumerState<AccountScreen> {
  bool _isLoggingOut = false;
  bool _isDeleting = false;

  Future<void> _logout() async {
    final confirmed = await confirmDialog(
      context,
      title: 'account.logout_confirm_title'.tr(),
      message: 'account.logout_confirm_message'.tr(),
      confirmLabel: 'home.logout'.tr(),
    );
    if (!mounted || !confirmed) return;

    setState(() => _isLoggingOut = true);
    try {
      await ref.read(riderAuthServiceProvider).logout();
    } catch (_) {
      // Best-effort server-side revoke — the local token is cleared
      // either way so the rider isn't stuck logged in if this fails
      // (e.g. offline).
    }
    await _clearSessionAndLeave();
  }

  Future<void> _deleteAccount() async {
    final deleted = await showDialog<bool>(
      context: context,
      builder: (_) => const DeleteAccountDialog(),
    );
    if (!mounted || deleted != true) return;

    setState(() => _isDeleting = true);
    await _clearSessionAndLeave();
  }

  /// Shared by [_logout] and [_deleteAccount] — both end the session the
  /// same way once the server side is done (revoked or the account is
  /// gone): stop the location heartbeat, drop the push tag, clear the
  /// stored token, and head back to Welcome.
  Future<void> _clearSessionAndLeave() async {
    ref.read(riderLocationTrackerProvider).stop();
    ref.read(oneSignalServiceProvider).clearRiderTag();
    await ref.read(secureStorageProvider).clearToken();
    ref.read(isLoggedInProvider.notifier).state = false;
    if (mounted) context.go('/');
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(riderProfileProvider);

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(riderProfileProvider);
        await ref.read(riderProfileProvider.future);
      },
      child: profile.when(
        data: (rider) => ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            _ProfileHeader(rider: rider),
            const SizedBox(height: AppSpacing.lg),
            _VerificationCard(
              rider: rider,
              onUpdateDocuments: () => context.push('/account/settings'),
            ),
            const SizedBox(height: AppSpacing.xl),
            _MenuTile(
              icon: Icons.settings_outlined,
              label: 'account.menu_account_setting'.tr(),
              onTap: () => context.push('/account/settings'),
            ),
            _MenuTile(
              icon: Icons.account_balance_outlined,
              label: 'iban.title'.tr(),
              trailingValue: rider.iban == null ? 'iban.not_set'.tr() : '•••• ${rider.iban!.substring(rider.iban!.length - 4)}',
              onTap: () => showIbanSheet(context, iban: rider.iban, holder: rider.ibanHolder),
            ),
            _MenuTile(
              icon: Icons.payments_outlined,
              label: 'account.menu_my_earning'.tr(),
              onTap: () => ref.read(homeTabIndexProvider.notifier).state = earningTabIndex,
            ),
            _MenuTile(
              icon: Icons.history_rounded,
              label: 'account.menu_order_history'.tr(),
              onTap: () => ref.read(homeTabIndexProvider.notifier).state = historyTabIndex,
            ),
            _MenuTile(
              icon: Icons.language_rounded,
              label: 'account.language'.tr(),
              trailingValue: currentLanguageLabel(context),
              onTap: () => showLanguagePicker(context),
            ),
            _MenuTile(
              icon: Icons.help_outline_rounded,
              label: 'account.menu_support'.tr(),
              onTap: () => context.push('/support'),
            ),
            const SizedBox(height: AppSpacing.xl),
            OutlinedButton.icon(
              onPressed: _isDeleting ? null : _deleteAccount,
              icon: _isDeleting
                  ? const SizedBox(height: 18, width: 18, child: AppLoader(size: 16, color: AppColors.error))
                  : const Icon(Icons.delete_outline_rounded),
              label: Text('account.delete_account'.tr()),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.error,
                side: const BorderSide(color: AppColors.error),
                minimumSize: const Size.fromHeight(52),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            PrimaryButton(
              label: 'home.logout'.tr(),
              icon: Icons.logout_rounded,
              onPressed: _logout,
              isLoading: _isLoggingOut,
            ),
          ],
        ),
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
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({required this.rider});

  final RiderProfile rider;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _Avatar(photoUrl: rider.photoUrl),
        const SizedBox(height: AppSpacing.md),
        Text(rider.name, style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontSize: 20)),
        const SizedBox(height: AppSpacing.md),
        _ContactRow(icon: Icons.mail_outline_rounded, value: rider.email),
        const SizedBox(height: 6),
        _ContactRow(icon: Icons.phone_outlined, value: rider.phone),
      ],
    );
  }
}

/// Verification-status card on the Account tab — the rider's approval
/// standing plus which of the three documents (photo / driving licence /
/// ID proof) are on file. A rider the app is logged in as is always
/// `approved` (the backend blocks the rest), so in practice this shows a
/// "Verified Partner" badge; it still renders the other states honestly in
/// case `GET /rider/me` ever reports one.
class _VerificationCard extends StatelessWidget {
  const _VerificationCard({required this.rider, required this.onUpdateDocuments});

  final RiderProfile rider;
  final VoidCallback onUpdateDocuments;

  ({Color color, Color background, IconData icon, String labelKey}) get _badge {
    switch (rider.verificationStatus) {
      case RiderVerificationStatus.approved:
        return (color: AppColors.success, background: AppColors.successBackground, icon: Icons.verified_rounded, labelKey: 'verification.badge_verified');
      case RiderVerificationStatus.rejected:
        return (color: AppColors.error, background: AppColors.errorBackground, icon: Icons.cancel_rounded, labelKey: 'verification.badge_rejected');
      case RiderVerificationStatus.blocked:
        return (color: AppColors.error, background: AppColors.errorBackground, icon: Icons.block_rounded, labelKey: 'verification.badge_blocked');
      case RiderVerificationStatus.pending:
        return (color: AppColors.primaryDark, background: AppColors.heroBackground, icon: Icons.hourglass_top_rounded, labelKey: 'verification.badge_pending');
    }
  }

  @override
  Widget build(BuildContext context) {
    final badge = _badge;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'verification.section_title'.tr(),
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(color: badge.background, borderRadius: BorderRadius.circular(999)),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(badge.icon, size: 14, color: badge.color),
                    const SizedBox(width: 4),
                    Text(
                      badge.labelKey.tr(),
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: badge.color),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const Divider(height: AppSpacing.lg, color: AppColors.divider),
          _DocumentRow(labelKey: 'verification.doc_photo', uploaded: _has(rider.photoUrl)),
          const SizedBox(height: 8),
          _DocumentRow(labelKey: 'verification.doc_license', uploaded: _has(rider.drivingLicenseUrl)),
          const SizedBox(height: 8),
          _DocumentRow(labelKey: 'verification.doc_id', uploaded: _has(rider.idProofUrl)),
          const SizedBox(height: AppSpacing.sm),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton(
              onPressed: onUpdateDocuments,
              style: TextButton.styleFrom(foregroundColor: AppColors.primaryDark, padding: EdgeInsets.zero),
              child: Text('verification.update_documents'.tr(), style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
    );
  }

  static bool _has(String? url) => url != null && url.isNotEmpty;
}

class _DocumentRow extends StatelessWidget {
  const _DocumentRow({required this.labelKey, required this.uploaded});

  final String labelKey;
  final bool uploaded;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(
          uploaded ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
          size: 18,
          color: uploaded ? AppColors.success : AppColors.textSecondary,
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(child: Text(labelKey.tr(), style: const TextStyle(fontSize: 13, color: AppColors.textPrimary))),
        Text(
          (uploaded ? 'verification.doc_uploaded' : 'verification.doc_missing').tr(),
          style: TextStyle(fontSize: 12, color: uploaded ? AppColors.success : AppColors.textSecondary),
        ),
      ],
    );
  }
}

class _ContactRow extends StatelessWidget {
  const _ContactRow({required this.icon, required this.value});

  final IconData icon;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: 16, color: AppColors.textSecondary),
        const SizedBox(width: 6),
        Text(value, style: const TextStyle(color: AppColors.textSecondary)),
      ],
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({this.photoUrl});

  final String? photoUrl;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 88,
      width: 88,
      decoration: const BoxDecoration(color: AppColors.surfaceMuted, shape: BoxShape.circle),
      child: photoUrl == null || photoUrl!.isEmpty
          ? const Icon(Icons.person_rounded, color: AppColors.textSecondary, size: 44)
          : ClipRRect(
              borderRadius: BorderRadius.circular(44),
              child: Image.network(
                photoUrl!,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) =>
                    const Icon(Icons.person_rounded, color: AppColors.textSecondary, size: 44),
              ),
            ),
    );
  }
}

class _MenuTile extends StatelessWidget {
  const _MenuTile({required this.icon, required this.label, required this.onTap, this.trailingValue});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  /// Shown right before the chevron — e.g. the current language name on
  /// the Language tile, so the rider can see their selection without
  /// opening the picker.
  final String? trailingValue;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Row(
              children: [
                Icon(icon, size: 20, color: AppColors.primaryDark),
                const SizedBox(width: AppSpacing.sm),
                Expanded(child: Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600))),
                if (trailingValue != null) ...[
                  Text(trailingValue!, style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                  const SizedBox(width: 4),
                ],
                const Icon(Icons.chevron_right_rounded, color: AppColors.textSecondary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
