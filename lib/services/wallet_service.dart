import 'api_client.dart';
import 'payment_service.dart';

/// A single row in the Wallet History list (project.txt Module 12) — a
/// credit (recharge, gateway top-up) or a debit (order payment).
class WalletTransactionItem {
  const WalletTransactionItem({
    required this.id,
    required this.type,
    required this.amount,
    required this.description,
    this.orderId,
    required this.createdAt,
  });

  final int id;
  final String type;
  final double amount;
  final String description;
  final int? orderId;
  final DateTime createdAt;

  bool get isCredit => type == 'credit';

  factory WalletTransactionItem.fromJson(Map<String, dynamic> json) {
    return WalletTransactionItem(
      id: json['id'] as int,
      type: json['type'] as String,
      amount: (json['amount'] as num).toDouble(),
      description: json['description'] as String? ?? '',
      orderId: json['order_id'] as int?,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}

/// One page of `GET /wallet/history`, as Laravel's paginator serializes it
/// — mirrors `OrderListPage`'s shape for the same infinite-scroll pattern.
class WalletHistoryPage {
  const WalletHistoryPage({required this.items, required this.currentPage, required this.lastPage});

  final List<WalletTransactionItem> items;
  final int currentPage;
  final int lastPage;

  bool get hasMore => currentPage < lastPage;

  factory WalletHistoryPage.fromJson(Map<String, dynamic> json) {
    return WalletHistoryPage(
      items: (json['data'] as List).map((e) => WalletTransactionItem.fromJson(e as Map<String, dynamic>)).toList(),
      currentPage: json['current_page'] as int,
      lastPage: json['last_page'] as int,
    );
  }
}

/// Talks to the customer's `GET /wallet/*` and `POST /wallet/recharge*`
/// endpoints (project.txt Module 12). Requires auth — only ever called
/// once the customer is logged in.
class WalletService {
  WalletService(this._apiClient);

  final ApiClient _apiClient;

  Future<double> getBalance() async {
    final data = await _apiClient.get('/wallet/balance');
    return ((data as Map<String, dynamic>)['balance'] as num).toDouble();
  }

  /// Wallet transaction history, 10 per page — [page] drives the Wallet
  /// screen's History tab infinite scroll.
  Future<WalletHistoryPage> getHistory({required int page}) async {
    final data = await _apiClient.get('/wallet/history', queryParameters: {'page': page});
    return WalletHistoryPage.fromJson(data as Map<String, dynamic>);
  }

  /// Creates a Stripe PaymentIntent for a wallet recharge of [amount] — a
  /// raw amount, independent of any order (unlike
  /// `PaymentService.createStripeIntent`).
  Future<StripeIntent> createStripeIntent(double amount) async {
    final data = await _apiClient.post('/wallet/recharge/stripe/intent', data: {'amount': amount});
    return StripeIntent.fromJson(data as Map<String, dynamic>);
  }

  /// Creates a Razorpay Order for a wallet recharge of [amount] — same as
  /// [createStripeIntent] but for Razorpay Checkout.
  Future<RazorpayOrder> createRazorpayOrder(double amount) async {
    final data = await _apiClient.post('/wallet/recharge/razorpay/order', data: {'amount': amount});
    return RazorpayOrder.fromJson(data as Map<String, dynamic>);
  }

  /// Initializes a Paystack hosted checkout for a wallet recharge of
  /// [amount] — open [GatewayCheckout.authorizationUrl] in a WebView, then
  /// call [recharge] with [GatewayCheckout.reference].
  Future<GatewayCheckout> createPaystackCheckout(double amount) async {
    final data = await _apiClient.post('/wallet/recharge/paystack/initialize', data: {'amount': amount});
    return GatewayCheckout.fromJson(data as Map<String, dynamic>);
  }

  /// Initializes a Flutterwave hosted checkout for a wallet recharge —
  /// same flow as [createPaystackCheckout].
  Future<GatewayCheckout> createFlutterwaveCheckout(double amount) async {
    final data = await _apiClient.post('/wallet/recharge/flutterwave/initialize', data: {'amount': amount});
    return GatewayCheckout.fromJson(data as Map<String, dynamic>);
  }

  /// Verifies the gateway payment and credits the wallet — returns the new
  /// balance. Exactly one of the stripe/razorpay/paystack/flutterwave
  /// reference groups should be set, matching [paymentMethod].
  Future<double> recharge({
    required String paymentMethod,
    String? stripePaymentIntentId,
    String? razorpayPaymentId,
    String? razorpayOrderId,
    String? razorpaySignature,
    String? paystackReference,
    String? flutterwaveReference,
  }) async {
    final data = await _apiClient.post(
      '/wallet/recharge',
      data: {
        'payment_method': paymentMethod,
        'stripe_payment_intent_id': ?stripePaymentIntentId,
        'razorpay_payment_id': ?razorpayPaymentId,
        'razorpay_order_id': ?razorpayOrderId,
        'razorpay_signature': ?razorpaySignature,
        'paystack_reference': ?paystackReference,
        'flutterwave_reference': ?flutterwaveReference,
      },
    );
    return ((data as Map<String, dynamic>)['balance'] as num).toDouble();
  }
}
