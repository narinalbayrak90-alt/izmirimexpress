import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../providers/app_providers.dart';
import '../../services/api_exception.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../widgets/app_loader.dart';
import '../home/home_category.dart';
import 'booking_draft.dart';
import 'booking_providers.dart';
import 'booking_stepper.dart';
import 'fare_estimate.dart';

/// Step 4 of the booking flow: category, pickup/drop-off, and the
/// server-computed fare (project.txt Module 6) with a coupon picker.
///
/// The fare is never calculated here — this screen only ever displays
/// whatever `POST /fare/estimate` returns, and re-requests it whenever a
/// coupon is applied or removed.
class SummaryScreen extends ConsumerStatefulWidget {
  const SummaryScreen({super.key});

  @override
  ConsumerState<SummaryScreen> createState() => _SummaryScreenState();
}

class _SummaryScreenState extends ConsumerState<SummaryScreen> {
  FareEstimate? _estimate;
  bool _isLoading = true;
  String? _loadError;
  bool _isApplyingCoupon = false;

  @override
  void initState() {
    super.initState();
    _loadEstimate();
  }

  BookingDraft get _draft => ref.read(bookingDraftProvider);

  Future<void> _loadEstimate({String? couponCode}) async {
    final draft = _draft;
    final category = draft.category;
    final pickup = draft.pickup?.latLng;
    final dropoff = draft.dropoff?.latLng;

    if (category == null || pickup == null || dropoff == null) {
      setState(() {
        _isLoading = false;
        _loadError = 'booking.missing_details_error'.tr();
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _loadError = null;
    });
    try {
      final estimate = await ref
          .read(fareServiceProvider)
          .estimate(categoryId: category.id, pickup: pickup, dropoff: dropoff, couponCode: couponCode);
      if (!mounted) return;
      setState(() {
        _estimate = estimate;
        _isLoading = false;
      });
      ref.read(bookingFareEstimateProvider.notifier).state = estimate;
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _loadError = e.message;
      });
    }
  }

  Future<void> _applyCoupon(String code) async {
    setState(() => _isApplyingCoupon = true);
    final draft = _draft;
    try {
      final estimate = await ref
          .read(fareServiceProvider)
          .estimate(
            categoryId: draft.category!.id,
            pickup: draft.pickup!.latLng!,
            dropoff: draft.dropoff!.latLng!,
            couponCode: code,
          );
      if (!mounted) return;
      setState(() {
        _estimate = estimate;
        _isApplyingCoupon = false;
      });
      ref.read(bookingFareEstimateProvider.notifier).state = estimate;
      Navigator.of(context).pop();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _isApplyingCoupon = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _removeCoupon() async {
    Navigator.of(context).pop();
    await _loadEstimate();
  }

  void _openCouponPicker() {
    final estimate = _estimate;
    if (estimate == null) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => _CouponPickerSheet(
        estimate: estimate,
        isApplying: _isApplyingCoupon,
        onSelect: _applyCoupon,
        onRemove: _removeCoupon,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('booking.new_booking'.tr())),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.md, AppSpacing.md, 0),
              child: const BookingStepper(currentStep: 3),
            ),
            Expanded(child: _buildBody(context)),
            _buildBottomBar(context),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_isLoading) {
      return const Center(child: AppLoader());
    }
    if (_loadError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline_rounded, color: AppColors.error, size: 40),
              const SizedBox(height: AppSpacing.sm),
              Text(_loadError!, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textSecondary)),
              const SizedBox(height: AppSpacing.md),
              OutlinedButton(onPressed: () => _loadEstimate(), child: Text('common.retry'.tr())),
            ],
          ),
        ),
      );
    }

    final estimate = _estimate!;
    final draft = _draft;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'booking.review_title'.tr(),
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
          ),
          const SizedBox(height: AppSpacing.md),
          if (draft.category != null) _CategoryRow(category: draft.category!, vehicleType: estimate.vehicleType),
          const SizedBox(height: AppSpacing.sm),
          _ScheduleRow(scheduledAt: draft.scheduledAt),
          const SizedBox(height: AppSpacing.md),
          if (draft.pickup != null)
            _AddressCard(icon: Icons.trip_origin, iconColor: AppColors.primaryDark, label: 'orders.pickup'.tr(), address: draft.pickup!),
          const SizedBox(height: AppSpacing.sm),
          if (draft.dropoff != null)
            _AddressCard(icon: Icons.flag_rounded, iconColor: AppColors.accent, label: 'orders.dropoff'.tr(), address: draft.dropoff!),
          const SizedBox(height: AppSpacing.md),
          InkWell(
            onTap: _openCouponPicker,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: AppColors.heroBackground,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.primary.withValues(alpha: 0.4)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.local_offer_outlined, color: AppColors.primaryDark),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      estimate.appliedCoupon != null
                          ? 'booking.coupon_applied'.tr(namedArgs: {
                              'code': estimate.appliedCoupon!.code,
                              'amount': estimate.format(estimate.appliedCoupon!.discountAmount),
                            })
                          : 'booking.apply_coupon'.tr(),
                      style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded, color: AppColors.textSecondary),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          _FareBreakdown(estimate: estimate),
        ],
      ),
    );
  }

  /// Guest browsing is allowed everywhere up to this point (project.txt
  /// Module 2) — placing an order is the first step that requires auth, so
  /// this is where we check for a token: guests go to log in first (which
  /// hands off to the payment screen itself once they're authenticated —
  /// see [postAuthRoute]), already-logged-in customers go straight there.
  Future<void> _placeOrder(BuildContext context) async {
    final token = await ref.read(secureStorageProvider).readToken();
    if (!context.mounted) return;
    if (token == null || token.isEmpty) {
      context.push('/login');
      return;
    }
    context.push('/booking/payment');
  }

  Widget _buildBottomBar(BuildContext context) {
    final estimate = _estimate;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.background,
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 16, offset: const Offset(0, -4))],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.md, AppSpacing.md, AppSpacing.sm),
        child: SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: estimate == null ? null : () => _placeOrder(context),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(estimate == null ? 'booking.place_order'.tr() : 'booking.place_order_with_total'.tr(namedArgs: {'total': estimate.format(estimate.total)})),
                const SizedBox(width: 8),
                const Icon(Icons.arrow_forward_rounded, size: 18),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ScheduleRow extends StatelessWidget {
  const _ScheduleRow({required this.scheduledAt});

  final DateTime? scheduledAt;

  @override
  Widget build(BuildContext context) {
    final date = scheduledAt;
    final label = date == null
        ? 'booking.sending_now'.tr()
        : 'booking.scheduled_for'.tr(namedArgs: {
            'date': DateFormat.yMMMd(context.locale.toString()).format(date),
            'time': TimeOfDay.fromDateTime(date).format(context),
          });

    return Row(
      children: [
        const Icon(Icons.schedule_rounded, size: 16, color: AppColors.textSecondary),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
      ],
    );
  }
}

