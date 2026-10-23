import 'package:easy_localization/easy_localization.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

/// A pickup/drop-off address as returned by `GET /orders/{id}`.
class OrderAddress {
  const OrderAddress({
    required this.formattedAddress,
    this.houseNumber,
    this.landmark,
    this.remark,
    required this.lat,
    required this.lng,
  });

  final String formattedAddress;
  final String? houseNumber;
  final String? landmark;
  final String? remark;
  final double lat;
  final double lng;

  LatLng get latLng => LatLng(lat, lng);

  factory OrderAddress.fromJson(Map<String, dynamic> json) {
    return OrderAddress(
      formattedAddress: json['formatted_address'] as String? ?? '',
      houseNumber: json['house_number'] as String?,
      landmark: json['landmark'] as String?,
      remark: json['remark'] as String?,
      lat: (json['lat'] as num).toDouble(),
      lng: (json['lng'] as num).toDouble(),
    );
  }
}

/// The assigned rider's public details + live position, as returned by
/// `GET /orders/{id}` once `order.rider_id` is set. Assignment and location
/// updates themselves come from the (separate, not-built-here) Rider App —
/// see `OrderController::show` on the backend.
class OrderRider {
  const OrderRider({
    required this.id,
    required this.name,
    required this.phone,
    this.vehicleType,
    this.vehicleNumber,
    required this.ratingAvg,
    this.photoUrl,
    this.currentLat,
    this.currentLng,
  });

  final int id;
  final String name;
  final String phone;
  final String? vehicleType;
  final String? vehicleNumber;
  final double ratingAvg;
  final String? photoUrl;
  final double? currentLat;
  final double? currentLng;

  /// Null until the rider's app has reported a location at least once.
  LatLng? get position => (currentLat != null && currentLng != null) ? LatLng(currentLat!, currentLng!) : null;

  factory OrderRider.fromJson(Map<String, dynamic> json) {
    return OrderRider(
      id: json['id'] as int,
      name: json['name'] as String? ?? '',
      phone: json['phone'] as String? ?? '',
      vehicleType: json['vehicle_type'] as String?,
      vehicleNumber: json['vehicle_number'] as String?,
      ratingAvg: (json['rating_avg'] as num?)?.toDouble() ?? 0,
      photoUrl: json['photo'] as String?,
      currentLat: (json['current_lat'] as num?)?.toDouble(),
      currentLng: (json['current_lng'] as num?)?.toDouble(),
    );
  }
}

/// project.txt Module 10's order status timeline stages, in order.
/// `cancelled` is a separate terminal state, not part of this linear list.
const List<String> orderStatusStages = [
  'pending',
  'confirmed',
  'rider_assigned',
  'picked_up',
  'in_transit',
  'delivered',
];

/// Statuses an order never moves on from — used both to stop
/// [OrderTrackingScreen]'s polling and, in the Order History list, to
/// decide whether an order still gets a Track Order button.
const List<String> terminalOrderStatuses = ['delivered', 'cancelled'];

const Map<String, String> _orderStatusLabelKeys = {
  'pending': 'order_status.pending',
  'confirmed': 'order_status.confirmed',
  'rider_assigned': 'order_status.rider_assigned',
  'picked_up': 'order_status.picked_up',
  'in_transit': 'order_status.in_transit',
  'delivered': 'order_status.delivered',
  'cancelled': 'order_status.cancelled',
};

/// Human label for an order's *current* status — shared by the Order
/// History list's status badge and the Home screen's active-orders
/// carousel. Distinct from [OrderTrackingScreen]'s own stage labels, which
/// name timeline steps ("Order Placed") rather than describe where the
/// order sits right now ("Pending").
String orderStatusLabel(String status) {
  final key = _orderStatusLabelKeys[status];
  return key == null ? status : key.tr();
}

/// Full snapshot from `GET /orders/{id}`, polled every few seconds by
/// [OrderTrackingScreen] to drive the status timeline and live map.
class OrderStatus {
  const OrderStatus({
    required this.id,
    required this.status,
    required this.paymentMethod,
    required this.paymentStatus,
    required this.total,
    required this.distanceKm,
    required this.categoryName,
    this.categoryIcon,
    required this.pickup,
    required this.dropoff,
    this.rider,
    this.etaMinutes,
    this.pickupOtp,
    this.deliveryOtp,
    this.receiverName,
    this.receiverPhone,
  });

  final int id;
  final String status;
  final String paymentMethod;
  final String paymentStatus;
  final double total;
  final double distanceKm;
  final String categoryName;
  final String? categoryIcon;
  final OrderAddress pickup;
  final OrderAddress dropoff;
  final OrderRider? rider;
  final int? etaMinutes;

