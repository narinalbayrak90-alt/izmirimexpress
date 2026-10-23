import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../providers/app_providers.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../widgets/app_bottom_nav.dart';
import '../../widgets/responsive_shell.dart';
import '../../widgets/app_loader.dart';
import '../../widgets/install_app.dart';
import '../booking/booking_providers.dart';
import '../welcome/welcome_provider.dart';
import 'active_orders_carousel.dart';
import 'home_category.dart';
import 'home_provider.dart';

/// Home screen: hero booking banner, category grid (from `GET /home`), and
/// static trust/quick-action sections. Everything except the category grid
/// (and the hero banner's illustration, reused from [welcomeContentProvider])
/// is intentionally static — the screens those sections link to (booking
/// flow, tracking, order history, other tabs) don't exist yet.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  /// Re-fetches the welcome content and categories, and waits for both to
  /// settle so the pull-to-refresh spinner stays up until fresh data (or a
  /// fallback) is ready. Failures are swallowed here — each section already
  /// has its own fallback/error handling in its `.when()`.
  Future<void> _onRefresh(WidgetRef ref) async {
    ref.invalidate(welcomeContentProvider);
    ref.invalidate(homeCategoriesProvider);
    ref.invalidate(activeOrdersProvider);
    try {
      await Future.wait([
        ref.read(welcomeContentProvider.future),
        ref.read(homeCategoriesProvider.future),
        ref.read(activeOrdersProvider.future),
      ]);
    } catch (_) {
      // Each section already falls back gracefully via its own `.when()`.
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDesktop = DesktopLayoutScope.of(context);

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: () => _onRefresh(ref),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: isDesktop
                ? const EdgeInsets.all(AppSpacing.xl)
                : const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.md, AppSpacing.md, AppSpacing.xl),
            children: [
              // On desktop the site header already shows the logo and links.
              if (!isDesktop) ...[
                const _HomeHeader(),
                const SizedBox(height: AppSpacing.lg),
              ],
              const InstallAppCard(),
              const _HeroBanner(),
              const SizedBox(height: AppSpacing.xl),
              Text('home.send_anything'.tr(), style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontSize: 19)),
              const SizedBox(height: AppSpacing.md),
              const _CategoryGrid(),
              const SizedBox(height: AppSpacing.xl),
              const _TrustBadgesBanner(),
              const SizedBox(height: AppSpacing.xl),
              Text('home.quick_actions'.tr(), style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontSize: 20)),
              const SizedBox(height: AppSpacing.md),
              const _QuickActions(),
              const ActiveOrdersCarousel(),
            ],
          ),
        ),
      ),
      bottomNavigationBar: const AppBottomNav(activeTab: AppTab.home),
    );
  }
}

class _HomeHeader extends ConsumerWidget {
  const _HomeHeader();

  /// Guest browsing is allowed everywhere per project.txt Module 2 — same
  /// gate as the bottom nav's Bookings/Track tabs: a guest tapping the
  /// bell goes to log in first rather than hitting an auth-required screen.
  Future<void> _openNotifications(BuildContext context, WidgetRef ref) async {
    final token = await ref.read(secureStorageProvider).readToken();
    if (!context.mounted) return;
    context.push(token == null || token.isEmpty ? '/login' : '/notifications');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(appSettingsProvider).valueOrNull;
    final logoUrl = settings?.appLogoUrl;
    final appName = settings?.appName ?? 'app_name'.tr();

    return Row(
      children: [
        Container(
          height: 42,
          width: 42,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(12)),
          child: (logoUrl != null && logoUrl.isNotEmpty)
              ? Image.network(
                  logoUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) =>
                      const Icon(Icons.local_shipping_rounded, color: Colors.white, size: 22),
                )
              : const Icon(Icons.local_shipping_rounded, color: Colors.white, size: 22),
        ),
        const SizedBox(width: AppSpacing.sm),
        Text(
          appName,
          style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
        ),
        const Spacer(),
        InkWell(
          onTap: () => _openNotifications(context, ref),
          borderRadius: BorderRadius.circular(21),
          child: Container(
            height: 42,
            width: 42,
            decoration: const BoxDecoration(color: AppColors.surfaceMuted, shape: BoxShape.circle),
            child: const Icon(Icons.notifications_none_rounded, color: AppColors.textPrimary, size: 22),
          ),
        ),
      ],
    );
  }
}

