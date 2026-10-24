import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';

import '../../providers/app_providers.dart';
import '../../services/api_exception.dart';
import '../../services/app_settings.dart';
import '../../services/payment_service.dart';
import '../../services/wallet_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../utils/live_refresh.dart';
import '../../widgets/app_loader.dart';
import '../../widgets/gateway_checkout_page.dart';
import '../../widgets/primary_button.dart';
import '../home/home_provider.dart';

const _presetAmounts = [20, 50, 100, 500];

/// Display metadata for a gateway option — mirrors
/// `PaymentMethodScreen`'s `_methodInfo`, minus Cash on Delivery (a
/// recharge always needs an online payment).
const Map<String, ({IconData icon, String titleKey, String subtitleKey})> _gatewayInfo = {
  'stripe': (icon: Icons.credit_card_rounded, titleKey: 'booking.payment_stripe_title', subtitleKey: 'booking.payment_stripe_subtitle'),
  'razorpay': (icon: Icons.account_balance_wallet_outlined, titleKey: 'booking.payment_razorpay_title', subtitleKey: 'booking.payment_razorpay_subtitle'),
  'paystack': (icon: Icons.account_balance_outlined, titleKey: 'booking.payment_paystack_title', subtitleKey: 'booking.payment_paystack_subtitle'),
  'flutterwave': (icon: Icons.bolt_outlined, titleKey: 'booking.payment_flutterwave_title', subtitleKey: 'booking.payment_flutterwave_subtitle'),
};

/// The online gateways a wallet recharge can use — every enabled payment
/// method except Cash on Delivery.
const _rechargeGateways = {'stripe', 'razorpay', 'paystack', 'flutterwave'};

/// Wallet screen (project.txt Module 12) — balance header, a Recharge tab
/// (preset/custom amount + Stripe/Razorpay) and a History tab (every
/// credit/debit transaction). Reached from the Account screen's Wallet
/// quick action.
class WalletScreen extends ConsumerStatefulWidget {
  const WalletScreen({super.key});

  @override
  ConsumerState<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends ConsumerState<WalletScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabController = TabController(length: 2, vsync: this);

  double? _balance;

  final _amountController = TextEditingController();
  String? _selectedMethod;
  PaymentKeys? _paymentKeys;
  bool _isRecharging = false;

  final _historyScrollController = ScrollController();
  final List<WalletTransactionItem> _transactions = [];
  int _historyPage = 1;
  bool _historyHasMore = true;
  bool _isLoadingHistory = true;
  bool _isLoadingMoreHistory = false;
  String? _historyError;

  @override
  void initState() {
    super.initState();
    _loadBalance();
    _loadFirstHistoryPage();
    _balanceTicker.start();
    _historyScrollController.addListener(_onHistoryScroll);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _amountController.dispose();
    _balanceTicker.stop();
    _historyScrollController.removeListener(_onHistoryScroll);
    _historyScrollController.dispose();
    super.dispose();
  }

  /// Live balance, e.g. after a refund or an admin top-up.
  late final _balanceTicker = LiveTicker(_loadBalance, every: const Duration(seconds: 20));

  Future<void> _loadBalance() async {
    try {
      final balance = await ref.read(walletServiceProvider).getBalance();
      if (!mounted) return;
      setState(() => _balance = balance);
    } on ApiException {
      // Header just stays on its loading state — the Recharge/History tabs
      // still work and will surface their own errors independently.
    }
  }

  void _onHistoryScroll() {
    if (!_historyHasMore || _isLoadingHistory || _isLoadingMoreHistory) return;
    final threshold = _historyScrollController.position.maxScrollExtent - 300;
    if (_historyScrollController.position.pixels >= threshold) {
      _loadNextHistoryPage();
    }
  }

  Future<void> _loadFirstHistoryPage() async {
    setState(() {
      _isLoadingHistory = true;
      _historyError = null;
    });
    try {
      final result = await ref.read(walletServiceProvider).getHistory(page: 1);
      if (!mounted) return;
      setState(() {
        _transactions
          ..clear()
          ..addAll(result.items);
        _historyPage = result.currentPage;
        _historyHasMore = result.hasMore;
        _isLoadingHistory = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoadingHistory = false;
        _historyError = e.message;
      });
    }
  }

