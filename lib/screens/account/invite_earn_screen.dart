import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/app_providers.dart';
import '../../services/api_exception.dart';
import '../../services/app_settings.dart';
import '../../services/referral_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../widgets/app_loader.dart';
import '../home/home_provider.dart';

/// Invite & Earn screen (project.txt Module 14) — once the customer's
/// first order is delivered they get a shareable referral code (see
/// `ReferralService::maybeGenerateCode` on the backend); until then this
/// explains the workflow instead of showing an empty/broken screen.
class InviteEarnScreen extends ConsumerStatefulWidget {
  const InviteEarnScreen({super.key});

  @override
  ConsumerState<InviteEarnScreen> createState() => _InviteEarnScreenState();
}

class _InviteEarnScreenState extends ConsumerState<InviteEarnScreen> {
  ReferralInfo? _info;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loadError = null);
    try {
      final info = await ref.read(referralServiceProvider).getInfo();
      if (!mounted) return;
      setState(() => _info = info);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _loadError = e.message);
    }
  }

  void _copyCode(String code) {
    Clipboard.setData(ClipboardData(text: code));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('invite.code_copied'.tr()), backgroundColor: AppColors.success),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(appSettingsProvider).valueOrNull ?? const AppSettings.fallback();

    return Scaffold(
      appBar: AppBar(title: Text('account.invite_earn'.tr())),
      body: SafeArea(top: false, child: _buildBody(settings)),
    );
  }

  Widget _buildBody(AppSettings settings) {
    final info = _info;

    if (info == null && _loadError == null) {
      return const Center(child: AppLoader());
    }
    if (_loadError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline_rounded, color: AppColors.error, size: 40),
              const SizedBox(height: AppSpacing.sm),
              Text(_loadError!, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textSecondary)),
              const SizedBox(height: AppSpacing.md),
              OutlinedButton(onPressed: _load, child: Text('common.retry'.tr())),
            ],
          ),
        ),
      );
    }

    if (!info!.enabled) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.card_giftcard_rounded, color: AppColors.textSecondary, size: 40),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'invite.not_available'.tr(),
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: info.referralCode != null
          ? _ReferralCodeSection(info: info, settings: settings, onCopy: () => _copyCode(info.referralCode!))
          : _WorkflowSection(info: info, settings: settings),
    );
  }
}

class _ReferralCodeSection extends StatelessWidget {
  const _ReferralCodeSection({required this.info, required this.settings, required this.onCopy});

  final ReferralInfo info;
  final AppSettings settings;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(AppSpacing.lg),
          decoration: BoxDecoration(color: AppColors.heroBackground, borderRadius: BorderRadius.circular(20)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    height: 32,
                    width: 32,
                    decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                    child: const Icon(Icons.card_giftcard_rounded, size: 18, color: AppColors.primaryDark),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Text('invite.your_referral_code'.tr(), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.md, horizontal: AppSpacing.md),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.primary.withValues(alpha: 0.4), width: 1.5),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        info.referralCode!,
                        style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, letterSpacing: 3, color: AppColors.textPrimary),
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: onCopy,
                      icon: const Icon(Icons.copy_rounded, size: 16),
                      label: Text('common.copy'.tr()),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'invite.share_code_description'.tr(),
                style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary, height: 1.4),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        Row(
          children: [
            Expanded(
              child: _RewardStatCard(
                icon: Icons.volunteer_activism_rounded,
                iconColor: AppColors.success,
                iconBackground: AppColors.successBackground,
                label: 'invite.you_earn'.tr(),
                value: settings.format(info.referrerReward),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: _RewardStatCard(
                icon: Icons.redeem_rounded,
                iconColor: AppColors.accent,
                iconBackground: AppColors.infoBackground,
                label: 'invite.they_earn'.tr(),
                value: settings.format(info.refereeReward),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              const Icon(Icons.groups_rounded, color: AppColors.primaryDark),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  info.totalReferrals == 0
                      ? 'invite.no_referrals_yet'.tr()
                      : info.totalReferrals == 1
                          ? 'invite.referral_count_one'.tr(namedArgs: {'count': '${info.totalReferrals}'})
                          : 'invite.referral_count_other'.tr(namedArgs: {'count': '${info.totalReferrals}'}),
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _RewardStatCard extends StatelessWidget {
  const _RewardStatCard({
    required this.icon,
    required this.iconColor,
    required this.iconBackground,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final Color iconColor;
  final Color iconBackground;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 36,
            width: 36,
            decoration: BoxDecoration(color: iconBackground, shape: BoxShape.circle),
            child: Icon(icon, size: 18, color: iconColor),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
          Text(label, style: const TextStyle(fontSize: 11.5, color: AppColors.textSecondary)),
        ],
      ),
    );
  }
}

/// Shown until the customer's first order is delivered — explains, in
/// steps, how their referral code gets unlocked rather than just showing
/// an empty screen.
class _WorkflowSection extends StatelessWidget {
  const _WorkflowSection({required this.info, required this.settings});

  final ReferralInfo info;
  final AppSettings settings;

  @override
  Widget build(BuildContext context) {
    final steps = [
      (
        icon: Icons.local_shipping_outlined,
        title: 'invite.step1_title'.tr(),
        subtitle: 'invite.step1_subtitle'.tr(),
      ),
      (
        icon: Icons.check_circle_outline_rounded,
        title: 'invite.step2_title'.tr(),
        subtitle: 'invite.step2_subtitle'.tr(),
      ),
      (
        icon: Icons.qr_code_2_rounded,
        title: 'invite.step3_title'.tr(),
        subtitle: 'invite.step3_subtitle'.tr(),
      ),
      (
        icon: Icons.card_giftcard_rounded,
        title: 'invite.step4_title'.tr(),
        subtitle: 'invite.step4_subtitle'.tr(
          namedArgs: {
            'referrerReward': settings.format(info.referrerReward),
            'refereeReward': settings.format(info.refereeReward),
          },
        ),
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(AppSpacing.lg),
          decoration: BoxDecoration(color: AppColors.heroBackground, borderRadius: BorderRadius.circular(20)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                height: 44,
                width: 44,
                decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                child: const Icon(Icons.card_giftcard_rounded, color: AppColors.primaryDark),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'invite.code_on_its_way'.tr(),
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
              ),
              const SizedBox(height: 4),
              Text(
                'invite.complete_first_delivery'.tr(),
                style: const TextStyle(fontSize: 13, color: AppColors.textSecondary, height: 1.4),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        Text('invite.how_it_works'.tr(), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
        const SizedBox(height: AppSpacing.md),
        for (var i = 0; i < steps.length; i++)
          _WorkflowStep(
            index: i + 1,
            icon: steps[i].icon,
            title: steps[i].title,
            subtitle: steps[i].subtitle,
            isLast: i == steps.length - 1,
          ),
      ],
    );
  }
}

class _WorkflowStep extends StatelessWidget {
  const _WorkflowStep({
    required this.index,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.isLast,
  });

  final int index;
  final IconData icon;
  final String title;
  final String subtitle;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                height: 36,
                width: 36,
                decoration: const BoxDecoration(color: AppColors.heroBackground, shape: BoxShape.circle),
                child: Center(
                  child: Text(
                    '$index',
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.primaryDark),
                  ),
                ),
              ),
              if (!isLast) Expanded(child: Container(width: 2, color: AppColors.border)),
            ],
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.lg, top: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(icon, size: 16, color: AppColors.primaryDark),
                      const SizedBox(width: 6),
                      Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(subtitle, style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary, height: 1.4)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
