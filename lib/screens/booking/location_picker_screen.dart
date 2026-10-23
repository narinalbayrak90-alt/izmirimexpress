import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../providers/app_providers.dart';
import '../../services/address_service.dart';
import '../../services/api_exception.dart';
import '../../services/app_settings.dart';
import '../../services/google_places_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../widgets/app_loader.dart';
import '../home/home_provider.dart';
import 'booking_draft.dart';
import 'booking_stepper.dart';
import 'working_hours.dart';
import 'working_hours_provider.dart';

/// Address labels the customer can tag a pickup/drop-off with (project.txt
/// Module 4) — shown as chips before the House/Flat No. field. [value] is
/// the canonical identifier stored/matched against on the backend and
/// never translated; [labelKey] is what's actually displayed.
const _addressLabels = [
  (value: 'Home', labelKey: 'booking.address_label_home', icon: Icons.home_rounded),
  (value: 'Office', labelKey: 'booking.address_label_office', icon: Icons.business_rounded),
  (value: 'Other', labelKey: 'booking.address_label_other', icon: Icons.place_rounded),
];

/// Shared map/search/address UI for both the Pickup and Drop-off steps of
/// the booking flow (project.txt Module 4) — the two screens differ only in
/// step index, address label, whether to auto-locate the device on load,
/// whether the search field auto-focuses, whether the Landmark field and
/// "Schedule for Later" option show, and what happens on "Continue".
///
/// The pin is fixed at the screen center — the map moves underneath it as
/// the user drags, rather than the pin itself being draggable. The address
/// field is reverse-geocoded from whatever point sits under the pin once
/// the camera settles.
class LocationPickerScreen extends ConsumerStatefulWidget {
  const LocationPickerScreen({
    super.key,
    required this.stepIndex,
    required this.addressLabel,
    required this.autoLocateOnLoad,
    required this.autoFocusSearch,
    required this.onContinue,
    this.initialCenter,
    this.showLandmarkField = true,
    this.showScheduleOption = false,
    this.restrictToDeliveryArea = false,
  });

  final int stepIndex;
  final String addressLabel;
  final bool autoLocateOnLoad;
  final bool autoFocusSearch;
  final LatLng? initialCenter;
  final bool showLandmarkField;
  final bool showScheduleOption;

  /// When true, a pin outside the admin-configured delivery area (App
  /// Setting > Delivery Area) blocks "Continue" with an inline error —
  /// used by the Pickup step so an out-of-area order is caught immediately
  /// instead of only at final checkout (`OrderController` enforces the
  /// same check server-side regardless).
  final bool restrictToDeliveryArea;

  /// [scheduledAt] is always null unless [showScheduleOption] is true and
  /// the user picked "Schedule for Later" with a valid date/time.
  final void Function(BookingAddress address, DateTime? scheduledAt) onContinue;

  @override
  ConsumerState<LocationPickerScreen> createState() => _LocationPickerScreenState();
}

class _LocationPickerScreenState extends ConsumerState<LocationPickerScreen> {
  // Neutral world-view default (no country bias) used only when there's no
  // current-location lookup or caller-provided starting point.
  static const _worldCenter = LatLng(20.0, 0.0);
  static const _worldZoom = 2.0;

  final _searchController = TextEditingController();
  final _houseNumberController = TextEditingController();
  final _landmarkController = TextEditingController();
  final _remarkController = TextEditingController();

  GoogleMapController? _mapController;
  late LatLng _center = widget.initialCenter ?? _worldCenter;
  String _address = '';
  bool _isResolvingAddress = false;
  bool _isLocatingDevice = false;
  List<PlaceSuggestion> _suggestions = [];
  Timer? _searchDebounce;

  // "Home" is the default (project.txt Module 4) — a saved address with its
  // own label overrides it once picked, see [_applySavedAddress].
  String? _selectedLabel = _addressLabels.first.value;

