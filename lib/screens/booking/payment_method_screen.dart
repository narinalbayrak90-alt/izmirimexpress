import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:go_router/go_router.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';

import '../../providers/app_providers.dart';
import '../../services/api_exception.dart';
import '../../services/app_settings.dart';
import '../../services/order_service.dart';
import '../../services/payment_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../widgets/gateway_checkout_page.dart';
import '../../widgets/primary_button.dart';
import '../home/home_provider.dart';
import 'booking_draft.dart';
import 'booking_providers.dart';
import 'booking_stepper.dart';
import 'fare_estimate.dart';

/// The logged-in customer's wallet balance, used only to preview the
/// Total / Wallet / Payable breakdown before checkout — the backend is the
/// authority on whether an order is actually payable (see
/// `OrderController::store`), this is display-only.
final _walletBalanceProvider = FutureProvider<double>((ref) => ref.watch(walletServiceProvider).getBalance());

/// Display metadata for a payment method — admin only stores which ones
/// are enabled (project.txt Module 8), the label/icon are cosmetic here.
class _PaymentMethodInfo {
  const _PaymentMethodInfo({required this.icon, required this.titleKey, required this.subtitleKey});

  final IconData icon;
  final String titleKey;
  final String subtitleKey;

  String get title => titleKey.tr();
  String get subtitle => subtitleKey.isEmpty ? '' : subtitleKey.tr();
}

const Map<String, _PaymentMethodInfo> _methodInfo = {
  // Synthetic method (not an admin-toggled gateway) — the only option
  // shown once the wallet balance already covers the whole order.
  'wallet': _PaymentMethodInfo(
    icon: Icons.account_balance_wallet_rounded,
    titleKey: 'booking.payment_wallet_title',
    subtitleKey: 'booking.payment_wallet_subtitle',
  ),
  'cod': _PaymentMethodInfo(
    icon: Icons.payments_outlined,
    titleKey: 'booking.payment_cod_title',
    subtitleKey: 'booking.payment_cod_subtitle',
  ),
  'stripe': _PaymentMethodInfo(
    icon: Icons.credit_card_rounded,
    titleKey: 'booking.payment_stripe_title',
    subtitleKey: 'booking.payment_stripe_subtitle',
  ),
  'razorpay': _PaymentMethodInfo(
    icon: Icons.account_balance_wallet_outlined,
    titleKey: 'booking.payment_razorpay_title',
    subtitleKey: 'booking.payment_razorpay_subtitle',
  ),
  'paystack': _PaymentMethodInfo(
    icon: Icons.account_balance_outlined,
    titleKey: 'booking.payment_paystack_title',
    subtitleKey: 'booking.payment_paystack_subtitle',
  ),
  'flutterwave': _PaymentMethodInfo(
    icon: Icons.bolt_outlined,
    titleKey: 'booking.payment_flutterwave_title',
    subtitleKey: 'booking.payment_flutterwave_subtitle',
  ),
};

/// Step 5 of the booking flow: choose a payment method (project.txt
/// Module 8). Only shows methods the admin has enabled
/// ([AppSettings.paymentMethods]) — reads the fare/coupon already computed
/// on the Summary step from [bookingFareEstimateProvider] rather than
/// re-fetching, since nothing about the order changes here.
///
/// Every method pays through the wallet: COD skips it entirely, while the
/// online gateways top the wallet up for whatever it doesn't already cover
/// and then pay the order from it — see `OrderController`.
///
/// If the wallet already covers the total, the order is placed directly —
/// no gateway involved. Otherwise Confirm opens the gateway for just the
/// shortfall: Stripe's payment sheet, Razorpay Checkout, or (Paystack /
/// Flutterwave) a hosted checkout page in an in-app WebView (see
/// [GatewayCheckoutPage]). On success the order is placed with that
/// payment's reference, which `OrderController::store` independently
/// re-verifies against the gateway's own API before trusting it. Stripe
/// and Razorpay also need a publishable key, fetched on demand from
/// `GET /payment/keys` (auth-required — never bundled into public `/home`).
class PaymentMethodScreen extends ConsumerStatefulWidget {
  const PaymentMethodScreen({super.key});

