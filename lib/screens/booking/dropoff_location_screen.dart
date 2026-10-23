import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'booking_providers.dart';
import 'location_picker_screen.dart';

/// Step 3 of the booking flow: pick the drop-off location.
///
/// Unlike the pickup step, this does NOT auto-select the device's current
/// location — the user is dropping off somewhere else, so the map starts
/// centered on the pickup point (if set) and the search field auto-focuses
/// to prompt the user to search for where they're sending the parcel.
class DropoffLocationScreen extends ConsumerWidget {
  const DropoffLocationScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pickup = ref.read(bookingDraftProvider).pickup;

    return LocationPickerScreen(
      stepIndex: 2,
      addressLabel: 'booking.dropoff_address_label'.tr(),
      autoLocateOnLoad: false,
      autoFocusSearch: true,
      initialCenter: pickup?.latLng,
      showRecipientFields: true,
      onContinue: (address, _) {
        final draft = ref.read(bookingDraftProvider);
        ref.read(bookingDraftProvider.notifier).state = draft.copyWith(dropoff: address);
        context.push('/booking/summary');
      },
    );
  }
}