  // "Send Now" is the default, per project.txt Module 5.
  bool _isScheduled = false;
  DateTime? _scheduledDate;
  TimeOfDay? _scheduledTime;
  WorkingHours? _workingHours;

  @override
  void initState() {
    super.initState();
    if (widget.autoLocateOnLoad) {
      _isLocatingDevice = true;
      _useCurrentLocation();
    }
    if (widget.showScheduleOption) {
      _loadWorkingHours();
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _houseNumberController.dispose();
    _landmarkController.dispose();
    _remarkController.dispose();
    _searchDebounce?.cancel();
    _mapController?.dispose();
    super.dispose();
  }

  Future<void> _loadWorkingHours() async {
    try {
      final hours = await ref.read(workingHoursProvider.future);
      if (mounted) setState(() => _workingHours = hours);
    } catch (_) {
      // Leave null — the date/time pickers treat that as unrestricted
      // rather than blocking scheduling entirely.
    }
  }

  Future<void> _useCurrentLocation() async {
    setState(() => _isLocatingDevice = true);
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return;
      }
      if (!await Geolocator.isLocationServiceEnabled()) return;

      final position = await Geolocator.getCurrentPosition();
      final target = LatLng(position.latitude, position.longitude);
      await _moveCamera(target, zoom: 16);
      await _resolveAddress(target);
    } catch (_) {
      // Location unavailable (permission permanently denied, no GPS, emulator
      // without a fix, etc.) — leave the map at its default/last position
      // rather than blocking the flow.
    } finally {
      if (mounted) setState(() => _isLocatingDevice = false);
    }
  }

  Future<void> _moveCamera(LatLng target, {double? zoom}) async {
    final controller = _mapController;
    if (controller == null) return;
    await controller.animateCamera(
      zoom == null ? CameraUpdate.newLatLng(target) : CameraUpdate.newLatLngZoom(target, zoom),
    );
  }

  Future<void> _resolveAddress(LatLng position) async {
    setState(() => _isResolvingAddress = true);
    try {
      final address = await ref.read(googlePlacesServiceProvider).reverseGeocode(position);
      if (!mounted) return;
      setState(() {
        _center = position;
        _address = address ?? '';
      });
    } catch (_) {
      // Backend/network issue — leave whatever address was previously
      // resolved rather than clearing it.
    } finally {
      if (mounted) setState(() => _isResolvingAddress = false);
    }
  }

  void _onSearchChanged(String query) {
    _searchDebounce?.cancel();
    if (query.trim().isEmpty) {
      setState(() => _suggestions = []);
      return;
    }
    _searchDebounce = Timer(const Duration(milliseconds: 400), () async {
      try {
        final results = await ref.read(googlePlacesServiceProvider).autocomplete(query);
        if (mounted) setState(() => _suggestions = results);
      } catch (_) {
        // Leave suggestions as-is on failure — not worth surfacing an error
        // for what's a best-effort autocomplete list.
      }
    });
  }

  Future<void> _onSuggestionSelected(PlaceSuggestion suggestion) async {
    setState(() {
      _suggestions = [];
      _searchController.text = suggestion.description;
    });
    FocusScope.of(context).unfocus();

    final target = await ref.read(googlePlacesServiceProvider).placeDetails(suggestion.placeId);
    if (target == null) return;
    await _moveCamera(target, zoom: 16);
    setState(() {
      _center = target;
      _address = suggestion.description;
    });
  }

  Future<void> _pickScheduleDate() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: _scheduledDate ?? today,
      firstDate: today,
      lastDate: today.add(const Duration(days: 30)),
      selectableDayPredicate: (date) {
        final hours = _workingHours?.forDate(date);
        return hours == null || !hours.closed;
      },
    );
    if (picked == null) return;
    setState(() {
      _scheduledDate = picked;
      // A time chosen for the previous date may not be valid for this one
      // (different day's working hours, or no longer in the future).
      _scheduledTime = null;
    });
  }

  Future<void> _pickScheduleTime() async {
    final date = _scheduledDate;
    if (date == null) return;

    final picked = await showTimePicker(context: context, initialTime: _scheduledTime ?? TimeOfDay.now());
    if (picked == null) return;

    final candidate = DateTime(date.year, date.month, date.day, picked.hour, picked.minute);
    if (candidate.isBefore(DateTime.now())) {
      _showScheduleError('booking.future_time_error'.tr());
      return;
    }

    final dayHours = _workingHours?.forDate(date);
    if (dayHours != null && !dayHours.closed) {
      final pickedMinutes = picked.hour * 60 + picked.minute;
      if (pickedMinutes < dayHours.openMinutes || pickedMinutes > dayHours.closeMinutes) {
        _showScheduleError('booking.time_range_error'.tr(namedArgs: {'open': dayHours.open, 'close': dayHours.close}));
        return;
      }
    }

    setState(() => _scheduledTime = picked);
  }

  Future<void> _showSavedAddresses() async {
    final selected = await showModalBottomSheet<SavedAddress>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => const _SavedAddressSheet(),
    );
    if (selected == null) return;
    await _applySavedAddress(selected);
  }

  Future<void> _applySavedAddress(SavedAddress address) async {
    setState(() {
      _center = address.latLng;
      _address = address.formattedAddress;
      _searchController.text = address.formattedAddress;
      _houseNumberController.text = address.houseNumber ?? '';
      _landmarkController.text = address.landmark ?? '';
      _remarkController.text = address.remark ?? '';
      _selectedLabel = (address.label != null && address.label!.isNotEmpty) ? address.label : _addressLabels.first.value;
    });
    await _moveCamera(address.latLng, zoom: 16);
  }

  void _showScheduleError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  double _distanceKm(LatLng point, DeliveryArea area) {
    return Geolocator.distanceBetween(point.latitude, point.longitude, area.lat, area.lng) / 1000;
  }

  @override
  Widget build(BuildContext context) {
    final scheduleReady = !widget.showScheduleOption ||
        !_isScheduled ||
        (_scheduledDate != null && _scheduledTime != null);
    final hasResolvedLocation = _address.trim().isNotEmpty && !_isResolvingAddress;

    final deliveryArea = ref.watch(appSettingsProvider).valueOrNull?.deliveryArea;
    final isOutsideDeliveryArea = widget.restrictToDeliveryArea &&
        deliveryArea != null &&
        hasResolvedLocation &&
        _distanceKm(_center, deliveryArea) > deliveryArea.radiusKm;

    final canContinue = hasResolvedLocation && scheduleReady && !isOutsideDeliveryArea;

    return Scaffold(
      appBar: AppBar(title: Text('booking.new_booking'.tr())),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.md, AppSpacing.md, 0),
              child: BookingStepper(currentStep: widget.stepIndex),
            ),
            const SizedBox(height: AppSpacing.md),
            // Deliberately NOT inside the scrollable below — a GoogleMap
            // nested in a ListView loses vertical drag gestures to the
            // ListView's own scroll recognizer, making the map undraggable.
            // Giving it a fixed area outside any scrollable avoids that
            // gesture-arena conflict entirely.
            SizedBox(
              height: 320,
              child: Stack(
                children: [
                  GoogleMap(
                    initialCameraPosition: CameraPosition(
                      target: _center,
                      zoom: widget.initialCenter != null ? 16 : _worldZoom,
                    ),
                    onMapCreated: (controller) => _mapController = controller,
                    onCameraMove: (position) => _center = position.target,
                    onCameraIdle: () => _resolveAddress(_center),
                    myLocationEnabled: true,
                    myLocationButtonEnabled: false,
                    zoomControlsEnabled: false,
                  ),
                  // Fixed center pin — the map moves underneath it.
                  IgnorePointer(
                    child: Center(
                      child: Transform.translate(
                        offset: const Offset(0, -20),
                        child: const Icon(
                          Icons.location_on_rounded,
                          size: 44,
                          color: AppColors.primaryDark,
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: AppSpacing.md,
                    right: AppSpacing.md,
                    top: AppSpacing.md,
                    child: _SearchBar(
                      controller: _searchController,
                      suggestions: _suggestions,
                      autofocus: widget.autoFocusSearch,
                      onChanged: _onSearchChanged,
                      onSuggestionSelected: _onSuggestionSelected,
                    ),
                  ),
                  Positioned(
                    right: AppSpacing.md,
                    bottom: AppSpacing.md,
                    child: FloatingActionButton.small(
                      heroTag: 'use-current-location-${widget.stepIndex}',
                      backgroundColor: AppColors.background,
                      foregroundColor: AppColors.textPrimary,
                      onPressed: _isLocatingDevice ? null : _useCurrentLocation,
                      child: _isLocatingDevice
                          ? const AppLoader(size: 18, color: AppColors.textPrimary)
                          : const Icon(Icons.my_location_rounded),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            widget.addressLabel,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          InkWell(
                            onTap: _showSavedAddresses,
                            borderRadius: BorderRadius.circular(8),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.bookmark_outline_rounded, size: 15, color: AppColors.accent),
                                  const SizedBox(width: 4),
                                  Text(
                                    'booking.choose_saved_address'.tr(),
                                    style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.accent),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      _AddressPreview(address: _address, isResolving: _isResolvingAddress),
                      if (isOutsideDeliveryArea) ...[
                        const SizedBox(height: AppSpacing.sm),
                        const _OutsideDeliveryAreaBanner(),
                      ],
                      const SizedBox(height: AppSpacing.md),
                      Row(
                        children: [
                          for (final option in _addressLabels) ...[
                            Expanded(
                              child: _AddressLabelChip(
                                label: option.labelKey.tr(),
                                icon: option.icon,
                                selected: _selectedLabel == option.value,
                                onTap: () => setState(() => _selectedLabel = option.value),
                              ),
                            ),
                            if (option != _addressLabels.last) const SizedBox(width: AppSpacing.sm),
                          ],
                        ],
                      ),
                      const SizedBox(height: AppSpacing.md),
                      TextField(
                        controller: _houseNumberController,
                        decoration: InputDecoration(
                          labelText: 'booking.house_number_label'.tr(),
                        ),
                      ),
                      if (widget.showLandmarkField) ...[
                        const SizedBox(height: AppSpacing.sm),
                        TextField(
                          controller: _landmarkController,
                          decoration: InputDecoration(labelText: 'booking.landmark_label'.tr()),
                        ),
                      ],
                      const SizedBox(height: AppSpacing.sm),
                      TextField(
                        controller: _remarkController,
                        decoration: InputDecoration(labelText: 'booking.remark_label'.tr()),
                      ),
                      if (widget.showScheduleOption) ...[
                        const SizedBox(height: AppSpacing.md),
                        _ScheduleSection(
                          isScheduled: _isScheduled,
                          scheduledDate: _scheduledDate,
                          scheduledTime: _scheduledTime,
                          onModeChanged: (scheduled) => setState(() => _isScheduled = scheduled),
                          onPickDate: _pickScheduleDate,
                          onPickTime: _pickScheduleTime,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            DecoratedBox(
              decoration: BoxDecoration(
                color: AppColors.background,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 16,
                    offset: const Offset(0, -4),
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md,
                  AppSpacing.md,
                  AppSpacing.md,
                  AppSpacing.sm,
                ),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: canContinue
                        ? () {
                            DateTime? scheduledAt;
                            if (widget.showScheduleOption && _isScheduled) {
                              final date = _scheduledDate!;
                              final time = _scheduledTime!;
                              scheduledAt = DateTime(date.year, date.month, date.day, time.hour, time.minute);
                            }
                            widget.onContinue(
                              BookingAddress(
                                latLng: _center,
                                formattedAddress: _address,
                                houseNumber: _houseNumberController.text,
                                landmark: _landmarkController.text,
                                remark: _remarkController.text,
                                label: _selectedLabel,
                              ),
                              scheduledAt,
                            );
                          }
                        : null,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text('common.continue'.tr()),
                        const SizedBox(width: 8),
                        const Icon(Icons.arrow_forward_rounded, size: 18),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AddressPreview extends StatelessWidget {
  const _AddressPreview({required this.address, required this.isResolving});

  final String address;
  final bool isResolving;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          const Icon(Icons.place_outlined, size: 18, color: AppColors.textSecondary),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              isResolving
                  ? 'booking.locating_address'.tr()
                  : (address.isEmpty ? 'booking.drag_map_hint'.tr() : address),
              style: const TextStyle(fontSize: 13, color: AppColors.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}

class _OutsideDeliveryAreaBanner extends StatelessWidget {
  const _OutsideDeliveryAreaBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded, size: 18, color: AppColors.error),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              'booking.outside_delivery_area'.tr(),
              style: const TextStyle(fontSize: 12, color: AppColors.error),
            ),
          ),
        ],
      ),
    );
  }
}

class _ScheduleSection extends StatelessWidget {
  const _ScheduleSection({
    required this.isScheduled,
    required this.scheduledDate,
    required this.scheduledTime,
    required this.onModeChanged,
    required this.onPickDate,
    required this.onPickTime,
  });

  final bool isScheduled;
  final DateTime? scheduledDate;
  final TimeOfDay? scheduledTime;
  final ValueChanged<bool> onModeChanged;
  final VoidCallback onPickDate;
  final VoidCallback onPickTime;

  String _formatDate(BuildContext context, DateTime date) => DateFormat.yMMMd(context.locale.toString()).format(date);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'booking.pickup_time'.tr(),
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            Expanded(
              child: _ScheduleModeButton(
                label: 'booking.send_now'.tr(),
                icon: Icons.bolt_rounded,
                selected: !isScheduled,
                onTap: () => onModeChanged(false),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: _ScheduleModeButton(
                label: 'booking.schedule_for_later'.tr(),
                icon: Icons.event_rounded,
                selected: isScheduled,
                onTap: () => onModeChanged(true),
              ),
            ),
          ],
        ),
        if (isScheduled) ...[
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Expanded(
                child: _PickerField(
                  label: 'booking.date_label'.tr(),
                  value: scheduledDate == null ? 'booking.select_date'.tr() : _formatDate(context, scheduledDate!),
                  icon: Icons.calendar_today_rounded,
                  onTap: onPickDate,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: _PickerField(
                  label: 'booking.time_label'.tr(),
                  value: scheduledTime == null ? 'booking.select_time'.tr() : scheduledTime!.format(context),
                  icon: Icons.access_time_rounded,
                  onTap: scheduledDate == null ? null : onPickTime,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _ScheduleModeButton extends StatelessWidget {
  const _ScheduleModeButton({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        decoration: BoxDecoration(
          color: selected ? AppColors.heroBackground : AppColors.background,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: selected ? AppColors.primary : AppColors.border, width: selected ? 1.5 : 1),
        ),
        child: Column(
          children: [
            Icon(icon, size: 20, color: selected ? AppColors.primaryDark : AppColors.textSecondary),
            const SizedBox(height: 4),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                color: selected ? AppColors.textPrimary : AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AddressLabelChip extends StatelessWidget {
  const _AddressLabelChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        decoration: BoxDecoration(
          color: selected ? AppColors.heroBackground : AppColors.background,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: selected ? AppColors.primary : AppColors.border, width: selected ? 1.5 : 1),
        ),
        child: Column(
          children: [
            Icon(icon, size: 18, color: selected ? AppColors.primaryDark : AppColors.textSecondary),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                color: selected ? AppColors.textPrimary : AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Bottom sheet listing the customer's previously used addresses (`GET
/// /addresses`) so a repeat pickup/drop-off can be picked in one tap
/// instead of re-searching or re-dragging the map.
class _SavedAddressSheet extends ConsumerStatefulWidget {
  const _SavedAddressSheet();

  @override
  ConsumerState<_SavedAddressSheet> createState() => _SavedAddressSheetState();
}

class _SavedAddressSheetState extends ConsumerState<_SavedAddressSheet> {
  List<SavedAddress>? _addresses;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final addresses = await ref.read(addressServiceProvider).getSavedAddresses();
      if (!mounted) return;
      setState(() => _addresses = addresses);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    }
  }

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
              'booking.saved_addresses'.tr(),
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
            ),
            const SizedBox(height: AppSpacing.sm),
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.5),
              child: _buildBody(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    final addresses = _addresses;

    if (addresses == null && _error == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
        child: Center(child: AppLoader()),
      );
    }
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textSecondary)),
            const SizedBox(height: AppSpacing.sm),
            OutlinedButton(onPressed: _load, child: Text('common.retry'.tr())),
          ],
        ),
      );
    }
    if (addresses!.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
        child: Center(
          child: Text('booking.no_saved_addresses'.tr(), style: const TextStyle(color: AppColors.textSecondary)),
        ),
      );
    }

    return ListView.separated(
      shrinkWrap: true,
      itemCount: addresses.length,
      separatorBuilder: (context, index) => const Divider(height: 1, color: AppColors.divider),
      itemBuilder: (context, index) {
        final address = addresses[index];
        return ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.place_outlined, color: AppColors.textSecondary),
          title: Text(
            (address.label != null && address.label!.isNotEmpty) ? address.label! : 'booking.saved_address_fallback'.tr(),
            style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.textPrimary),
          ),
          subtitle: Text(
            address.formattedAddress,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
          ),
          onTap: () => Navigator.of(context).pop(address),
        );
      },
    );
  }
}

