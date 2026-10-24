import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

/// Checks whether a newer APK has been published and offers it.
///
/// The rider app isn't on Google Play, so nothing updates it for us: every
/// build CI publishes (see `.github/workflows/rider-apk.yml`) uploads the
/// APK plus a small `version.json` to the repo's latest GitHub release, and
/// this compares that build number with the one baked into this APK at
/// build time (`--dart-define=BUILD_NUMBER=...`). A local `flutter run`
/// has no build number, so it never prompts.
///
/// The update installs from inside the app: the APK downloads with a
/// progress bar and goes straight to Android's installer (MainActivity's
/// `izmirim/updates` channel), no browser or GitHub page involved.
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
      // Plain text, decoded here: GitHub serves release assets as
      // application/octet-stream, which Dio wouldn't parse as JSON itself.
      final response = await _dio.get<String>(
        _versionUrl,
        queryParameters: {'t': DateTime.now().millisecondsSinceEpoch},
        options: Options(responseType: ResponseType.plain, receiveTimeout: const Duration(seconds: 10)),
      );
      final data = jsonDecode(response.data ?? '');
      if (data is! Map) return null;
      final build = (data['build'] as num?)?.toInt() ?? 0;
      final url = data['url'] as String?;
      return build > currentBuild && url != null && url.isNotEmpty ? url : null;
    } catch (_) {
      return null;
    }
  }

  bool _checking = false;
  DateTime? _lastCheck;

  /// Shows the "new version" dialog over [context] when there is one. Runs
  /// at launch and whenever the app comes back to the foreground, at most
  /// once every few minutes and never with a dialog already open.
  Future<void> promptIfOutdated(BuildContext Function() context) async {
    final now = DateTime.now();
    if (_checking || (_lastCheck != null && now.difference(_lastCheck!) < const Duration(minutes: 3))) return;
    _checking = true;
    _lastCheck = now;
    try {
      await _prompt(context);
    } finally {
      _checking = false;
    }
  }

  Future<void> _prompt(BuildContext Function() context) async {
    final url = await newerApkUrl();
    if (url == null) return;
    final dialogContext = context();
    if (!dialogContext.mounted) return;

    await showDialog<void>(
      context: dialogContext,
      barrierDismissible: false,
      builder: (context) => _UpdateDialog(url: url, dio: _dio),
    );
  }
}

const _channel = MethodChannel('izmirim/updates');

enum _Stage { offer, downloading, ready, failed }

/// The "new version" dialog: offer → download with progress → install.
/// Stays open after handing the APK to the installer, so a rider who first
/// has to allow installs from this app can come back and tap Install again.
class _UpdateDialog extends StatefulWidget {
  const _UpdateDialog({required this.url, required this.dio});

  final String url;
  final Dio dio;

  @override
  State<_UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<_UpdateDialog> {
  _Stage _stage = _Stage.offer;
  double? _progress;
  String? _apkPath;
  bool _needsPermission = false;
  CancelToken? _cancel;

  @override
  void dispose() {
    _cancel?.cancel();
    super.dispose();
  }

  Future<void> _download() async {
    setState(() {
      _stage = _Stage.downloading;
      _progress = null;
    });
    try {
      final dir = await _channel.invokeMethod<String>('updatesDir');
      final path = '$dir/izmirim-kurye.apk';
      _cancel = CancelToken();
      await widget.dio.download(
        widget.url,
        path,
        cancelToken: _cancel,
        deleteOnError: true,
        onReceiveProgress: (received, total) {
          if (!mounted || total <= 0) return;
          setState(() => _progress = received / total);
        },
      );
      if (!mounted) return;
      setState(() {
        _apkPath = path;
        _stage = _Stage.ready;
      });
      await _install();
    } catch (_) {
      if (mounted) setState(() => _stage = _Stage.failed);
    }
  }

  Future<void> _install() async {
    final path = _apkPath;
    if (path == null) return;
    try {
      final outcome = await _channel.invokeMethod<String>('install', {'path': path});
      if (mounted) setState(() => _needsPermission = outcome == 'needs_permission');
    } catch (_) {
      if (mounted) setState(() => _stage = _Stage.failed);
    }
  }

  void _openInBrowser() {
    Navigator.of(context).pop();
    launchUrl(Uri.parse(widget.url), mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final close = TextButton(onPressed: () => Navigator.of(context).pop(), child: Text('update.later'.tr()));

    return switch (_stage) {
      _Stage.offer => AlertDialog(
          title: Text('update.title'.tr()),
          content: Text('update.message'.tr()),
          actions: [close, FilledButton(onPressed: _download, child: Text('update.download'.tr()))],
        ),
      _Stage.downloading => AlertDialog(
          title: Text('update.downloading'.tr()),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              LinearProgressIndicator(value: _progress),
              const SizedBox(height: 12),
              Text(_progress == null ? '' : '%${(_progress! * 100).round()}', textAlign: TextAlign.end),
            ],
          ),
          actions: [close],
        ),
      _Stage.ready => AlertDialog(
          title: Text('update.ready_title'.tr()),
          content: Text(_needsPermission ? 'update.permission_message'.tr() : 'update.ready_message'.tr()),
          actions: [close, FilledButton(onPressed: _install, child: Text('update.install'.tr()))],
        ),
      _Stage.failed => AlertDialog(
          title: Text('update.failed_title'.tr()),
          content: Text('update.failed_message'.tr()),
          actions: [
            TextButton(onPressed: _openInBrowser, child: Text('update.open_browser'.tr())),
            FilledButton(onPressed: _download, child: Text('common.retry'.tr())),
          ],
        ),
    };
  }
}