  Future<void> _loadNextHistoryPage() async {
    setState(() => _isLoadingMoreHistory = true);
    try {
      final result = await ref.read(walletServiceProvider).getHistory(page: _historyPage + 1);
      if (!mounted) return;
      setState(() {
        _transactions.addAll(result.items);
        _historyPage = result.currentPage;
        _historyHasMore = result.hasMore;
        _isLoadingMoreHistory = false;
      });
    } on ApiException {
      if (!mounted) return;
      setState(() => _isLoadingMoreHistory = false);
    }
  }

  Future<void> _fetchPaymentKeysIfNeeded() async {
    if (_paymentKeys != null) return;
    try {
      final keys = await ref.read(paymentServiceProvider).getKeys();
      if (!mounted) return;
      setState(() => _paymentKeys = keys);
    } on ApiException {
      // Recharge will surface its own error if a key turns out to be
      // missing when the customer actually tries to pay.
    }
  }

  double? get _enteredAmount => double.tryParse(_amountController.text.trim());

  Future<void> _recharge() async {
    final amount = _enteredAmount;
    final method = _selectedMethod;
    if (amount == null || amount <= 0 || method == null) return;

    setState(() => _isRecharging = true);
    if (method == 'stripe' && !kIsWeb) {
      await _rechargeWithStripe(amount);
    } else if (method == 'razorpay') {
      await _rechargeWithRazorpay(amount);
    } else {
      await _rechargeWithHostedCheckout(amount, method);
    }
  }

