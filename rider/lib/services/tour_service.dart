import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'api_client.dart';
import 'road_route_service.dart';

/// One stop of the rider's tour: a pickup or a drop-off of one order.
class TourStop {
  const TourStop({
    required this.key,
    required this.orderId,
    required this.isPickup,
    required this.position,
    required this.location,
    required this.address,
    this.contactName,
    this.contactPhone,
    this.categoryName,
    required this.eta,
    required this.legMeters,
    this.readyAt,
  });

  final String key;
  final int orderId;
  final bool isPickup;

  /// 1-based place in the tour.
  final int position;
  final LatLng location;
  final String address;
  final String? contactName;
  final String? contactPhone;
  final String? categoryName;
  final DateTime eta;
  final int legMeters;

  /// Set while the shop has said the parcel isn't ready yet.
  final DateTime? readyAt;

  factory TourStop.fromJson(Map<String, dynamic> json) {
    return TourStop(
      key: json['key'] as String,
      orderId: json['order_id'] as int,
      isPickup: json['kind'] == 'pickup',
      position: json['position'] as int,
      location: LatLng((json['lat'] as num).toDouble(), (json['lng'] as num).toDouble()),
      address: json['address'] as String? ?? '',
      contactName: json['contact_name'] as String?,
      contactPhone: json['contact_phone'] as String?,
      categoryName: json['category'] as String?,
      eta: DateTime.tryParse(json['eta'] as String? ?? '')?.toLocal() ?? DateTime.now(),
      legMeters: (json['leg_meters'] as num?)?.toInt() ?? 0,
      readyAt: DateTime.tryParse(json['ready_at'] as String? ?? '')?.toLocal(),
    );
  }
}

/// The rider's stops in the order the backend planned (RiderTourController):
/// quickest overall, each parcel collected before it is delivered.
class RiderTour {
  const RiderTour({
    required this.stops,
    required this.totalSeconds,
    required this.totalMeters,
    this.line,
    required this.delayWarning,
  });

  static const empty = RiderTour(stops: [], totalSeconds: 0, totalMeters: 0, delayWarning: false);

  final List<TourStop> stops;
  final int totalSeconds;
  final int totalMeters;

  /// The road through every stop in order; null when no router answered.
  final List<LatLng>? line;
  final bool delayWarning;

  /// A tour is only worth showing as such with more than one order in it.
  bool get isMultiOrder => stops.map((s) => s.orderId).toSet().length > 1;

  factory RiderTour.fromJson(Map<String, dynamic> json) {
    final polyline = json['polyline'] as String?;
    return RiderTour(
      stops: (json['stops'] as List? ?? const [])
          .map((s) => TourStop.fromJson(s as Map<String, dynamic>))
          .toList(),
      totalSeconds: (json['total_seconds'] as num?)?.toInt() ?? 0,
      totalMeters: (json['total_meters'] as num?)?.toInt() ?? 0,
      line: polyline == null || polyline.isEmpty ? null : RoadRouteService.decode(polyline),
      delayWarning: json['delay_warning'] as bool? ?? false,
    );
  }
}

/// What accepting an order would add to the current tour.
class TourPreview {
  const TourPreview({required this.addedSeconds, required this.addedMeters, required this.delayWarning});

  final int addedSeconds;
  final int addedMeters;
  final bool delayWarning;
}

class TourService {
  TourService(this._apiClient);

  final ApiClient _apiClient;

  Future<RiderTour> tour({LatLng? from}) async {
    final data = await _apiClient.get('/rider/tour', queryParameters: _at(from));
    return RiderTour.fromJson(data as Map<String, dynamic>);
  }

  Future<TourPreview> preview(int orderId, {LatLng? from}) async {
    final data = await _apiClient.get('/rider/orders/$orderId/tour-preview', queryParameters: _at(from)) as Map<String, dynamic>;
    return TourPreview(
      addedSeconds: (data['added_seconds'] as num?)?.toInt() ?? 0,
      addedMeters: (data['added_meters'] as num?)?.toInt() ?? 0,
      delayWarning: data['delay_warning'] as bool? ?? false,
    );
  }

  /// The shop says the parcel isn't ready: keep this pickup back for
  /// [minutes] and plan the other stops first.
  Future<void> notReady(int orderId, {int minutes = 10}) {
    return _apiClient.post('/rider/orders/$orderId/not-ready', data: {'minutes': minutes});
  }

  Map<String, dynamic>? _at(LatLng? from) =>
      from == null ? null : {'lat': from.latitude.toStringAsFixed(6), 'lng': from.longitude.toStringAsFixed(6)};
}
