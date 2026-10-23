import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/app_providers.dart';
import '../services/pwa_install.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';

/// Installs the web app: the browser's own dialog on Android / desktop
/// Chrome, or the "Share > Add to Home Screen" steps on iOS.
Future<void> installApp(BuildContext context) async {
  if (PwaInstall.canPrompt) {
    await PwaInstall.prompt();
    return;
  }
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (context) => const _IosInstallSteps(),
  );
}

/// Home screen card offering to install the app; shown only on the web
/// build while installing is possible and the customer hasn't closed it.
class InstallAppCard extends ConsumerStatefulWidget {
  const InstallAppCard({super.key});

  @override
  ConsumerState<InstallAppCard> createState() => _InstallAppCardState();
}

class _InstallAppCardState extends ConsumerState<InstallAppCard> {
  StreamSubscription<void>? _changes;
  late bool _dismissed = ref.read(settingsStorageProvider).isInstallCardDismissed();

  @override
  void initState() {
    super.initState();
    // The install dialog usually becomes available a moment after load.
    _changes = PwaInstall.changes.listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _changes?.cancel();
    super.dispose();
  }

  void _dismiss() {
    ref.read(settingsStorageProvider).setInstallCardDismissed();
    setState(() => _dismissed = true);
  }

  @override
  Widget build(BuildContext context) {
    if (_dismissed || !PwaInstall.isAvailable) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: Container(
        padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.xs, AppSpacing.sm),
        decoration: BoxDecoration(color: AppColors.infoBackground, borderRadius: BorderRadius.circular(16)),
        child: Row(
          children: [
            Container(
              height: 40,
              width: 40,
              decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(10)),
              child: const Icon(Icons.install_mobile_rounded, color: AppColors.accent, size: 22),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'pwa.card_title'.tr(),
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'pwa.card_subtitle'.tr(),
                    style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            FilledButton(
              onPressed: () => installApp(context),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.textPrimary,
                foregroundColor: Colors.white,
                minimumSize: const Size(0, 36),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
              child: Text('pwa.install'.tr()),
            ),
            IconButton(
              onPressed: _dismiss,
              tooltip: 'common.close'.tr(),
              icon: const Icon(Icons.close_rounded, size: 18, color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

class _IosInstallSteps extends StatelessWidget {
  const _IosInstallSteps();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'pwa.ios_title'.tr(),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
            ),
            const SizedBox(height: AppSpacing.md),
            _Step(number: 1, icon: Icons.ios_share_rounded, text: 'pwa.ios_step_share'.tr()),
            _Step(number: 2, icon: Icons.add_box_outlined, text: 'pwa.ios_step_add'.tr()),
            _Step(number: 3, icon: Icons.check_circle_outline_rounded, text: 'pwa.ios_step_confirm'.tr()),
            const SizedBox(height: AppSpacing.sm),
            Text('pwa.ios_note'.tr(), style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          ],
        ),
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.number, required this.icon, required this.text});

  final int number;
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        children: [
          CircleAvatar(
            radius: 14,
            backgroundColor: AppColors.primary,
            child: Text(
              '$number',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Icon(icon, color: AppColors.accent, size: 22),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 14, color: AppColors.textPrimary))),
        ],
      ),
    );
  }
}
