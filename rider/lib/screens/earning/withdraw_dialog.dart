import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/app_providers.dart';
import '../../services/api_exception.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../widgets/app_loader.dart';
import '../home/home_provider.dart';

/// Amount-entry dialog for the Earning tab's Withdraw action — capped at
/// [availableBalance], which the caller fetched right before opening this
/// (see HomeScreen's `_openWithdrawDialog`) so it reflects the rider's
/// current balance rather than a possibly-stale cached value. Pops `true`
/// on a successful submit so the caller knows to refresh the balance/list,
/// `false`/`null` otherwise.
class WithdrawDialog extends ConsumerStatefulWidget {
  const WithdrawDialog({super.key, required this.availableBalance});

  final double availableBalance;

  @override
  ConsumerState<WithdrawDialog> createState() => _WithdrawDialogState();
}

class _WithdrawDialogState extends ConsumerState<WithdrawDialog> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  bool _isSubmitting = false;

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final amount = double.parse(_amountController.text.trim());
    setState(() => _isSubmitting = true);
    try {
      await ref.read(riderWithdrawalServiceProvider).request(amount);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final currency = ref.watch(riderSettingsProvider).valueOrNull ?? const RiderSettings();

    return AlertDialog(
      title: Text('earning.withdraw_dialog_title'.tr()),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'earning.withdraw_available_balance'.tr(namedArgs: {'amount': currency.format(widget.availableBalance)}),
              style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
            const SizedBox(height: AppSpacing.md),
            TextFormField(
              controller: _amountController,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                prefixText: '${currency.currencySign} ',
                hintText: 'earning.withdraw_amount_hint'.tr(),
              ),
              validator: (value) {
                final amount = double.tryParse(value?.trim() ?? '');
                if (amount == null || amount <= 0) return 'earning.withdraw_amount_error'.tr();
                if (amount > widget.availableBalance) return 'earning.withdraw_amount_exceeds_error'.tr();
                return null;
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(false),
          child: Text('common.cancel'.tr()),
        ),
        ElevatedButton(
          // The app-wide ElevatedButton theme (see AppTheme) sets a
          // full-width minimumSize meant for screen-level primary buttons
          // — reset it here so this dialog action sizes to its content
          // like Cancel does, instead of stretching edge to edge.
          style: ElevatedButton.styleFrom(minimumSize: const Size(64, 40)),
          onPressed: _isSubmitting ? null : _submit,
          child: _isSubmitting
              ? const SizedBox(height: 20, width: 20, child: AppLoader(size: 18, color: AppColors.textPrimary))
              : Text('earning.withdraw_submit'.tr()),
        ),
      ],
    );
  }
}
