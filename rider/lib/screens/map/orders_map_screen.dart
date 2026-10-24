import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../providers/app_providers.dart';
import '../../services/rider_order_service.dart';
import '../../services/tour_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../widgets/order_map_pins.dart';
import '../home/home_provider.dart';

/// Map tab: every stop the rider has to visit, plus (while online) the new
/// orders waiting nearby.
///
/// - Own orders not yet picked up: an orange pickup pin and a green
///   drop-off pin, joined by the road between them.
/// - Own orders already picked up: only the green drop-off pin is left.
/// - New orders (online only): a blue pin at the pickup.
/// - With two or more own orders, those stops come from the planned tour
///   instead: numbered pins in visiting order and one road line through
///   them (see TourService).
///
/// Tapping a pin shows its address; tapping that bubble opens the order,
/// where it can be accepted or worked as usual. The lists refresh every
/// 30 seconds while this tab is showing.
class OrdersMapScreen extends ConsumerStatefulWidget {
  const OrdersMapScreen({super.key});

  @override
  ConsumerState<OrdersMapScreen> createState() => _OrdersMapScreenState();
}

class _OrdersMapScreenState extends ConsumerState<OrdersMapScreen> {
  GoogleMapController? _controller;
  Timer? _timer;
  bool _locationAllowed = false;

  /// The pins the camera was last fitted to — refit only when that set
  /// changes, so a background refresh doesn't yank the map away from
  /// wherever the rider has panned it.
  String _fittedTo = '';

