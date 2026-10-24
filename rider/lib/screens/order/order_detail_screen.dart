import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../providers/app_providers.dart';
import '../../services/api_exception.dart';
import '../../services/rider_order_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../widgets/app_loader.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/primary_button.dart';
import '../home/home_provider.dart';
import 'order_detail_provider.dart';

/// Full order detail and the rider-driven half of the delivery lifecycle:
/// confirmed -[accept]-> rider_assigned -[pickup]-> picked_up
/// -[in-transit]-> in_transit -[deliver]-> delivered (see
/// RiderOrderController's own class doc comment on the backend — every
/// action below calls exactly the endpoint documented there).
///
/// Shows [RiderOrderDetail.earning], never [RiderOrderDetail.total] — the
/// rider earns their cut, not the customer's full payment (see
/// RiderOrderController::earningFor). The one place `total` still surfaces
/// is [_CodReminder], since a COD rider genuinely needs to know the exact
/// cash amount to collect on delivery.
class OrderDetailScreen extends ConsumerStatefulWidget {
  const OrderDetailScreen({super.key, required this.orderId});

  final int orderId;

  @override
  ConsumerState<OrderDetailScreen> createState() => _OrderDetailScreenState();
}

class _OrderDetailScreenState extends ConsumerState<OrderDetailScreen> {
  final _pickupOtpController = TextEditingController();
  final _deliverOtpController = TextEditingController();
  final _receiverNameController = TextEditingController();
  final _receiverPhoneController = TextEditingController();
  File? _deliveryPhoto;
  bool _isSubmitting = false;

  @override
  void dispose() {
    _pickupOtpController.dispose();
    _deliverOtpController.dispose();
    _receiverNameController.dispose();
    _receiverPhoneController.dispose();
    super.dispose();
  }

  void _refresh() {
    ref.invalidate(orderDetailProvider(widget.orderId));
    ref.invalidate(availableOrdersProvider);
    ref.invalidate(activeOrdersProvider);
  }

  Future<void> _call(String? phone) async {
    if (phone == null || phone.isEmpty) return;
    // Straight to the dialer — canLaunchUrl() can wrongly answer false on
    // newer Android, so it isn't asked first.
    await launchUrl(Uri(scheme: 'tel', path: phone.replaceAll(' ', '')), mode: LaunchMode.externalApplication);
  }

  /// Opens turn-by-turn directions in whatever maps app is installed —
  /// Google's universal `?api=1` link works the same way on Android and
  /// iOS without needing separate `geo:`/`maps:` scheme handling, and
  /// falls back to the browser if nothing's installed.
  Future<void> _navigate(RiderOrderAddress address) async {
    final uri = Uri.parse('https://www.google.com/maps/dir/?api=1&destination=${address.lat},${address.lng}');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _runAction(Future<RiderOrderActionResult> Function() action, {String? successMessage}) async {
    setState(() => _isSubmitting = true);
    try {
      await action();
      if (!mounted) return;
      if (successMessage != null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(successMessage)));
      }
      _refresh();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _accept() async {
    final confirmed = await confirmDialog(
      context,
      title: 'order_detail.accept_confirm_title'.tr(),
      message: 'order_detail.accept_confirm_message'.tr(),
      confirmLabel: 'home.accept'.tr(),
    );
    if (!mounted || !confirmed) return;

    await _runAction(
      () => ref.read(riderOrderServiceProvider).accept(widget.orderId),
      successMessage: 'home.accept_success'.tr(),
    );
  }

  Future<void> _release() async {
    final confirmed = await confirmDialog(
      context,
      title: 'order_detail.release_confirm_title'.tr(),
      message: 'order_detail.release_confirm_message'.tr(),
      confirmLabel: 'order_detail.release'.tr(),
    );
    if (!mounted || !confirmed) return;

    await _runAction(
      () => ref.read(riderOrderServiceProvider).release(widget.orderId),
      successMessage: 'order_detail.release_success'.tr(),
    );
    if (mounted) context.pop();
  }

  Future<void> _pickup(bool otpRequired) async {
    if (otpRequired && _pickupOtpController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('order_detail.otp_required_error'.tr())),
      );
      return;
    }

