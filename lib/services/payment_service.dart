import '../screens/booking/booking_draft.dart';
import 'api_client.dart';

/// Publishable payment gateway keys from `GET /payment/keys` — the ones
/// the gateways' own SDKs are designed to receive client-side. Null for
/// whichever gateway isn't enabled in App Setting > Payment Gateway.
///
/// Paystack and Flutterwave are paid for through their hosted checkout
/// pages (see [PaymentService.createPaystackCheckout] /
/// [createFlutterwaveCheckout] and `GatewayCheckoutPage`), so the app
/// doesn't actually need their keys — they're carried here only so this
/// model stays in step with the endpoint.
class PaymentKeys {
  const PaymentKeys({
    this.stripePublicKey,
    this.razorpayKeyId,
    this.paystackPublicKey,
    this.flutterwavePublicKey,
    this.flutterwaveEncryptionKey,
  });

  final String? stripePublicKey;
  final String? razorpayKeyId;
  final String? paystackPublicKey;
  final String? flutterwavePublicKey;
  final String? flutterwaveEncryptionKey;

  factory PaymentKeys.fromJson(Map<String, dynamic> json) {
    return PaymentKeys(
      stripePublicKey: json['stripe_public_key'] as String?,
      razorpayKeyId: json['razorpay_key_id'] as String?,
      paystackPublicKey: json['paystack_public_key'] as String?,
      flutterwavePublicKey: json['flutterwave_public_key'] as String?,
      flutterwaveEncryptionKey: json['flutterwave_encryption_key'] as String?,
    );
  }
}

/// A hosted Paystack/Flutterwave checkout ready to open in a WebView —
/// [authorizationUrl] is the page to load, [reference] is the charge
/// reference (Paystack `reference` / Flutterwave `tx_ref`) the backend
/// independently re-verifies once the customer is done paying.
class GatewayCheckout {
  const GatewayCheckout({
    required this.authorizationUrl,
    required this.reference,
    required this.payableAmount,
  });

  final String authorizationUrl;
  final String reference;
  final double payableAmount;

  factory GatewayCheckout.fromJson(Map<String, dynamic> json) {
    return GatewayCheckout(
      authorizationUrl: json['authorization_url'] as String,
      // Paystack returns `reference`, Flutterwave returns `tx_ref`.
      reference: (json['reference'] ?? json['tx_ref']) as String,
      payableAmount: (json['payable_amount'] as num).toDouble(),
    );
  }
}

/// A Stripe PaymentIntent ready for the payment sheet to confirm.
class StripeIntent {
  const StripeIntent({required this.clientSecret, required this.paymentIntentId, required this.payableAmount});

  final String clientSecret;
  final String paymentIntentId;
  final double payableAmount;

  factory StripeIntent.fromJson(Map<String, dynamic> json) {
    return StripeIntent(
      clientSecret: json['client_secret'] as String,
      paymentIntentId: json['payment_intent_id'] as String,
      payableAmount: (json['payable_amount'] as num).toDouble(),
    );
  }
}

/// A Razorpay order ready for Razorpay Checkout to open.
class RazorpayOrder {
  const RazorpayOrder({required this.orderId, required this.keyId, required this.payableAmount});

  final String orderId;
  final String keyId;
  final double payableAmount;

  factory RazorpayOrder.fromJson(Map<String, dynamic> json) {
    return RazorpayOrder(
      orderId: json['order_id'] as String,
      keyId: json['key_id'] as String,
      payableAmount: (json['payable_amount'] as num).toDouble(),
    );
  }
}

/// Payment gateway calls — key fetch plus creating the charge for whatever
/// the wallet doesn't already cover (project.txt Module 8). Every call here
/// re-runs the same pricing/validation gate `POST /orders` uses
/// (`OrderPricingService`), so a charge is never created for an order that
/// would then be rejected anyway.
class PaymentService {
  PaymentService(this._apiClient);

  final ApiClient _apiClient;

  Future<PaymentKeys> getKeys() async {
    final data = await _apiClient.get('/payment/keys');
    return PaymentKeys.fromJson(data as Map<String, dynamic>);
  }

  Future<StripeIntent> createStripeIntent({
    required int categoryId,
    required BookingAddress pickup,
    required BookingAddress dropoff,
    String? couponCode,
  }) async {
    final data = await _apiClient.post('/payment/stripe/intent', data: _priceRequest(categoryId, pickup, dropoff, couponCode));
    return StripeIntent.fromJson(data as Map<String, dynamic>);
  }

  Future<RazorpayOrder> createRazorpayOrder({
    required int categoryId,
    required BookingAddress pickup,
    required BookingAddress dropoff,
    String? couponCode,
  }) async {
    final data = await _apiClient.post('/payment/razorpay/order', data: _priceRequest(categoryId, pickup, dropoff, couponCode));
    return RazorpayOrder.fromJson(data as Map<String, dynamic>);
  }

  /// Initializes a Paystack hosted checkout for whatever the wallet
  /// doesn't already cover — open [GatewayCheckout.authorizationUrl] in a
  /// WebView, then place the order with [GatewayCheckout.reference].
  Future<GatewayCheckout> createPaystackCheckout({
    required int categoryId,
    required BookingAddress pickup,
    required BookingAddress dropoff,
    String? couponCode,
  }) async {
    final data = await _apiClient.post('/payment/paystack/initialize', data: _priceRequest(categoryId, pickup, dropoff, couponCode));
    return GatewayCheckout.fromJson(data as Map<String, dynamic>);
  }

  /// Initializes a Flutterwave hosted checkout — same flow as
  /// [createPaystackCheckout].
  Future<GatewayCheckout> createFlutterwaveCheckout({
    required int categoryId,
    required BookingAddress pickup,
    required BookingAddress dropoff,
    String? couponCode,
  }) async {
    final data = await _apiClient.post('/payment/flutterwave/initialize', data: _priceRequest(categoryId, pickup, dropoff, couponCode));
    return GatewayCheckout.fromJson(data as Map<String, dynamic>);
  }

  Map<String, dynamic> _priceRequest(int categoryId, BookingAddress pickup, BookingAddress dropoff, String? couponCode) {
    return {
      'category_id': categoryId,
      'pickup': pickup.toApiJson(),
      'dropoff': dropoff.toApiJson(),
      if (couponCode != null && couponCode.isNotEmpty) 'coupon_code': couponCode,
    };
  }
}
