import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'api_client.dart';

/// One of the customer's previously used pickup/drop-off addresses, as
/// returned by `GET /addresses` (project.txt Module 4 — "Choose from saved
/// address" on the booking map screens).
class SavedAddress {
  const SavedAddress({
    required this.id,
    this.label,
    required this.formattedAddress,
    this.houseNumber,
    this.landmark,
    this.remark,
    required this.lat,
    required this.lng,
    required this.orderCount,
  });

  final int id;
  final String? label;
  final String formattedAddress;
  final String? houseNumber;
  final String? landmark;
  final String? remark;
  final double lat;
  final double lng;

  /// How many orders (pickup or drop-off, any status) ever used this
  /// address, across every duplicate row it has — see
  /// `AddressController::index`. Shown on the Account screen's Saved
  /// Addresses list.
  final int orderCount;

  LatLng get latLng => LatLng(lat, lng);

  factory SavedAddress.fromJson(Map<String, dynamic> json) {
    return SavedAddress(
      id: json['id'] as int,
      label: json['label'] as String?,
      formattedAddress: json['formatted_address'] as String? ?? '',
      houseNumber: json['house_number'] as String?,
      landmark: json['landmark'] as String?,
      remark: json['remark'] as String?,
      lat: (json['lat'] as num).toDouble(),
      lng: (json['lng'] as num).toDouble(),
      orderCount: json['order_count'] as int? ?? 0,
    );
  }
}

/// Talks to `GET /addresses`.
class AddressService {
  AddressService(this._apiClient);

  final ApiClient _apiClient;

  Future<List<SavedAddress>> getSavedAddresses() async {
    final data = await _apiClient.get('/addresses');
    return (data as List).map((e) => SavedAddress.fromJson(e as Map<String, dynamic>)).toList();
  }
}
