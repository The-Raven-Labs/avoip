import 'package:flutter_test/flutter_test.dart';

import 'package:authenticav/services/sc1_ble_setup.dart';

void main() {
  group('setup code from the SC-1 label', () {
    test('is sent without spaces or hyphens', () {
      expect(Sc1BleSetup.normalizeSetupCode('12345678'), '12345678');
      expect(Sc1BleSetup.normalizeSetupCode('1234 5678'), '12345678');
      expect(Sc1BleSetup.normalizeSetupCode('1234-5678'), '12345678');
      expect(Sc1BleSetup.normalizeSetupCode(' 1234 - 5678 \n'), '12345678');
    });

    test('keeps every other character exactly as typed', () {
      // Older units may use letters; never change case or drop characters.
      expect(Sc1BleSetup.normalizeSetupCode('aB3-x9'), 'aB3x9');
    });

    test('nothing typed stays empty', () {
      expect(Sc1BleSetup.normalizeSetupCode('  - '), isEmpty);
    });
  });
}
