import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/app_providers.dart';
import '../screens/home/home_provider.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';

/// Lets screens know they're inside the desktop layout, where the
/// [ResponsiveShell] header replaces the phone's bottom nav.
class DesktopLayoutScope extends InheritedWidget {
  const DesktopLayoutScope({super.key, required super.child});

  static bool of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<DesktopLayoutScope>() != null;

  @override
  bool updateShouldNotify(DesktopLayoutScope oldWidget) => false;
}

/// Keeps a full-width action button (Continue, Place Order) at a button's
/// width on desktop instead of a bar spanning the whole page.
class DesktopActionWidth extends StatelessWidget {
  const DesktopActionWidth({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!DesktopLayoutScope.of(context)) return child;
    return Center(
      child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 420), child: child),
    );
  }
}

/// Wraps every route (via `MaterialApp.builder`) so the app fits the screen
/// it runs on:
///
/// - Phone: untouched.
/// - Tablet / narrow window: the phone layout, centered at phone width —
///   screens are laid out for a phone (full-width buttons, edge-to-edge
///   cards), and stretched across a wide window they turn into huge bars.
/// - Desktop: a regular website — a top header with the navigation and a
///   centered content area whose width suits the page (narrow for forms,
///   wide for the home page and maps).
///
/// [MediaQuery] is narrowed to the content area in both framed layouts, so
/// widgets that size themselves from the screen width (sheets, carousels,
/// dialogs) see the frame, not the window.
class ResponsiveShell extends ConsumerStatefulWidget {
  const ResponsiveShell({super.key, required this.child});

  final Widget child;

  static const double phoneMaxWidth = 480;
  static const double desktopMinWidth = 900;

  @override
  ConsumerState<ResponsiveShell> createState() => _ResponsiveShellState();
}

class _ResponsiveShellState extends ConsumerState<ResponsiveShell> {
  late final GoRouter _router = ref.read(routerProvider);

  @override
  void initState() {
    super.initState();
    // The shell sits above the Navigator, so it follows route changes to
    // size the content area and highlight the active header link.
    _router.routerDelegate.addListener(_onRouteChanged);
  }

  @override
  void dispose() {
    _router.routerDelegate.removeListener(_onRouteChanged);
    super.dispose();
  }

  void _onRouteChanged() {
    if (mounted) setState(() {});
  }

  /// The top route's location — the pushed one, not the stack's base.
  String get _path {
    if (_router.routerDelegate.currentConfiguration.isEmpty) return '/';
    return _router.state.matchedLocation;
  }

