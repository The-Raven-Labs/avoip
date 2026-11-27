import 'package:flutter_test/flutter_test.dart';

import 'package:authenticav/services/wifi_qr.dart';

void main() {
  group('the SC-1 label', () {
    test('reads the code printed on the label', () {
      final wifi =
          WifiQr.parse('WIFI:T:WPA;S:Authentic-SC1-2063;P:XXXX-XXXX-XXXX;;')!;
      expect(wifi.ssid, 'Authentic-SC1-2063');
      expect(wifi.password, 'XXXX-XXXX-XXXX');
      expect(wifi.security, 'WPA');
      expect(wifi.hidden, isFalse);
      expect(wifi.isOpen, isFalse);
      expect(wifi.isSc1Hotspot, isTrue);
    });

    test('only SC-1 hotspots pass the check, including the factory one', () {
      bool sc1(String ssid) => WifiQr(ssid: ssid, password: 'x').isSc1Hotspot;
      expect(sc1('Authentic-SC1'), isTrue); // older units
      expect(sc1('Authentic-SC1-2063'), isTrue);
      expect(sc1('Authentic-SC1-'), isFalse);
      expect(sc1('Authentic-SC1-abc'), isFalse);
      expect(sc1('Authentic-SC1-2063-guest'), isFalse);
      expect(sc1('Home Wi-Fi'), isFalse);
      expect(sc1('xAuthentic-SC1-2063'), isFalse);
    });
  });

  group('escapes', () {
    test(r'\ ; , : " in a name or password are unescaped', () {
      final wifi =
          WifiQr.parse(r'WIFI:T:WPA;S:My\;Net\:2;P:pa\\ss\:w\,o\"rd;;')!;
      expect(wifi.ssid, 'My;Net:2');
      expect(wifi.password, r'pa\ss:w,o"rd');
    });

    test('an escaped separator does not end a field', () {
      final wifi = WifiQr.parse(r'WIFI:S:a\;b;P:c\;d;;')!;
      expect(wifi.ssid, 'a;b');
      expect(wifi.password, 'c;d');
    });

    test('an escaped backslash right before the separator ends the field', () {
      final wifi = WifiQr.parse(r'WIFI:S:net;P:pass\\;T:WPA;;')!;
      expect(wifi.password, r'pass\');
      expect(wifi.security, 'WPA');
    });

    test('a backslash before any other character is kept', () {
      final wifi = WifiQr.parse(r'WIFI:S:net;P:a\b;;')!;
      expect(wifi.password, r'a\b');
    });

    test('a colon inside a value is fine', () {
      final wifi = WifiQr.parse('WIFI:S:lab:5G;P:a:b;;')!;
      expect(wifi.ssid, 'lab:5G');
      expect(wifi.password, 'a:b');
    });

    test('a quoted value is taken literally', () {
      final wifi = WifiQr.parse('WIFI:S:"1234";P:"abcd";;')!;
      expect(wifi.ssid, '1234');
      expect(wifi.password, 'abcd');
    });
  });

  group('variations', () {
    test('open network', () {
      final wifi = WifiQr.parse('WIFI:T:nopass;S:Guest;;')!;
      expect(wifi.isOpen, isTrue);
      expect(wifi.password, isNull);
    });

    test('hidden network', () {
      expect(WifiQr.parse('WIFI:S:net;P:pw;H:true;;')!.hidden, isTrue);
      expect(WifiQr.parse('WIFI:S:net;P:pw;H:false;;')!.hidden, isFalse);
    });

    test('fields in any order, prefix in any case, spaces around it', () {
      final wifi = WifiQr.parse('  wifi:P:pw;S:net;T:wpa2;;\n')!;
      expect(wifi.ssid, 'net');
      expect(wifi.password, 'pw');
      expect(wifi.security, 'WPA2');
    });

    test('without the closing ;;', () {
      expect(WifiQr.parse('WIFI:S:net;P:pw')!.password, 'pw');
    });

    test('a code that does not say the type still has its password', () {
      final wifi = WifiQr.parse('WIFI:S:net;P:pw;;')!;
      expect(wifi.security, '');
      expect(wifi.isOpen, isFalse);
    });
  });

  group('not usable', () {
    test('anything else is rejected', () {
      for (final payload in [
        '',
        'hello',
        'https://example.com',
        'WIFI',
        'WIFI:',
        'WIFI:T:WPA;P:pw;;', // no network name
        'WIFI:S:;P:pw;;', // empty network name
      ]) {
        expect(WifiQr.parse(payload), isNull, reason: payload);
      }
    });

    test('WPA-Enterprise needs more than a password', () {
      expect(WifiQr.parse('WIFI:T:WPA2-EAP;S:corp;;'), isNull);
      expect(WifiQr.parse('WIFI:T:WPA;S:corp;E:PEAP;I:user;P:pw;;'), isNull);
    });
  });

  test('the password is never printed', () {
    final wifi = WifiQr.parse('WIFI:T:WPA;S:Authentic-SC1-2063;P:SECRET-PW;;')!;
    expect(wifi.toString(), isNot(contains('SECRET-PW')));
    expect(wifi.toString(), contains('Authentic-SC1-2063'));
  });
}