class _CategoryRow extends StatelessWidget {
  const _CategoryRow({required this.category, required this.vehicleType});

  final HomeCategory category;
  final String vehicleType;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          height: 40,
          width: 40,
          child: (category.iconUrl != null && category.iconUrl!.isNotEmpty)
              ? Image.network(
                  category.iconUrl!,
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) =>
                      const Icon(Icons.inventory_2_outlined, color: AppColors.primaryDark),
                )
              : const Icon(Icons.inventory_2_outlined, color: AppColors.primaryDark),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(category.name, style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
              Text(
                'booking.delivery_via'.tr(namedArgs: {'vehicle': _vehicleLabel(vehicleType)}),
                style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
      ],
    );
  }

  static const _vehicleLabelKeys = {
    'bike': 'vehicle.bike',
    'car': 'vehicle.car',
    'van': 'vehicle.van',
    'truck': 'vehicle.truck',
  };

  String _vehicleLabel(String value) {
    final key = _vehicleLabelKeys[value];
    return key == null ? value : key.tr();
  }
}

class _AddressCard extends StatelessWidget {
  const _AddressCard({required this.icon, required this.iconColor, required this.label, required this.address});

  final IconData icon;
  final Color iconColor;
  final String label;
  final BookingAddress address;

  @override
  Widget build(BuildContext context) {
    final details = [
      address.houseNumber,
      address.landmark,
      if (address.remark.isNotEmpty) 'booking.note_prefix'.tr(namedArgs: {'note': address.remark}),
    ].where((value) => value.trim().isNotEmpty).join(' · ');

    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: iconColor),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textSecondary),
                ),
                Text(address.formattedAddress, style: const TextStyle(fontSize: 13, color: AppColors.textPrimary)),
                if (details.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(details, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FareBreakdown extends StatelessWidget {
  const _FareBreakdown({required this.estimate});

  final FareEstimate estimate;

  @override
  Widget build(BuildContext context) {
    final coupon = estimate.appliedCoupon;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          _FareLine(label: 'booking.base_fare'.tr(), value: estimate.format(estimate.baseFare)),
          _FareLine(
            label: 'booking.distance_line'.tr(namedArgs: {
              'distance': estimate.distanceKm.toStringAsFixed(1),
              'rate': estimate.format(estimate.perKmRate),
            }),
            value: estimate.format(estimate.distanceKm * estimate.perKmRate),
          ),
          if (coupon != null) ...[
            const Divider(height: AppSpacing.lg, color: AppColors.divider),
            _FareLine(label: 'booking.subtotal'.tr(), value: estimate.format(estimate.subtotal)),
            _FareLine(
              label: 'booking.discount_line'.tr(namedArgs: {'code': coupon.code}),
              value: '-${estimate.format(coupon.discountAmount)}',
              valueColor: AppColors.success,
            ),
          ],
          const Divider(height: AppSpacing.lg, color: AppColors.divider),
          _FareLine(label: 'orders.total'.tr(), value: estimate.format(estimate.total), isTotal: true),
        ],
      ),
    );
  }
}

