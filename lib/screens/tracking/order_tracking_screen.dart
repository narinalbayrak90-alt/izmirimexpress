import 'dart:async';
import 'dart:math' as math;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../providers/app_providers.dart';
import '../../services/api_exception.dart';
import '../../services/app_settings.dart';
import '../../services/order_status.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../widgets/app_loader.dart';
import '../home/home_provider.dart';

const _riderTrackingStatuses = ['rider_assigned', 'picked_up', 'in_transit'];

/// Order tracking screen (project.txt Module 10) — landed on right after
/// placing an order. Polls `GET /orders/{id}` every 5 seconds:
///
/// - `pending`/`confirmed`: map shows the pickup -> drop-off route.
/// - `rider_assigned`/`picked_up`/`in_transit`: map shows the rider's live
///   position (animated smoothly between polls rather than jump-cutting)
///   plus a live ETA to wherever they're currently headed.
/// - `delivered`/`cancelled`: terminal — polling stops.
class OrderTrackingScreen extends ConsumerStatefulWidget {
  const OrderTrackingScreen({super.key, required this.orderId, this.showPaymentSuccessToast = false});

  final int orderId;

  /// True when this order was just paid online (Stripe/Razorpay top-up, or
  /// the wallet already covering it) — shows a one-time "Payment
  /// successful" toast on arrival. COD orders stay unpaid until delivery,
  /// so they never set this.
  final bool showPaymentSuccessToast;

  @override
  ConsumerState<OrderTrackingScreen> createState() => _OrderTrackingScreenState();
}

class _OrderTrackingScreenState extends ConsumerState<OrderTrackingScreen> with SingleTickerProviderStateMixin {
  static const _pollInterval = Duration(seconds: 5);

  Timer? _pollTimer;
  GoogleMapController? _mapController;
  OrderStatus? _status;
  String? _loadError;
  bool _isCancelling = false;

  String? _routeKey;
  List<LatLng> _routePolyline = [];

  late final AnimationController _riderAnimController = AnimationController(vsync: this, duration: _pollInterval)
    ..addListener(_onRiderAnimTick);
  LatLng? _riderAnimFrom;
  LatLng? _riderAnimTo;
  LatLng? _riderDisplayPosition;

