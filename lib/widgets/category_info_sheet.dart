import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../screens/home/home_category.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';

/// Shows a category's description in a bottom sheet before the booking
/// starts from the home grid (which skips the category step, where the
/// description is otherwise shown). True when the customer continues.
/// Categories without a description go straight through.
Future<bool> confirmCategory(BuildContext context, HomeCategory category) async {
  if (category.description == null) return true;
  final go = await showModalBottomSheet<bool>(
    context: context,
    backgroundColor: AppColors.background,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    constraints: const BoxConstraints(maxWidth: 480),
    builder: (context) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, AppSpacing.md),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                SizedBox(
                  width: 44,
                  height: 44,
                  child: (category.iconUrl != null && category.iconUrl!.isNotEmpty)
                      ? Image.network(
                          category.iconUrl!,
                          fit: BoxFit.contain,
                          cacheWidth: 192,
                          errorBuilder: (context, error, stackTrace) =>
                              const Icon(Icons.inventory_2_outlined, color: AppColors.primaryDark),
                        )
                      : const Icon(Icons.inventory_2_outlined, color: AppColors.primaryDark),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    category.name,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              category.description!,
              style: const TextStyle(fontSize: 14, height: 1.45, color: AppColors.textSecondary),
            ),
            const SizedBox(height: AppSpacing.lg),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('common.continue'.tr()),
                  const SizedBox(width: 8),
                  const Icon(Icons.arrow_forward_rounded, size: 18),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
  return go ?? false;
}
