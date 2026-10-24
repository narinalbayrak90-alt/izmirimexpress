/// Turkish IBAN helpers, matching the backend's App\Rules\Iban: TR plus
/// 24 digits with a valid ISO 13616 check number.
library;

String normalizeIban(String input) => input.replaceAll(RegExp(r'[\s-]+'), '').toUpperCase();

bool isValidTrIban(String input) {
  final iban = normalizeIban(input);
  if (!RegExp(r'^TR\d{24}$').hasMatch(iban)) return false;

  // Move the first four characters to the end, letters to numbers
  // (A=10 … Z=35), and the result mod 97 must be 1.
  final rearranged = iban.substring(4) + iban.substring(0, 4);
  var rest = 0;
  for (final unit in rearranged.codeUnits) {
    final value = unit >= 65 ? '${unit - 55}' : String.fromCharCode(unit);
    for (final digit in value.codeUnits) {
      rest = (rest * 10 + digit - 48) % 97;
    }
  }
  return rest == 1;
}

/// TR12 3456 7890 … for showing on screen.
String formatIban(String iban) {
  final clean = normalizeIban(iban);
  final groups = <String>[];
  for (var i = 0; i < clean.length; i += 4) {
    groups.add(clean.substring(i, i + 4 > clean.length ? clean.length : i + 4));
  }
  return groups.join(' ');
}
