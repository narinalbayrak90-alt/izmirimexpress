import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../screens/home/home_provider.dart';
import '../services/rider_order_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import 'app_loader.dart';

/// A single order row — shared by the Home tab's Active/Available Orders
/// sections and the History/Earning tabs' order lists, so all four look
/// and behave the same. Always shows [RiderOrderSummary.earning], never
/// `total` — see order_detail_screen.dart's own class doc comment for why.
class RiderOrderCard extends ConsumerWidget {
  const RiderOrderCard({super.key, required this.order, this.onAccept, this.isAccepting = false});

  final RiderOrderSummary order;

  /// Non-null only for the Home tab's Available Orders section — every
  /// other list (Active Orders, History, Earning) omits this and the card
  /// falls back to showing status/distance in its place.
  final VoidCallback? onAccept;
  final bool isAccepting;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currency = ref.watch(riderSettingsProvider).valueOrNull ?? const RiderSettings();

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
          onTap: () => context.push('/orders/${order.id}'),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _CategoryIcon(iconUrl: order.categoryIconUrl),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(order.categoryName, style: const TextStyle(fontWeight: FontWeight.w700)),
                          if (order.status != null)
                            Text(
                              'order_status.${order.status}'.tr(),
                              style: const TextStyle(fontSize: 12, color: AppColors.primaryDark, fontWeight: FontWeight.w600),
                            )
                          else if (order.distanceFromRiderKm != null)
                            Text(
                              'home.distance_away'.tr(namedArgs: {'distance': order.distanceFromRiderKm!.toStringAsFixed(1)}),
                              style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                            ),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          currency.format(order.earning),
                          style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.success),
                        ),
                        Text('home.earn_label'.tr(), style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                _AddressLine(icon: Icons.trip_origin, address: order.pickupAddress),
                const SizedBox(height: 4),
                _AddressLine(icon: Icons.location_on_rounded, address: order.dropoffAddress),
                if (onAccept != null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: isAccepting ? null : onAccept,
                      child: isAccepting
                          ? const AppLoader(size: 20, color: AppColors.textPrimary)
                          : Text('home.accept'.tr()),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AddressLine extends StatelessWidget {
  const _AddressLine({required this.icon, required this.address});

  final IconData icon;
  final String address;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: AppColors.textSecondary),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            address,
            style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

class _CategoryIcon extends StatelessWidget {
  const _CategoryIcon({this.iconUrl});

  final String? iconUrl;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 40,
      width: 40,
      decoration: BoxDecoration(color: AppColors.surfaceMuted, borderRadius: BorderRadius.circular(10)),
      child: iconUrl == null || iconUrl!.isEmpty
          ? const Icon(Icons.inventory_2_outlined, color: AppColors.textSecondary, size: 20)
          : ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.network(
                iconUrl!,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) =>
                    const Icon(Icons.inventory_2_outlined, color: AppColors.textSecondary, size: 20),
              ),
            ),
    );
  }
}
