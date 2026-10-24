import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/app_providers.dart';
import '../../services/api_exception.dart';
import '../../services/rider_cash_deposit_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../widgets/app_loader.dart';
import '../home/home_provider.dart';

/// Shows the company IBAN and lets the rider report a transfer of the COD
/// cash they hold. The report waits for the office's approval before it
/// lowers the cash in hand. Pops `true` after a successful report.
class IbanDepositDialog extends ConsumerStatefulWidget {
  const IbanDepositDialog({super.key, required this.info});

  final CashDepositInfo info;

  @override
  ConsumerState<IbanDepositDialog> createState() => _IbanDepositDialogState();
}

class _IbanDepositDialogState extends ConsumerState<IbanDepositDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _amountController;
  final _noteController = TextEditingController();
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    final reportable = widget.info.reportable;
    _amountController = TextEditingController(text: reportable > 0 ? reportable.toStringAsFixed(2) : '');
  }

  @override
  void dispose() {
    _amountController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _copyIban(String iban) async {
    await Clipboard.setData(ClipboardData(text: iban.replaceAll(' ', '')));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('earning.iban_copied'.tr())));
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final amount = double.parse(_amountController.text.trim().replaceAll(',', '.'));
    setState(() => _isSubmitting = true);
    try {
      await ref.read(riderCashDepositServiceProvider).reportIbanTransfer(amount, note: _noteController.text.trim());
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
    final iban = widget.info.iban!;

    return AlertDialog(
      title: Text('earning.iban_dialog_title'.tr()),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'earning.iban_dialog_hint'.tr(namedArgs: {'amount': currency.format(widget.info.reportable)}),
                style: const TextStyle(fontSize: 13, color: AppColors.textSecondary, height: 1.4),
              ),
              const SizedBox(height: AppSpacing.md),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(AppSpacing.sm),
                decoration: BoxDecoration(
                  color: AppColors.heroBackground,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (iban.accountHolder != null)
                      Text(iban.accountHolder!, style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                    if (iban.bankName != null)
                      Text(iban.bankName!, style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Expanded(
                          child: SelectableText(
                            iban.iban,
                            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: AppColors.textPrimary),
                          ),
                        ),
                        IconButton(
                          tooltip: 'earning.iban_copy'.tr(),
                          icon: const Icon(Icons.copy_rounded, size: 20, color: AppColors.primaryDark),
                          onPressed: () => _copyIban(iban.iban),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              TextFormField(
                controller: _amountController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: 'earning.iban_amount_label'.tr(),
                  prefixText: '${currency.currencySign} ',
                ),
                validator: (value) {
                  final amount = double.tryParse((value ?? '').trim().replaceAll(',', '.'));
                  if (amount == null || amount <= 0) return 'earning.withdraw_amount_error'.tr();
                  if (amount > widget.info.reportable + 0.001) return 'earning.iban_amount_exceeds_error'.tr();
                  return null;
                },
              ),
              const SizedBox(height: AppSpacing.sm),
              TextFormField(
                controller: _noteController,
                maxLength: 255,
                decoration: InputDecoration(labelText: 'earning.iban_note_label'.tr()),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(false),
          child: Text('common.cancel'.tr()),
        ),
        ElevatedButton(
          // Same reset as WithdrawDialog: the app-wide theme makes
          // ElevatedButtons full width.
          style: ElevatedButton.styleFrom(minimumSize: const Size(64, 40)),
          onPressed: _isSubmitting ? null : _submit,
          child: _isSubmitting
              ? const SizedBox(height: 20, width: 20, child: AppLoader(size: 18, color: AppColors.textPrimary))
              : Text('earning.iban_submit'.tr()),
        ),
      ],
    );
  }
}
