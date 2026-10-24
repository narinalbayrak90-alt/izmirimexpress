import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/app_providers.dart';
import '../../services/rider_order_service.dart';
import '../../services/rider_withdrawal_service.dart';

/// Today's/lifetime earnings summary — the Earning tab's stat cards.
final earningsSummaryProvider = FutureProvider.autoDispose<RiderEarningsSummary>((ref) {
  return ref.watch(riderOrderServiceProvider).earnings();
});

/// Available balance plus this rider's own withdrawal request history —
/// the Withdraw button's limit and the Earning tab's "Withdrawal
/// Requests" list.
final withdrawalSummaryProvider = FutureProvider.autoDispose<RiderWithdrawalSummary>((ref) {
  return ref.watch(riderWithdrawalServiceProvider).summary();
});

/// Recent delivered orders backing the Earning tab's list — reuses the
/// same completed-orders endpoint as History, filtered down to
/// `delivered` only (a cancelled order earned nothing, so it doesn't
/// belong on an earnings list).
final recentEarningsProvider = FutureProvider.autoDispose<List<RiderOrderSummary>>((ref) async {
  final completed = await ref.watch(riderOrderServiceProvider).myOrders(filter: 'completed');
  return completed.where((order) => order.status == 'delivered').toList();
});
