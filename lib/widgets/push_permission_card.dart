import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/app_providers.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';

/// Home screen card asking a signed-in customer to allow notifications,
/// so order updates reach them as pushes. Browsers only show their
/// "allow" prompt from a tap (Safari and Firefox ignore it otherwise),
/// which is why this is a button rather than a prompt on load. Hidden
/// once they've answered, for guests, and where push isn't possible
/// (e.g. iPhone Safari before the site is added to the home screen).
class PushPermissionCard extends ConsumerStatefulWidget {
  const PushPermissionCard({super.key});

  @override
  ConsumerState<PushPermissionCard> createState() => _PushPermissionCardState();
}

class _PushPermissionCardState extends ConsumerState<PushPermissionCard> {
  bool _signedIn = false;
  bool _dismissed = false;
  bool _asking = false;

  @override
  void initState() {
    super.initState();
    ref.read(secureStorageProvider).readToken().then((token) {
      if (mounted) setState(() => _signedIn = token != null && token.isNotEmpty);
    });
  }

  Future<void> _turnOn() async {
    setState(() => _asking = true);
    final messenger = ScaffoldMessenger.of(context);
    final granted = await ref.read(oneSignalServiceProvider).requestPermission();
    if (!mounted) return;
    setState(() => _asking = false);
    if (granted) messenger.showSnackBar(SnackBar(content: Text('push.enabled'.tr())));
  }

  @override
  Widget build(BuildContext context) {
    final service = ref.watch(oneSignalServiceProvider);
    if (!_signedIn || _dismissed || !service.needsPermission) return const SizedBox.shrink();

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
              decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(10)),
              child: const Icon(Icons.notifications_active_outlined, color: AppColors.textPrimary),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'push.title'.tr(),
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'push.subtitle'.tr(),
                    style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            FilledButton(
              onPressed: _asking ? null : _turnOn,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.textPrimary,
                foregroundColor: Colors.white,
                minimumSize: const Size(0, 36),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
              child: Text('push.turn_on'.tr()),
            ),
            IconButton(
              onPressed: () => setState(() => _dismissed = true),
              tooltip: 'common.close'.tr(),
              icon: const Icon(Icons.close_rounded, size: 18, color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}
