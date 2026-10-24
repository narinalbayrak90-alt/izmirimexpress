import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/app_providers.dart';
import '../../services/rider_order_service.dart';

/// Full detail for one order, from `GET /rider/orders/{order}` — keyed by
/// order id so each [OrderDetailScreen] instance gets its own cached copy.
/// `autoDispose` since there's no reason to keep it once the screen is
/// left; callers re-fetch with `ref.invalidate(orderDetailProvider(id))`
/// after every action (accept/release/pickup/in-transit/deliver) rather
/// than trying to patch the cached value by hand.
final orderDetailProvider = FutureProvider.autoDispose.family<RiderOrderDetail, int>((ref, orderId) {
  return ref.watch(riderOrderServiceProvider).show(orderId);
});