class _FareLine extends StatelessWidget {
  const _FareLine({required this.label, required this.value, this.isTotal = false, this.valueColor});

  final String label;
  final String value;
  final bool isTotal;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontSize: isTotal ? 16 : 13,
      fontWeight: isTotal ? FontWeight.w700 : FontWeight.w400,
      color: AppColors.textPrimary,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: style.copyWith(color: AppColors.textSecondary, fontWeight: FontWeight.w400)),
          Text(value, style: style.copyWith(color: valueColor ?? style.color)),
        ],
      ),
    );
  }
}

class _CouponPickerSheet extends StatelessWidget {
  const _CouponPickerSheet({
    required this.estimate,
    required this.isApplying,
    required this.onSelect,
    required this.onRemove,
  });

  final FareEstimate estimate;
  final bool isApplying;
  final ValueChanged<String> onSelect;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'booking.apply_coupon'.tr(),
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
            ),
            const SizedBox(height: AppSpacing.md),
            if (estimate.appliedCoupon != null)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.close_rounded, color: AppColors.error),
                title: Text('booking.remove_coupon'.tr()),
                onTap: isApplying ? null : onRemove,
              ),
            if (estimate.availableCoupons.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
                child: Text('booking.no_coupons'.tr(), style: const TextStyle(color: AppColors.textSecondary)),
              )
            else
              ...estimate.availableCoupons.map((coupon) {
                final isApplied = estimate.appliedCoupon?.code == coupon.code;
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  enabled: coupon.isEligible && !isApplying,
                  leading: Icon(
                    Icons.local_offer_rounded,
                    color: coupon.isEligible ? AppColors.primaryDark : AppColors.textSecondary,
                  ),
                  title: Text(coupon.code, style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text(
                    coupon.isEligible
                        ? coupon.discountLabel
                        : 'booking.min_order'.tr(namedArgs: {
                            'amount': coupon.minOrderAmount != null ? estimate.format(coupon.minOrderAmount!) : '',
                            'discount': coupon.discountLabel,
                          }),
                  ),
                  trailing: isApplied ? const Icon(Icons.check_circle_rounded, color: AppColors.success) : null,
                  onTap: coupon.isEligible && !isApplying ? () => onSelect(coupon.code) : null,
                );
              }),
          ],
        ),
      ),
    );
  }
}
