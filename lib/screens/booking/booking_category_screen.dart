import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../widgets/app_loader.dart';
import '../../widgets/responsive_shell.dart';
import '../home/home_category.dart';
import '../home/home_provider.dart';
import '../welcome/welcome_provider.dart';
import 'booking_providers.dart';
import 'booking_stepper.dart';

/// Step 1 of the booking flow ("New Booking"): pick a parcel category.
///
/// Reuses [homeCategoriesProvider] (same `GET /home` data as the home
/// screen) rather than fetching categories again. Pickup/Drop-off/Summary
/// (Module 4/5) don't exist yet, so "Continue" has nowhere to go — it's
/// wired up as a TODO once those steps are built.
class BookingCategoryScreen extends ConsumerStatefulWidget {
  const BookingCategoryScreen({super.key});

  @override
  ConsumerState<BookingCategoryScreen> createState() =>
      _BookingCategoryScreenState();
}

class _BookingCategoryScreenState extends ConsumerState<BookingCategoryScreen> {
  int? _selectedCategoryId;

  @override
  Widget build(BuildContext context) {
    final categories = ref.watch(homeCategoriesProvider);

    return Scaffold(
      appBar: AppBar(title: Text('booking.new_booking'.tr())),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Expanded(
              // Category count is dynamic, so the last item (the safe-
              // delivery banner) isn't guaranteed to fully fit above the
              // fixed Continue bar. Fading the bottom edge instead of
              // letting it get sliced flat makes that read as "more below,
              // scroll for it" rather than a rendering glitch.
              child: ShaderMask(
                shaderCallback: (rect) => const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.black, Colors.black, Colors.transparent],
                  stops: [0.0, 0.94, 1.0],
                ).createShader(rect),
                blendMode: BlendMode.dstIn,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.md,
                    AppSpacing.md,
                    AppSpacing.md,
                    AppSpacing.xl,
                  ),
                  children: [
                    const BookingStepper(currentStep: 0),
                    const SizedBox(height: AppSpacing.xl),
                    Text(
                      'booking.category_title'.tr(),
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'booking.category_subtitle'.tr(),
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    categories.when(
                      data: (items) {
                        if (items.isEmpty) return const SizedBox.shrink();
                        // Default-select the first category, matching the
                        // reference design's initial state.
                        _selectedCategoryId ??= items.first.id;
                        // A Wrap (rather than GridView) so a fixed-size card
                        // renders at its natural width regardless of row
                        // count, left-aligned like a regular grid.
                        return LayoutBuilder(
                          builder: (context, constraints) {
                            // 3 columns on a phone; on wider screens as many
                            // as fit at about 120px, with square cards, so
                            // they stay card-sized.
                            final columns = ((constraints.maxWidth + AppSpacing.sm) / (120 + AppSpacing.sm))
                                .floor()
                                .clamp(3, 8);
                            final aspectRatio = columns > 3 ? 1.0 : 0.85;
                            final cardWidth =
                                (constraints.maxWidth -
                                    AppSpacing.sm * (columns - 1)) /
                                columns;
                            return Wrap(
                              alignment: WrapAlignment.start,
                              spacing: AppSpacing.sm,
                              runSpacing: AppSpacing.sm,
                              children: [
                                for (final category in items)
                                  SizedBox(
                                    width: cardWidth,
                                    height: cardWidth / aspectRatio,
                                    child: _CategorySelectCard(
                                      category: category,
                                      isSelected:
                                          category.id == _selectedCategoryId,
                                      onTap: () => setState(
                                        () => _selectedCategoryId = category.id,
                                      ),
                                    ),
                                  ),
                              ],
                            );
                          },
                        );
                      },
                      loading: () => const SizedBox(
                        height: 200,
                        child: Center(child: AppLoader()),
                      ),
                      error: (error, stackTrace) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
                        child: Text(
                          'booking.categories_load_error'.tr(),
                          style: const TextStyle(color: AppColors.textSecondary),
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    const _SafeDeliveryBanner(),
                  ],
                ),
              ),
            ),
            DecoratedBox(
              decoration: BoxDecoration(
                color: AppColors.background,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 16,
                    offset: const Offset(0, -4),
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md,
                  AppSpacing.md,
                  AppSpacing.md,
                  AppSpacing.sm,
                ),
                child: Column(
                  children: [
                    DesktopActionWidth(
                      child: SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _selectedCategoryId == null
                              ? null
                              : () {
                                  final items = categories.asData?.value;
                                  if (items == null) return;
                                  HomeCategory? selected;
                                  for (final item in items) {
                                    if (item.id == _selectedCategoryId) {
                                      selected = item;
                                      break;
                                    }
                                  }
                                  if (selected == null) return;
  
                                  final draft = ref.read(bookingDraftProvider);
                                  ref.read(bookingDraftProvider.notifier).state = draft.copyWith(
                                    category: selected,
                                  );
                                  context.push('/booking/pickup');
                                },
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text('common.continue'.tr()),
                              const SizedBox(width: 8),
                              const Icon(Icons.arrow_forward_rounded, size: 18),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.lock_outline_rounded,
                          size: 14,
                          color: AppColors.textSecondary,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'booking.data_secure'.tr(),
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CategorySelectCard extends StatelessWidget {
  const _CategorySelectCard({
    required this.category,
    required this.isSelected,
    required this.onTap,
  });

  final HomeCategory category;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(
          vertical: AppSpacing.sm,
          horizontal: AppSpacing.xs,
        ),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.heroBackground : AppColors.background,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? AppColors.primary : AppColors.border,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  height: 40,
                  width: 40,
                  child:
                      (category.iconUrl != null && category.iconUrl!.isNotEmpty)
                      ? Image.network(
                          category.iconUrl!,
                          fit: BoxFit.contain,
                          cacheWidth: 256,
                          errorBuilder: (context, error, stackTrace) =>
                              const Icon(
                                Icons.inventory_2_outlined,
                                color: AppColors.primaryDark,
                              ),
                        )
                      : const Icon(
                          Icons.inventory_2_outlined,
                          color: AppColors.primaryDark,
                        ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  category.name,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
            if (isSelected)
              Positioned(
                top: -4,
                right: -4,
                child: Container(
                  height: 20,
                  width: 20,
                  decoration: const BoxDecoration(
                    color: AppColors.primary,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.check_rounded,
                    size: 14,
                    color: Colors.white,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SafeDeliveryBanner extends ConsumerWidget {
  const _SafeDeliveryBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Reuses the same admin-managed illustration as the welcome/home
    // screens — there's no dedicated "safe delivery" illustration asset.
    final imageUrl = ref.watch(welcomeContentProvider).asData?.value.imageUrl;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.infoBackground,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          Container(
            height: 40,
            width: 40,
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.check_circle_rounded,
              color: AppColors.accent,
              size: 24,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'booking.safe_delivery_title'.tr(),
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'booking.safe_delivery_subtitle'.tr(),
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          if (imageUrl != null && imageUrl.isNotEmpty) ...[
            const SizedBox(width: AppSpacing.sm),
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.network(
                imageUrl,
                height: 56,
                width: 56,
                cacheWidth: 192,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) =>
                    const SizedBox.shrink(),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