class _PickerField extends StatelessWidget {
  const _PickerField({required this.label, required this.value, required this.icon, required this.onTap});

  final String label;
  final String value;
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.sm),
        decoration: BoxDecoration(
          color: onTap == null ? AppColors.divider : AppColors.surfaceMuted,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: AppColors.textSecondary),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                value,
                style: const TextStyle(fontSize: 12, color: AppColors.textPrimary),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SearchBar extends StatelessWidget {
  const _SearchBar({
    required this.controller,
    required this.suggestions,
    required this.autofocus,
    required this.onChanged,
    required this.onSuggestionSelected,
  });

  final TextEditingController controller;
  final List<PlaceSuggestion> suggestions;
  final bool autofocus;
  final ValueChanged<String> onChanged;
  final ValueChanged<PlaceSuggestion> onSuggestionSelected;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Material(
          elevation: 3,
          borderRadius: BorderRadius.circular(12),
          child: TextField(
            controller: controller,
            autofocus: autofocus,
            onChanged: onChanged,
            decoration: InputDecoration(
              hintText: 'booking.search_hint'.tr(),
              prefixIcon: Icon(Icons.search_rounded),
              filled: true,
              fillColor: AppColors.background,
              border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.all(Radius.circular(12)),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.all(Radius.circular(12)),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),
        if (suggestions.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(top: AppSpacing.xs),
            constraints: const BoxConstraints(maxHeight: 220),
            child: Material(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(12),
              elevation: 4,
              child: ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                itemCount: suggestions.length,
                separatorBuilder: (context, index) =>
                    const Divider(height: 1, color: AppColors.divider),
                itemBuilder: (context, index) {
                  final suggestion = suggestions[index];
                  return ListTile(
                    dense: true,
                    leading: const Icon(Icons.place_outlined, size: 20),
                    title: Text(suggestion.description, style: const TextStyle(fontSize: 13)),
                    onTap: () => onSuggestionSelected(suggestion),
                  );
                },
              ),
            ),
          ),
      ],
    );
  }
}
