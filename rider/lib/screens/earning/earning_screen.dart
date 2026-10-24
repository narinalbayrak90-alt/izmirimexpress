import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/rider_order_service.dart';
import '../../services/rider_withdrawal_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../widgets/app_loader.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/rider_order_card.dart';
import '../home/home_provider.dart';
import 'earning_provider.dart';

/// Earning tab: today's/lifetime totals, the Withdraw button's requests
/// (see HomeScreen's app-bar action and `_openWithdrawDialog`), and a
/// list of recently delivered orders — the bottom nav's third
/// destination.
class EarningScreen extends ConsumerWidget {
  const EarningScreen({super.key});

  Future<void> _refresh(WidgetRef ref) async {
    ref.invalidate(earningsSummaryProvider);
    ref.invalidate(withdrawalSummaryProvider);
    ref.invalidate(recentEarningsProvider);
    await Future.wait([
      ref.read(earningsSummaryProvider.future),
      ref.read(withdrawalSummaryProvider.future),
      ref.read(recentEarningsProvider.future),
    ]);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(earningsSummaryProvider);

    return RefreshIndicator(
      onRefresh: () => _refresh(ref),
      child: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          summary.when(
            data: (data) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _SummaryCards(summary: data),
                if (data.cashInHand != null) ...[
                  if (data.cashInHand! > 0 || data.cashDeposits.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.sm),
                    _CashInHandCard(summary: data),
                  ],
                ] else if (data.todayCodCollected > 0) ...[
                  const SizedBox(height: AppSpacing.sm),
                  _CodDepositBanner(amount: data.todayCodCollected),
                ],
              ],
            ),
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
              child: Center(child: AppLoader(size: 28)),
            ),
            error: (_, _) => EmptyState(message: 'common.error'.tr()),
          ),
          const SizedBox(height: AppSpacing.xl),
          Text('earning.withdrawals_title'.tr(), style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontSize: 18)),
          const SizedBox(height: AppSpacing.sm),
          const _WithdrawalRequestsSection(),
          const SizedBox(height: AppSpacing.xl),
          Text('earning.recent_title'.tr(), style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontSize: 18)),
          const SizedBox(height: AppSpacing.sm),
          const _RecentDeliveriesSection(),
        ],
      ),
    );
  }
}

class _SummaryCards extends ConsumerWidget {
  const _SummaryCards({required this.summary});

  final RiderEarningsSummary summary;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currency = ref.watch(riderSettingsProvider).valueOrNull ?? const RiderSettings();

    return Row(
      children: [
        Expanded(
          child: _StatCard(
            label: 'earning.today_earning'.tr(),
            value: currency.format(summary.todayEarning),
            sublabel: 'earning.deliveries_count'.tr(namedArgs: {'count': '${summary.todayDeliveries}'}),
            background: AppColors.successBackground,
            valueColor: AppColors.success,
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: _StatCard(
            label: 'earning.total_earning'.tr(),
            value: currency.format(summary.totalEarning),
            sublabel: 'earning.deliveries_count'.tr(namedArgs: {'count': '${summary.totalDeliveries}'}),
            background: AppColors.heroBackground,
            valueColor: AppColors.primaryDark,
          ),
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.value,
    required this.sublabel,
    required this.background,
    required this.valueColor,
  });

  final String label;
  final String value;
  final String sublabel;
  final Color background;
  final Color valueColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
          const SizedBox(height: 4),
          Text(value, style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: valueColor)),
          const SizedBox(height: 2),
          Text(sublabel, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
        ],
      ),
    );
  }
}

/// Cash-in-hand reminder — the full customer payment (not the rider's
/// cut, see [RiderEarningsSummary.todayCodCollected]) collected across
/// today's delivered COD orders and still owed to the office. Only shown
/// once there's actually something to deposit.
class _CodDepositBanner extends ConsumerWidget {
  const _CodDepositBanner({required this.amount});

  final double amount;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currency = ref.watch(riderSettingsProvider).valueOrNull ?? const RiderSettings();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.heroBackground,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.account_balance_wallet_outlined, color: AppColors.primaryDark, size: 22),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              'earning.cod_deposit_reminder'.tr(namedArgs: {'amount': currency.format(amount)}),
              style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.textPrimary, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}

/// Cash still owed to the office ([RiderEarningsSummary.cashInHand]) and
/// the latest handovers the office recorded. It drops to zero once the
/// office takes the cash; the rider's earning is untouched and is paid out
/// by withdrawal.
class _CashInHandCard extends ConsumerWidget {
  const _CashInHandCard({required this.summary});

  final RiderEarningsSummary summary;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currency = ref.watch(riderSettingsProvider).valueOrNull ?? const RiderSettings();
    final cash = summary.cashInHand ?? 0;
    final owes = cash > 0;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: owes ? AppColors.heroBackground : AppColors.successBackground,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: (owes ? AppColors.primary : AppColors.success).withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                owes ? Icons.account_balance_wallet_outlined : Icons.check_circle_outline,
                color: owes ? AppColors.primaryDark : AppColors.success,
                size: 22,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      owes
                          ? 'earning.cash_in_hand'.tr(namedArgs: {'amount': currency.format(cash)})
                          : 'earning.cash_settled'.tr(),
                      style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.textPrimary, height: 1.4),
                    ),
                    if (summary.todayCodCollected > 0) ...[
                      const SizedBox(height: 2),
                      Text(
                        'earning.cash_collected_today'.tr(namedArgs: {'amount': currency.format(summary.todayCodCollected)}),
                        style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          if (summary.cashDeposits.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            const Divider(height: 1),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'earning.cash_deposits_title'.tr(),
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 4),
            ...summary.cashDeposits.map(
              (deposit) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        deposit.createdAt == null ? '—' : DateFormat('d MMM y, HH:mm').format(deposit.createdAt!),
                        style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
                      ),
                    ),
                    Text(
                      currency.format(deposit.amount),
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _WithdrawalRequestsSection extends ConsumerWidget {
  const _WithdrawalRequestsSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(withdrawalSummaryProvider);

    return summary.when(
      data: (data) {
        if (data.requests.isEmpty) {
          return EmptyState(message: 'earning.no_withdrawals'.tr());
        }
        return Column(
          children: data.requests.map((request) => _WithdrawalCard(request: request)).toList(),
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

class _WithdrawalCard extends ConsumerWidget {
  const _WithdrawalCard({required this.request});

  final RiderWithdrawal request;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currency = ref.watch(riderSettingsProvider).valueOrNull ?? const RiderSettings();

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                currency.format(request.amount),
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
              ),
              const Spacer(),
              _StatusPill(status: request.status),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            DateFormat('d MMM y, h:mm a').format(request.createdAt),
            style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
          if (request.note != null && request.note!.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(request.note!, style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
          ],
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final Color color = switch (status) {
      'approved' => AppColors.success,
      'declined' => AppColors.error,
      _ => AppColors.textSecondary,
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
      child: Text(
        'earning.withdrawal_status.$status'.tr(),
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color),
      ),
    );
  }
}

class _RecentDeliveriesSection extends ConsumerWidget {
  const _RecentDeliveriesSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final orders = ref.watch(recentEarningsProvider);

    return orders.when(
      data: (list) {
        if (list.isEmpty) {
          return EmptyState(message: 'earning.no_deliveries'.tr());
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
