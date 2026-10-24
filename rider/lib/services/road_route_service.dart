import 'package:dio/dio.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

/// Road routes for the map screens, from the backend's directions proxy
/// (`GET /maps/directions/json`, the same one the customer app uses: Google
/// first, then the Routes API, then OSRM). The proxy returns Google's own
/// JSON rather than the usual `{success, data}` envelope, so this reads it
/// with Dio directly instead of going through ApiClient.
///
/// Routes are cached for the app's lifetime (keyed to ~10 m), so the map
/// tab's 30-second refresh and reopening an order never fetch the same
/// route twice. When no route comes back the caller gets a straight line,
/// which isn't cached, so a later try can still find the road.
class RoadRouteService {
  RoadRouteService(this._dio);

  final Dio _dio;
  final _cache = <String, List<LatLng>>{};
  final _pending = <String, Future<List<LatLng>>>{};

  Future<List<LatLng>> route(LatLng from, LatLng to) {
    final key = '${_coord(from)}>${_coord(to)}';
    final cached = _cache[key];
    if (cached != null) return Future.value(cached);
    // The block body matters: `=> _pending.remove(key)` would hand
    // whenComplete this very future to wait on, and it would never finish.
    return _pending[key] ??= _fetch(key, from, to).whenComplete(() {
      _pending.remove(key);
    });
  }

  Future<List<LatLng>> _fetch(String key, LatLng from, LatLng to) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/maps/directions/json',
        queryParameters: {'origin': _coord(from), 'destination': _coord(to), 'mode': 'driving'},
      );
      final routes = response.data?['routes'];
      final first = routes is List && routes.isNotEmpty ? routes.first : null;
      final overview = first is Map ? first['overview_polyline'] : null;
      final encoded = overview is Map ? overview['points'] : null;
      if (encoded is String && encoded.isNotEmpty) {
        return _cache[key] = _decode(encoded);
      }
    } catch (_) {
      // Fall through to the straight line.
    }
    return [from, to];
  }

  static String _coord(LatLng p) => '${p.latitude.toStringAsFixed(5)},${p.longitude.toStringAsFixed(5)}';

  /// Google's encoded polyline format
  /// (developers.google.com/maps/documentation/utilities/polylinealgorithm).
  static List<LatLng> _decode(String encoded) {
    final points = <LatLng>[];
    var index = 0, lat = 0, lng = 0;

    int next() {
      var result = 0, shift = 0, chunk = 0;
      do {
        chunk = encoded.codeUnitAt(index++) - 63;
        result |= (chunk & 0x1f) << shift;
        shift += 5;
      } while (chunk >= 0x20 && index < encoded.length);
      return (result & 1) != 0 ? ~(result >> 1) : result >> 1;
    }

    while (index < encoded.length) {
      lat += next();
      if (index >= encoded.length) break;
      lng += next();
      points.add(LatLng(lat / 1e5, lng / 1e5));
    }
    return points;
  }
}
