import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../providers/app_providers.dart';
import '../../services/api_exception.dart';
import '../../services/rider_auth_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../widgets/app_loader.dart';
import '../../widgets/primary_button.dart';

/// Verification-status screen for a rider whose account can't sign in yet
/// (project.txt Module 4 — admin approval gates the Rider App). Reached
/// right after signup, and from the Login screen whenever `POST
/// /rider/auth/login` is blocked for a pending/rejected/blocked account.
///
/// It re-checks `POST /rider/auth/status` on open and on every "Check
/// Again" tap, using the [identifier]/[password] passed through `extra` —
/// held only in memory for this screen, never stored. Once the account is
/// approved the rider is sent to Login to sign in for real.
class VerificationStatusScreen extends ConsumerStatefulWidget {
  const VerificationStatusScreen({super.key, required this.identifier, required this.password});

  final String identifier;
  final String password;

  @override
  ConsumerState<VerificationStatusScreen> createState() => _VerificationStatusScreenState();
}

class _VerificationStatusScreenState extends ConsumerState<VerificationStatusScreen> {
  RiderVerificationStatus? _status;
  bool _isChecking = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    setState(() {
      _isChecking = true;
      _error = null;
    });
    try {
      final result = await ref.read(riderAuthServiceProvider).checkStatus(
            identifier: widget.identifier,
            password: widget.password,
          );
      if (!mounted) return;
      setState(() {
        _status = result.status;
        _isChecking = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _isChecking = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.go('/login'),
        ),
        title: Text('verification.title'.tr()),
      ),
      body: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          child: _buildBody(context),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_isChecking && _status == null) {
      return const Center(child: AppLoader());
    }

    if (_error != null && _status == null) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline_rounded, color: AppColors.error, size: 48),
          const SizedBox(height: AppSpacing.md),
          Text(_error!, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyLarge),
          const SizedBox(height: AppSpacing.xl),
          PrimaryButton(label: 'common.retry'.tr(), onPressed: _check, isLoading: _isChecking),
          const SizedBox(height: AppSpacing.sm),
          TextButton(
            onPressed: () => context.go('/login'),
            child: Text('verification.back_to_login'.tr()),
          ),
        ],
      );
    }

    final visual = _visualFor(_status ?? RiderVerificationStatus.pending);

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          height: 96,
          width: 96,
          decoration: BoxDecoration(color: visual.background, shape: BoxShape.circle),
          child: Icon(visual.icon, color: visual.color, size: 52),
        ),
        const SizedBox(height: AppSpacing.lg),
        Text(
          visual.titleKey.tr(),
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: 12),
        Text(
          visual.messageKey.tr(),
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: AppColors.textSecondary, height: 1.5),
        ),
        const SizedBox(height: AppSpacing.xl),
        if ((_status ?? RiderVerificationStatus.pending).isApproved)
          PrimaryButton(
            label: 'verification.continue_to_login'.tr(),
            onPressed: () => context.go('/login'),
          )
        else ...[
          PrimaryButton(
            label: 'verification.check_again'.tr(),
            icon: Icons.refresh_rounded,
            onPressed: _check,
            isLoading: _isChecking,
          ),
          const SizedBox(height: AppSpacing.sm),
          TextButton(
            onPressed: () => context.go('/login'),
            child: Text('verification.back_to_login'.tr()),
          ),
        ],
      ],
    );
  }

  _StatusVisual _visualFor(RiderVerificationStatus status) {
    switch (status) {
      case RiderVerificationStatus.approved:
        return const _StatusVisual(
          icon: Icons.verified_rounded,
          color: AppColors.success,
          background: AppColors.successBackground,
          titleKey: 'verification.approved_title',
          messageKey: 'verification.approved_message',
        );
      case RiderVerificationStatus.rejected:
        return const _StatusVisual(
          icon: Icons.cancel_rounded,
          color: AppColors.error,
          background: AppColors.errorBackground,
          titleKey: 'verification.rejected_title',
          messageKey: 'verification.rejected_message',
        );
      case RiderVerificationStatus.blocked:
        return const _StatusVisual(
          icon: Icons.block_rounded,
          color: AppColors.error,
          background: AppColors.errorBackground,
          titleKey: 'verification.blocked_title',
          messageKey: 'verification.blocked_message',
        );
      case RiderVerificationStatus.pending:
        return const _StatusVisual(
          icon: Icons.hourglass_top_rounded,
          color: AppColors.primaryDark,
          background: AppColors.heroBackground,
          titleKey: 'verification.pending_title',
          messageKey: 'verification.pending_message',
        );
    }
  }
}

class _StatusVisual {
  const _StatusVisual({
    required this.icon,
    required this.color,
    required this.background,
    required this.titleKey,
    required this.messageKey,
  });

  final IconData icon;
  final Color color;
  final Color background;
  final String titleKey;
  final String messageKey;
}
