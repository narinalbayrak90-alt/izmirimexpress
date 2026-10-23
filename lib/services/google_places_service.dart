import 'package:dio/dio.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../config/env.dart';

/// A single autocomplete search result.
class PlaceSuggestion {
  const PlaceSuggestion({required this.placeId, required this.description});

  final String placeId;
  final String description;
}

/// Thin client over the Google Places Autocomplete, Place Details,
/// Geocoding and Directions REST APIs — used by the pickup/drop-off map
/// screens for the search field and reverse-geocoding, and by the order
/// tracking screen for the road-following route polyline.
///
/// Deliberately a plain [Dio] instance (not [ApiClient]/[dioProvider]) since
/// these calls go straight to Google, not our backend — they must not carry
/// the backend auth token header. The polyline is display-only (drawing the
/// route on the map), unlike fare distance which is always computed and
/// verified server-side (project.txt Module 6).
class GooglePlacesService {
  GooglePlacesService(this._dio);

  final Dio _dio;

  Future<List<PlaceSuggestion>> autocomplete(String input) async {
    if (input.trim().isEmpty) return [];

    final response = await _dio.get(
      '/place/autocomplete/json',
      queryParameters: {'input': input, 'key': Env.googleMapsApiKey},
    );

    final predictions = response.data['predictions'] as List<dynamic>? ?? [];
    return predictions
        .map(
          (p) => PlaceSuggestion(
            placeId: p['place_id'] as String,
            description: p['description'] as String,
          ),
        )
        .toList();
  }

  Future<LatLng?> placeDetails(String placeId) async {
    final response = await _dio.get(
      '/place/details/json',
      queryParameters: {'place_id': placeId, 'fields': 'geometry', 'key': Env.googleMapsApiKey},
    );

    final location = response.data['result']?['geometry']?['location'];
    if (location == null) return null;
    return LatLng((location['lat'] as num).toDouble(), (location['lng'] as num).toDouble());
  }

  Future<String?> reverseGeocode(LatLng position) async {
    final response = await _dio.get(
      '/geocode/json',
      queryParameters: {
        'latlng': '${position.latitude},${position.longitude}',
        'key': Env.googleMapsApiKey,
      },
    );

    final results = response.data['results'] as List<dynamic>? ?? [];
    if (results.isEmpty) return null;
    return results.first['formatted_address'] as String?;
  }

  /// Road-following route between two points, for drawing on the order
  /// tracking map. Returns an empty list if Directions has no route (e.g.
  /// unreachable points) — callers should fall back to a straight line.
  Future<List<LatLng>> getRoute(LatLng origin, LatLng destination) async {
    final response = await _dio.get(
      '/directions/json',
      queryParameters: {
        'origin': '${origin.latitude},${origin.longitude}',
        'destination': '${destination.latitude},${destination.longitude}',
        'mode': 'driving',
        'key': Env.googleMapsApiKey,
      },
    );

    final points = response.data['routes']?[0]?['overview_polyline']?['points'] as String?;
    if (points == null || points.isEmpty) return [];
    return _decodePolyline(points);
  }

  /// Decodes Google's polyline encoding
  /// (developers.google.com/maps/documentation/utilities/polylinealgorithm).
  List<LatLng> _decodePolyline(String encoded) {
    final points = <LatLng>[];
    var index = 0;
    var lat = 0;
    var lng = 0;

    while (index < encoded.length) {
      lat += _decodeSignedVarint(encoded, index, (next) => index = next);
      lng += _decodeSignedVarint(encoded, index, (next) => index = next);
      points.add(LatLng(lat / 1e5, lng / 1e5));
    }
    return points;
  }

  /// Decodes one signed varint starting at [start], reporting the index
  /// just past it via [onConsumed] (Dart has no `out` params).
  int _decodeSignedVarint(String encoded, int start, void Function(int nextIndex) onConsumed) {
    var index = start;
    var result = 0;
    var shift = 0;
    int chunk;
    do {
      chunk = encoded.codeUnitAt(index++) - 63;
      result |= (chunk & 0x1f) << shift;
      shift += 5;
    } while (chunk >= 0x20);

    onConsumed(index);
    return (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
  }
}
