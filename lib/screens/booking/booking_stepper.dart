import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';

/// The 5-step progress indicator shown at the top of the booking flow
/// (Category -> Pickup -> Drop-off -> Summary -> Payment).
class BookingStepper extends StatelessWidget {
  const BookingStepper({super.key, required this.currentStep});

  final int currentStep;

  static const _steps = [
    (icon: Icons.inventory_2_rounded, labelKey: 'booking.step_category'),
    (icon: Icons.local_shipping_outlined, labelKey: 'booking.step_pickup'),
    (icon: Icons.flag_outlined, labelKey: 'booking.step_dropoff'),
    (icon: Icons.verified_outlined, labelKey: 'booking.step_summary'),
    (icon: Icons.payment_rounded, labelKey: 'booking.step_payment'),
  ];

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < _steps.length; i++) ...[
          if (i > 0) Expanded(child: _StepConnector(isActive: i <= currentStep)),
          _StepDot(icon: _steps[i].icon, label: _steps[i].labelKey.tr(), isActive: i <= currentStep),
        ],
      ],
    );
  }
}

class _StepDot extends StatelessWidget {
  const _StepDot({required this.icon, required this.label, required this.isActive});

  final IconData icon;
  final String label;
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          height: 44,
          width: 44,
          decoration: BoxDecoration(
            color: isActive ? AppColors.primary : AppColors.background,
            shape: BoxShape.circle,
            border: Border.all(color: isActive ? AppColors.primary : AppColors.border, width: 1.5),
          ),
          child: Icon(icon, size: 20, color: isActive ? Colors.white : AppColors.textSecondary),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: isActive ? AppColors.textPrimary : AppColors.textSecondary,
            fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ],
    );
  }
}

class _StepConnector extends StatelessWidget {
  const _StepConnector({required this.isActive});

  final bool isActive;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 21, left: 4, right: 4),
      child: CustomPaint(
        size: const Size(double.infinity, 2),
        painter: _DashedLinePainter(color: isActive ? AppColors.primary : AppColors.border),
      ),
    );
  }
}

class _DashedLinePainter extends CustomPainter {
  _DashedLinePainter({required this.color});

  final Color color;
  static const _dashWidth = 4.0;
  static const _dashGap = 3.0;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;

    var x = 0.0;
    while (x < size.width) {
      canvas.drawLine(Offset(x, 1), Offset(x + _dashWidth, 1), paint);
      x += _dashWidth + _dashGap;
    }
  }

  @override
  bool shouldRepaint(covariant _DashedLinePainter oldDelegate) => oldDelegate.color != color;
}
