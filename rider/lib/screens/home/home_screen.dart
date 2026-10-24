import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/app_providers.dart';
import '../../services/api_exception.dart';
import '../../services/rider_auth_service.dart';
import '../../services/rider_order_service.dart';
import '../../services/rider_withdrawal_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../widgets/app_loader.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/rider_order_card.dart';
import '../account/account_screen.dart';
import '../earning/earning_provider.dart';
import '../earning/earning_screen.dart';
import '../earning/withdraw_dialog.dart';
import '../history/history_screen.dart';
import '../map/orders_map_screen.dart';
import 'home_provider.dart';
import 'tour_card.dart';

/// The app's bottom-nav shell: Home / Map / History / Earning / Account, all
/// kept alive together in an [IndexedStack] (not separate routes) so
/// switching tabs never re-fetches or loses scroll position — this app's
/// screens are simple enough that a full [StatefulShellRoute] would just
/// be extra ceremony for no real benefit. Which tab is showing lives in
/// [homeTabIndexProvider], not local [State], so the Account tab's menu
/// can jump straight to Earning/History (see AccountScreen).
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  static const _titleKeys = ['app_name', 'map.title', 'history.title', 'earning.title', 'account.title'];

  /// Fetches the rider's up-to-the-moment balance (not whatever
  /// [withdrawalSummaryProvider] last cached — the Earning tab may have
  /// been sitting open for a while) before opening [WithdrawDialog], so
  /// the cap shown there can't be stale.
  Future<void> _openWithdrawDialog() async {
    ref.invalidate(withdrawalSummaryProvider);
    final RiderWithdrawalSummary summary;
    try {
      summary = await ref.read(withdrawalSummaryProvider.future);
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      return;
    }
    if (!mounted) return;

    if (summary.cashInHand > 0) {
      final currency = ref.read(riderSettingsProvider).valueOrNull ?? const RiderSettings();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('earning.withdraw_cash_first'.tr(namedArgs: {'amount': currency.format(summary.cashInHand)}))),
      );
      return;
    }

    if (summary.availableBalance <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('earning.withdraw_no_balance'.tr())),
      );
      return;
    }

    final requested = await showDialog<bool>(
      context: context,
      builder: (_) => WithdrawDialog(availableBalance: summary.availableBalance),
    );
    if (requested == true) {
      if (!mounted) return;
      ref.invalidate(withdrawalSummaryProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('earning.withdraw_success'.tr())),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final tabIndex = ref.watch(homeTabIndexProvider);

    return Scaffold(
      appBar: AppBar(
        // Home is the shell's own root — every other tab got there via a
        // nav tap (or an Account-menu jump), so it gets a "back to Home"
        // action instead of the default AppBar back arrow, which would
        // otherwise pop the whole route (there's nothing to pop to).
        leading: tabIndex == homeTabIndex
            ? null
            : IconButton(
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: () => ref.read(homeTabIndexProvider.notifier).state = homeTabIndex,
              ),
        title: Text(_titleKeys[tabIndex].tr()),
        actions: tabIndex == earningTabIndex
            ? [
                TextButton.icon(
                  onPressed: _openWithdrawDialog,
                  icon: const Icon(Icons.account_balance_wallet_outlined, size: 18),
                  label: Text('earning.withdraw'.tr()),
                ),
              ]
            : null,
      ),
      body: SafeArea(
        top: false,
        child: IndexedStack(
          index: tabIndex,
          children: const [
            _HomeTab(),
            OrdersMapScreen(),
            HistoryScreen(),
            EarningScreen(),
            AccountScreen(),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: tabIndex,
        onDestinationSelected: (index) => ref.read(homeTabIndexProvider.notifier).state = index,
        destinations: [
          NavigationDestination(icon: const Icon(Icons.home_outlined), selectedIcon: const Icon(Icons.home_rounded), label: 'nav.home'.tr()),
          NavigationDestination(icon: const Icon(Icons.map_outlined), selectedIcon: const Icon(Icons.map_rounded), label: 'nav.map'.tr()),
          NavigationDestination(icon: const Icon(Icons.history_rounded), selectedIcon: const Icon(Icons.history_rounded), label: 'nav.history'.tr()),
          NavigationDestination(icon: const Icon(Icons.payments_outlined), selectedIcon: const Icon(Icons.payments_rounded), label: 'nav.earning'.tr()),
          NavigationDestination(icon: const Icon(Icons.person_outline_rounded), selectedIcon: const Icon(Icons.person_rounded), label: 'nav.account'.tr()),
        ],
      ),
    );
  }
}

/// Home tab body: go online/offline, see the order(s) currently assigned,
/// and accept newly available ones — the tab the "new order available"
/// push (see OneSignalService::notifyOrderAvailable on the backend) brings
/// the rider to, and where they'd land anyway just by having the app open.
///
/// Going online does two things together: flips `is_online` (what makes
/// the backend include this rider in that push broadcast) and starts
/// [RiderLocationTracker] (what keeps `GET /rider/orders/available`'s
/// distance sort — and the customer's live ETA — accurate). They're kept
/// in lockstep everywhere this tab touches either one.
class _HomeTab extends ConsumerStatefulWidget {
  const _HomeTab();

  @override
  ConsumerState<_HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends ConsumerState<_HomeTab> {
  bool _isTogglingAvailability = false;
  final Set<int> _acceptingOrderIds = {};
  bool _hasResumedTracker = false;
  bool _hasTaggedPush = false;

  Future<void> _toggleAvailability(bool goOnline) async {
    if (goOnline) {
      final granted = await ref.read(riderLocationServiceProvider).ensurePermission();
      if (!granted) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('home.location_permission_required'.tr())),
        );
        return;
      }
    }

    setState(() => _isTogglingAvailability = true);
    try {
      await ref.read(riderAuthServiceProvider).updateAvailability(goOnline);
      if (goOnline) {
        ref.read(riderLocationTrackerProvider).start();
      } else {
        ref.read(riderLocationTrackerProvider).stop();
      }
      ref.invalidate(riderProfileProvider);
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _isTogglingAvailability = false);
    }
  }

  Future<void> _accept(RiderOrderSummary order) async {
    final message = await acceptConfirmMessage(ref, order.id);
    if (!mounted) return;
    final confirmed = await confirmDialog(
      context,
      title: 'order_detail.accept_confirm_title'.tr(),
      message: message,
      confirmLabel: 'home.accept'.tr(),
    );
    if (!mounted || !confirmed) return;

    setState(() => _acceptingOrderIds.add(order.id));
    try {
      await ref.read(riderOrderServiceProvider).accept(order.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('home.accept_success'.tr())),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      // A 409 here means another rider's accept won the race first (see
      // RiderOrderController::accept's row lock) — the backend's own
      // message already says so clearly enough to show as-is.
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _acceptingOrderIds.remove(order.id));
      ref.invalidate(availableOrdersProvider);
      ref.invalidate(activeOrdersProvider);
    }
  }

  Future<void> _refresh() async {
    // Available orders are only fetched/shown while online — an offline
    // rider receives no new orders (the backend returns an empty list and
    // blocks accept; see RiderOrderController), so there's nothing to
    // pull for here either.
    final isOnline = ref.read(riderProfileProvider).valueOrNull?.isOnline ?? false;

    ref.invalidate(riderProfileProvider);
    ref.invalidate(activeOrdersProvider);
    if (isOnline) ref.invalidate(availableOrdersProvider);

    await Future.wait([
      ref.read(riderProfileProvider.future),
      ref.read(activeOrdersProvider.future),
      if (isOnline) ref.read(availableOrdersProvider.future),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(riderProfileProvider);

    // Resume the location heartbeat if the rider was already online when
    // the app (re)started — e.g. it was killed mid-shift. Runs once per
    // profile load, not on every rebuild.
    ref.listen(riderProfileProvider, (previous, next) {
      final rider = next.valueOrNull;
      // Re-tag on every app start, not only at login, so new-order pushes
      // reach riders whose session outlived an install or an SDK reset.
      if (rider != null && !_hasTaggedPush) {
        _hasTaggedPush = true;
        ref.read(oneSignalServiceProvider).tagRiderId(rider.id);
        ref.read(oneSignalServiceProvider).requestPermission();
      }
      if (rider != null && rider.isOnline && !_hasResumedTracker) {
        _hasResumedTracker = true;
        ref.read(riderLocationTrackerProvider).start();
      }
    });

    return profile.when(
      data: (rider) => RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            Text(
              'home.welcome'.tr(namedArgs: {'name': rider.name}),
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: AppSpacing.sm),
            _VerificationBanner(status: rider.verificationStatus),
            const SizedBox(height: AppSpacing.md),
            _AvailabilityCard(
              isOnline: rider.isOnline,
              isLoading: _isTogglingAvailability,
              onChanged: _toggleAvailability,
            ),
            if (!rider.isOnline) ...[
              const SizedBox(height: AppSpacing.sm),
              _OfflineBanner(),
            ],
            const _NotificationPermissionCard(),
            const SizedBox(height: AppSpacing.xl),
            Text('home.active_orders_title'.tr(), style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontSize: 18)),
            const SizedBox(height: AppSpacing.sm),
            const TourCard(),
            _ActiveOrdersSection(),
            // New/available orders are only relevant while the rider is
            // online — showing (or fetching) them while offline would let
            // a rider accept an order without their location being
            // tracked, since going online is what starts the location
            // heartbeat (see this tab's own class doc comment).
            if (rider.isOnline) ...[
              const SizedBox(height: AppSpacing.xl),
              Text('home.available_orders_title'.tr(), style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontSize: 18)),
              const SizedBox(height: AppSpacing.sm),
              _AvailableOrdersSection(
                acceptingOrderIds: _acceptingOrderIds,
                onAccept: _accept,
              ),
            ],
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
            TextButton(onPressed: () => ref.invalidate(riderProfileProvider), child: Text('common.retry'.tr())),
          ],
        ),
      ),
    );
  }
}