  /// Content width for the current page on desktop.
  double _contentWidthFor(String path) {
    const wide = 1120.0;
    const medium = 760.0;
    const narrow = 520.0;

    if (path == '/home' || path == '/booking/pickup' || path == '/booking/dropoff') return wide;
    if (RegExp(r'^/orders/\d+$').hasMatch(path)) return wide;
    if (const ['/', '/login', '/signup', '/forgot-password', '/otp-verify'].contains(path)) return narrow;
    return medium;
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final width = mediaQuery.size.width;

    if (width <= ResponsiveShell.phoneMaxWidth) return widget.child;

    if (width < ResponsiveShell.desktopMinWidth) {
      return _FramedContent(width: ResponsiveShell.phoneMaxWidth, height: mediaQuery.size.height, child: widget.child);
    }

    final path = _path;
    final theme = Theme.of(context);
    return DesktopLayoutScope(
      child: Theme(
        // Phone-sized 52px buttons look oversized on a desktop page.
        data: theme.copyWith(
          elevatedButtonTheme: ElevatedButtonThemeData(
            style: theme.elevatedButtonTheme.style?.copyWith(
              minimumSize: const WidgetStatePropertyAll(Size.fromHeight(46)),
            ),
          ),
        ),
        child: ColoredBox(
          color: AppColors.frameBackdrop,
          child: Column(
            children: [
              _DesktopHeader(router: _router, path: path),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    const verticalMargin = AppSpacing.lg;
                    final contentWidth = _contentWidthFor(path).clamp(0.0, constraints.maxWidth - 2 * AppSpacing.lg);
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: verticalMargin),
                      child: _FramedContent(
                        width: contentWidth,
                        height: constraints.maxHeight - 2 * verticalMargin,
                        borderRadius: 20,
                        child: widget.child,
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FramedContent extends StatelessWidget {
  const _FramedContent({required this.width, required this.height, required this.child, this.borderRadius = 0});

  final double width;
  final double height;
  final double borderRadius;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    return ColoredBox(
      color: AppColors.frameBackdrop,
      child: Center(
        child: Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(borderRadius),
            boxShadow: const [BoxShadow(color: Color(0x1F000000), blurRadius: 24)],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(borderRadius),
            child: MediaQuery(
              data: mediaQuery.copyWith(
                size: Size(width, height),
                padding: EdgeInsets.zero,
                viewPadding: EdgeInsets.zero,
              ),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

class _DesktopHeader extends ConsumerWidget {
  const _DesktopHeader({required this.router, required this.path});

  final GoRouter router;
  final String path;

  /// Same guest gate as the phone's bottom nav: pages that need an account
  /// send a guest to log in first.
  Future<void> _openAuthed(WidgetRef ref, String location, {Object? extra}) async {
    final token = await ref.read(secureStorageProvider).readToken();
    if (token == null || token.isEmpty) {
      router.push('/login');
      return;
    }
    router.go(location, extra: extra);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(appSettingsProvider).valueOrNull;
    final logoUrl = settings?.appLogoUrl;
    final appName = settings?.appName ?? 'app_name'.tr();

    return Material(
      color: AppColors.background,
      elevation: 1,
      shadowColor: Colors.black26,
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: 72,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1120),
              // The header links never take keyboard focus: the first one
              // otherwise stays highlighted after every page change.
              child: ExcludeFocus(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                  child: Row(
                    children: [
                      InkWell(
                        canRequestFocus: false,
                        onTap: () => router.go('/home'),
                        borderRadius: BorderRadius.circular(12),
                        child: Padding(
                          padding: const EdgeInsets.all(AppSpacing.xs),
                          child: Row(
                            children: [
                              Container(
                                height: 40,
                                width: 40,
                                decoration: BoxDecoration(
                                  color: AppColors.primary,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                clipBehavior: Clip.antiAlias,
                                child: logoUrl != null && logoUrl.isNotEmpty
                                    ? Image.network(
                                        logoUrl,
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, _, _) => const _LogoIcon(),
                                      )
                                    : const _LogoIcon(),
                              ),
                              const SizedBox(width: AppSpacing.sm),
                              Text(
                                appName,
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const Spacer(),
                      _HeaderLink(label: 'nav.home'.tr(), isActive: path == '/home', onTap: () => router.go('/home')),
                      _HeaderLink(
                        label: 'nav.bookings'.tr(),
                        isActive: path == '/orders' || path.startsWith('/orders/'),
                        onTap: () => _openAuthed(ref, '/orders', extra: {'filter': 'all'}),
                      ),
                      _HeaderLink(
                        label: 'notifications.title'.tr(),
                        isActive: path == '/notifications',
                        onTap: () => _openAuthed(ref, '/notifications'),
                      ),
                      _HeaderLink(
                        label: 'nav.account'.tr(),
                        isActive: path.startsWith('/account'),
                        onTap: () => _openAuthed(ref, '/account'),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      FilledButton.icon(
                        onPressed: () => router.go('/booking'),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: AppColors.textPrimary,
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                        ),
                        icon: const Icon(Icons.add_rounded, size: 20),
                        label: Text('booking.new_booking'.tr()),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LogoIcon extends StatelessWidget {
  const _LogoIcon();

  @override
  Widget build(BuildContext context) => const Icon(Icons.local_shipping_rounded, color: Colors.white, size: 22);
}

class _HeaderLink extends StatelessWidget {
  const _HeaderLink({required this.label, required this.isActive, required this.onTap});

  final String label;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
      child: TextButton(
        onPressed: onTap,
        style: TextButton.styleFrom(
          foregroundColor: isActive ? AppColors.primaryDark : AppColors.textSecondary,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          textStyle: TextStyle(fontSize: 15, fontWeight: isActive ? FontWeight.w700 : FontWeight.w500),
        ),
        child: Text(label),
      ),
    );
  }
}
