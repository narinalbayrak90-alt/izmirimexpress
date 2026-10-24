import '../screens/booking/booking_draft.dart';
import 'api_client.dart';
import 'order_status.dart';

/// Result of `POST /orders` — just enough to confirm the order to the
/// customer; the full order record (with addresses, fare breakdown, etc.)
/// belongs to the Order History screen (Module 11), not built yet.
class PlacedOrder {
  const PlacedOrder({required this.id, required this.status, required this.paymentStatus, required this.walletBalance});

  final int id;
  final String status;
  final String paymentStatus;
  final double walletBalance;

  factory PlacedOrder.fromJson(Map<String, dynamic> json) {
    final order = json['order'] as Map<String, dynamic>;
    return PlacedOrder(
      id: order['id'] as int,
      status: order['status'] as String,
      paymentStatus: order['payment_status'] as String,
      walletBalance: (json['wallet_balance'] as num).toDouble(),
    );
  }
}

/// Places an order (project.txt Module 9) via `POST /orders`. Fare is
/// never sent from the app — only the category/addresses/coupon the
/// backend needs to recompute it itself (see `FareCalculator`).
///
/// The `stripe*`/`razorpay*`/`paystackReference`/`flutterwaveReference`
/// fields are only needed when the wallet didn't already cover the total —
/// they're the gateway charge reference the backend independently
/// re-verifies against that gateway's own API before trusting it (see
/// `OrderController::store`).
class OrderService {
  OrderService(this._apiClient);

  final ApiClient _apiClient;

  Future<PlacedOrder> placeOrder({
    required int categoryId,
    required BookingAddress pickup,
    required BookingAddress dropoff,
    required String paymentMethod,
    String? couponCode,
    DateTime? scheduledAt,
    String? stripePaymentIntentId,
    String? stripeCheckoutSessionId,
    String? razorpayPaymentId,
    String? razorpayOrderId,
    String? razorpaySignature,
    String? paystackReference,
    String? flutterwaveReference,
    String? paytrReference,
  }) async {
    final data = await _apiClient.post(
      '/orders',
      data: {
        'category_id': categoryId,
        'pickup': pickup.toApiJson(),
        'dropoff': dropoff.toApiJson(),
        'payment_method': paymentMethod,
        if (couponCode != null && couponCode.isNotEmpty) 'coupon_code': couponCode,
        if (scheduledAt != null) 'scheduled_at': scheduledAt.toIso8601String(),
        if (dropoff.contactName.trim().isNotEmpty) 'receiver_name': dropoff.contactName.trim(),
        'receiver_phone': ?dropoff.contactPhone,
        'stripe_payment_intent_id': ?stripePaymentIntentId,
        'stripe_checkout_session_id': ?stripeCheckoutSessionId,
        'razorpay_payment_id': ?razorpayPaymentId,
        'razorpay_order_id': ?razorpayOrderId,
        'razorpay_signature': ?razorpaySignature,
        'paystack_reference': ?paystackReference,
        'flutterwave_reference': ?flutterwaveReference,
        'paytr_reference': ?paytrReference,
      },
    );
    return PlacedOrder.fromJson(data as Map<String, dynamic>);
  }

  /// Order tracking (project.txt Module 10) — status, addresses, and the
  /// rider's live position/ETA once one is assigned. Polled by
  /// [OrderTrackingScreen] every few seconds.
  Future<OrderStatus> getOrderStatus(int orderId) async {
    final data = await _apiClient.get('/orders/$orderId');
    return OrderStatus.fromJson(data as Map<String, dynamic>);
  }

  /// Order history (project.txt Module 11), 10 per page — [page] drives
  /// [MyOrdersScreen]'s infinite scroll, [filter] is `all`, `active`, or
  /// `completed`.
  Future<OrderListPage> getOrders({required int page, String filter = 'all'}) async {
    final data = await _apiClient.get('/orders', queryParameters: {'page': page, 'filter': filter});
    return OrderListPage.fromJson(data as Map<String, dynamic>);
  }

  /// Customer-initiated cancellation (project.txt Module 10) — only
  /// succeeds while [OrderStatus.isCancellable] is true; the backend is
  /// the actual source of truth on that (see Api\OrderController::cancel),
  /// this is just what the button's visibility mirrors.
  Future<void> cancelOrder(int orderId) {
    return _apiClient.post('/orders/$orderId/cancel');
  }
}