    await _runAction(
      () => ref.read(riderOrderServiceProvider).pickup(
            widget.orderId,
            otp: otpRequired ? _pickupOtpController.text.trim() : null,
          ),
      successMessage: 'order_detail.picked_up_success'.tr(),
    );
  }

  Future<void> _inTransit() {
    return _runAction(
      () => ref.read(riderOrderServiceProvider).inTransit(widget.orderId),
      successMessage: 'order_detail.in_transit_success'.tr(),
    );
  }

  /// Camera only, never the gallery — unlike the signup screen's document
  /// uploads, this is proof the rider is physically at the drop-off right
  /// now, so it has to be a live shot rather than a photo picked from
  /// storage.
  Future<void> _pickDeliveryPhoto() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.camera, maxWidth: 1600, imageQuality: 85);
    if (picked == null) return;
    setState(() => _deliveryPhoto = File(picked.path));
  }

  Future<void> _deliver(bool otpRequired, bool photoRequired) async {
    if (otpRequired && _deliverOtpController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('order_detail.otp_required_error'.tr())),
      );
      return;
    }
    if (photoRequired && _deliveryPhoto == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('order_detail.photo_required_error'.tr())),
      );
      return;
    }

    await _runAction(
      () => ref.read(riderOrderServiceProvider).deliver(
            widget.orderId,
            otp: otpRequired ? _deliverOtpController.text.trim() : null,
            photoPath: _deliveryPhoto?.path,
            receiverName: _receiverNameController.text.trim(),
            receiverPhone: _receiverPhoneController.text.trim(),
          ),
      successMessage: 'order_detail.delivered_success'.tr(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final detail = ref.watch(orderDetailProvider(widget.orderId));

    return Scaffold(
      appBar: AppBar(title: Text('order_detail.title'.tr(namedArgs: {'id': '${widget.orderId}'}))),
      body: SafeArea(
        top: false,
        child: detail.when(
          data: (order) => RefreshIndicator(
            onRefresh: () async {
              _refresh();
              await ref.read(orderDetailProvider(widget.orderId).future);
            },
            child: ListView(
              padding: const EdgeInsets.all(AppSpacing.lg),
              children: [
                _EarningCard(order: order),
                if (order.codAmountToCollect != null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  _CodReminder(amount: order.codAmountToCollect!),
                ],
                const SizedBox(height: AppSpacing.lg),
                _AddressCard(
                  label: 'order_detail.pickup_label'.tr(),
                  icon: Icons.trip_origin,
                  address: order.pickup,
                  onCall: () => _call(order.pickup.contactPhone),
                  onNavigate: () => _navigate(order.pickup),
                ),
                const SizedBox(height: AppSpacing.sm),
                _AddressCard(
                  label: 'order_detail.dropoff_label'.tr(),
                  icon: Icons.location_on_rounded,
                  address: order.dropoff,
                  onCall: () => _call(order.dropoff.contactPhone),
                  onNavigate: () => _navigate(order.dropoff),
                ),
                if (order.note != null && order.note!.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.sm),
                  _NoteCard(note: order.note!),
                ],
                const SizedBox(height: AppSpacing.xl),
                _buildActionArea(order),
              ],
            ),
          ),
          loading: () => const Center(child: AppLoader()),
          error: (_, _) => Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('common.error'.tr()),
                const SizedBox(height: AppSpacing.md),
                TextButton(onPressed: _refresh, child: Text('common.retry'.tr())),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildActionArea(RiderOrderDetail order) {
    switch (order.status) {
      case 'confirmed':
        return PrimaryButton(label: 'home.accept'.tr(), onPressed: _accept, isLoading: _isSubmitting);

      case 'rider_assigned':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (order.pickupOtpRequired) ...[
              _OtpField(controller: _pickupOtpController, label: 'order_detail.pickup_otp_label'.tr()),
              const SizedBox(height: AppSpacing.md),
            ],
            PrimaryButton(
              label: 'order_detail.mark_picked_up'.tr(),
              onPressed: () => _pickup(order.pickupOtpRequired),
              isLoading: _isSubmitting,
            ),
            const SizedBox(height: AppSpacing.sm),
            OutlinedButton(
              onPressed: _isSubmitting ? null : _release,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.error,
                side: const BorderSide(color: AppColors.error),
                minimumSize: const Size.fromHeight(52),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: Text('order_detail.release'.tr()),
            ),
          ],
        );

      case 'picked_up':
        return PrimaryButton(label: 'order_detail.mark_in_transit'.tr(), onPressed: _inTransit, isLoading: _isSubmitting);

      case 'in_transit':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (order.deliveryOtpRequired) ...[
              _OtpField(controller: _deliverOtpController, label: 'order_detail.delivery_otp_label'.tr()),
              const SizedBox(height: AppSpacing.md),
            ],
            if (order.deliveryImageRequired) ...[
              _DeliveryPhotoPicker(photo: _deliveryPhoto, onPick: _pickDeliveryPhoto),
              const SizedBox(height: AppSpacing.md),
            ],
            _FieldLabel('order_detail.receiver_name_label'.tr()),
            const SizedBox(height: 8),
            TextFormField(
              controller: _receiverNameController,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(prefixIcon: Icon(Icons.person_outline_rounded)),
            ),
            const SizedBox(height: AppSpacing.md),
            _FieldLabel('order_detail.receiver_phone_label'.tr()),
            const SizedBox(height: 8),
            TextFormField(
              controller: _receiverPhoneController,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(prefixIcon: Icon(Icons.phone_outlined)),
            ),
            const SizedBox(height: AppSpacing.lg),
            PrimaryButton(
              label: 'order_detail.mark_delivered'.tr(),
              onPressed: () => _deliver(order.deliveryOtpRequired, order.deliveryImageRequired),
              isLoading: _isSubmitting,
            ),
          ],
        );

      case 'delivered':
        return _CompletedState(order: order, title: 'order_detail.delivered_title'.tr(), icon: Icons.check_circle_rounded, color: AppColors.success);

      case 'cancelled':
        return _CompletedState(order: order, title: 'order_detail.cancelled_title'.tr(), icon: Icons.cancel_rounded, color: AppColors.error);

      default:
        return const SizedBox.shrink();
    }
  }
}

