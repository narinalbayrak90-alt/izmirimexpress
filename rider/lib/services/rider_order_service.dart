import 'package:dio/dio.dart';

import 'api_client.dart';

/// A row on the Home screen's Available-Orders or Active-Orders list —
/// the shared shape `GET /rider/orders/available` and `GET /rider/orders`
/// both return. [status] is only present on the latter (an available
/// order is always `confirmed`, so the list doesn't bother repeating it);
/// [distanceFromRiderKm] is only present on the former, and only once the
/// rider has reported a location (see RiderAuthService.updateLocation).
///
/// [earning] — not [total] — is what the app actually shows the rider;
/// see RiderOrderController::earningFor (backend) for why they're not the
/// same number.
class RiderOrderSummary {
  const RiderOrderSummary({
    required this.id,
    this.status,
    required this.distanceKm,
    this.distanceFromRiderKm,
    required this.total,
    required this.earning,
    this.paymentMethod,
    required this.createdAt,
    required this.categoryName,
    this.categoryIconUrl,
    required this.pickupAddress,
    required this.dropoffAddress,
  });

  final int id;
  final String? status;
  final double distanceKm;
  final double? distanceFromRiderKm;
  final double total;
  final double earning;
  final String? paymentMethod;
  final DateTime createdAt;
  final String categoryName;
  final String? categoryIconUrl;
  final String pickupAddress;
  final String dropoffAddress;

  factory RiderOrderSummary.fromJson(Map<String, dynamic> json) {
    final category = json['category'] as Map<String, dynamic>;

    return RiderOrderSummary(
      id: json['id'] as int,
      status: json['status'] as String?,
      distanceKm: (json['distance_km'] as num).toDouble(),
      distanceFromRiderKm: (json['distance_from_rider_km'] as num?)?.toDouble(),
      total: (json['total'] as num).toDouble(),
      earning: (json['earning'] as num).toDouble(),
      paymentMethod: json['payment_method'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      categoryName: category['name'] as String? ?? '',
      categoryIconUrl: category['icon'] as String?,
      pickupAddress: json['pickup_address'] as String? ?? '',
      dropoffAddress: json['dropoff_address'] as String? ?? '',
    );
  }
}

/// An address slice of [RiderOrderDetail] — pickup or dropoff, each with
/// its own contact to call/message on arrival (`sender_*`/`receiver_*` on
/// the backend, snapshotted onto the order rather than looked up live).
class RiderOrderAddress {
  const RiderOrderAddress({
    required this.formattedAddress,
    this.houseNumber,
    this.landmark,
    this.remark,
    required this.lat,
    required this.lng,
    this.contactName,
    this.contactPhone,
  });

  final String formattedAddress;
  final String? houseNumber;
  final String? landmark;
  final String? remark;
  final double lat;
  final double lng;
  final String? contactName;
  final String? contactPhone;

  factory RiderOrderAddress.fromJson(Map<String, dynamic> json) {
    return RiderOrderAddress(
      formattedAddress: json['formatted_address'] as String? ?? '',
      houseNumber: json['house_number'] as String?,
      landmark: json['landmark'] as String?,
      remark: json['remark'] as String?,
      lat: (json['lat'] as num).toDouble(),
      lng: (json['lng'] as num).toDouble(),
      contactName: json['contact_name'] as String?,
      contactPhone: json['contact_phone'] as String?,
    );
  }
}

/// Full order detail, from `GET /rider/orders/{order}` — either this
/// rider's own order at any stage, or (before it's accepted) a preview of
/// any order [RiderOrderService.available] would list.
class RiderOrderDetail {
  const RiderOrderDetail({
    required this.id,
    required this.status,
    required this.paymentMethod,
    required this.paymentStatus,
    required this.total,
    required this.earning,
    this.codAmountToCollect,
    required this.distanceKm,
    this.note,
    this.scheduledAt,
    required this.createdAt,
    required this.pickupOtpRequired,
    required this.deliveryOtpRequired,
    required this.deliveryImageRequired,
    required this.categoryName,
    this.categoryIconUrl,
    required this.pickup,
    required this.dropoff,
    this.parcelPhotoUrl,
    this.receiverName,
    this.receiverPhone,
  });

  final int id;
  final String status;
  final String paymentMethod;
  final String paymentStatus;
  final double total;
  final double earning;

  /// Only non-null for a COD order — what the rider needs to collect in
  /// person on delivery (see [RiderOrderService.deliver]'s doc comment).
  final double? codAmountToCollect;
  final double distanceKm;
  final String? note;
  final DateTime? scheduledAt;
  final DateTime createdAt;
  final bool pickupOtpRequired;
  final bool deliveryOtpRequired;
  final bool deliveryImageRequired;
  final String categoryName;
  final String? categoryIconUrl;
  final RiderOrderAddress pickup;
  final RiderOrderAddress dropoff;

