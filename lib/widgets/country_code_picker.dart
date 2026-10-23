import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';

/// Translation keys for the country codes an admin is most likely to enable
/// (project.txt Module 1's app-setting default list) — purely cosmetic for
/// the picker sheet. A code the admin adds that isn't in this map still
/// works, it just shows as "+<code>" with no country name.
const Map<String, String> _countryNameKeys = {
  '91': 'country.india',
  '1': 'country.us_canada',
  '44': 'country.uk',
  '61': 'country.australia',
  '971': 'country.uae',
  '966': 'country.saudi_arabia',
  '65': 'country.singapore',
  '49': 'country.germany',
  '33': 'country.france',
  '86': 'country.china',
  '81': 'country.japan',
  '82': 'country.south_korea',
  '92': 'country.pakistan',
  '880': 'country.bangladesh',
  '234': 'country.nigeria',
  '27': 'country.south_africa',
  '20': 'country.egypt',
  '62': 'country.indonesia',
  '60': 'country.malaysia',
  '63': 'country.philippines',
  '55': 'country.brazil',
  '52': 'country.mexico',
  '34': 'country.spain',
  '39': 'country.italy',
  '31': 'country.netherlands',
  '64': 'country.new_zealand',
};

String countryName(String code) {
  final key = _countryNameKeys[code];
  return key == null ? 'country.unknown'.tr(namedArgs: {'code': code}) : key.tr();
}

/// Opens the country-code picker bottom sheet, shared by the Signup and
/// Personal Information screens (both collect a country code + phone).
void pickCountryCode(
  BuildContext context, {
  required List<String> countryCodes,
  required String selected,
  required ValueChanged<String> onSelect,
}) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (sheetContext) => CountryCodeSheet(
      countryCodes: countryCodes,
      selected: selected,
      onSelect: (code) {
        onSelect(code);
        Navigator.of(sheetContext).pop();
      },
    ),
  );
}

/// The "+91" tappable box shown in front of a phone number field, styled to
/// match the app's [InputDecorationTheme] (surfaceMuted fill, 12px radius)
/// even though it isn't itself a [TextFormField].
class CountryCodeField extends StatelessWidget {
  const CountryCodeField({super.key, required this.code, required this.onTap});

  final String code;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        height: 52,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: AppColors.surfaceMuted,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('+$code', style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
            const SizedBox(width: 4),
            const Icon(Icons.expand_more_rounded, size: 18, color: AppColors.textSecondary),
          ],
        ),
      ),
    );
  }
}

class CountryCodeSheet extends StatelessWidget {
  const CountryCodeSheet({super.key, required this.countryCodes, required this.selected, required this.onSelect});

  final List<String> countryCodes;
  final String selected;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'common.select_country_code'.tr(),
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
            ),
            const SizedBox(height: AppSpacing.sm),
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.5),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: countryCodes.length,
                itemBuilder: (context, index) {
                  final code = countryCodes[index];
                  final isSelected = code == selected;
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Text('+$code', style: const TextStyle(fontWeight: FontWeight.w700)),
                    title: Text(countryName(code)),
                    trailing: isSelected ? const Icon(Icons.check_circle_rounded, color: AppColors.success) : null,
                    onTap: () => onSelect(code),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
