import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../services/order_status.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import 'home_provider.dart';

/// Zomato-style "your order is on the way" strip at the bottom of Home —
/// swipeable when the customer has more than one active order (capped at
/// the 5 most recent — [activeOrdersProvider]), tapping a card jumps
/// straight into that order's live tracking screen. Renders nothing for a
/// guest or a customer with no active orders.
class ActiveOrdersCarousel extends ConsumerWidget {
  const ActiveOrdersCarousel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final orders = ref.watch(activeOrdersProvider).valueOrNull ?? const [];
    if (orders.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('home.live_orders'.tr(), style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontSize: 20)),
          const SizedBox(height: AppSpacing.md),
          _OrderCarousel(orders: orders),
        ],
      ),
    );
  }
}

class _OrderCarousel extends StatefulWidget {
  const _OrderCarousel({required this.orders});

  final List<OrderListItem> orders;

  @override
  State<_OrderCarousel> createState() => _OrderCarouselState();
}

class _OrderCarouselState extends State<_OrderCarousel> {
  // Slightly under 1 so the next card peeks at the edge — the visual cue
  // that there's more to swipe to.
  late final PageController _controller = PageController(viewportFraction: 0.94);
  int _page = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 96,
          child: PageView.builder(
            controller: _controller,
            itemCount: widget.orders.length,
            onPageChanged: (page) => setState(() => _page = page),
            itemBuilder: (context, index) {
              final isLast = index == widget.orders.length - 1;
              return Padding(
                padding: EdgeInsets.only(right: isLast ? 0 : AppSpacing.sm),
                child: _ActiveOrderCard(order: widget.orders[index]),
              );
            },
          ),
        ),
        if (widget.orders.length > 1) ...[
          const SizedBox(height: AppSpacing.sm),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < widget.orders.length; i++)
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  height: 6,
                  width: _page == i ? 18 : 6,
                  decoration: BoxDecoration(
                    color: _page == i ? AppColors.primaryDark : AppColors.border,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

class _ActiveOrderCard extends StatelessWidget {
  const _ActiveOrderCard({required this.order});

  final OrderListItem order;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => context.push('/orders/${order.id}'),
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: AppColors.heroBackground,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.primary.withValues(alpha: 0.35)),
        ),
        child: Row(
          children: [
            Container(
              height: 44,
              width: 44,
              decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
              child: (order.categoryIcon != null && order.categoryIcon!.isNotEmpty)
                  ? ClipOval(
                      child: Image.network(
                        order.categoryIcon!,
                        fit: BoxFit.cover,
                        cacheWidth: 144,
                        errorBuilder: (context, error, stackTrace) =>
                            const Icon(Icons.local_shipping_rounded, color: AppColors.primaryDark),
                      ),
                    )
                  : const Icon(Icons.local_shipping_rounded, color: AppColors.primaryDark),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'home.active_order_title'.tr(namedArgs: {
                      'id': '${order.id}',
                      'status': orderStatusLabel(order.status),
                    }),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'home.active_order_destination'.tr(namedArgs: {'address': order.dropoffAddress}),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: AppColors.primaryDark),
          ],
        ),
      ),
    );
  }
}