  @override
  ConsumerState<PaymentMethodScreen> createState() => _PaymentMethodScreenState();
}

class _PaymentMethodScreenState extends ConsumerState<PaymentMethodScreen> {
  String? _selectedMethod;
  bool _isSubmitting = false;
  PaymentKeys? _paymentKeys;
  bool _isFetchingKeys = false;

  /// The methods actually offered given the wallet balance. Once the
  /// wallet covers the whole order the gateways are dropped — there's
  /// nothing for them to charge — leaving "pay from wallet", plus COD if
  /// the admin enabled it (for a customer who'd rather keep their balance).
  List<String> _visibleMethods(List<String> enabled, FareEstimate? estimate, double walletBalance) {
    if (estimate == null) return enabled;
    final walletCoversTotal = estimate.total > 0 && walletBalance >= estimate.total - 0.001;
    if (!walletCoversTotal) return enabled;
    return ['wallet', if (enabled.contains('cod')) 'cod'];
  }

  Future<void> _fetchPaymentKeysIfNeeded() async {
    if (_selectedMethod == null ||
        _selectedMethod == 'cod' ||
        _selectedMethod == 'wallet' ||
        _paymentKeys != null ||
        _isFetchingKeys) {
      return;
    }
    setState(() => _isFetchingKeys = true);
    try {
      final keys = await ref.read(paymentServiceProvider).getKeys();
      if (!mounted) return;
      setState(() {
        _paymentKeys = keys;
        _isFetchingKeys = false;
      });
    } on ApiException {
      // Non-fatal: Confirm still works via the wallet-covers-it path.
      // Only an actual gateway top-up would need this key, and that step
      // isn't wired up yet — see the class doc comment.
      if (!mounted) return;
      setState(() => _isFetchingKeys = false);
    }
  }

  Future<void> _confirm(FareEstimate estimate, double walletBalance) async {
    final method = _selectedMethod;
    final draft = ref.read(bookingDraftProvider);
    if (method == null || draft.category == null || draft.pickup == null || draft.dropoff == null) return;

    final payable = method == 'cod' ? estimate.total : (estimate.total - walletBalance).clamp(0, estimate.total).toDouble();

    // COD, wallet-covers-it ('wallet' method or any method with nothing
    // left to charge) → place directly, no gateway step.
    if (method == 'cod' || method == 'wallet' || payable <= 0) {
      await _placeOrder(draft, estimate, method);
      return;
    }

    if (method == 'stripe' && !kIsWeb) {
      await _payWithStripe(draft, estimate);
    } else if (method == 'razorpay') {
      await _payWithRazorpay(draft, estimate);
    } else if (method == 'stripe' || method == 'paystack' || method == 'flutterwave') {
      await _payWithHostedCheckout(draft, estimate, method);
    }
  }

