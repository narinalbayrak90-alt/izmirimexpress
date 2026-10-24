import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../providers/app_providers.dart';
import '../../services/api_exception.dart';
import '../../services/app_settings.dart';
import '../../services/order_status.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../utils/live_refresh.dart';
import '../../widgets/app_loader.dart';
import '../home/home_provider.dart';

/// A static, non-polling receipt view of a single order (project.txt
/// Module 11 — "View Detail" from the Order History list) — pickup/drop-off
/// addresses, fare, payment, and rider info if one's assigned.
///
/// Unlike [OrderTrackingScreen] this doesn't poll or show a live map; an
/// order still in progress gets a "Track This Order" button through to that
/// screen instead of duplicating its live view here.
class OrderDetailScreen extends ConsumerStatefulWidget {
  const OrderDetailScreen({super.key, required this.orderId});

  final int orderId;

  @override
  ConsumerState<OrderDetailScreen> createState() => _OrderDetailScreenState();
}

class _OrderDetailScreenState extends ConsumerState<OrderDetailScreen> {
  OrderStatus? _status;
  String? _loadError;
  late final _ticker = LiveTicker(_refreshQuietly);

  @override
  void initState() {
    super.initState();
    _load();
    _ticker.start();
  }

  @override
  void dispose() {
    _ticker.stop();
    super.dispose();
  }

  /// Live update: keeps the last good status on screen if a poll fails.
  Future<void> _refreshQuietly() async {
    try {
      final status = await ref.read(orderServiceProvider).getOrderStatus(widget.orderId);
      if (!mounted) return;
      setState(() {
        _status = status;
        _loadError = null;
      });
    } catch (_) {}
  }

  Future<void> _load() async {
    setState(() => _loadError = null);
    try {
      final status = await ref.read(orderServiceProvider).getOrderStatus(widget.orderId);
      if (!mounted) return;
      setState(() => _status = status);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _loadError = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(appSettingsProvider).valueOrNull ?? const AppSettings.fallback();
    final status = _status;

    return Scaffold(
      appBar: AppBar(title: Text(status == null ? 'orders.detail_title'.tr() : 'orders.detail_title_with_id'.tr(namedArgs: {'id': '${status.id}'}))),
      body: SafeArea(
        top: false,
        child: status == null ? _buildInitialState() : _buildDetail(status, settings),
      ),
    );
  }

  Widget _buildInitialState() {
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
    return const Center(child: AppLoader());
  }

  Widget _buildDetail(OrderStatus status, AppSettings settings) {
    final isActive = !terminalOrderStatuses.contains(status.status);

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(color: AppColors.heroBackground, borderRadius: BorderRadius.circular(16)),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(status.categoryName, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: AppColors.textPrimary)),
                    const SizedBox(height: 2),
                    Text(
                      'orders.distance_and_method'.tr(namedArgs: {
                        'distance': status.distanceKm.toStringAsFixed(1),
                        'method': paymentMethodLabel(status.paymentMethod),
                      }),
                      style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
              Text(settings.format(status.total), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        Text('orders.addresses'.tr(), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
        const SizedBox(height: AppSpacing.sm),
        _AddressCard(icon: Icons.trip_origin_rounded, iconColor: AppColors.success, label: 'orders.pickup'.tr(), address: status.pickup),
        const SizedBox(height: AppSpacing.sm),
        _AddressCard(icon: Icons.location_on_rounded, iconColor: AppColors.error, label: 'orders.dropoff'.tr(), address: status.dropoff),
        if ((status.receiverName ?? '').isNotEmpty || (status.receiverPhone ?? '').isNotEmpty) ...[
          const SizedBox(height: AppSpacing.lg),
          Text('booking.recipient_title'.tr(), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
          const SizedBox(height: AppSpacing.sm),
          if ((status.receiverName ?? '').isNotEmpty) _InfoRow(label: 'booking.recipient_name_label'.tr(), value: status.receiverName!),
          if ((status.receiverPhone ?? '').isNotEmpty) _InfoRow(label: 'booking.recipient_phone_label'.tr(), value: status.receiverPhone!),
        ],
        const SizedBox(height: AppSpacing.lg),
        Text('orders.payment'.tr(), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
        const SizedBox(height: AppSpacing.sm),
        _InfoRow(label: 'orders.payment_method'.tr(), value: paymentMethodLabel(status.paymentMethod)),
        _InfoRow(label: 'orders.payment_status'.tr(), value: status.paymentStatus == 'paid' ? 'orders.paid'.tr() : 'order_status.pending'.tr()),
        _InfoRow(label: 'orders.total'.tr(), value: settings.format(status.total)),
        if (status.rider != null) ...[
          const SizedBox(height: AppSpacing.lg),
          Text('orders.rider'.tr(), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
          const SizedBox(height: AppSpacing.sm),
          _InfoRow(label: 'orders.rider_name'.tr(), value: status.rider!.name),
          _InfoRow(label: 'orders.rider_phone'.tr(), value: status.rider!.phone),
          if (status.rider!.vehicleNumber != null && status.rider!.vehicleNumber!.isNotEmpty)
            _InfoRow(label: 'orders.rider_vehicle'.tr(), value: status.rider!.vehicleNumber!),
        ],
        const SizedBox(height: AppSpacing.xl),
        if (isActive)
          OutlinedButton.icon(
            onPressed: () => context.push('/orders/${status.id}'),
            icon: const Icon(Icons.local_shipping_outlined),
            label: Text('orders.track_this_order'.tr()),
          ),
      ],
    );
  }
}

class _AddressCard extends StatelessWidget {
  const _AddressCard({required this.icon, required this.iconColor, required this.label, required this.address});

  final IconData icon;
  final Color iconColor;
  final String label;
  final OrderAddress address;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: iconColor),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textSecondary)),
                const SizedBox(height: 2),
                Text(address.formattedAddress, style: const TextStyle(fontSize: 13, color: AppColors.textPrimary)),
                if (address.landmark != null && address.landmark!.isNotEmpty)
                  Text('orders.landmark'.tr(namedArgs: {'landmark': address.landmark!}), style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
          Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
        ],
      ),
    );
  }
}
