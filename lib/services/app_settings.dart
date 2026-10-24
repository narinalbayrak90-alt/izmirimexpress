import 'package:flutter/foundation.dart';

/// Admin-configured delivery geo-fence (App Setting > Delivery Area) — a
/// pickup must fall within [radiusKm] of ([lat], [lng]) to be accepted.
/// Mirrors the same check `OrderController::store` makes server-side, so
/// the app can reject an out-of-area pickup immediately instead of only at
/// final checkout.
class DeliveryArea {
  const DeliveryArea({required this.lat, required this.lng, required this.radiusKm});

  final double lat;
  final double lng;
  final double radiusKm;

  factory DeliveryArea.fromJson(Map<String, dynamic> json) {
    return DeliveryArea(
      lat: (json['lat'] as num).toDouble(),
      lng: (json['lng'] as num).toDouble(),
      radiusKm: (json['radius_km'] as num).toDouble(),
    );
  }

  Map<String, dynamic> toJson() => {'lat': lat, 'lng': lng, 'radius_km': radiusKm};
}

/// App-wide settings admin-configured on the backend (currency, language,
/// signup verification, ...), sourced from `GET /home`'s `settings` block
/// and cached locally via [SettingsStorageService] so the rest of the app
/// can read them without re-fetching `/home` (project.txt Module 1/2).
class AppSettings {
  const AppSettings({
    required this.appName,
    this.appLogoUrl,
    required this.currencySign,
    required this.currencyCode,
    required this.currencyPosition,
    required this.defaultLanguage,
    required this.signupVerificationType,
    required this.countryCodes,
    required this.paymentMethods,
    required this.deliveryArea,
    required this.maxDeliveryDistanceKm,
    this.onesignalAppId,
    this.liveKey,
    this.liveCluster,
  });

  /// App Setting > Welcome Page — shown in the home header and anywhere
  /// else the app's name/logo appears, instead of a hardcoded string/icon.
  final String appName;
  final String? appLogoUrl;

  final String currencySign;
  final String currencyCode;
  final String currencyPosition;
  final String defaultLanguage;

  /// `none` | `sms` | `email` | `whatsapp`.
  final String signupVerificationType;

  /// Calling codes (no `+`, e.g. `91`) selectable on the signup screen,
  /// admin-configured via the Signup Verification card.
  final List<String> countryCodes;

  /// `cod` | `stripe` | `razorpay`, admin-configured via the Payment
  /// Gateway settings — project.txt Module 8: the payment method screen
  /// only shows whichever of these are enabled.
  final List<String> paymentMethods;

  /// Null if the admin hasn't set a delivery area yet — unrestricted.
  final DeliveryArea? deliveryArea;

  /// Max pickup-to-drop-off distance, in kilometers.
  final double maxDeliveryDistanceKm;

  /// App Setting > Push Notification's OneSignal App ID for the customer
  /// app — null until the admin configures it. Only the App ID (the
  /// client SDK's own init key, meant to be public) is ever shared here;
  /// the REST API key stays server-only.
  final String? onesignalAppId;

  /// Pusher key and cluster for instant refresh; null until the admin sets
  /// them in App Setting > Push Notification > Live Updates.
  final String? liveKey;
  final String? liveCluster;

  static const _fallbackAppName = 'İzmirim Express';
  static const _fallbackCountryCodes = ['90', '91', '1', '44', '61', '971', '966', '65', '49', '33', '86'];
  static const _fallbackPaymentMethods = ['cod'];

  /// Gateways whose Flutter SDKs only run natively (Razorpay Checkout) —
  /// hidden in the web build. Stripe, Paystack and Flutterwave still work
  /// there through their hosted checkout pages.
  static const _nativeOnlyPaymentMethods = ['razorpay'];
  static const _fallbackMaxDeliveryDistanceKm = 25.0;

  factory AppSettings.fromJson(Map<String, dynamic> json) {
    final codes = (json['signup_verification_country_codes'] as List<dynamic>?)
        ?.map((e) => e.toString())
        .toList();
    final methods = (json['payment_methods'] as List<dynamic>?)
        ?.map((e) => e.toString())
        .where((method) => !kIsWeb || !_nativeOnlyPaymentMethods.contains(method))
        .toList();
    final deliveryAreaJson = json['delivery_area'] as Map<String, dynamic>?;

    return AppSettings(
      appName: (json['app_name'] as String?)?.trim().isNotEmpty == true
          ? json['app_name'] as String
          : _fallbackAppName,
      appLogoUrl: json['app_logo'] as String?,
      currencySign: json['currency_sign'] as String? ?? r'$',
      currencyCode: json['currency_code'] as String? ?? 'USD',
      currencyPosition: json['currency_position'] as String? ?? 'left',
      defaultLanguage: json['default_language'] as String? ?? 'tr',
      signupVerificationType: json['signup_verification_type'] as String? ?? 'none',
      countryCodes: (codes == null || codes.isEmpty) ? _fallbackCountryCodes : codes,
      paymentMethods: (methods == null || methods.isEmpty) ? _fallbackPaymentMethods : methods,
      deliveryArea: deliveryAreaJson == null ? null : DeliveryArea.fromJson(deliveryAreaJson),
      maxDeliveryDistanceKm:
          (json['max_delivery_distance_km'] as num?)?.toDouble() ?? _fallbackMaxDeliveryDistanceKm,
      onesignalAppId: json['onesignal_app_id'] as String?,
      liveKey: json['live'] is Map ? json['live']['key'] as String? : null,
      liveCluster: json['live'] is Map ? json['live']['cluster'] as String? : null,
    );
  }

  /// Formats [amount] with the admin's currency sign/position — the same
  /// formatting `FareEstimate.format` applies to a fare response, for
  /// screens (like order tracking) that only have a plain number to show.
  String format(double amount) {
    final formatted = amount.toStringAsFixed(2);
    return currencyPosition == 'right' ? '$formatted$currencySign' : '$currencySign$formatted';
  }

  Map<String, dynamic> toJson() => {
        'app_name': appName,
        'app_logo': appLogoUrl,
        'currency_sign': currencySign,
        'currency_code': currencyCode,
        'currency_position': currencyPosition,
        'default_language': defaultLanguage,
        'signup_verification_type': signupVerificationType,
        'signup_verification_country_codes': countryCodes,
        'payment_methods': paymentMethods,
        'delivery_area': deliveryArea?.toJson(),
        'max_delivery_distance_km': maxDeliveryDistanceKm,
        'onesignal_app_id': onesignalAppId,
        'live': liveKey == null ? null : {'key': liveKey, 'cluster': liveCluster},
      };

  /// Used before the first successful `/home` fetch (fresh install, no
  /// cache yet) or when the backend is unreachable and nothing is cached —
  /// same "graceful fallback" rule as [WelcomeContent.fallback]. No
  /// delivery area restriction, matching the backend's own fallback.
  const AppSettings.fallback()
      : appName = _fallbackAppName,
        appLogoUrl = null,
        currencySign = r'$',
        currencyCode = 'USD',
        currencyPosition = 'left',
        defaultLanguage = 'tr',
        signupVerificationType = 'none',
        countryCodes = _fallbackCountryCodes,
        paymentMethods = _fallbackPaymentMethods,
        deliveryArea = null,
        maxDeliveryDistanceKm = _fallbackMaxDeliveryDistanceKm,
        onesignalAppId = null,
        liveKey = null,
        liveCluster = null;
}
