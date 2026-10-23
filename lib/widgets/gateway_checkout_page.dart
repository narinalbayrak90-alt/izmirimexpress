import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../theme/app_colors.dart';
import 'app_loader.dart';

/// Full-screen in-app browser for a hosted Paystack/Flutterwave checkout
/// page (project.txt Module 8). Neither gateway ships a maintained Flutter
/// SDK we want to depend on, so the customer pays on the gateway's own
/// hosted page and we watch for the redirect back to
/// `{APP_URL}/payment/callback` (set by the backend when it initializes
/// the charge — see `PaystackService` / `FlutterwaveService`).
///
/// Pops with:
///  * `true`  — checkout finished; the caller should now hit the backend,
///              which independently re-verifies the charge with the
///              gateway before trusting it (so a "true" here that was
///              actually a failed/abandoned payment is caught there).
///  * `false` — the customer backed out, or the redirect carried an
///              explicit `status=cancelled` / `failed`.
class GatewayCheckoutPage extends StatefulWidget {
  const GatewayCheckoutPage({super.key, required this.authorizationUrl, required this.title});

  final String authorizationUrl;
  final String title;

  @override
  State<GatewayCheckoutPage> createState() => _GatewayCheckoutPageState();
}

class _GatewayCheckoutPageState extends State<GatewayCheckoutPage> {
  late final WebViewController _controller;
  bool _isLoading = true;
  bool _settled = false;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) => _handleUrl(request.url) ? NavigationDecision.prevent : NavigationDecision.navigate,
          onUrlChange: (change) {
            if (change.url != null) _handleUrl(change.url!);
          },
          onPageStarted: (_) {
            if (mounted) setState(() => _isLoading = true);
          },
          onPageFinished: (_) {
            if (mounted) setState(() => _isLoading = false);
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.authorizationUrl));
  }

  /// Returns true (and closes the sheet) once [url] is the backend's
  /// payment-callback URL, otherwise false so the WebView keeps loading it.
  bool _handleUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.path.contains('/payment/callback')) return false;
    if (_settled) return true;
    _settled = true;

    final status = (uri.queryParameters['status'] ?? '').toLowerCase();
    final cancelled = status == 'cancelled' || status == 'canceled' || status == 'failed';

    if (mounted) Navigator.of(context).pop(!cancelled);
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !_settled) {
          _settled = true;
          Navigator.of(context).pop(false);
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.title),
          leading: IconButton(
            icon: const Icon(Icons.close_rounded),
            onPressed: () {
              if (_settled) return;
              _settled = true;
              Navigator.of(context).pop(false);
            },
          ),
        ),
        body: Stack(
          children: [
            WebViewWidget(controller: _controller),
            if (_isLoading)
              const ColoredBox(
                color: AppColors.background,
                child: Center(child: AppLoader()),
              ),
          ],
        ),
      ),
    );
  }
}

/// Opens [GatewayCheckoutPage] as a full-screen route and resolves to
/// whether the customer completed checkout (see the class doc for the
/// exact meaning of the boolean).
Future<bool> openGatewayCheckout(
  BuildContext context, {
  required String authorizationUrl,
  required String title,
}) async {
  final result = await Navigator.of(context).push<bool>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => GatewayCheckoutPage(authorizationUrl: authorizationUrl, title: title),
    ),
  );
  return result ?? false;
}