  Future<void> _rechargeWithStripe(double amount) async {
    try {
      final intent = await ref.read(walletServiceProvider).createStripeIntent(amount);

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
      await _confirmRecharge(paymentMethod: 'stripe', stripePaymentIntentId: intent.paymentIntentId);
    } on StripeException catch (e) {
      if (!mounted) return;
      setState(() => _isRecharging = false);
      if (e.error.code != FailureCode.Canceled) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.error.localizedMessage ?? e.error.message ?? 'booking.payment_failed'.tr())),
        );
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _isRecharging = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _rechargeWithRazorpay(double amount) async {
    try {
      final order = await ref.read(walletServiceProvider).createRazorpayOrder(amount);

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
        'description': 'account.wallet_recharge'.tr(),
      });

      final result = await completer.future;
      razorpay.clear();

      if (result?.paymentId == null || result?.orderId == null || result?.signature == null) {
        if (!mounted) return;
        setState(() => _isRecharging = false);
        return;
      }

      if (!mounted) return;
      await _confirmRecharge(
        paymentMethod: 'razorpay',
        razorpayPaymentId: result!.paymentId,
        razorpayOrderId: result.orderId,
        razorpaySignature: result.signature,
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _isRecharging = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  /// Opens Paystack's or Flutterwave's hosted checkout page in an in-app
  /// WebView for a wallet recharge (see [GatewayCheckoutPage]). On
  /// completion, credits the wallet via [_confirmRecharge] — the backend
  /// re-verifies the charge with the gateway before crediting.
  Future<void> _rechargeWithHostedCheckout(double amount, String method) async {
    try {
      final wallet = ref.read(walletServiceProvider);
      final checkout = switch (method) {
        'stripe' => await wallet.createStripeCheckout(amount),
        'paystack' => await wallet.createPaystackCheckout(amount),
        _ => await wallet.createFlutterwaveCheckout(amount),
      };

      if (!mounted) return;
      final completed = await openGatewayCheckout(
        context,
        authorizationUrl: checkout.authorizationUrl,
        title: 'account.wallet_recharge'.tr(),
      );
      if (!mounted) return;
      if (!completed) {
        setState(() => _isRecharging = false);
        return;
      }

      await _confirmRecharge(
        paymentMethod: method,
        stripeCheckoutSessionId: method == 'stripe' ? checkout.reference : null,
        paystackReference: method == 'paystack' ? checkout.reference : null,
        flutterwaveReference: method == 'flutterwave' ? checkout.reference : null,
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _isRecharging = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _confirmRecharge({
    required String paymentMethod,
    String? stripePaymentIntentId,
    String? stripeCheckoutSessionId,
    String? razorpayPaymentId,
    String? razorpayOrderId,
    String? razorpaySignature,
    String? paystackReference,
    String? flutterwaveReference,
  }) async {
    try {
      final balance = await ref.read(walletServiceProvider).recharge(
            paymentMethod: paymentMethod,
            stripePaymentIntentId: stripePaymentIntentId,
            stripeCheckoutSessionId: stripeCheckoutSessionId,
            razorpayPaymentId: razorpayPaymentId,
            razorpayOrderId: razorpayOrderId,
            razorpaySignature: razorpaySignature,
            paystackReference: paystackReference,
            flutterwaveReference: flutterwaveReference,
          );
      if (!mounted) return;
      setState(() {
        _balance = balance;
        _isRecharging = false;
        _amountController.clear();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('account.wallet_recharged'.tr()), backgroundColor: AppColors.success),
      );
      _loadFirstHistoryPage();
      _tabController.animateTo(1);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _isRecharging = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(appSettingsProvider).valueOrNull ?? const AppSettings.fallback();
    WidgetsBinding.instance.addPostFrameCallback((_) => _fetchPaymentKeysIfNeeded());

    return Scaffold(
      appBar: AppBar(title: Text('account.wallet'.tr())),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.md, AppSpacing.md, 0),
              child: _BalanceCard(balance: _balance, settings: settings),
            ),
            const SizedBox(height: AppSpacing.md),
            TabBar(
              controller: _tabController,
              labelColor: AppColors.primaryDark,
              unselectedLabelColor: AppColors.textSecondary,
              indicatorColor: AppColors.primary,
              labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
              tabs: [Tab(text: 'account.recharge'.tr()), Tab(text: 'account.history'.tr())],
            ),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildRechargeTab(settings),
                  _buildHistoryTab(settings),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRechargeTab(AppSettings settings) {
    final gateways = settings.paymentMethods.where(_rechargeGateways.contains).toList();
    final enteredAmount = _enteredAmount;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('account.recharge_amount'.tr(), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              for (final preset in _presetAmounts) ...[
                Expanded(
                  child: _AmountChip(
                    label: settings.format(preset.toDouble()),
                    isSelected: enteredAmount == preset,
                    onTap: () => setState(() => _amountController.text = preset.toString()),
                  ),
                ),
                if (preset != _presetAmounts.last) const SizedBox(width: AppSpacing.sm),
              ],
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: _amountController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}'))],
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: 'account.enter_custom_amount'.tr(),
              prefixIcon: Padding(
                padding: const EdgeInsets.all(14),
                child: Text(settings.currencySign, style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
              ),
              prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          Text('booking.select_payment_method'.tr(), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
          const SizedBox(height: AppSpacing.sm),
          if (gateways.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
              child: Text(
                'account.no_online_payment_methods'.tr(),
                style: const TextStyle(color: AppColors.textSecondary),
              ),
            )
          else
            ...gateways.map(
              (method) => Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: _GatewayTile(
                  method: method,
                  isSelected: method == _selectedMethod,
                  onTap: () => setState(() => _selectedMethod = method),
                ),
              ),
            ),
          const SizedBox(height: AppSpacing.lg),
          PrimaryButton(
            label: enteredAmount == null || enteredAmount <= 0
                ? 'account.recharge_wallet'.tr()
                : 'account.recharge_with_amount'.tr(namedArgs: {'amount': settings.format(enteredAmount)}),
            isLoading: _isRecharging,
            onPressed: (enteredAmount == null || enteredAmount <= 0 || _selectedMethod == null) ? null : _recharge,
          ),
          const SizedBox(height: AppSpacing.md),
        ],
      ),
    );
  }

  Widget _buildHistoryTab(AppSettings settings) {
    if (_isLoadingHistory) {
      return const Center(child: AppLoader());
    }
    if (_historyError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline_rounded, color: AppColors.error, size: 40),
              const SizedBox(height: AppSpacing.sm),
              Text(_historyError!, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textSecondary)),
              const SizedBox(height: AppSpacing.md),
              OutlinedButton(onPressed: _loadFirstHistoryPage, child: Text('common.retry'.tr())),
            ],
          ),
        ),
      );
    }
    if (_transactions.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.receipt_long_outlined, color: AppColors.textSecondary, size: 40),
              const SizedBox(height: AppSpacing.sm),
              Text('account.no_transactions'.tr(), style: const TextStyle(color: AppColors.textSecondary)),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadFirstHistoryPage,
      child: ListView.separated(
        controller: _historyScrollController,
        padding: const EdgeInsets.all(AppSpacing.md),
        itemCount: _transactions.length + (_historyHasMore ? 1 : 0),
        separatorBuilder: (context, index) => const SizedBox(height: AppSpacing.sm),
        itemBuilder: (context, index) {
          if (index >= _transactions.length) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
              child: Center(child: AppLoader(size: 24)),
            );
          }
          return _TransactionRow(transaction: _transactions[index], settings: settings);
        },
      ),
    );
  }
}