  /// Only set once [RiderOrderService.deliver] has actually run.
  final String? parcelPhotoUrl;
  final String? receiverName;
  final String? receiverPhone;

  factory RiderOrderDetail.fromJson(Map<String, dynamic> json) {
    final category = json['category'] as Map<String, dynamic>;

    return RiderOrderDetail(
      id: json['id'] as int,
      status: json['status'] as String,
      paymentMethod: json['payment_method'] as String,
      paymentStatus: json['payment_status'] as String,
      total: (json['total'] as num).toDouble(),
      earning: (json['earning'] as num).toDouble(),
      codAmountToCollect: (json['cod_amount_to_collect'] as num?)?.toDouble(),
      distanceKm: (json['distance_km'] as num).toDouble(),
      note: json['note'] as String?,
      scheduledAt: json['scheduled_at'] == null ? null : DateTime.parse(json['scheduled_at'] as String),
      createdAt: DateTime.parse(json['created_at'] as String),
      pickupOtpRequired: json['pickup_otp_required'] as bool,
      deliveryOtpRequired: json['delivery_otp_required'] as bool,
      deliveryImageRequired: json['delivery_image_required'] as bool,
      categoryName: category['name'] as String? ?? '',
      categoryIconUrl: category['icon'] as String?,
      pickup: RiderOrderAddress.fromJson(json['pickup'] as Map<String, dynamic>),
      dropoff: RiderOrderAddress.fromJson(json['dropoff'] as Map<String, dynamic>),
      parcelPhotoUrl: json['parcel_photo'] as String?,
      receiverName: json['receiver_name'] as String?,
      receiverPhone: json['receiver_phone'] as String?,
    );
  }
}

/// The short status/proof-of-delivery slice returned by every order-action
/// endpoint (accept/release/pickup/in-transit/deliver) — enough to update
/// the UI without a full detail re-fetch.
class RiderOrderActionResult {
  const RiderOrderActionResult({
    required this.id,
    required this.status,
    required this.earning,
    this.codAmountToCollect,
    this.parcelPhotoUrl,
    this.receiverName,
    this.receiverPhone,
  });

  final int id;
  final String status;
  final double earning;
  final double? codAmountToCollect;
  final String? parcelPhotoUrl;
  final String? receiverName;
  final String? receiverPhone;

  factory RiderOrderActionResult.fromJson(Map<String, dynamic> json) {
    return RiderOrderActionResult(
      id: json['id'] as int,
      status: json['status'] as String,
      earning: (json['earning'] as num).toDouble(),
      codAmountToCollect: (json['cod_amount_to_collect'] as num?)?.toDouble(),
      parcelPhotoUrl: json['parcel_photo'] as String?,
      receiverName: json['receiver_name'] as String?,
      receiverPhone: json['receiver_phone'] as String?,
    );
  }
}

/// Today's and lifetime earnings, from `GET /rider/orders/earnings` — backs
/// the Earning tab's summary cards. Counted off `delivered` orders only
/// (see RiderOrderController::earnings on the backend).
class RiderEarningsSummary {
  const RiderEarningsSummary({
    required this.todayEarning,
    required this.todayDeliveries,
    required this.todayCodCollected,
    required this.totalEarning,
    required this.totalDeliveries,
  });

  final double todayEarning;
  final int todayDeliveries;

  /// Cash in hand, not earnings — the full customer payment (not the
  /// rider's cut) across today's delivered COD orders, still owed to the
  /// office. See RiderOrderController::earnings' doc comment on the backend.
  final double todayCodCollected;
  final double totalEarning;
  final int totalDeliveries;

  factory RiderEarningsSummary.fromJson(Map<String, dynamic> json) {
    return RiderEarningsSummary(
      todayEarning: (json['today_earning'] as num).toDouble(),
      todayDeliveries: json['today_deliveries'] as int,
      todayCodCollected: (json['today_cod_collected'] as num).toDouble(),
      totalEarning: (json['total_earning'] as num).toDouble(),
      totalDeliveries: json['total_deliveries'] as int,
    );
  }
}

/// One page of [RiderOrderService.historyPage] — the History tab's
/// infinite-scroll unit. [hasMore] mirrors the backend paginator's
/// `current_page < last_page`, so the caller knows whether to fetch
/// another page or stop.
class RiderOrderPage {
  const RiderOrderPage({required this.orders, required this.hasMore});

  final List<RiderOrderSummary> orders;
  final bool hasMore;
}

/// Talks to the `/rider/orders/*` endpoints backing the Home screen and
/// the order detail/pickup/deliver flow.
class RiderOrderService {
  RiderOrderService(this._apiClient);

