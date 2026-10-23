import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/app_providers.dart';
import '../../services/app_settings.dart';
import '../../services/order_status.dart';
import 'home_category.dart';

/// `GET /home`'s full payload: categories plus the app-wide settings block
/// (project.txt Module 1 — "all the setting data load on homepage API and
/// save in localstorage so we can use that in entire app like currency,
/// language etc."). Fetched once and cached via [SettingsStorageService] as
/// a side effect, so [appSettingsProvider] can read it back synchronously.
class HomeData {
  const HomeData({required this.categories, required this.settings});

  final List<HomeCategory> categories;
  final AppSettings settings;
}

final homeDataProvider = FutureProvider<HomeData>((ref) async {
  final data = await ref.watch(apiClientProvider).get('/home') as Map<String, dynamic>;

  final categories = (data['categories'] as List<dynamic>? ?? [])
      .map((json) => HomeCategory.fromJson(json as Map<String, dynamic>))
      .toList();
  final settings = AppSettings.fromJson(data['settings'] as Map<String, dynamic>? ?? {});

  await ref.read(settingsStorageProvider).save(settings);

  return HomeData(categories: categories, settings: settings);
});

/// Categories shown on the home screen — kept as its own provider so
/// existing screens don't need to know about [HomeData].
final homeCategoriesProvider = FutureProvider<List<HomeCategory>>((ref) async {
  return (await ref.watch(homeDataProvider.future)).categories;
});

/// App-wide settings for use anywhere in the app (signup's country code
/// list, currency formatting, etc.). Falls back to whatever was cached on
/// the last successful `/home` fetch — or [AppSettings.fallback] if nothing
/// is cached yet — so screens don't hard-fail when offline.
final appSettingsProvider = FutureProvider<AppSettings>((ref) async {
  try {
    return (await ref.watch(homeDataProvider.future)).settings;
  } catch (_) {
    return ref.read(settingsStorageProvider).read() ?? const AppSettings.fallback();
  }
});

/// How many active orders the Home screen's carousel shows at once — just
/// a taste, not the full list (that's what My Orders' Active tab is for).
const _activeOrdersCarouselLimit = 5;

/// The logged-in customer's in-progress orders, for the Home screen's
/// active-orders carousel — empty (rather than an error) for a guest, same
/// as the rest of the app's guest-browsing rule. `autoDispose` so it
/// re-fetches fresh each time Home mounts instead of holding a stale list.
final activeOrdersProvider = FutureProvider.autoDispose<List<OrderListItem>>((ref) async {
  final token = await ref.watch(secureStorageProvider).readToken();
  if (token == null || token.isEmpty) return [];
  final page = await ref.watch(orderServiceProvider).getOrders(page: 1, filter: 'active');
  return page.items.take(_activeOrdersCarouselLimit).toList();
});
