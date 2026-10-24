import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/app_providers.dart';
import '../../services/api_exception.dart';
import '../../services/rider_order_service.dart';
import '../../theme/app_spacing.dart';
import '../../widgets/app_loader.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/rider_order_card.dart';

/// How close to the bottom (in pixels) a scroll needs to get before the
/// next page is fetched — far enough ahead that the loader at the list's
/// end is rarely visible mid-scroll.
const _loadMoreThreshold = 200.0;

/// History tab: this rider's completed orders (delivered or cancelled),
/// 10 per page — matching the backend's fixed `paginate(10)` (see
/// RiderOrderController::index) — loaded incrementally as the rider
/// scrolls rather than all at once.
class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({super.key});

  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  final _scrollController = ScrollController();
  final List<RiderOrderSummary> _orders = [];

  int _page = 1;
  bool _hasMore = true;
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasError = false;

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
    if (_isLoadingMore || !_hasMore) return;
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - _loadMoreThreshold) {
      _loadMore();
    }
  }

  Future<void> _loadFirstPage() async {
    setState(() {
      _isLoading = true;
      _hasError = false;
    });
    try {
      final page = await ref.read(riderOrderServiceProvider).historyPage(1);
      if (!mounted) return;
      setState(() {
        _orders
          ..clear()
          ..addAll(page.orders);
        _page = 1;
        _hasMore = page.hasMore;
      });
    } on ApiException {
      if (!mounted) return;
      setState(() => _hasError = true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadMore() async {
    setState(() => _isLoadingMore = true);
    try {
      final nextPage = await ref.read(riderOrderServiceProvider).historyPage(_page + 1);
      if (!mounted) return;
      setState(() {
        _orders.addAll(nextPage.orders);
        _page += 1;
        _hasMore = nextPage.hasMore;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      // Leave _hasMore as-is so the next scroll (or a manual retry) tries
      // again — a dropped page shouldn't permanently stop the list.
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _isLoadingMore = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: AppLoader());
    }

    if (_hasError && _orders.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('common.error'.tr()),
            const SizedBox(height: AppSpacing.md),
            TextButton(onPressed: _loadFirstPage, child: Text('common.retry'.tr())),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadFirstPage,
      child: _orders.isEmpty
          ? ListView(
              padding: const EdgeInsets.all(AppSpacing.lg),
              children: [EmptyState(message: 'history.empty'.tr())],
            )
          : ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(AppSpacing.lg),
              itemCount: _orders.length + (_hasMore ? 1 : 0),
              itemBuilder: (context, index) {
                if (index >= _orders.length) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
                    child: Center(child: AppLoader(size: 28)),
                  );
                }
                return RiderOrderCard(order: _orders[index]);
              },
            ),
    );
  }
}
