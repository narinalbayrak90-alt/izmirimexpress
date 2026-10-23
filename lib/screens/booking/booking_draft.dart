import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../home/home_category.dart';

/// Address details captured on the Pickup/Drop-off map screens.
class BookingAddress {
  const BookingAddress({
    this.latLng,
    this.formattedAddress = '',
    this.houseNumber = '',
    this.landmark = '',
    this.remark = '',
    this.label,
  });

  final LatLng? latLng;
  final String formattedAddress;
  final String houseNumber;
  final String landmark;
  final String remark;

  /// "Home" / "Office" / "Other" (project.txt Module 4) — optional, purely
  /// for the customer's own reference on `GET /addresses`'s saved-address
  /// picker. Null when the customer didn't tag this address.
  final String? label;

  BookingAddress copyWith({
    LatLng? latLng,
    String? formattedAddress,
    String? houseNumber,
    String? landmark,
    String? remark,
    String? label,
  }) {
    return BookingAddress(
      latLng: latLng ?? this.latLng,
      formattedAddress: formattedAddress ?? this.formattedAddress,
      houseNumber: houseNumber ?? this.houseNumber,
      landmark: landmark ?? this.landmark,
      remark: remark ?? this.remark,
      label: label ?? this.label,
    );
  }

  /// Shape expected by every backend endpoint that takes a pickup/dropoff
  /// address (`POST /orders`, `POST /payment/stripe/intent`,
  /// `POST /payment/razorpay/order`) — [latLng] must be set before calling.
  Map<String, dynamic> toApiJson() {
    final position = latLng!;
    return {
      'lat': position.latitude,
      'lng': position.longitude,
      'formatted_address': formattedAddress,
      if (houseNumber.isNotEmpty) 'house_number': houseNumber,
      if (landmark.isNotEmpty) 'landmark': landmark,
      if (remark.isNotEmpty) 'remark': remark,
      if (label != null && label!.isNotEmpty) 'label': label,
    };
  }
}

/// In-progress state for the multi-step booking flow (Category -> Pickup ->
/// Drop-off -> Summary). Held in [bookingDraftProvider] so each step can
/// read/update its own slice without threading data through route params.
class BookingDraft {
  const BookingDraft({this.category, this.pickup, this.dropoff, this.scheduledAt});

  final HomeCategory? category;
  final BookingAddress? pickup;
  final BookingAddress? dropoff;

  /// Null means "send now" (the default) — set only when the user picks
  /// "Schedule for Later" on the Pickup step.
  final DateTime? scheduledAt;

  BookingDraft copyWith({
    HomeCategory? category,
    BookingAddress? pickup,
    BookingAddress? dropoff,
    DateTime? scheduledAt,
  }) {
    return BookingDraft(
      category: category ?? this.category,
      pickup: pickup ?? this.pickup,
      dropoff: dropoff ?? this.dropoff,
      scheduledAt: scheduledAt ?? this.scheduledAt,
    );
  }
}
