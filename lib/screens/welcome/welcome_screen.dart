import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../providers/app_providers.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_loader.dart';
import '../../widgets/primary_button.dart';
import 'welcome_content.dart';
import 'welcome_provider.dart';

/// First screen shown on a fresh app install: image/illustration, title,
/// description and a "Get Started" CTA, sourced from `GET /welcome`
/// ([welcomeContentProvider]). Tapping "Get Started" persists a
/// one-time-seen flag (see [buildRouter]'s redirect) so this screen never
/// shows again after the first launch, and navigates to `/home`.
class WelcomeScreen extends ConsumerWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final welcomeContent = ref.watch(welcomeContentProvider);

    return welcomeContent.when(
      data: (content) => _WelcomeView(content: content),
      loading: () => const Scaffold(body: Center(child: AppLoader())),
      // Backend unreachable/not configured yet — fall back to built-in
      // defaults rather than leaving the buyer with a blank/error screen.
      error: (_, _) => _WelcomeView(content: WelcomeContent.fallback()),
    );
  }
}

class _WelcomeView extends ConsumerWidget {
  const _WelcomeView({required this.content});

  final WelcomeContent content;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            children: [
              const Spacer(flex: 2),
              _Illustration(imageUrl: content.imageUrl),
              const Spacer(flex: 2),
              Text(
                content.title,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 12),
              Text(
                content.description,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: AppColors.textSecondary),
              ),
              const Spacer(flex: 3),
              PrimaryButton(
                label: 'welcome.get_started'.tr(),
                icon: Icons.arrow_forward_rounded,
                onPressed: () async {
                  await ref.read(onboardingStorageProvider).markWelcomeSeen();
                  if (context.mounted) context.go('/home');
                },
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}

class _Illustration extends StatelessWidget {
  const _Illustration({this.imageUrl});

  final String? imageUrl;

  @override
  Widget build(BuildContext context) {
    if (imageUrl == null || imageUrl!.isEmpty) {
      return const _PlaceholderIllustration();
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Image.network(
        imageUrl!,
        width: double.infinity,
        height: 320,
        fit: BoxFit.contain,
        loadingBuilder: (context, child, progress) {
          if (progress == null) return child;
          return const SizedBox(
            height: 320,
            width: double.infinity,
            child: Center(child: AppLoader()),
          );
        },
        // Broken/unreachable image URL — fall back to the built-in
        // illustration instead of showing Flutter's default error icon.
        errorBuilder: (context, error, stackTrace) => const _PlaceholderIllustration(),
      ),
    );
  }
}

class _PlaceholderIllustration extends StatelessWidget {
  const _PlaceholderIllustration();

  @override
  Widget build(BuildContext context) {
    // Built-in placeholder illustration so the screen renders without
    // requiring a design asset or admin-configured image.
    return SizedBox(
      height: 260,
      width: 260,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            height: 260,
            width: 260,
            decoration: const BoxDecoration(
              color: AppColors.surfaceMuted,
              shape: BoxShape.circle,
            ),
          ),
          Container(
            height: 190,
            width: 190,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
          ),
          Container(
            height: 140,
            width: 140,
            decoration: BoxDecoration(
              color: AppColors.primary,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.35),
                  blurRadius: 24,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: const Icon(
              Icons.local_shipping_rounded,
              color: Colors.white,
              size: 64,
            ),
          ),
        ],
      ),
    );
  }
}
