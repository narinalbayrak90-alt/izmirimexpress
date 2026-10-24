import 'package:flutter/material.dart';
import 'package:loading_animation_widget/loading_animation_widget.dart';

import '../theme/app_colors.dart';

/// The app's loading indicator — a staggered dots wave, used everywhere a
/// spinner is needed (full-page loads, pull-to-refresh/pagination, button
/// submit state) so every loading state in the app looks the same and a
/// future style change only means editing this one widget.
class AppLoader extends StatelessWidget {
  const AppLoader({super.key, this.size = 40, this.color});

  /// Defaults to [AppColors.primaryDark]; pass an explicit color when the
  /// loader sits on a background that needs a different one (e.g. white on
  /// the primary-yellow button background).
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return LoadingAnimationWidget.staggeredDotsWave(
      color: color ?? AppColors.primaryDark,
      size: size,
    );
  }
}