/// Slim verification-status strip under the Home greeting. A logged-in
/// rider is always `approved` (the backend's `rider` middleware rejects
/// every request otherwise), so this normally reads "Verified partner" —
/// but if an admin blocks the account mid-shift, the next profile refresh
/// surfaces that here instead of the rider only finding out when an action
/// fails.
class _VerificationBanner extends StatelessWidget {
  const _VerificationBanner({required this.status});

  final RiderVerificationStatus status;

  @override
  Widget build(BuildContext context) {
    final ({Color color, Color background, IconData icon, String textKey}) v = switch (status) {
      RiderVerificationStatus.approved => (
          color: AppColors.success,
          background: AppColors.successBackground,
          icon: Icons.verified_rounded,
          textKey: 'verification.home_verified',
        ),
      RiderVerificationStatus.pending => (
          color: AppColors.primaryDark,
          background: AppColors.heroBackground,
          icon: Icons.hourglass_top_rounded,
          textKey: 'verification.home_review',
        ),
      RiderVerificationStatus.rejected || RiderVerificationStatus.blocked => (
          color: AppColors.error,
          background: AppColors.errorBackground,
          icon: Icons.error_outline_rounded,
          textKey: 'verification.home_blocked',
        ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 8),
      decoration: BoxDecoration(color: v.background, borderRadius: BorderRadius.circular(10)),
      child: Row(
        children: [
          Icon(v.icon, size: 16, color: v.color),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              v.textKey.tr(),
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: v.color),
            ),
          ),
        ],
      ),
    );
  }
}