  /// The in-person handoff code to show the rider at pickup — present
  /// only while there's actually one waiting to be used (see
  /// RiderOrderController::accept/pickup on the backend, which is what
  /// generates and later clears it). Null once picked up, or if the admin
  /// setting was off when this order was placed.
  final String? pickupOtp;

  /// Same idea as [pickupOtp], for the drop-off handoff.
  final String? deliveryOtp;

  /// The recipient the customer entered on the Drop-off step, if any.
  final String? receiverName;
  final String? receiverPhone;

  bool get isCancelled => status == 'cancelled';

  /// Mirrors the backend's own gate — see Api\OrderController::cancel —
  /// so the Cancel button only ever shows while the call would actually
  /// succeed. Once a rider has physically picked the parcel up, there's
  /// no clean undo.
  bool get isCancellable => const ['pending', 'confirmed', 'rider_assigned'].contains(status);

  factory OrderStatus.fromJson(Map<String, dynamic> json) {
    final order = json['order'] as Map<String, dynamic>;
    final category = order['category'] as Map<String, dynamic>?;
    final riderJson = json['rider'] as Map<String, dynamic>?;

    return OrderStatus(
      id: order['id'] as int,
      status: order['status'] as String,
      paymentMethod: order['payment_method'] as String,
      paymentStatus: order['payment_status'] as String,
      total: (order['total'] as num).toDouble(),
      distanceKm: (order['distance_km'] as num).toDouble(),
      categoryName: category?['name'] as String? ?? '',
      categoryIcon: category?['icon'] as String?,
      pickup: OrderAddress.fromJson(order['pickup'] as Map<String, dynamic>),
      dropoff: OrderAddress.fromJson(order['dropoff'] as Map<String, dynamic>),
      rider: riderJson == null ? null : OrderRider.fromJson(riderJson),
      etaMinutes: json['eta_minutes'] as int?,
      pickupOtp: order['pickup_otp'] as String?,
      deliveryOtp: order['delivery_otp'] as String?,
      receiverName: order['receiver_name'] as String?,
      receiverPhone: order['receiver_phone'] as String?,
    );
  }
}

/// A single row in the Order History list (project.txt Module 11) — the
/// summary `GET /orders` returns, lighter than [OrderStatus] since the list
/// doesn't need the full pickup/drop-off coordinates or rider position.
class OrderListItem {
  const OrderListItem({
    required this.id,
    required this.status,
    required this.paymentMethod,
    required this.paymentStatus,
    required this.total,
    required this.distanceKm,
    required this.createdAt,
    required this.categoryName,
    this.categoryIcon,
    required this.pickupAddress,
    required this.dropoffAddress,
  });

  final int id;
  final String status;
  final String paymentMethod;
  final String paymentStatus;
  final double total;
  final double distanceKm;
  final DateTime createdAt;
  final String categoryName;
  final String? categoryIcon;
  final String pickupAddress;
  final String dropoffAddress;

  bool get isActive => !terminalOrderStatuses.contains(status);

  factory OrderListItem.fromJson(Map<String, dynamic> json) {
    final category = json['category'] as Map<String, dynamic>?;
    return OrderListItem(
      id: json['id'] as int,
      status: json['status'] as String,
      paymentMethod: json['payment_method'] as String,
      paymentStatus: json['payment_status'] as String,
      total: (json['total'] as num).toDouble(),
      distanceKm: (json['distance_km'] as num).toDouble(),
      createdAt: DateTime.parse(json['created_at'] as String),
      categoryName: category?['name'] as String? ?? '',
      categoryIcon: category?['icon'] as String?,
      pickupAddress: json['pickup_address'] as String? ?? '',
      dropoffAddress: json['dropoff_address'] as String? ?? '',
    );
  }
}

/// One page of `GET /orders`, as Laravel's paginator serializes it —
/// [currentPage]/[lastPage] tell [MyOrdersScreen] whether an infinite-scroll
/// fetch should ask for another page.
class OrderListPage {
  const OrderListPage({required this.items, required this.currentPage, required this.lastPage});

  final List<OrderListItem> items;
  final int currentPage;
  final int lastPage;

  bool get hasMore => currentPage < lastPage;

  factory OrderListPage.fromJson(Map<String, dynamic> json) {
    return OrderListPage(
      items: (json['data'] as List).map((e) => OrderListItem.fromJson(e as Map<String, dynamic>)).toList(),
      currentPage: json['current_page'] as int,
      lastPage: json['last_page'] as int,
    );
  }
}

/// Customer-facing name of a payment method ("cod" → "Kapıda Nakit Ödeme"),
/// reusing the payment screen's own labels.
String paymentMethodLabel(String method) {
  final key = 'booking.payment_${method}_title';
  final label = key.tr();
  return label == key ? method.toUpperCase() : label;
}
