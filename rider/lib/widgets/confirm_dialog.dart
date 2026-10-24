import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

/// A plain title/message confirm-or-cancel dialog — shared by every
/// order action that shouldn't fire on a single accidental tap (Accept,
/// Release, ...). Returns true only if the rider explicitly confirmed;
/// dismissing the dialog any other way (back button, tap outside) counts
/// as cancelling.
Future<bool> confirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(false), child: Text('common.cancel'.tr())),
        TextButton(onPressed: () => Navigator.of(context).pop(true), child: Text(confirmLabel)),
      ],
    ),
  );
  return confirmed == true;
}