class _EarningCard extends ConsumerWidget {
  const _EarningCard({required this.order});

  final RiderOrderDetail order;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currency = ref.watch(riderSettingsProvider).valueOrNull ?? const RiderSettings();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(color: AppColors.successBackground, borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('order_detail.earning_label'.tr(), style: const TextStyle(color: AppColors.success, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text(
            currency.format(order.earning),
            style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w800, color: AppColors.success),
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Text(order.categoryName, style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(width: AppSpacing.sm),
              Text('•', style: const TextStyle(color: AppColors.textSecondary)),
              const SizedBox(width: AppSpacing.sm),
              Text('${order.distanceKm.toStringAsFixed(1)} km', style: const TextStyle(color: AppColors.textSecondary)),
            ],
          ),
        ],
      ),
    );
  }
}

class _CodReminder extends ConsumerWidget {
  const _CodReminder({required this.amount});

  final double amount;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currency = ref.watch(riderSettingsProvider).valueOrNull ?? const RiderSettings();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.heroBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.payments_outlined, color: AppColors.primaryDark, size: 20),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              'order_detail.cod_reminder'.tr(namedArgs: {'amount': currency.format(amount)}),
              style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}

class _AddressCard extends StatelessWidget {
  const _AddressCard({
    required this.label,
    required this.icon,
    required this.address,
    required this.onCall,
    required this.onNavigate,
  });

  final String label;
  final IconData icon;
  final RiderOrderAddress address;
  final VoidCallback onCall;
  final VoidCallback onNavigate;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: AppColors.primaryDark),
              const SizedBox(width: 6),
              Expanded(child: Text(label, style: const TextStyle(fontWeight: FontWeight.w700))),
              TextButton.icon(
                onPressed: onNavigate,
                icon: const Icon(Icons.directions_rounded, size: 18),
                label: Text('order_detail.navigate'.tr()),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(address.formattedAddress, style: const TextStyle(fontSize: 14)),
          if (address.landmark != null && address.landmark!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(address.landmark!, style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
            ),
          if (address.contactName != null && address.contactName!.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${address.contactName}${address.contactPhone != null ? ' • ${address.contactPhone}' : ''}',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                ),
                if (address.contactPhone != null && address.contactPhone!.isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.call_rounded, color: AppColors.success),
                    onPressed: onCall,
                    tooltip: 'order_detail.call'.tr(),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _NoteCard extends StatelessWidget {
  const _NoteCard({required this.note});

  final String note;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(color: AppColors.infoBackground, borderRadius: BorderRadius.circular(12)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline_rounded, size: 18, color: AppColors.accent),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: Text(note, style: const TextStyle(fontSize: 13))),
        ],
      ),
    );
  }
}

class _OtpField extends StatelessWidget {
  const _OtpField({required this.controller, required this.label});

  final TextEditingController controller;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _FieldLabel(label),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(prefixIcon: Icon(Icons.password_rounded)),
        ),
      ],
    );
  }
}

class _DeliveryPhotoPicker extends StatelessWidget {
  const _DeliveryPhotoPicker({required this.photo, required this.onPick});

  final File? photo;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _FieldLabel('order_detail.delivery_photo_label'.tr()),
        const SizedBox(height: 8),
        InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onPick,
          child: Container(
            height: 140,
            width: double.infinity,
            decoration: BoxDecoration(
              color: AppColors.surfaceMuted,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: photo == null
                ? const Center(child: Icon(Icons.add_a_photo_outlined, color: AppColors.textSecondary, size: 32))
                : ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.file(photo!, fit: BoxFit.cover, width: double.infinity),
                  ),
          ),
        ),
      ],
    );
  }
}

class _CompletedState extends StatelessWidget {
  const _CompletedState({required this.order, required this.title, required this.icon, required this.color});

  final RiderOrderDetail order;
  final String title;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, color: color, size: 48),
        const SizedBox(height: AppSpacing.sm),
        Text(title, style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontSize: 20)),
        if (order.parcelPhotoUrl != null) ...[
          const SizedBox(height: AppSpacing.md),
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.network(order.parcelPhotoUrl!, height: 160, fit: BoxFit.cover),
          ),
        ],
        if (order.receiverName != null && order.receiverName!.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            'order_detail.received_by'.tr(namedArgs: {'name': order.receiverName!}),
            style: const TextStyle(color: AppColors.textSecondary),
          ),
        ],
      ],
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary));
  }
}
