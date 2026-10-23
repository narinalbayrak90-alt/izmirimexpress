import 'package:flutter/services.dart';

/// Turkish phone numbers as typed by a customer — "0532 123 45 67",
/// "532 123 45 67" or "+90 532 ..." — reduced to the 10-digit national
/// number (5321234567). The backend accepts the same forms and stores them
/// as +905321234567 (see PlaceOrderRequest).
class TrPhone {
  TrPhone._();

  static String digits(String input) {
    var digits = input.replaceAll(RegExp(r'\D'), '');
    if (digits.length > 10 && digits.startsWith('90')) digits = digits.substring(2);
    if (digits.startsWith('0')) digits = digits.substring(1);
    return digits;
  }

  /// Landline (2xx/3xx/4xx) or mobile (5xx) national number.
  static bool isValid(String input) => RegExp(r'^[2-5]\d{9}$').hasMatch(digits(input));

  /// "+905321234567", or null when [input] isn't a complete number.
  static String? toE164(String input) => isValid(input) ? '+90${digits(input)}' : null;

  /// "532 123 45 67" — how the number is shown while typing.
  static String format(String nationalDigits) {
    final d = nationalDigits;
    final buffer = StringBuffer();
    for (var i = 0; i < d.length; i++) {
      if (i == 3 || i == 6 || i == 8) buffer.write(' ');
      buffer.write(d[i]);
    }
    return buffer.toString();
  }
}

/// Keeps a phone field to at most 10 national digits, spaced as
/// "5XX XXX XX XX". A leading 0 or +90 typed or pasted by the customer is
/// dropped, since the field already shows +90 as its prefix.
class TrPhoneInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    var digits = TrPhone.digits(newValue.text);
    if (digits.length > 10) digits = digits.substring(0, 10);
    final text = TrPhone.format(digits);
    return TextEditingValue(text: text, selection: TextSelection.collapsed(offset: text.length));
  }
}
