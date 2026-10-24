import 'package:flutter_test/flutter_test.dart';
import 'package:pickup_rider/utils/iban.dart';

void main() {
  test('accepts a valid TR IBAN with or without spaces', () {
    expect(isValidTrIban('TR330006100519786457841326'), isTrue);
    expect(isValidTrIban('tr33 0006 1005 1978 6457 8413 26'), isTrue);
  });

  test('rejects a wrong check number, length or country', () {
    expect(isValidTrIban('TR330006100519786457841327'), isFalse);
    expect(isValidTrIban('TR33000610051978645784132'), isFalse);
    expect(isValidTrIban('DE89370400440532013000'), isFalse);
  });

  test('formats in groups of four', () {
    expect(formatIban('TR330006100519786457841326'), 'TR33 0006 1005 1978 6457 8413 26');
  });
}
