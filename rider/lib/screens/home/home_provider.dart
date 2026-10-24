import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/app_providers.dart';
import '../../services/rider_auth_service.dart';
import '../../services/rider_order_service.dart';

/// Tab indices within [HomeScreen]'s [IndexedStack]/bottom nav — a single
/// source of truth so anything that needs to jump to a specific tab (the
/// Account tab's "My Earning"/"Order History" menu items, the Earning
/// tab's own app-bar Withdraw button) doesn't hardcode a magic number.
const homeTabIndex = 0;
const historyTabIndex = 1;
const earningTabIndex = 2;
const accountTabIndex = 3;

/// Which bottom-nav tab is currently showing. A plain [StateProvider]
/// (not local [State]) so any descendant — not just [HomeScreen] itself —
/// can switch tabs, e.g. the Account tab's menu items jumping to Earning
/// or History.
final homeTabIndexProvider = StateProvider<int>((ref) => homeTabIndex);

/// The logged-in rider's own profile, from `GET /rider/me` — drives the
/// Home screen's availability switch and greeting.
final riderProfileProvider = FutureProvider<RiderProfile>((ref) {
  return ref.watch(riderAuthServiceProvider).me();
});

/// Admin-configured values the Rider App needs everywhere — the app's own
/// OneSignal App ID (App Setting > Push Notification > Driver App) plus
/// currency display settings (App Setting > General), fetched once from
/// `GET /rider/settings` the same way the User App fetches its own via
/// `GET /home` (see [PickupRiderApp]'s `ref.listen`).
class RiderSettings {
  const RiderSettings({this.onesignalAppId, this.currencySign = '\$', this.currencyPosition = 'left'});

  final String? onesignalAppId;
  final String currencySign;
  final String currencyPosition;

  factory RiderSettings.fromJson(Map<String, dynamic> json) {
    final sign = json['currency_sign'] as String?;
    return RiderSettings(
      onesignalAppId: json['onesignal_app_id'] as String?,
      currencySign: (sign == null || sign.isEmpty) ? '\$' : sign,
      currencyPosition: json['currency_position'] as String? ?? 'left',
    );
  }

  /// Formats [amount] with this currency's sign in the admin-configured
  /// position — mirrors the backend's own `"{$sign}{$amount}"` formatting
  /// (see Api\OrderController), no space between sign and amount.
  String format(num amount) {
    final value = amount.toStringAsFixed(2);
    return currencyPosition == 'right' ? '$value$currencySign' : '$currencySign$value';
  }
}

final riderSettingsProvider = FutureProvider<RiderSettings>((ref) async {
  final data = await ref.watch(apiClientProvider).get('/rider/settings');
  return RiderSettings.fromJson(data as Map<String, dynamic>);
});

/// Unassigned orders this rider can accept right now — the pull-based
/// list backing the Home screen's Available Orders section, refreshed
/// after every accept attempt (win or lose) and by pull-to-refresh.
final availableOrdersProvider = FutureProvider.autoDispose<List<RiderOrderSummary>>((ref) {
  return ref.watch(riderOrderServiceProvider).available();
});

/// This rider's own in-progress orders (rider_assigned/picked_up/
/// in_transit) — the Home screen's Active Order section.
final activeOrdersProvider = FutureProvider.autoDispose<List<RiderOrderSummary>>((ref) {
  return ref.watch(riderOrderServiceProvider).myOrders(filter: 'active');
});
