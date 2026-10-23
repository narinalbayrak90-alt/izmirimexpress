import 'package:easy_localization/easy_localization.dart';

/// A coupon currently applied to the fare, returned by `POST /fare/estimate`.
class AppliedCoupon {
  const AppliedCoupon({
    required this.code,
    required this.discountType,
    required this.value,
    required this.discountAmount,
  });

  final String code;
  final String discountType; // 'flat' | 'percent'
  final double value;
  final double discountAmount;

  factory AppliedCoupon.fromJson(Map<String, dynamic> json) {
    return AppliedCoupon(
      code: json['code'] as String,
      discountType: json['discount_type'] as String,
      value: (json['value'] as num).toDouble(),
      discountAmount: (json['discount_amount'] as num).toDouble(),
    );
  }
}

/// A coupon the user could apply, with eligibility already evaluated
/// server-side against the current subtotal.
class AvailableCoupon {
  const AvailableCoupon({
    required this.code,
    required this.discountType,
    required this.value,
    required this.isEligible,
    this.minOrderAmount,
  });

  final String code;
  final String discountType;
  final double value;
  final double? minOrderAmount;
  final bool isEligible;

  factory AvailableCoupon.fromJson(Map<String, dynamic> json) {
    return AvailableCoupon(
      code: json['code'] as String,
      discountType: json['discount_type'] as String,
      value: (json['value'] as num).toDouble(),
      minOrderAmount: (json['min_order_amount'] as num?)?.toDouble(),
      isEligible: json['is_eligible'] as bool,
    );
  }

  String get discountLabel => discountType == 'percent'
      ? 'booking.discount_percent_off'.tr(namedArgs: {'value': value.toStringAsFixed(0)})
      : 'booking.discount_flat_off'.tr(namedArgs: {'value': value.toStringAsFixed(0)});
}

/// Server-computed fare breakdown for a category + pickup/drop-off pair —
/// see `FareController::estimate` on the backend. Every amount here comes
/// from the backend; nothing is calculated client-side (project.txt Module
/// 6 / Security Notes: fare must never be computed in the app).
class FareEstimate {
  const FareEstimate({
    required this.distanceKm,
    required this.vehicleType,
    required this.baseFare,
    required this.perKmRate,
    required this.subtotal,
    required this.total,
    required this.availableCoupons,
    required this.currencySign,
    required this.currencyPosition,
    this.appliedCoupon,
  });

  final double distanceKm;
  final String vehicleType;
  final double baseFare;
  final double perKmRate;
  final double subtotal;
  final AppliedCoupon? appliedCoupon;
  final double total;
  final List<AvailableCoupon> availableCoupons;
  final String currencySign;
  final String currencyPosition; // 'left' | 'right'

  factory FareEstimate.fromJson(Map<String, dynamic> json) {
    return FareEstimate(
      distanceKm: (json['distance_km'] as num).toDouble(),
      vehicleType: json['vehicle_type'] as String,
      baseFare: (json['base_fare'] as num).toDouble(),
      perKmRate: (json['per_km_rate'] as num).toDouble(),
      subtotal: (json['subtotal'] as num).toDouble(),
      total: (json['total'] as num).toDouble(),
      appliedCoupon: json['applied_coupon'] == null
          ? null
          : AppliedCoupon.fromJson(json['applied_coupon'] as Map<String, dynamic>),
      availableCoupons: (json['available_coupons'] as List<dynamic>? ?? [])
          .map((e) => AvailableCoupon.fromJson(e as Map<String, dynamic>))
          .toList(),
      currencySign: json['currency_sign'] as String? ?? '\$',
      currencyPosition: json['currency_position'] as String? ?? 'left',
    );
  }

  String format(double amount) {
    final formatted = amount.toStringAsFixed(2);
    return currencyPosition == 'right' ? '$formatted$currencySign' : '$currencySign$formatted';
  }
}