class _AvailabilityCard extends StatelessWidget {
  const _AvailabilityCard({required this.isOnline, required this.isLoading, required this.onChanged});

  final bool isOnline;
  final bool isLoading;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      decoration: BoxDecoration(
        color: isOnline ? AppColors.successBackground : AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(
            isOnline ? Icons.wifi_tethering_rounded : Icons.wifi_tethering_off_rounded,
            color: isOnline ? AppColors.success : AppColors.textSecondary,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              isOnline ? 'home.online'.tr() : 'home.offline'.tr(),
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: isOnline ? AppColors.success : AppColors.textPrimary,
              ),
            ),
          ),
          if (isLoading)
            const SizedBox(height: 24, width: 24, child: AppLoader(size: 20))
          else
            Switch(
              value: isOnline,
              activeThumbColor: AppColors.success,
              onChanged: onChanged,
            ),
        ],
      ),
    );
  }
}

/// Shown while the OS blocks this app's notifications, so a rider can't
/// miss new-order pushes without knowing it. The button asks again, or
/// opens the system settings when Android won't show the prompt any more
/// (the rider denied it before). Hidden when push isn't configured yet.
class _NotificationPermissionCard extends ConsumerStatefulWidget {
  const _NotificationPermissionCard();

  @override
  ConsumerState<_NotificationPermissionCard> createState() => _NotificationPermissionCardState();
}

class _NotificationPermissionCardState extends ConsumerState<_NotificationPermissionCard> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) ref.read(oneSignalServiceProvider).refreshPermission();
  }

  @override
  Widget build(BuildContext context) {
    final service = ref.watch(oneSignalServiceProvider);

    return ValueListenableBuilder<bool?>(
      valueListenable: service.permission,
      builder: (context, granted, _) {
        if (granted != false) return const SizedBox.shrink();

        return Padding(
          padding: const EdgeInsets.only(top: AppSpacing.md),
          child: Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: AppColors.errorBackground,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Icon(Icons.notifications_off_outlined, color: AppColors.error),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    'home.notifications_off'.tr(),
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.error),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                FilledButton(
                  onPressed: service.requestPermission,
                  child: Text('home.notifications_turn_on'.tr()),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _OfflineBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Text(
      'home.offline_banner'.tr(),
      style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
    );
  }
}

class _ActiveOrdersSection extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final orders = ref.watch(activeOrdersProvider);

    return orders.when(
      data: (list) {
        if (list.isEmpty) {
          return EmptyState(message: 'home.no_active_orders'.tr());
        }
        return Column(
          children: list.map((order) => RiderOrderCard(order: order)).toList(),
        );
      },
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
        child: Center(child: AppLoader(size: 28)),
      ),
      error: (_, _) => EmptyState(message: 'home.load_error'.tr()),
    );
  }
}

class _AvailableOrdersSection extends ConsumerWidget {
  const _AvailableOrdersSection({required this.acceptingOrderIds, required this.onAccept});

  final Set<int> acceptingOrderIds;
  final Future<void> Function(RiderOrderSummary order) onAccept;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final orders = ref.watch(availableOrdersProvider);

    return orders.when(
      data: (list) {
        if (list.isEmpty) {
          return EmptyState(message: 'home.no_available_orders'.tr());
        }
        return Column(
          children: list
              .map((order) => RiderOrderCard(
                    order: order,
                    onAccept: () => onAccept(order),
                    isAccepting: acceptingOrderIds.contains(order.id),
                  ))
              .toList(),
        );
      },
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
        child: Center(child: AppLoader(size: 28)),
      ),
      error: (_, _) => EmptyState(message: 'home.load_error'.tr()),
    );
  }
}