  /// Numbered tour pins, drawn on first use (see OrderMapPins.numbered).
  final _pins = <String, BitmapDescriptor>{};
  final _drawingPins = <String>{};

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (ref.read(homeTabIndexProvider) == mapTabIndex) _refresh();
    });
    ref.read(riderLocationServiceProvider).ensurePermission().then((allowed) {
      if (mounted && allowed) setState(() => _locationAllowed = true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  void _refresh() {
    ref.invalidate(activeOrdersProvider);
    if (ref.read(riderProfileProvider).valueOrNull?.isOnline ?? false) {
      ref.invalidate(availableOrdersProvider);
    }
  }

  void _open(int orderId) => context.push('/orders/$orderId');

  BitmapDescriptor? _pin(TourStop stop) {
    final key = '${stop.position}-${stop.isPickup}';
    final pin = _pins[key];
    if (pin == null && _drawingPins.add(key)) {
      OrderMapPins.numbered(stop.position, pickup: stop.isPickup).then((drawn) {
        if (mounted) setState(() => _pins[key] = drawn);
      });
    }
    return pin;
  }

  /// With two or more orders the stops come from the planned tour: numbered
  /// in the order to visit them and joined by one road line.
  void _addTour(RiderTour tour, Set<Marker> markers, Set<Polyline> lines) {
    for (final stop in tour.stops) {
      final pin = _pin(stop);
      markers.add(Marker(
        markerId: MarkerId('t${stop.key}'),
        position: stop.location,
        icon: pin ?? (stop.isPickup ? OrderMapPins.pickup : OrderMapPins.dropoff),
        anchor: pin == null ? const Offset(0.5, 1) : const Offset(0.5, 0.5),
        zIndexInt: 100 - stop.position,
        infoWindow: InfoWindow(
          title: '${stop.position}. ${stop.isPickup ? 'tour.pickup'.tr() : 'tour.dropoff'.tr()} · #${stop.orderId}',
          snippet: stop.address,
          onTap: () => _open(stop.orderId),
        ),
      ));
    }

    final road = tour.line;
    lines.add(Polyline(
      polylineId: const PolylineId('tour'),
      points: road ?? tour.stops.map((s) => s.location).toList(),
      color: AppColors.primaryDark,
      width: 5,
      patterns: road == null ? [PatternItem.dash(20), PatternItem.gap(12)] : const [],
    ));
  }

  ({Set<Marker> markers, Set<Polyline> lines}) _build(
    List<RiderOrderSummary> active,
    List<RiderOrderSummary> available,
    RiderTour? tour,
  ) {
    final markers = <Marker>{};
    final lines = <Polyline>{};

    if (tour != null && tour.isMultiOrder) {
      _addTour(tour, markers, lines);
      active = const [];
    }

    for (final order in active) {
      final pickup = order.pickupLocation, dropoff = order.dropoffLocation;
      final pickedUp = order.status == 'picked_up' || order.status == 'in_transit';
      if (pickup != null && !pickedUp) {
        markers.add(Marker(
          markerId: MarkerId('p${order.id}'),
          position: OrderMapPins.latLng(pickup),
          icon: OrderMapPins.pickup,
          infoWindow: InfoWindow(
            title: 'map.pickup_title'.tr(namedArgs: {'id': '${order.id}'}),
            snippet: order.pickupAddress,
            onTap: () => _open(order.id),
          ),
        ));
      }
      if (dropoff != null) {
        markers.add(Marker(
          markerId: MarkerId('d${order.id}'),
          position: OrderMapPins.latLng(dropoff),
          icon: OrderMapPins.dropoff,
          infoWindow: InfoWindow(
            title: 'map.dropoff_title'.tr(namedArgs: {'id': '${order.id}'}),
            snippet: order.dropoffAddress,
            onTap: () => _open(order.id),
          ),
        ));
      }
      if (pickup != null && dropoff != null && !pickedUp) {
        final ends = (OrderMapPins.latLng(pickup), OrderMapPins.latLng(dropoff));
        final road = ref.watch(roadRouteProvider(ends)).valueOrNull;
        lines.add(Polyline(
          polylineId: PolylineId('l${order.id}'),
          // Dashed straight line until the road route has loaded.
          points: road ?? [ends.$1, ends.$2],
          color: AppColors.primaryDark,
          width: 4,
          patterns: road == null ? [PatternItem.dash(20), PatternItem.gap(12)] : const [],
        ));
      }
    }

    final settings = ref.watch(riderSettingsProvider).valueOrNull;
    for (final order in available) {
      final pickup = order.pickupLocation;
      if (pickup == null) continue;
      markers.add(Marker(
        markerId: MarkerId('a${order.id}'),
        position: OrderMapPins.latLng(pickup),
        icon: OrderMapPins.available,
        infoWindow: InfoWindow(
          title: 'map.new_order_title'.tr(namedArgs: {
            'id': '${order.id}',
            'earning': settings?.format(order.earning) ?? order.earning.toStringAsFixed(2),
          }),
          snippet: 'map.tap_for_detail'.tr(),
          onTap: () => _open(order.id),
        ),
      ));
    }

    return (markers: markers, lines: lines);
  }

  void _fit(Set<Marker> markers) {
    final controller = _controller;
    if (controller == null || markers.isEmpty) return;
    final key = (markers.map((m) => m.markerId.value).toList()..sort()).join(',');
    if (key == _fittedTo) return;
    _fittedTo = key;
    final points = markers.map((m) => m.position).toList();
    controller.animateCamera(points.length == 1
        ? CameraUpdate.newLatLngZoom(points.first, 15)
        : CameraUpdate.newLatLngBounds(OrderMapPins.bounds(points), 56));
  }

  @override
  Widget build(BuildContext context) {
    final isOnline = ref.watch(riderProfileProvider).valueOrNull?.isOnline ?? false;
    final active = ref.watch(activeOrdersProvider);
    final available = isOnline ? ref.watch(availableOrdersProvider) : const AsyncValue<List<RiderOrderSummary>>.data([]);

    final tour = ref.watch(tourProvider).valueOrNull;
    final (:markers, :lines) = _build(active.valueOrNull ?? const [], available.valueOrNull ?? const [], tour);
    final loading = active.isLoading || available.isLoading;
    WidgetsBinding.instance.addPostFrameCallback((_) => _fit(markers));

    return Stack(
      children: [
        GoogleMap(
          initialCameraPosition: const CameraPosition(target: OrderMapPins.izmir, zoom: 12),
          markers: markers,
          polylines: lines,
          myLocationEnabled: _locationAllowed,
          myLocationButtonEnabled: _locationAllowed,
          mapToolbarEnabled: false,
          zoomControlsEnabled: false,
          padding: const EdgeInsets.only(top: 64),
          onMapCreated: (controller) {
            _controller = controller;
            _fit(markers);
          },
        ),
        Positioned(
          top: AppSpacing.sm,
          left: AppSpacing.sm,
          right: AppSpacing.sm,
          child: _Legend(showAvailable: isOnline, loading: loading, onRefresh: _refresh),
        ),
        if (!loading && markers.isEmpty)
          Positioned(
            left: AppSpacing.lg,
            right: AppSpacing.lg,
            bottom: AppSpacing.lg,
            child: Material(
              color: Colors.white,
              elevation: 2,
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Text(
                  isOnline ? 'map.empty'.tr() : 'map.empty_offline'.tr(),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.showAvailable, required this.loading, required this.onRefresh});

  final bool showAvailable;
  final bool loading;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      elevation: 2,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.only(left: AppSpacing.md),
        child: Row(
          children: [
            Expanded(
              child: Wrap(
                spacing: AppSpacing.md,
                children: [
                  _LegendDot(color: const Color(0xFFFF8F00), label: 'map.legend_pickup'.tr()),
                  _LegendDot(color: AppColors.success, label: 'map.legend_dropoff'.tr()),
                  if (showAvailable) _LegendDot(color: AppColors.accent, label: 'map.legend_new'.tr()),
                ],
              ),
            ),
            loading
                ? const Padding(
                    padding: EdgeInsets.all(14),
                    child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                  )
                : IconButton(onPressed: onRefresh, icon: const Icon(Icons.refresh_rounded), tooltip: 'map.refresh'.tr()),
          ],
        ),
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(fontSize: 13)),
      ],
    );
  }
}