  @override
  void initState() {
    super.initState();
    _fetchStatus();
    if (widget.showPaymentSuccessToast) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('tracking.payment_success'.tr()),
            backgroundColor: AppColors.success,
          ),
        );
      });
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _riderAnimController.dispose();
    _mapController?.dispose();
    super.dispose();
  }

  Future<void> _fetchStatus() async {
    try {
      final status = await ref.read(orderServiceProvider).getOrderStatus(widget.orderId);
      if (!mounted) return;
      final previous = _status;
      setState(() {
        _status = status;
        _loadError = null;
      });
      await _onStatusUpdated(previous, status);
      _scheduleNextPoll(status);
    } catch (e) {
      if (!mounted) return;
      if (_status == null) {
        setState(() => _loadError = 'tracking.load_error'.tr());
      }
      // Otherwise keep showing the last known status — a single missed
      // poll shouldn't blank a screen the customer is actively watching.
      // Still try again on the usual cadence.
      _scheduleNextPoll(_status);
    }
  }

  void _scheduleNextPoll(OrderStatus? status) {
    _pollTimer?.cancel();
    if (status != null && terminalOrderStatuses.contains(status.status)) return;
    _pollTimer = Timer(_pollInterval, _fetchStatus);
  }

  Future<void> _confirmCancel() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('tracking.cancel_confirm_title'.tr()),
        content: Text('tracking.cancel_confirm_body'.tr()),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text('common.cancel'.tr()),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: Text('tracking.cancel_order'.tr()),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _cancelOrder();
  }

  Future<void> _cancelOrder() async {
    setState(() => _isCancelling = true);
    try {
      await ref.read(orderServiceProvider).cancelOrder(widget.orderId);
      if (!mounted) return;
      await _fetchStatus();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('tracking.cancel_success'.tr())),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _isCancelling = false);
    }
  }

  Future<void> _onStatusUpdated(OrderStatus? previous, OrderStatus next) async {
    await _updateRoutePolyline(next);
    _updateRiderAnimation(next);
    await _fitCamera(next);
  }

  /// Road-following pickup -> drop-off route, fetched once per pair (not
  /// re-fetched every poll) and only while there's no rider en route yet.
  Future<void> _updateRoutePolyline(OrderStatus status) async {
    if (_riderTrackingStatuses.contains(status.status) || terminalOrderStatuses.contains(status.status)) {
      return;
    }

    final key = '${status.pickup.lat},${status.pickup.lng}>${status.dropoff.lat},${status.dropoff.lng}';
    if (_routeKey == key) return;
    _routeKey = key;

    try {
      final points = await ref.read(googlePlacesServiceProvider).getRoute(status.pickup.latLng, status.dropoff.latLng);
      if (!mounted) return;
      setState(() {
        _routePolyline = points.isEmpty ? [status.pickup.latLng, status.dropoff.latLng] : points;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _routePolyline = [status.pickup.latLng, status.dropoff.latLng]);
    }
  }

  /// Animates the rider marker from wherever it currently sits to the
  /// freshly-polled position over the poll interval, so it glides
  /// continuously instead of snapping every 5 seconds.
  void _updateRiderAnimation(OrderStatus status) {
    final riderPosition = status.rider?.position;
    if (riderPosition == null || !_riderTrackingStatuses.contains(status.status)) {
      return;
    }

    _riderAnimFrom = _riderDisplayPosition ?? riderPosition;
    _riderAnimTo = riderPosition;
    _riderDisplayPosition ??= riderPosition;
    _riderAnimController
      ..reset()
      ..forward();
  }

  void _onRiderAnimTick() {
    final from = _riderAnimFrom;
    final to = _riderAnimTo;
    if (from == null || to == null) return;
    final t = _riderAnimController.value;
    setState(() {
      _riderDisplayPosition = LatLng(
        from.latitude + (to.latitude - from.latitude) * t,
        from.longitude + (to.longitude - from.longitude) * t,
      );
    });
  }

  Future<void> _fitCamera(OrderStatus status) async {
    final controller = _mapController;
    if (controller == null) return;

    final points = <LatLng>[status.pickup.latLng, status.dropoff.latLng];
    final riderPosition = _riderDisplayPosition;
    if (riderPosition != null && _riderTrackingStatuses.contains(status.status)) {
      points.add(riderPosition);
    }

    if (points.length == 1) {
      await controller.animateCamera(CameraUpdate.newLatLngZoom(points.first, 14));
      return;
    }

    var minLat = points.first.latitude, maxLat = points.first.latitude;
    var minLng = points.first.longitude, maxLng = points.first.longitude;
    for (final point in points) {
      minLat = math.min(minLat, point.latitude);
      maxLat = math.max(maxLat, point.latitude);
      minLng = math.min(minLng, point.longitude);
      maxLng = math.max(maxLng, point.longitude);
    }

    try {
      await controller.animateCamera(
        CameraUpdate.newLatLngBounds(
          LatLngBounds(southwest: LatLng(minLat, minLng), northeast: LatLng(maxLat, maxLng)),
          72,
        ),
      );
    } catch (_) {
      // Map not laid out yet, or bounds too small to fit — next update retries.
    }
  }

  Set<Marker> _buildMarkers(OrderStatus status) {
    final markers = <Marker>{
      Marker(
        markerId: const MarkerId('pickup'),
        position: status.pickup.latLng,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
        infoWindow: InfoWindow(title: 'orders.pickup'.tr()),
      ),
      Marker(
        markerId: const MarkerId('dropoff'),
        position: status.dropoff.latLng,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
        infoWindow: InfoWindow(title: 'orders.dropoff'.tr()),
      ),
    };

    final riderPosition = _riderDisplayPosition;
    if (riderPosition != null && _riderTrackingStatuses.contains(status.status)) {
      markers.add(
        Marker(
          markerId: const MarkerId('rider'),
          position: riderPosition,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
          infoWindow: InfoWindow(title: status.rider?.name ?? 'orders.rider'.tr()),
          anchor: const Offset(0.5, 0.5),
          flat: true,
        ),
      );
    }

    return markers;
  }

  @override
  Widget build(BuildContext context) {
    final status = _status;
    final settings = ref.watch(appSettingsProvider).valueOrNull ?? const AppSettings.fallback();

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          tooltip: 'common.back'.tr(),
          // Reached by a push from My Orders' Track Order button (back
          // should return there) as well as by a go() replacing the stack
          // right after placing an order (nothing to pop back to, so back
          // falls through to Home same as before).
          onPressed: () {
            if (Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
            } else {
              context.go('/home');
            }
          },
        ),
        title: Text(status == null ? 'orders.detail_title'.tr() : 'orders.detail_title_with_id'.tr(namedArgs: {'id': '${status.id}'})),
        actions: [
          IconButton(
            icon: const Icon(Icons.account_circle_outlined),
            tooltip: 'account.my_account'.tr(),
            onPressed: () => context.push('/account'),
          ),
        ],
      ),
      body: status == null ? _buildInitialState() : _buildTracking(status, settings),
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
              OutlinedButton(onPressed: _fetchStatus, child: Text('common.retry'.tr())),
            ],
          ),
        ),
      );
    }
    return const Center(child: AppLoader());
  }

  Widget _buildTracking(OrderStatus status, AppSettings settings) {
    return Column(
      children: [
        // Half the screen, per spec — two equal Expanded panes.
        Expanded(
          child: GoogleMap(
            initialCameraPosition: CameraPosition(target: status.pickup.latLng, zoom: 13),
            onMapCreated: (controller) {
              _mapController = controller;
              _fitCamera(status);
            },
            markers: _buildMarkers(status),
            polylines: {
              if (_routePolyline.isNotEmpty)
                Polyline(
                  polylineId: const PolylineId('route'),
                  points: _routePolyline,
                  color: AppColors.primaryDark,
                  width: 4,
                ),
            },
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _OrderSummaryRow(status: status, settings: settings),
                if (status.pickupOtp != null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  _OtpCard(
                    label: 'tracking.pickup_otp_label'.tr(),
                    code: status.pickupOtp!,
                    hint: 'tracking.pickup_otp_hint'.tr(),
                  ),
                ],
                if (status.deliveryOtp != null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  _OtpCard(
                    label: 'tracking.delivery_otp_label'.tr(),
                    code: status.deliveryOtp!,
                    hint: 'tracking.delivery_otp_hint'.tr(),
                  ),
                ],
                const SizedBox(height: AppSpacing.lg),
                if (status.rider != null) ...[
                  _RiderCard(rider: status.rider!, etaMinutes: status.etaMinutes),
                  const SizedBox(height: AppSpacing.lg),
                ],
                Text(
                  'orders.order_status'.tr(),
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                ),
                const SizedBox(height: AppSpacing.sm),
                _StatusTimeline(status: status.status),
                if (status.isCancellable) ...[
                  const SizedBox(height: AppSpacing.lg),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: _isCancelling ? null : _confirmCancel,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.error,
                        side: const BorderSide(color: AppColors.error),
                        minimumSize: const Size.fromHeight(52),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      child: _isCancelling
                          ? const SizedBox(height: 20, width: 20, child: AppLoader(size: 18, color: AppColors.error))
                          : Text('tracking.cancel_order'.tr()),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _OrderSummaryRow extends StatelessWidget {
  const _OrderSummaryRow({required this.status, required this.settings});

  final OrderStatus status;
  final AppSettings settings;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(color: AppColors.surfaceMuted, borderRadius: BorderRadius.circular(12)),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(status.categoryName, style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                Text(
                  'orders.distance_and_method'.tr(namedArgs: {
                    'distance': status.distanceKm.toStringAsFixed(1),
                    'method': status.paymentMethod.toUpperCase(),
                  }),
                  style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          Text(
            settings.format(status.total),
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
          ),
        ],
      ),
    );
  }
}

/// The in-person handoff code — pickup or delivery — for the customer to
/// read out to their rider. Shown right on the tracking screen (not just
/// buried in the push notification that also delivers it, see
/// OneSignalService::notifyCustomer on the backend) since this is exactly
/// where a customer waiting for their rider is already looking.
class _OtpCard extends StatelessWidget {
  const _OtpCard({required this.label, required this.code, required this.hint});

  final String label;
  final String code;
  final String hint;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.heroBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.password_rounded, color: AppColors.primaryDark),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
                Text(
                  code,
                  style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, letterSpacing: 6, color: AppColors.textPrimary),
                ),
                Text(hint, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RiderCard extends StatelessWidget {
  const _RiderCard({required this.rider, required this.etaMinutes});

  final OrderRider rider;
  final int? etaMinutes;

  @override
  Widget build(BuildContext context) {
    final details = [
      if (rider.vehicleType != null && rider.vehicleType!.isNotEmpty) rider.vehicleType!,
      if (rider.vehicleNumber != null && rider.vehicleNumber!.isNotEmpty) rider.vehicleNumber!,
    ].join(' · ');

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.heroBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: AppColors.primary.withValues(alpha: 0.2),
            backgroundImage: (rider.photoUrl != null && rider.photoUrl!.isNotEmpty) ? NetworkImage(rider.photoUrl!) : null,
            child: (rider.photoUrl == null || rider.photoUrl!.isEmpty)
                ? const Icon(Icons.person_rounded, color: AppColors.primaryDark)
                : null,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(rider.name, style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                if (details.isNotEmpty)
                  Text(details, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                Text(rider.phone, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
              ],
            ),
          ),
          if (etaMinutes != null)
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('tracking.eta_minutes'.tr(namedArgs: {'minutes': '$etaMinutes'}), style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.primaryDark)),
                Text('tracking.eta'.tr(), style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
              ],
            ),
        ],
      ),
    );
  }
}

