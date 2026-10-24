import 'package:onesignal_flutter/onesignal_flutter.dart';

import '../config/env.dart';

/// Thin wrapper around the OneSignal SDK — the single place in the app
/// that touches `OneSignal.*` directly, so nothing else needs to know the
/// SDK's API surface. Same shape as the User App's own OneSignalService,
/// tagging `rider_id` instead of `user_id`.
class OneSignalService {
  bool _isInitialized = false;

  /// Rider id tagged before the SDK was initialized (the App ID arrives
  /// with `/rider/settings`), applied as soon as [initialize] runs.
  int? _pendingRiderId;

  void initialize(String appId) {
    if (_isInitialized || appId.isEmpty) return;

    OneSignal.Debug.setLogLevel(Env.isProduction ? OSLogLevel.none : OSLogLevel.verbose);
    OneSignal.initialize(appId);
    _isInitialized = true;

    final riderId = _pendingRiderId;
    if (riderId != null) {
      OneSignal.User.addTagWithKey('rider_id', riderId.toString());
      OneSignal.Notifications.requestPermission(true);
    }
  }

  /// Requests OS-level notification permission — a no-op if already
  /// granted/denied. Needed for push to actually arrive on iOS and on
  /// Android 13+ (POST_NOTIFICATIONS is a runtime permission there).
  Future<bool> requestPermission() async {
    if (!_isInitialized) return false;
    return OneSignal.Notifications.requestPermission(true);
  }

  /// Tags this device with the logged-in rider's id so the backend can
  /// target it — both personally (order status pushes, once built) and as
  /// part of the "every online rider whose vehicle type matches" broadcast
  /// `OneSignalService::notifyOrderAvailable` (backend) sends when a new
  /// order needs a rider. See RiderAuthController::login/register and
  /// this app's own login/reset-password screens for where this is called.
  ///
  /// Also called on every Home load, so a rider who was already signed in
  /// (or signed in before the SDK was ready) still gets tagged.
  void tagRiderId(int riderId) {
    _pendingRiderId = riderId;
    if (!_isInitialized) return;
    OneSignal.User.addTagWithKey('rider_id', riderId.toString());
  }

  /// Removes the `rider_id` tag on logout so a shared/reused device
  /// doesn't keep receiving the previous rider's order offers after
  /// they've signed out.
  void clearRiderTag() {
    _pendingRiderId = null;
    if (!_isInitialized) return;
    OneSignal.User.removeTag('rider_id');
  }

  /// Fires when the rider taps a push notification (foreground or
  /// background). Registered once from [PickupRiderApp] — [onOrderAvailable]
  /// is called with the `order_id` whenever the notification's `data.type`
  /// is `order_available` (see `notifyOrderAvailable` on the backend).
  void listenForOrderAvailableClicks(void Function(int orderId) onOrderAvailable) {
    OneSignal.Notifications.addClickListener((event) {
      final data = event.notification.additionalData;
      if (data == null || data['type'] != 'order_available') return;

      final orderId = _orderIdFrom(data);
      if (orderId != null) onOrderAvailable(orderId);
    });
  }

  /// Fires when the rider taps a push telling them an order they had was
  /// cancelled (see OneSignalService::notifyRiderOrderCancelled on the
  /// backend) — `data.type == 'order_cancelled'`.
  void listenForOrderCancelledClicks(void Function(int orderId) onOrderCancelled) {
    OneSignal.Notifications.addClickListener((event) {
      final data = event.notification.additionalData;
      if (data == null || data['type'] != 'order_cancelled') return;

      final orderId = _orderIdFrom(data);
      if (orderId != null) onOrderCancelled(orderId);
    });
  }

  int? _orderIdFrom(Map<String, dynamic> data) {
    final orderId = data['order_id'];
    if (orderId is int) return orderId;
    if (orderId is String) return int.tryParse(orderId);
    return null;
  }
}