  Future<void> _placeOrder(
    BookingDraft draft,
    FareEstimate estimate,
    String method, {
    String? stripePaymentIntentId,
    String? stripeCheckoutSessionId,
    String? razorpayPaymentId,
    String? razorpayOrderId,
    String? razorpaySignature,
    String? paystackReference,
    String? flutterwaveReference,
  }) async {
    setState(() => _isSubmitting = true);
    try {
      final order = await ref.read(orderServiceProvider).placeOrder(
            categoryId: draft.category!.id,
            pickup: draft.pickup!,
            dropoff: draft.dropoff!,
            paymentMethod: method,
            couponCode: estimate.appliedCoupon?.code,
            scheduledAt: draft.scheduledAt,
            stripePaymentIntentId: stripePaymentIntentId,
            stripeCheckoutSessionId: stripeCheckoutSessionId,
            razorpayPaymentId: razorpayPaymentId,
            razorpayOrderId: razorpayOrderId,
            razorpaySignature: razorpaySignature,
            paystackReference: paystackReference,
            flutterwaveReference: flutterwaveReference,
          );
      if (!mounted) return;
      await _onOrderPlaced(order);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  /// Opens Stripe's payment sheet for just the wallet shortfall. On
  /// success, places the order with the confirmed PaymentIntent's id —
  /// the backend fetches that intent from Stripe itself to verify it
  /// before trusting it, so the app never has to be trusted on its own.
  Future<void> _payWithStripe(BookingDraft draft, FareEstimate estimate) async {
    setState(() => _isSubmitting = true);
    try {
      final intent = await ref.read(paymentServiceProvider).createStripeIntent(
            categoryId: draft.category!.id,
            pickup: draft.pickup!,
            dropoff: draft.dropoff!,
            couponCode: estimate.appliedCoupon?.code,
          );

      final publishableKey = (_paymentKeys ?? await ref.read(paymentServiceProvider).getKeys()).stripePublicKey;
      if (publishableKey == null) {
        throw ApiException(message: 'booking.card_unavailable'.tr());
      }

      Stripe.publishableKey = publishableKey;
      await Stripe.instance.applySettings();
      await Stripe.instance.initPaymentSheet(
        paymentSheetParameters: SetupPaymentSheetParameters(
          paymentIntentClientSecret: intent.clientSecret,
          merchantDisplayName: 'app_name'.tr(),
        ),
      );
      await Stripe.instance.presentPaymentSheet();

      if (!mounted) return;
      await _placeOrder(draft, estimate, 'stripe', stripePaymentIntentId: intent.paymentIntentId);
    } on StripeException catch (e) {
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      // Canceled = the customer dismissed the sheet — not an error worth a snackbar.
      if (e.error.code != FailureCode.Canceled) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.error.localizedMessage ?? e.error.message ?? 'booking.payment_failed'.tr())),
        );
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  /// Opens Razorpay Checkout for just the wallet shortfall. Razorpay's
  /// plugin is event-based rather than Future-based, so a [Completer]
  /// bridges it into the same async flow as Stripe. On success, places the
  /// order with the payment/order id + signature — the backend
  /// re-verifies the signature and fetches the payment from Razorpay
  /// itself before trusting it.
  Future<void> _payWithRazorpay(BookingDraft draft, FareEstimate estimate) async {
    setState(() => _isSubmitting = true);
    try {
      final order = await ref.read(paymentServiceProvider).createRazorpayOrder(
            categoryId: draft.category!.id,
            pickup: draft.pickup!,
            dropoff: draft.dropoff!,
            couponCode: estimate.appliedCoupon?.code,
          );

      final razorpay = Razorpay();
      final completer = Completer<PaymentSuccessResponse?>();
      razorpay.on(Razorpay.EVENT_PAYMENT_SUCCESS, (PaymentSuccessResponse response) {
        if (!completer.isCompleted) completer.complete(response);
      });
      razorpay.on(Razorpay.EVENT_PAYMENT_ERROR, (PaymentFailureResponse response) {
        if (!completer.isCompleted) completer.complete(null);
      });
      razorpay.on(Razorpay.EVENT_EXTERNAL_WALLET, (ExternalWalletResponse response) {
        if (!completer.isCompleted) completer.complete(null);
      });

      razorpay.open({
        'key': order.keyId,
        'order_id': order.orderId,
        'amount': (order.payableAmount * 100).round(),
        'name': 'app_name'.tr(),
        'description': 'booking.order_payment'.tr(),
      });

      final result = await completer.future;
      razorpay.clear();

      if (result?.paymentId == null || result?.orderId == null || result?.signature == null) {
        // Cancelled/failed — Razorpay's own checkout UI already told the
        // customer why, no need for a second snackbar.
        if (!mounted) return;
        setState(() => _isSubmitting = false);
        return;
      }

      if (!mounted) return;
      await _placeOrder(
        draft,
        estimate,
        'razorpay',
        razorpayPaymentId: result!.paymentId,
        razorpayOrderId: result.orderId,
        razorpaySignature: result.signature,
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  /// Opens Paystack's or Flutterwave's hosted checkout page in an in-app
  /// WebView for just the wallet shortfall (see [GatewayCheckoutPage]). On
  /// completion, places the order with the charge reference — the backend
  /// fetches that charge from the gateway itself to verify it before
  /// trusting it, so the app is never trusted on its own.
  Future<void> _payWithHostedCheckout(BookingDraft draft, FareEstimate estimate, String method) async {
    setState(() => _isSubmitting = true);
    try {
      final payment = ref.read(paymentServiceProvider);
      final checkout = switch (method) {
        'stripe' => await payment.createStripeCheckout(
            categoryId: draft.category!.id,
            pickup: draft.pickup!,
            dropoff: draft.dropoff!,
            couponCode: estimate.appliedCoupon?.code,
          ),
        'paystack' => await payment.createPaystackCheckout(
            categoryId: draft.category!.id,
            pickup: draft.pickup!,
            dropoff: draft.dropoff!,
            couponCode: estimate.appliedCoupon?.code,
          ),
        _ => await payment.createFlutterwaveCheckout(
            categoryId: draft.category!.id,
            pickup: draft.pickup!,
            dropoff: draft.dropoff!,
            couponCode: estimate.appliedCoupon?.code,
          ),
      };

      if (!mounted) return;
      final completed = await openGatewayCheckout(
        context,
        authorizationUrl: checkout.authorizationUrl,
        title: 'booking.order_payment'.tr(),
      );
      if (!mounted) return;
      if (!completed) {
        // Cancelled/closed — the checkout page already showed the customer
        // where things stood, no second snackbar needed.
        setState(() => _isSubmitting = false);
        return;
      }

      await _placeOrder(
        draft,
        estimate,
        method,
        stripeCheckoutSessionId: method == 'stripe' ? checkout.reference : null,
        paystackReference: method == 'paystack' ? checkout.reference : null,
        flutterwaveReference: method == 'flutterwave' ? checkout.reference : null,
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  /// Order placed — clears the booking draft (nothing left to resume) and
  /// hands off to the tracking screen (project.txt Module 9: "If instant
  /// order -> auto navigate to Live Tracking screen"). `go()` rather than
  /// `push()` so the back button doesn't lead into the now-stale
  /// booking/payment screens.
  ///
  /// `payment_status == 'paid'` covers both online-payment cases (Stripe/
  /// Razorpay top-up, or the wallet already covering it) — COD stays
  /// `pending` until delivery, so it doesn't get the "payment successful"
  /// toast the tracking screen shows on arrival.
  Future<void> _onOrderPlaced(PlacedOrder order) async {
    ref.read(bookingDraftProvider.notifier).state = const BookingDraft();
    ref.read(bookingFareEstimateProvider.notifier).state = null;
    ref.invalidate(_walletBalanceProvider);

    if (!mounted) return;
    context.go(
      '/orders/${order.id}',
      extra: {'paymentSuccess': order.paymentStatus == 'paid'},
    );
  }

  @override
  Widget build(BuildContext context) {
    final estimate = ref.watch(bookingFareEstimateProvider);
    final settings = ref.watch(appSettingsProvider).valueOrNull ?? const AppSettings.fallback();
    final walletBalance = (ref.watch(_walletBalanceProvider).valueOrNull ?? 0).toDouble();
    final methods = _visibleMethods(settings.paymentMethods, estimate, walletBalance);
    final walletCoversTotal = methods.contains('wallet');
    // Reset the selection if the visible set changed under it (e.g. the
    // wallet balance loaded in and now covers the whole order).
    if (_selectedMethod == null || !methods.contains(_selectedMethod)) {
      _selectedMethod = methods.isNotEmpty ? methods.first : null;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _fetchPaymentKeysIfNeeded());

    return Scaffold(
      appBar: AppBar(title: Text('booking.new_booking'.tr())),
      body: SafeArea(
        top: false,
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.md, AppSpacing.md, 0),
              child: const BookingStepper(currentStep: 4),
            ),
            Expanded(child: _buildBody(context, estimate, methods, walletBalance, walletCoversTotal)),
          ],
        ),
      ),
      bottomNavigationBar: estimate == null || methods.isEmpty
          ? null
          : _buildBottomBar(context, estimate, walletBalance),
    );
  }

  Widget _buildBody(
    BuildContext context,
    FareEstimate? estimate,
    List<String> methods,
    double walletBalance,
    bool walletCoversTotal,
  ) {
    if (estimate == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Text(
            'booking.missing_order_details'.tr(),
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.textSecondary),
          ),
        ),
      );
    }

    final isCod = _selectedMethod == 'cod';
    final payable = isCod ? estimate.total : (estimate.total - walletBalance).clamp(0, estimate.total);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: AppColors.surfaceMuted,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                _SummaryRow(label: 'booking.order_total'.tr(), value: estimate.format(estimate.total), isTotal: true),
                if (!isCod) ...[
                  const SizedBox(height: 6),
                  _SummaryRow(label: 'booking.wallet_balance'.tr(), value: estimate.format(walletBalance)),
                  const Divider(height: AppSpacing.lg, color: AppColors.divider),
                  _SummaryRow(
                    label: 'booking.payable_now'.tr(),
                    value: estimate.format(payable.toDouble()),
                    isTotal: true,
                    valueColor: payable > 0 ? AppColors.primaryDark : AppColors.success,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            'booking.select_payment_method'.tr(),
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
          ),
          const SizedBox(height: AppSpacing.sm),
          if (walletCoversTotal) ...[
            Container(
              padding: const EdgeInsets.all(AppSpacing.sm),
              decoration: BoxDecoration(
                color: AppColors.surfaceMuted,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.info_outline_rounded, size: 18, color: AppColors.textSecondary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'booking.wallet_covers_notice'.tr(),
                      style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary, height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
          if (methods.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
              child: Text(
                'booking.no_payment_methods'.tr(),
                style: const TextStyle(color: AppColors.textSecondary),
              ),
            )
          else
            ...methods.map(
              (method) => Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: _PaymentMethodTile(
                  method: method,
                  isSelected: method == _selectedMethod,
                  onTap: () => setState(() => _selectedMethod = method),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBottomBar(BuildContext context, FareEstimate estimate, double walletBalance) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.background,
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 16, offset: const Offset(0, -4))],
      ),
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.only(bottom: AppSpacing.sm),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.md, AppSpacing.md, AppSpacing.sm),
          child: PrimaryButton(
            label: 'booking.confirm_and_pay'.tr(namedArgs: {'total': estimate.format(estimate.total)}),
            isLoading: _isSubmitting,
            onPressed: _selectedMethod == null ? null : () => _confirm(estimate, walletBalance),
          ),
        ),
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.label, required this.value, this.isTotal = false, this.valueColor});

  final String label;
  final String value;
  final bool isTotal;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(color: AppColors.textSecondary)),
        Text(
          value,
          style: TextStyle(
            fontSize: isTotal ? 18 : 14,
            fontWeight: isTotal ? FontWeight.w700 : FontWeight.w500,
            color: valueColor ?? AppColors.textPrimary,
          ),
        ),
      ],
    );
  }
}

class _PaymentMethodTile extends StatelessWidget {
  const _PaymentMethodTile({required this.method, required this.isSelected, required this.onTap});

  final String method;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final info = _methodInfo[method];
    final icon = info?.icon ?? Icons.payment_rounded;
    final title = info?.title ?? method;
    final subtitle = info?.subtitle ?? '';

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.heroBackground : AppColors.background,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: isSelected ? AppColors.primary : AppColors.border, width: isSelected ? 1.5 : 1),
        ),
        child: Row(
          children: [
            Icon(icon, color: AppColors.primaryDark),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                  if (subtitle.isNotEmpty)
                    Text(subtitle, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                ],
              ),
            ),
            Icon(
              isSelected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
              color: isSelected ? AppColors.primary : AppColors.border,
            ),
          ],
        ),
      ),
    );
  }
}
