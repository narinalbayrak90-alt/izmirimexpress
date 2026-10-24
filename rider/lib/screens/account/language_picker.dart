import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';

/// The app's supported locales, in the order they're offered — display
/// name is hardcoded in its own language (not run through `.tr()`) so a
/// rider who can't read the current locale can still recognize their own
/// language in the list, same convention most apps use for language pickers.
const _supportedLocales = [
  (locale: Locale('tr'), label: 'Türkçe'),
  (locale: Locale('en'), label: 'English'),
  (locale: Locale('es'), label: 'Español'),
  (locale: Locale('ar'), label: 'العربية'),
];

/// The current locale's own display name — used by the Account tab's
/// Language menu tile so the rider can see their selection without
/// opening the picker.
String currentLanguageLabel(BuildContext context) {
  final current = context.locale.languageCode;
  return _supportedLocales.firstWhere((entry) => entry.locale.languageCode == current).label;
}

/// Bottom sheet for picking the app's language — persisted automatically
/// by [EasyLocalization] (`saveLocale` defaults to true) so the choice
/// survives a restart, and switches text direction for Arabic
/// automatically since [MaterialApp.router] derives `Directionality`
/// from the active locale.
Future<void> showLanguagePicker(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (sheetContext) {
      final current = sheetContext.locale.languageCode;

      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: AppSpacing.sm),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              child: Text(
                'account.language'.tr(),
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            for (final entry in _supportedLocales)
              ListTile(
                title: Text(entry.label),
                trailing: entry.locale.languageCode == current
                    ? const Icon(Icons.check_rounded, color: AppColors.primaryDark)
                    : null,
                onTap: () {
                  sheetContext.setLocale(entry.locale);
                  Navigator.of(sheetContext).pop();
                },
              ),
            const SizedBox(height: AppSpacing.sm),
          ],
        ),
      );
    },
  );
}