class _StatusTimeline extends StatelessWidget {
  const _StatusTimeline({required this.status});

  final String status;

  static const _stageLabelKeys = {
    'pending': 'tracking.stage_order_placed',
    'confirmed': 'tracking.stage_confirmed',
    'rider_assigned': 'tracking.stage_rider_assigned',
    'picked_up': 'tracking.stage_picked_up',
    'in_transit': 'tracking.stage_in_transit',
    'delivered': 'tracking.stage_delivered',
  };

  static const _stageIcons = {
    'pending': Icons.receipt_long_rounded,
    'confirmed': Icons.verified_rounded,
    'rider_assigned': Icons.two_wheeler_rounded,
    'picked_up': Icons.inventory_2_rounded,
    'in_transit': Icons.local_shipping_rounded,
    'delivered': Icons.home_rounded,
  };

  @override
  Widget build(BuildContext context) {
    if (status == 'cancelled') {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: AppColors.error.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.error.withValues(alpha: 0.4)),
        ),
        child: Row(
          children: [
            const Icon(Icons.cancel_rounded, color: AppColors.error),
            const SizedBox(width: AppSpacing.sm),
            Text('tracking.order_cancelled'.tr(), style: const TextStyle(color: AppColors.error, fontWeight: FontWeight.w700)),
          ],
        ),
      );
    }

    final currentIndex = orderStatusStages.indexOf(status);

    return Column(
      children: [
        for (var i = 0; i < orderStatusStages.length; i++)
          _TimelineRow(
            icon: _stageIcons[orderStatusStages[i]]!,
            label: _stageLabelKeys[orderStatusStages[i]]!.tr(),
            isDone: i <= currentIndex,
            isLast: i == orderStatusStages.length - 1,
          ),
      ],
    );
  }
}

class _TimelineRow extends StatelessWidget {
  const _TimelineRow({required this.icon, required this.label, required this.isDone, required this.isLast});

  final IconData icon;
  final String label;
  final bool isDone;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final color = isDone ? AppColors.primary : AppColors.border;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                height: 32,
                width: 32,
                decoration: BoxDecoration(
                  color: isDone ? AppColors.primary : AppColors.background,
                  shape: BoxShape.circle,
                  border: Border.all(color: color, width: 1.5),
                ),
                child: Icon(icon, size: 16, color: isDone ? Colors.white : AppColors.textSecondary),
              ),
              if (!isLast) Expanded(child: Container(width: 2, color: color)),
            ],
          ),
          const SizedBox(width: AppSpacing.sm),
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.md, top: 6),
            child: Text(
              label,
              style: TextStyle(
                fontWeight: isDone ? FontWeight.w700 : FontWeight.w400,
                color: isDone ? AppColors.textPrimary : AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
