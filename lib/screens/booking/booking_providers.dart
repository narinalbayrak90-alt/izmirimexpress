import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/app_providers.dart';
import 'booking_draft.dart';
import 'fare_estimate.dart';

/// Shared state for the in-progress booking flow. Reset implicitly by
/// leaving the flow (nothing currently reads it outside `/booking/*`).
final bookingDraftProvider = StateProvider<BookingDraft>((ref) => const BookingDraft());

/// The Summary step's server-computed fare (with whatever coupon is
/// currently applied) — kept here rather than as that screen's local state
/// so it survives the Place Order -> login/signup -> Payment detour (a
/// `context.go()` after auth disposes the Summary screen entirely, which
/// would otherwise lose it). [SummaryScreen] writes to this every time it
/// loads or re-loads an estimate; [PaymentMethodScreen] just reads it.
final bookingFareEstimateProvider = StateProvider<FareEstimate?>((ref) => null);

/// Where to land after a successful login/signup/OTP verification: straight
/// to the payment method screen if "Place Order" is what triggered the auth
/// detour (a booking is in progress), otherwise the home screen.
String postAuthRoute(WidgetRef ref) {
  final draft = ref.read(bookingDraftProvider);
  final hasBookingInProgress = draft.category != null && draft.pickup != null && draft.dropoff != null;
  return hasBookingInProgress ? '/booking/payment' : '/home';
}

/// Persists the auth token and tags this device with the customer's id
/// (project.txt Module 14) so the backend can send personalised push
/// notifications — e.g. order status updates. Called right after every
/// successful login/signup/OTP-verification/password-reset, the only
/// places a fresh token is ever saved.
///
/// The permission prompt is fired but not awaited — there's no reason to
/// delay navigation on the customer answering the OS dialog.
Future<void> completeAuthSession(WidgetRef ref, {required String token, required int customerId}) async {
  await ref.read(secureStorageProvider).saveToken(token);
  ref.read(oneSignalServiceProvider).tagUserId(customerId);
  ref.read(oneSignalServiceProvider).requestPermission();
  try {
    final channel = (await ref.read(authServiceProvider).getProfile()).liveChannel;
    if (channel != null) ref.read(liveConnectionProvider).subscribe(channel);
  } catch (_) {
    // Polling still covers this session.
  }
}