  final ApiClient _apiClient;

  /// Unassigned, already-confirmed orders this rider is equipped to
  /// carry, nearest first — the pull-based counterpart to the
  /// `notifyOrderAvailable` push (backend), for whenever the rider just
  /// has the app open rather than reacting to a notification.
  Future<List<RiderOrderSummary>> available() => _list('/rider/orders/available');

  /// This rider's own orders — `filter=active` for anything still in
  /// progress (what the Home screen's Active Order section shows),
  /// `filter=completed` for delivered/cancelled history. Always the first
  /// page (see [historyPage] for the paged/infinite-scroll version the
  /// History tab uses instead).
  Future<List<RiderOrderSummary>> myOrders({String? filter}) {
    return _list('/rider/orders', queryParameters: filter == null ? null : {'filter': filter});
  }

  /// Page [page] (1-based) of this rider's completed orders, 10 per page
  /// (matching the backend's fixed `paginate(10)`, see
  /// RiderOrderController::index) — the History tab's infinite-scroll
  /// source.
  Future<RiderOrderPage> historyPage(int page) async {
    final data = await _apiClient.get(
      '/rider/orders',
      queryParameters: {'filter': 'completed', 'page': page},
    );
    final paginator = data as Map<String, dynamic>;
    final rows = paginator['data'] as List;

    return RiderOrderPage(
      orders: rows.map((row) => RiderOrderSummary.fromJson(row as Map<String, dynamic>)).toList(),
      hasMore: (paginator['current_page'] as int) < (paginator['last_page'] as int),
    );
  }

  /// Today's and lifetime earnings summary for the Earning tab.
  Future<RiderEarningsSummary> earnings() async {
    final data = await _apiClient.get('/rider/orders/earnings');
    return RiderEarningsSummary.fromJson(data as Map<String, dynamic>);
  }

  Future<List<RiderOrderSummary>> _list(String path, {Map<String, dynamic>? queryParameters}) async {
    final data = await _apiClient.get(path, queryParameters: queryParameters);
    final rows = (data as Map<String, dynamic>)['data'] as List;
    return rows.map((row) => RiderOrderSummary.fromJson(row as Map<String, dynamic>)).toList();
  }

  Future<RiderOrderDetail> show(int orderId) async {
    final data = await _apiClient.get('/rider/orders/$orderId');
    return RiderOrderDetail.fromJson(data as Map<String, dynamic>);
  }

  /// Claims an unassigned order — whoever's [accept] lands first on the
  /// backend's row lock wins it; a losing call surfaces as an
  /// [ApiException] with a 409 status ("no longer available"), not a
  /// crash, so the caller should just refresh the available list.
  Future<RiderOrderActionResult> accept(int orderId) => _action(orderId, 'accept');

  /// Hands an accepted-but-not-yet-picked-up order back to the pool.
  Future<RiderOrderActionResult> release(int orderId) => _action(orderId, 'release');

  /// [otp] is required only when [RiderOrderDetail.pickupOtpRequired] is
  /// true for this order — omit it otherwise.
  Future<RiderOrderActionResult> pickup(int orderId, {String? otp}) {
    return _action(orderId, 'pickup', data: otp == null ? null : {'otp': otp});
  }

  Future<RiderOrderActionResult> inTransit(int orderId) => _action(orderId, 'in-transit');

  /// [otp]/[photoPath] are required only when [RiderOrderDetail.deliveryOtpRequired]/
  /// [RiderOrderDetail.deliveryImageRequired] are true for this order.
  /// [receiverName]/[receiverPhone] are always optional — who actually
  /// took delivery, for the record.
  Future<RiderOrderActionResult> deliver(
    int orderId, {
    String? otp,
    String? photoPath,
    String? receiverName,
    String? receiverPhone,
  }) async {
    final data = FormData.fromMap({
      if (otp != null) 'otp': otp,
      if (photoPath != null) 'photo': await MultipartFile.fromFile(photoPath),
      if (receiverName != null && receiverName.isNotEmpty) 'receiver_name': receiverName,
      if (receiverPhone != null && receiverPhone.isNotEmpty) 'receiver_phone': receiverPhone,
    });

    final result = await _apiClient.post('/rider/orders/$orderId/deliver', data: data);
    return RiderOrderActionResult.fromJson(result as Map<String, dynamic>);
  }

  Future<RiderOrderActionResult> _action(int orderId, String action, {dynamic data}) async {
    final result = await _apiClient.post('/rider/orders/$orderId/$action', data: data);
    return RiderOrderActionResult.fromJson(result as Map<String, dynamic>);
  }
}
