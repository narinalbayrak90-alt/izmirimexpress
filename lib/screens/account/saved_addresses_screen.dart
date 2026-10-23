import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/app_providers.dart';
import '../../services/address_service.dart';
import '../../services/api_exception.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../widgets/app_loader.dart';

const _labelIcons = {
  'Home': Icons.home_rounded,
  'Office': Icons.business_rounded,
  'Other': Icons.place_rounded,
};

const _labelKeys = {
  'Home': 'booking.address_label_home',
  'Office': 'booking.address_label_office',
  'Other': 'booking.address_label_other',
};

String _displayLabel(String value) {
  final key = _labelKeys[value];
  return key == null ? value : key.tr();
}

/// Saved Addresses screen (project.txt Module 4) — every distinct address
/// the customer has used for a pickup or drop-off, with how many orders
/// each one has been used on. Reached from the Account screen's Saved
/// Addresses quick action; reuses the same `GET /addresses` the booking
/// screens' "Choose from saved address" picker calls.
class SavedAddressesScreen extends ConsumerStatefulWidget {
  const SavedAddressesScreen({super.key});

  @override
  ConsumerState<SavedAddressesScreen> createState() => _SavedAddressesScreenState();
}

class _SavedAddressesScreenState extends ConsumerState<SavedAddressesScreen> {
  List<SavedAddress>? _addresses;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loadError = null);
    try {
      final addresses = await ref.read(addressServiceProvider).getSavedAddresses();
      if (!mounted) return;
      setState(() => _addresses = addresses);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _loadError = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('account.saved_addresses'.tr())),
      body: SafeArea(top: false, child: _buildBody()),
    );
  }

  Widget _buildBody() {
    final addresses = _addresses;

    if (addresses == null && _loadError == null) {
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
              OutlinedButton(onPressed: _load, child: Text('common.retry'.tr())),
            ],
          ),
        ),
      );
    }
    if (addresses!.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.location_off_outlined, color: AppColors.textSecondary, size: 40),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'account.no_saved_addresses'.tr(),
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.all(AppSpacing.md),
        itemCount: addresses.length,
        separatorBuilder: (context, index) => const SizedBox(height: AppSpacing.sm),
        itemBuilder: (context, index) => _AddressCard(address: addresses[index]),
      ),
    );
  }
}

class _AddressCard extends StatelessWidget {
  const _AddressCard({required this.address});

  final SavedAddress address;

  @override
  Widget build(BuildContext context) {
    final rawLabel = (address.label != null && address.label!.isNotEmpty) ? address.label! : 'Other';
    final icon = _labelIcons[rawLabel] ?? Icons.place_rounded;
    final label = _displayLabel(rawLabel);

    final subParts = [
      if (address.houseNumber != null && address.houseNumber!.isNotEmpty) address.houseNumber!,
      if (address.landmark != null && address.landmark!.isNotEmpty) address.landmark!,
    ].join(' · ');

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 40,
            width: 40,
            decoration: const BoxDecoration(color: AppColors.heroBackground, shape: BoxShape.circle),
            child: Icon(icon, size: 20, color: AppColors.primaryDark),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                const SizedBox(height: 2),
                Text(
                  address.formattedAddress,
                  style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
                ),
                if (subParts.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(subParts, style: const TextStyle(fontSize: 11.5, color: AppColors.textSecondary)),
                ],
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(color: AppColors.infoBackground, borderRadius: BorderRadius.circular(20)),
            child: Text(
              address.orderCount == 1
                  ? 'account.order_count_one'.tr(namedArgs: {'count': '${address.orderCount}'})
                  : 'account.order_count_other'.tr(namedArgs: {'count': '${address.orderCount}'}),
              style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: AppColors.accent),
            ),
          ),
        ],
      ),
    );
  }
}
