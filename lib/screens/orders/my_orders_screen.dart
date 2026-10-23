import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../providers/app_providers.dart';
import '../../services/api_exception.dart';
import '../../services/app_settings.dart';
import '../../services/order_status.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../widgets/app_loader.dart';
import '../home/home_provider.dart';

const _filterValues = ['all', 'active', 'completed'];

String _filterLabel(String value) => 'orders.filter_$value'.tr();

/// Order History screen (project.txt Module 11) — the logged-in customer's
/// past and in-progress orders, newest first. Loads 10 at a time and fetches
/// the next page automatically as the list is scrolled (infinite scroll)
/// rather than a page-number control, matching how the rest of the app's
/// lists behave.
///
/// The All/Active/Completed filter re-queries the backend rather than
/// filtering a client-side cache, so switching filters always reflects the
/// full order history, not just whatever page happened to be loaded.
class MyOrdersScreen extends ConsumerStatefulWidget {
  const MyOrdersScreen({super.key, this.initialFilter = 'all'});

  /// "all", "active", or "completed" — lets the bottom nav's Track button
  /// land straight on the Active tab instead of always starting on All.
  final String initialFilter;

  @override
  ConsumerState<MyOrdersScreen> createState() => _MyOrdersScreenState();
}

class _MyOrdersScreenState extends ConsumerState<MyOrdersScreen> {
  final _scrollController = ScrollController();
  final List<OrderListItem> _orders = [];

  late String _filter = widget.initialFilter;
  int _page = 1;
  bool _hasMore = true;
  bool _isLoading = true;
  bool _isLoadingMore = false;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadFirstPage();
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_hasMore || _isLoading || _isLoadingMore) return;
    final threshold = _scrollController.position.maxScrollExtent - 300;
    if (_scrollController.position.pixels >= threshold) {
      _loadNextPage();
    }
  }

  Future<void> _loadFirstPage() async {
    setState(() {
      _isLoading = true;
      _loadError = null;
    });
    try {
      final result = await _fetchFirstPage();
      if (!mounted) return;
      setState(() {
        _orders
          ..clear()
          ..addAll(result.items);
        _page = result.currentPage;
        _hasMore = result.hasMore;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _loadError = e is ApiException ? e.message : 'common.unexpected_error'.tr();
      });
    }
  }

  /// The first load right after the site opens can hit a server that's
  /// still waking up; one quiet retry keeps that from flashing an error
  /// screen at the customer. A second failure is shown as usual.
  Future<OrderListPage> _fetchFirstPage() async {
    final service = ref.read(orderServiceProvider);
    try {
      return await service.getOrders(page: 1, filter: _filter);
    } catch (_) {
      await Future<void>.delayed(const Duration(milliseconds: 800));
      return service.getOrders(page: 1, filter: _filter);
    }
  }

  Future<void> _loadNextPage() async {
    setState(() => _isLoadingMore = true);
    try {
      final result = await ref.read(orderServiceProvider).getOrders(page: _page + 1, filter: _filter);
      if (!mounted) return;
      setState(() {
        _orders.addAll(result.items);
        _page = result.currentPage;
        _hasMore = result.hasMore;
        _isLoadingMore = false;
      });
    } on ApiException {
      // A failed "load more" leaves the list as-is — scrolling back up to
      // the threshold tries again rather than showing a dead-end error.
      if (!mounted) return;
      setState(() => _isLoadingMore = false);
    }
  }

  void _changeFilter(String filter) {
    if (filter == _filter) return;
    setState(() => _filter = filter);
    _loadFirstPage();
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(appSettingsProvider).valueOrNull ?? const AppSettings.fallback();

    return Scaffold(
      appBar: AppBar(title: Text('orders.title'.tr())),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            _FilterBar(selected: _filter, onSelect: _changeFilter),
            Expanded(child: _buildBody(settings)),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(AppSettings settings) {
    if (_isLoading) {
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
              OutlinedButton(onPressed: _loadFirstPage, child: Text('common.retry'.tr())),
            ],
          ),
        ),
      );
    }
    if (_orders.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.inventory_2_outlined, color: AppColors.textSecondary, size: 40),
              const SizedBox(height: AppSpacing.sm),
              Text(
                _filter == 'active'
                    ? 'orders.empty_active'.tr()
                    : _filter == 'completed'
                        ? 'orders.empty_completed'.tr()
                        : 'orders.empty_all'.tr(),
                style: const TextStyle(color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadFirstPage,
      child: ListView.separated(
        controller: _scrollController,
        padding: const EdgeInsets.all(AppSpacing.md),
        itemCount: _orders.length + (_hasMore ? 1 : 0),
        separatorBuilder: (context, index) => const SizedBox(height: AppSpacing.sm),
        itemBuilder: (context, index) {
          if (index >= _orders.length) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
              child: Center(child: AppLoader(size: 24)),
            );
          }
          return _OrderCard(order: _orders[index], settings: settings);
        },
      ),
    );
  }
}