class _HeroBanner extends ConsumerWidget {
  const _HeroBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Reuses the same admin-managed image as the welcome screen — only the
    // illustration is shared; this banner's copy stays static by design.
    final imageUrl = ref.watch(welcomeContentProvider).asData?.value.imageUrl;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(color: AppColors.heroBackground, borderRadius: BorderRadius.circular(20)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 6,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'home.hero_title'.tr(),
                  style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w700, color: AppColors.textPrimary, height: 1.25),
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'home.hero_subtitle'.tr(),
                  style: const TextStyle(fontSize: 13, color: AppColors.textSecondary, height: 1.4),
                ),
                const SizedBox(height: AppSpacing.md),
                ElevatedButton(
                  onPressed: () => context.push('/booking'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.textPrimary,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(0, 40),
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('home.book_now'.tr(), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                      const SizedBox(width: 6),
                      const Icon(Icons.arrow_forward_rounded, size: 16),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            flex: 5,
            // Capped so the illustration doesn't blow the banner up to
            // half a screen on a wide desktop page.
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 200),
              child: (imageUrl != null && imageUrl.isNotEmpty)
                  ? Image.network(
                      imageUrl,
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, stackTrace) => const Icon(
                        Icons.local_shipping_rounded,
                        size: 56,
                        color: AppColors.primaryDark,
                      ),
                    )
                  : const Icon(Icons.local_shipping_rounded, size: 56, color: AppColors.primaryDark),
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoryGrid extends ConsumerWidget {
  const _CategoryGrid();

  static const _columns = 4;
  static const _aspectRatio = 0.8;

  /// Tapping a category from Home already answers Step 1 of the booking
  /// flow, so this skips [BookingCategoryScreen] entirely and drops the
  /// customer straight into Step 2 (Pickup) with the category pre-filled.
  void _selectCategory(BuildContext context, WidgetRef ref, HomeCategory category) {
    final draft = ref.read(bookingDraftProvider);
    ref.read(bookingDraftProvider.notifier).state = draft.copyWith(category: category);
    context.push('/booking/pickup');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categories = ref.watch(homeCategoriesProvider);

    return categories.when(
      data: (items) {
        if (items.isEmpty) return const SizedBox.shrink();
        // A Wrap (rather than GridView) so a fixed-size card renders at
        // its natural width regardless of row count, left-aligned like a
        // regular grid.
        return LayoutBuilder(
          builder: (context, constraints) {
            // More columns once there's room for them (desktop web).
            final columns = constraints.maxWidth >= 900 ? _columns * 2 : _columns;
            final cardWidth = (constraints.maxWidth - AppSpacing.sm * (columns - 1)) / columns;
            return Wrap(
              alignment: WrapAlignment.start,
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                for (final category in items)
                  SizedBox(
                    width: cardWidth,
                    height: cardWidth / _aspectRatio,
                    child: _CategoryCard(
                      category: category,
                      onTap: () => _selectCategory(context, ref, category),
                    ),
                  ),
              ],
            );
          },
        );
      },
      loading: () => const SizedBox(height: 140, child: Center(child: AppLoader())),
      // Backend unreachable — omit the section rather than showing an error
      // state on an otherwise-static home screen.
      error: (error, stackTrace) => const SizedBox.shrink(),
    );
  }
}

class _CategoryCard extends StatelessWidget {
  const _CategoryCard({required this.category, required this.onTap});

