import 'package:easy_localization/easy_localization.dart';

/// Data shown on the [WelcomeScreen], sourced from `GET /welcome`.
///
/// `title`/`description` fall back to a built-in default whenever the admin
/// hasn't configured them yet (backend returns `''`), so a freshly
/// installed backend still renders a presentable screen instead of blank
/// text — required by project.txt's "graceful fallback" rule.
class WelcomeContent {
  const WelcomeContent({
    this.imageUrl,
    required this.title,
    required this.description,
  });

  final String? imageUrl;
  final String title;
  final String description;

  factory WelcomeContent.fromJson(Map<String, dynamic> json) {
    final title = (json['title'] as String?)?.trim();
    final description = (json['description'] as String?)?.trim();

    return WelcomeContent(
      imageUrl: json['image'] as String?,
      title: (title == null || title.isEmpty) ? 'welcome.default_title'.tr() : title,
      description: (description == null || description.isEmpty)
          ? 'welcome.default_description'.tr()
          : description,
    );
  }

  /// Used when the API is unreachable (e.g. backend not configured yet)
  /// so the screen still renders instead of showing an error state.
  WelcomeContent.fallback()
      : imageUrl = null,
        title = 'welcome.default_title'.tr(),
        description = 'welcome.default_description'.tr();
}
