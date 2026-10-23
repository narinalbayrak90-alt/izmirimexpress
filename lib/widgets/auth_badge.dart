import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Branded circular icon badge shared across the auth flow's headers
/// (login, signup, forgot password, OTP verification) for a consistent look.
class AuthBadge extends StatelessWidget {
  const AuthBadge({super.key, required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 72,
      width: 72,
      decoration: BoxDecoration(
        color: AppColors.primary,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.35),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Icon(icon, color: Colors.white, size: 32),
    );
  }
}
