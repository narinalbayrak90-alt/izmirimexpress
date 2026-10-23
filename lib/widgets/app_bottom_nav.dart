import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/app_providers.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';

/// Which bottom-nav destination is currently showing, so [AppBottomNav] can
/// highlight the right tab. "Bookings"/"Track" both push the Order History
/// screen (just with a different starting filter) rather than replacing the
/// current screen, so neither is ever an [activeTab] value.
enum AppTab { home, account }

/// Shared bottom nav + "New Booking" FAB, used by every top-level screen
/// (Home, Account, ...) so the tab bar looks and behaves the same
/// everywhere instead of each screen rebuilding its own copy.
class AppBottomNav extends ConsumerWidget {
  const AppBottomNav({super.key, required this.activeTab});

  final AppTab activeTab;

  /// Guest browsing is allowed everywhere per project.txt Module 2 — same
  /// gate as "Place Order" on the Summary step: a guest tapping Account
  /// goes to log in first rather than hitting an auth-required screen and
  /// bouncing straight back.
  Future<void> _openAccount(BuildContext context, WidgetRef ref) async {
    final token = await ref.read(secureStorageProvider).readToken();
    if (!context.mounted) return;
    context.push(token == null || token.isEmpty ? '/login' : '/account');
  }

  /// "Bookings" opens the Order History screen on the "All" filter,
  /// "Track" opens it pre-filtered to "Active" — same guest gate as
  /// [_openAccount] since order history needs a logged-in customer.
  Future<void> _openOrders(BuildContext context, WidgetRef ref, {String filter = 'all'}) async {
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
    final isHome = activeTab == AppTab.home;
    final isAccount = activeTab == AppTab.account;

    return SizedBox(
      height: 92,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.topCenter,
        children: [
          Positioned.fill(
            top: 12,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: AppColors.background,
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 16, offset: const Offset(0, -4))],
              ),
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, 0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _NavItem(
                        icon: isHome ? Icons.home_rounded : Icons.home_outlined,
                        label: 'nav.home'.tr(),
                        isActive: isHome,
                        onTap: isHome ? null : () => context.go('/home'),
                      ),
                      _NavItem(
                        icon: Icons.inventory_2_outlined,
                        label: 'nav.bookings'.tr(),
                        onTap: () => _openOrders(context, ref),
                      ),
                      const SizedBox(width: 56),
                      _NavItem(
                        icon: Icons.location_on_outlined,
                        label: 'nav.track'.tr(),
                        onTap: () => _openOrders(context, ref, filter: 'active'),
                      ),
                      _NavItem(
                        icon: isAccount ? Icons.person_rounded : Icons.person_outline_rounded,
                        label: 'nav.account'.tr(),
                        isActive: isAccount,
                        onTap: isAccount ? null : () => _openAccount(context, ref),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          GestureDetector(
            onTap: () => context.push('/booking'),
            child: Container(
              height: 56,
              width: 56,
              decoration: BoxDecoration(
                color: AppColors.primary,
                shape: BoxShape.circle,
                boxShadow: [BoxShadow(color: AppColors.primary.withValues(alpha: 0.4), blurRadius: 12, offset: const Offset(0, 4))],
              ),
              child: const Icon(Icons.add_rounded, color: Colors.white, size: 28),
            ),
          ),
        ],
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({required this.icon, required this.label, this.isActive = false, this.onTap});

  final IconData icon;
  final String label;
  final bool isActive;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final color = isActive ? AppColors.primaryDark : AppColors.textSecondary;
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 24),
        const SizedBox(height: 2),
        Text(label, style: TextStyle(fontSize: 11, color: color, fontWeight: isActive ? FontWeight.w600 : FontWeight.w400)),
      ],
    );

    if (onTap == null) return content;
    return GestureDetector(onTap: onTap, child: content);
  }
}
