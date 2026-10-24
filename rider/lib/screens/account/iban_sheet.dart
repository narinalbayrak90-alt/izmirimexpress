import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/app_providers.dart';
import '../../services/api_exception.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../utils/iban.dart';
import '../home/home_provider.dart';

/// Bottom sheet for the rider's payout IBAN (Account > IBAN details, and
/// the withdraw dialog when none is set). The admin panel edits the same
/// fields on the rider's page. Resolves to true once saved.
Future<bool> showIbanSheet(BuildContext context, {String? iban, String? holder}) async {
  final saved = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _IbanSheet(iban: iban, holder: holder),
  );
  return saved ?? false;
}

class _IbanSheet extends ConsumerStatefulWidget {
  const _IbanSheet({this.iban, this.holder});

  final String? iban;
  final String? holder;

  @override
  ConsumerState<_IbanSheet> createState() => _IbanSheetState();
}

class _IbanSheetState extends ConsumerState<_IbanSheet> {
  final _formKey = GlobalKey<FormState>();
  late final _ibanController = TextEditingController(text: widget.iban == null ? '' : formatIban(widget.iban!));
  late final _holderController = TextEditingController(text: widget.holder ?? '');
  bool _saving = false;

  @override
  void dispose() {
    _ibanController.dispose();
    _holderController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _saving = true);
    try {
      await ref.read(riderAuthServiceProvider).updateIban(
            iban: normalizeIban(_ibanController.text),
            holder: _holderController.text.trim(),
          );
      ref.invalidate(riderProfileProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('iban.saved'.tr())));
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.lg,
        0,
        AppSpacing.lg,
        MediaQuery.of(context).viewInsets.bottom + AppSpacing.lg,
      ),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('iban.title'.tr(), style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text('iban.subtitle'.tr(), style: const TextStyle(fontSize: 13, color: AppColors.textSecondary, height: 1.4)),
            const SizedBox(height: AppSpacing.md),
            IbanFields(ibanController: _ibanController, holderController: _holderController, required: true),
            const SizedBox(height: AppSpacing.lg),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: Text('iban.save'.tr()),
            ),
          ],
        ),
      ),
    );
  }
}

/// The IBAN and account holder fields, shared by the sheet and signup.
class IbanFields extends StatelessWidget {
  const IbanFields({super.key, required this.ibanController, required this.holderController, required this.required});

  final TextEditingController ibanController;
  final TextEditingController holderController;
  final bool required;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextFormField(
          controller: ibanController,
          textCapitalization: TextCapitalization.characters,
          keyboardType: TextInputType.visiblePassword,
          autocorrect: false,
          decoration: InputDecoration(
            labelText: 'iban.iban_label'.tr(),
            hintText: 'TR00 0000 0000 0000 0000 0000 00',
            prefixIcon: const Icon(Icons.account_balance_outlined),
          ),
          validator: (value) {
            final text = value?.trim() ?? '';
            if (text.isEmpty) return required ? 'iban.iban_required'.tr() : null;
            return isValidTrIban(text) ? null : 'iban.iban_invalid'.tr();
          },
        ),
        const SizedBox(height: AppSpacing.md),
        TextFormField(
          controller: holderController,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(
            labelText: 'iban.holder_label'.tr(),
            prefixIcon: const Icon(Icons.person_outline_rounded),
          ),
          validator: (value) {
            final hasIban = ibanController.text.trim().isNotEmpty;
            if ((required || hasIban) && (value == null || value.trim().length < 3)) return 'iban.holder_required'.tr();
            return null;
          },
        ),
      ],
    );
  }
}
