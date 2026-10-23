import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'booking_providers.dart';
import 'location_picker_screen.dart';

/// Step 2 of the booking flow: pick the pickup location. Auto-locates the
/// device on load (the user is picking up from where they already are, most
/// of the time) — unlike [DropoffLocationScreen], which instead prompts the
/// user to search.
class PickupLocationScreen extends ConsumerWidget {
  const PickupLocationScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return LocationPickerScreen(
      stepIndex: 1,
      addressLabel: 'booking.pickup_address_label'.tr(),
      autoLocateOnLoad: true,
      autoFocusSearch: false,
      showLandmarkField: false,
      showScheduleOption: true,
      restrictToDeliveryArea: true,
      onContinue: (address, scheduledAt) {
        final draft = ref.read(bookingDraftProvider);
        ref.read(bookingDraftProvider.notifier).state =
            draft.copyWith(pickup: address, scheduledAt: scheduledAt);
        context.push('/booking/dropoff');
      },
    );
  }
}
