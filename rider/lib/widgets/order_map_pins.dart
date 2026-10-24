import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../services/rider_order_service.dart';

/// Shared pin colours, so the Map tab, the order detail map and the legend
/// all agree: yellow-orange = pick up here, green = deliver here, blue = a
/// new order still waiting for a rider.
class OrderMapPins {
  OrderMapPins._();

  static final pickup = BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange);
  static final dropoff = BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen);
  static final available = BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure);

  /// İzmir city centre — where the map starts before any order is loaded.
  static const izmir = LatLng(38.4237, 27.1428);

  static LatLng latLng(RiderLatLng p) => LatLng(p.lat, p.lng);

  /// Smallest box around [points], padded a little so a single stop or two
  /// stops on the same street still give a sensible zoom.
  static LatLngBounds bounds(List<LatLng> points) {
    var south = points.first.latitude, north = south;
    var west = points.first.longitude, east = west;
    for (final p in points) {
      if (p.latitude < south) south = p.latitude;
      if (p.latitude > north) north = p.latitude;
      if (p.longitude < west) west = p.longitude;
      if (p.longitude > east) east = p.longitude;
    }
    const pad = 0.004;
    return LatLngBounds(
      southwest: LatLng(south - pad, west - pad),
      northeast: LatLng(north + pad, east + pad),
    );
  }
}
