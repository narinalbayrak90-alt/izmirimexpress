import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../screens/booking/fare_estimate.dart';
import 'api_client.dart';

/// Requests the server-computed fare for the booking flow's Summary step.
///
/// Uses [ApiClient] (our own backend, with auth headers/error handling) —
/// distinct from [GooglePlacesService], which talks to Google directly.
class FareService {
  FareService(this._apiClient);

  final ApiClient _apiClient;

  Future<FareEstimate> estimate({
    required int categoryId,
    required LatLng pickup,
    required LatLng dropoff,
    String? couponCode,
  }) async {
    final data = await _apiClient.post(
      '/fare/estimate',
      data: {
        'category_id': categoryId,
        'pickup_lat': pickup.latitude,
        'pickup_lng': pickup.longitude,
        'dropoff_lat': dropoff.latitude,
        'dropoff_lng': dropoff.longitude,
        if (couponCode != null && couponCode.trim().isNotEmpty) 'coupon_code': couponCode.trim(),
      },
    );
    return FareEstimate.fromJson(data as Map<String, dynamic>);
  }
}
