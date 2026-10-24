import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../providers/app_providers.dart';
import '../../services/api_exception.dart';
import '../../services/tour_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../widgets/confirm_dialog.dart';
import 'home_provider.dart';

/// Orange for pickups, green for drop-offs: the same colours as the map pins.
const tourPickupColor = Color(0xFFFF8F00);
const tourDropoffColor = AppColors.success;

/// Home tab card for a rider working two or more orders: the next stop in
/// full (with directions, a call button and "not ready" for pickups), then
/// the rest of the tour as a numbered list. Hidden for a single order,
/// where the order card already says everything.
class TourCard extends ConsumerWidget {
  const TourCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tour = ref.watch(tourProvider).valueOrNull;
    if (tour == null || !tour.isMultiOrder || tour.stops.isEmpty) return const SizedBox.shrink();

    final next = tour.stops.first;
    final rest = tour.stops.skip(1).toList();

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.primary, width: 1.5),
      ),
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.route_rounded, color: AppColors.primaryDark),
              const SizedBox(width: AppSpacing.sm),
              Text('tour.title'.tr(), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
              const Spacer(),
              Text(
                'tour.summary'.tr(namedArgs: {
                  'stops': '${tour.stops.length}',
                  'km': (tour.totalMeters / 1000).toStringAsFixed(1),
                  'min': '${(tour.totalSeconds / 60).ceil()}',
                }),
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
              ),
            ],
          ),
          if (tour.delayWarning) ...[
            const SizedBox(height: AppSpacing.xs),
            Text('tour.delay_warning'.tr(), style: const TextStyle(color: AppColors.error, fontSize: 12)),
          ],
          const SizedBox(height: AppSpacing.md),
          Text('tour.next'.tr(), style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
          const SizedBox(height: AppSpacing.xs),
          _NextStop(stop: next),
          if (rest.isNotEmpty) ...[
            const Divider(height: AppSpacing.lg),
            ...rest.map((stop) => _StopRow(stop: stop)),
          ],
        ],
      ),
    );
  }
}

class _NextStop extends ConsumerStatefulWidget {
  const _NextStop({required this.stop});

  final TourStop stop;

  @override
  ConsumerState<_NextStop> createState() => _NextStopState();
}

class _NextStopState extends ConsumerState<_NextStop> {
  bool _postponing = false;

  Future<void> _navigate() async {
    final at = widget.stop.location;
    final uri = Uri.parse('https://www.google.com/maps/dir/?api=1&travelmode=driving&destination=${at.latitude},${at.longitude}');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _call(String phone) async {
    await launchUrl(Uri(scheme: 'tel', path: phone.replaceAll(' ', '')), mode: LaunchMode.externalApplication);
  }

  Future<void> _notReady() async {
    final confirmed = await confirmDialog(
      context,
      title: 'tour.not_ready_title'.tr(),
      message: 'tour.not_ready_message'.tr(),
      confirmLabel: 'tour.not_ready_confirm'.tr(),
    );
    if (!mounted || !confirmed) return;

    setState(() => _postponing = true);
    try {
      await ref.read(tourServiceProvider).notReady(widget.stop.orderId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('tour.not_ready_done'.tr())));
      ref.invalidate(tourProvider);
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _postponing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final stop = widget.stop;
    final phone = stop.contactPhone;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _StopBadge(stop: stop, size: 34),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${stop.isPickup ? 'tour.pickup'.tr() : 'tour.dropoff'.tr()} · ${'tour.order'.tr(namedArgs: {'id': '${stop.orderId}'})}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 2),
                  Text(stop.address, style: const TextStyle(fontSize: 14)),
                  if (stop.contactName != null && stop.contactName!.isNotEmpty)
                    Text(stop.contactName!, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                  const SizedBox(height: 2),
                  Text(_timeLine(stop), style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.xs,
          children: [
            FilledButton.icon(
              onPressed: _navigate,
              icon: const Icon(Icons.navigation_rounded, size: 18),
              label: Text('tour.navigate'.tr()),
            ),
            if (phone != null && phone.isNotEmpty)
              OutlinedButton.icon(
                onPressed: () => _call(phone),
                icon: const Icon(Icons.call_rounded, size: 18),
                label: Text('tour.call'.tr()),
              ),
            OutlinedButton(
              onPressed: () => context.push('/orders/${stop.orderId}'),
              child: Text('tour.open_order'.tr()),
            ),
            if (stop.isPickup)
              TextButton(
                onPressed: _postponing ? null : _notReady,
                child: Text('tour.not_ready'.tr()),
              ),
          ],
        ),
      ],
    );
  }
}

class _StopRow extends StatelessWidget {
  const _StopRow({required this.stop});

  final TourStop stop;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => context.push('/orders/${stop.orderId}'),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            _StopBadge(stop: stop, size: 26),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${stop.isPickup ? 'tour.pickup'.tr() : 'tour.dropoff'.tr()} · #${stop.orderId}',
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                  ),
                  Text(stop.address, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13)),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Text(DateFormat.Hm().format(stop.eta), style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}

class _StopBadge extends StatelessWidget {
  const _StopBadge({required this.stop, required this.size});

  final TourStop stop;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: stop.isPickup ? tourPickupColor : tourDropoffColor,
        shape: BoxShape.circle,
      ),
      child: Text(
        '${stop.position}',
        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: size * 0.45),
      ),
    );
  }
}

String _timeLine(TourStop stop) {
  final readyAt = stop.readyAt;
  final eta = 'tour.eta'.tr(namedArgs: {'time': DateFormat.Hm().format(stop.eta)});
  if (readyAt == null) return eta;
  return '$eta · ${'tour.waiting_until'.tr(namedArgs: {'time': DateFormat.Hm().format(readyAt)})}';
}

/// The accept dialog's text: the usual responsibility note, plus what the
/// order adds to the tour when the rider already has orders. The preview
/// is best effort; without an answer in a few seconds the dialog shows
/// without it.
Future<String> acceptConfirmMessage(WidgetRef ref, int orderId) async {
  final base = 'order_detail.accept_confirm_message'.tr();
  final active = ref.read(activeOrdersProvider).valueOrNull ?? const [];
  if (active.isEmpty) return base;

  try {
    final position = ref.read(riderLocationTrackerProvider).lastPosition;
    final preview = await ref
        .read(tourServiceProvider)
        .preview(orderId, from: position == null ? null : LatLng(position.latitude, position.longitude))
        .timeout(const Duration(seconds: 4));
    final added = 'tour.preview'.tr(namedArgs: {
      'min': '${(preview.addedSeconds / 60).ceil()}',
      'km': (preview.addedMeters / 1000).toStringAsFixed(1),
    });
    return [base, added, if (preview.delayWarning) 'tour.preview_warning'.tr()].join('\n\n');
  } catch (_) {
    return base;
  }
}
