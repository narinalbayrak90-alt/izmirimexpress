import 'package:dio/dio.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Checks whether a newer APK has been published and offers it.
///
/// The rider app isn't on Google Play, so nothing updates it for us: every
/// build CI publishes (see `.github/workflows/rider-apk.yml`) uploads the
/// APK plus a small `version.json` to the repo's latest GitHub release, and
/// this compares that build number with the one baked into this APK at
/// build time (`--dart-define=BUILD_NUMBER=...`). A local `flutter run`
/// has no build number, so it never prompts.
class AppUpdateService {
  AppUpdateService({Dio? dio}) : _dio = dio ?? Dio();

  static const currentBuild = int.fromEnvironment('BUILD_NUMBER');

  static const _versionUrl =
      'https://github.com/narinalbayrak90-alt/izmirimexpress/releases/latest/download/version.json';

  final Dio _dio;

  /// The newer release's APK link, or null when this build is current (or
  /// the check fails — an update prompt is never worth an error).
  Future<String?> newerApkUrl() async {
    if (currentBuild == 0) return null;
    try {
      final response = await _dio.get<dynamic>(
        _versionUrl,
        options: Options(responseType: ResponseType.json, receiveTimeout: const Duration(seconds: 10)),
      );
      final data = response.data;
      if (data is! Map) return null;
      final build = (data['build'] as num?)?.toInt() ?? 0;
      final url = data['url'] as String?;
      return build > currentBuild && url != null && url.isNotEmpty ? url : null;
    } catch (_) {
      return null;
    }
  }

  /// Shows the "new version" dialog over [context] when there is one.
  Future<void> promptIfOutdated(BuildContext Function() context) async {
    final url = await newerApkUrl();
    if (url == null) return;
    final dialogContext = context();
    if (!dialogContext.mounted) return;

    await showDialog<void>(
      context: dialogContext,
      builder: (context) => AlertDialog(
        title: Text('update.title'.tr()),
        content: Text('update.message'.tr()),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: Text('update.later'.tr())),
          FilledButton(
            onPressed: () {
              Navigator.of(context).pop();
              launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
            },
            child: Text('update.download'.tr()),
          ),
        ],
      ),
    );
  }
}