  final HomeCategory category;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm, horizontal: AppSpacing.xs),
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              height: 36,
              width: 36,
              child: (category.iconUrl != null && category.iconUrl!.isNotEmpty)
                  ? Image.network(
                      category.iconUrl!,
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, stackTrace) =>
                          const Icon(Icons.inventory_2_outlined, color: AppColors.primaryDark),
                    )
                  : const Icon(Icons.inventory_2_outlined, color: AppColors.primaryDark),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              category.name,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
            ),
          ],
        ),
      ),
    );
  }
}

class _TrustBadgesBanner extends StatelessWidget {
  const _TrustBadgesBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(color: AppColors.infoBackground, borderRadius: BorderRadius.circular(20)),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'home.trust_title'.tr(),
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                ),
                const SizedBox(height: AppSpacing.sm),
                Wrap(
                  spacing: 12,
                  runSpacing: 6,
                  children: [
                    _TrustBadgeRow(icon: Icons.verified_user_outlined, label: 'home.trust_secure_delivery'.tr()),
                    _TrustBadgeRow(icon: Icons.access_time_rounded, label: 'home.trust_on_time'.tr()),
                    _TrustBadgeRow(icon: Icons.location_on_outlined, label: 'home.trust_live_tracking'.tr()),
                  ],
                ),
              ],
            ),
          ),
          Image.asset('assets/tracking.png', width: 56, height: 56, fit: BoxFit.contain),
        ],
      ),
    );
  }
}

class _TrustBadgeRow extends StatelessWidget {
  const _TrustBadgeRow({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: AppColors.textPrimary),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(fontSize: 13, color: AppColors.textPrimary)),
      ],
    );
  }
}

class _QuickActions extends ConsumerWidget {
  const _QuickActions();

  /// Track / History open the orders list on the Active / Completed filter
  /// — same guest gate as the bottom nav: a guest logs in first.
  Future<void> _openOrders(BuildContext context, WidgetRef ref, String filter) async {
    final token = await ref.read(secureStorageProvider).readToken();
    if (!context.mounted) return;
    if (token == null || token.isEmpty) {
      context.push('/login');
      return;
    }
    context.push('/orders', extra: {'filter': filter});
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Row(
      children: [
        Expanded(
          child: _QuickActionCard(
            icon: Icons.add_box_rounded,
            iconColor: AppColors.primaryDark,
            background: AppColors.heroBackground,
            title: 'home.quick_action_book_title'.tr(),
            subtitle: 'home.quick_action_book_subtitle'.tr(),
            onTap: () => context.push('/booking'),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: _QuickActionCard(
            icon: Icons.search_rounded,
            iconColor: AppColors.success,
            background: AppColors.successBackground,
            title: 'home.quick_action_track_title'.tr(),
            subtitle: 'home.quick_action_track_subtitle'.tr(),
            onTap: () => _openOrders(context, ref, 'active'),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: _QuickActionCard(
            icon: Icons.history_rounded,
            iconColor: AppColors.accent,
            background: AppColors.infoBackground,
            title: 'home.quick_action_history_title'.tr(),
            subtitle: 'home.quick_action_history_subtitle'.tr(),
            onTap: () => _openOrders(context, ref, 'completed'),
          ),
        ),
      ],
    );
  }
}

class _QuickActionCard extends StatelessWidget {
  const _QuickActionCard({
    required this.icon,
    required this.iconColor,
    required this.background,
    required this.title,
    required this.subtitle,
    this.onTap,
  });

  final IconData icon;
  final Color iconColor;
  final Color background;
  final String title;
  final String subtitle;

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final content = Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: iconColor, size: 22),
          const SizedBox(height: AppSpacing.xs),
          Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: AppColors.textPrimary)),
          const SizedBox(height: 2),
          Text(subtitle, style: const TextStyle(fontSize: 10.5, color: AppColors.textSecondary), maxLines: 2),
        ],
      ),
    );

    if (onTap == null) return content;
    return InkWell(onTap: onTap, borderRadius: BorderRadius.circular(16), child: content);
  }
}