class _FilterBar extends StatelessWidget {
  const _FilterBar({required this.selected, required this.onSelect});

  final String selected;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.md, AppSpacing.sm),
      child: Row(
        children: [
          for (final value in _filterValues) ...[
            Expanded(
              child: _FilterChip(
                label: _filterLabel(value),
                isSelected: selected == value,
                onTap: () => onSelect(value),
              ),
            ),
            if (value != _filterValues.last) const SizedBox(width: AppSpacing.sm),
          ],
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({required this.label, required this.isSelected, required this.onTap});

  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary : AppColors.surfaceMuted,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: isSelected ? AppColors.primary : AppColors.border),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: isSelected ? AppColors.textPrimary : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}

class _OrderCard extends StatelessWidget {
  const _OrderCard({required this.order, required this.settings});

  final OrderListItem order;
  final AppSettings settings;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'orders.card_title'.tr(namedArgs: {'id': '${order.id}', 'category': order.categoryName}),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              _StatusBadge(status: order.status),
            ],
          ),
          const SizedBox(height: 4),
          Text(_formatDate(context, order.createdAt), style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          const SizedBox(height: AppSpacing.sm),
          _AddressLine(icon: Icons.trip_origin_rounded, iconColor: AppColors.success, address: order.pickupAddress),
          const SizedBox(height: 4),
          _AddressLine(icon: Icons.location_on_rounded, iconColor: AppColors.error, address: order.dropoffAddress),
          const SizedBox(height: AppSpacing.sm),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                settings.format(order.total),
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
              ),
              Text(
                'orders.distance_and_method'.tr(namedArgs: {
                  'distance': order.distanceKm.toStringAsFixed(1),
                  'method': paymentMethodLabel(order.paymentMethod),
                }),
                style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              if (order.isActive) ...[
                Expanded(
                  child: TextButton.icon(
                    onPressed: () => context.push('/orders/${order.id}'),
                    icon: const Icon(Icons.local_shipping_outlined, size: 15),
                    label: Text('orders.track_order'.tr()),
                    style: _orderCardButtonStyle(
                      backgroundColor: const Color(0xFFF3F3F3),
                      foregroundColor: AppColors.textPrimary,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
              ],
              Expanded(
                child: TextButton.icon(
                  onPressed: () => context.push('/orders/${order.id}/detail'),
                  icon: const Icon(Icons.receipt_long_outlined, size: 15),
                  label: Text('orders.view_detail'.tr()),
                  style: _orderCardButtonStyle(
                    backgroundColor: AppColors.heroBackground,
                    foregroundColor: AppColors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static ButtonStyle _orderCardButtonStyle({required Color backgroundColor, required Color foregroundColor}) {
    return TextButton.styleFrom(
      backgroundColor: backgroundColor,
      foregroundColor: foregroundColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      padding: const EdgeInsets.symmetric(vertical: 8),
      minimumSize: const Size(0, 36),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      textStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
    );
  }

  String _formatDate(BuildContext context, DateTime date) {
    return DateFormat.yMMMd(context.locale.toString()).format(date.toLocal());
  }
}

class _AddressLine extends StatelessWidget {
  const _AddressLine({required this.icon, required this.iconColor, required this.address});

  final IconData icon;
  final Color iconColor;
  final String address;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 14, color: iconColor),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            address,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
          ),
        ),
      ],
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});

  final String status;

  static const _colors = {
    'pending': AppColors.textSecondary,
    'confirmed': AppColors.accent,
    'rider_assigned': AppColors.purple,
    'picked_up': AppColors.primaryDark,
    'in_transit': AppColors.primaryDark,
    'delivered': AppColors.success,
    'cancelled': AppColors.error,
  };

  static const _backgrounds = {
    'pending': AppColors.surfaceMuted,
    'confirmed': AppColors.infoBackground,
    'rider_assigned': AppColors.purpleBackground,
    'picked_up': AppColors.heroBackground,
    'in_transit': AppColors.heroBackground,
    'delivered': AppColors.successBackground,
    'cancelled': AppColors.errorBackground,
  };

  @override
  Widget build(BuildContext context) {
    final color = _colors[status] ?? AppColors.textSecondary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: _backgrounds[status] ?? AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        orderStatusLabel(status),
        style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: color),
      ),
    );
  }
}