class _BalanceCard extends StatelessWidget {
  const _BalanceCard({required this.balance, required this.settings});

  final double? balance;
  final AppSettings settings;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(color: AppColors.heroBackground, borderRadius: BorderRadius.circular(20)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                height: 32,
                width: 32,
                decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                child: const Icon(Icons.account_balance_wallet_rounded, size: 18, color: AppColors.primaryDark),
              ),
              const SizedBox(width: AppSpacing.sm),
              Text('account.wallet_balance'.tr(), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          balance == null
              ? const AppLoader(size: 28)
              : Text(
                  settings.format(balance!),
                  style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
                ),
        ],
      ),
    );
  }
}

class _AmountChip extends StatelessWidget {
  const _AmountChip({required this.label, required this.isSelected, required this.onTap});

  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary : AppColors.surfaceMuted,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: isSelected ? AppColors.primary : AppColors.border),
        ),
        child: Text(
          label,
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: isSelected ? AppColors.textPrimary : AppColors.textSecondary),
        ),
      ),
    );
  }
}

class _GatewayTile extends StatelessWidget {
  const _GatewayTile({required this.method, required this.isSelected, required this.onTap});

  final String method;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final info = _gatewayInfo[method];

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
            Icon(info?.icon ?? Icons.payment_rounded, color: AppColors.primaryDark),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(info?.titleKey.tr() ?? method, style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                  if (info != null) Text(info.subtitleKey.tr(), style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
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

class _TransactionRow extends StatelessWidget {
  const _TransactionRow({required this.transaction, required this.settings});

  final WalletTransactionItem transaction;
  final AppSettings settings;

  String _formatDate(BuildContext context, DateTime date) {
    return DateFormat.yMMMd(context.locale.toString()).format(date.toLocal());
  }

  @override
  Widget build(BuildContext context) {
    final isCredit = transaction.isCredit;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            height: 40,
            width: 40,
            decoration: BoxDecoration(
              color: isCredit ? AppColors.successBackground : AppColors.errorBackground,
              shape: BoxShape.circle,
            ),
            child: Icon(
              isCredit ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded,
              size: 18,
              color: isCredit ? AppColors.success : AppColors.error,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  transaction.description,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                ),
                const SizedBox(height: 2),
                Text(_formatDate(context, transaction.createdAt), style: const TextStyle(fontSize: 11.5, color: AppColors.textSecondary)),
              ],
            ),
          ),
          Text(
            '${isCredit ? '+' : '-'}${settings.format(transaction.amount)}',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: isCredit ? AppColors.success : AppColors.error),
          ),
        ],
      ),
    );
  }
}
