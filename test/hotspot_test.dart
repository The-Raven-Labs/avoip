import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:authenticav/config/api_config.dart';
import 'package:authenticav/services/controller_discovery.dart';

FoundController _found(String ip, {String? hostname, String name = 'SC-1'}) =>
    FoundController(
      name: name,
      hostname: hostname,
      ip: ip,
      addresses: [ip],
      port: 8000,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late HttpServer server;
  var healthy = true;

  setUp(() async {
    // The test binding answers every HTTP request with 400; use real HTTP
    // to reach the fake controller below.
    HttpOverrides.global = null;
    healthy = true;
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    ApiConfig.useForTesting('127.0.0.1', testPort: server.port);
    server.listen((req) async {
      expect(req.uri.path, '/health');
      req.response.statusCode = healthy ? 200 : 503;
      req.response.write(jsonEncode({'status': healthy ? 'ok' : 'down'}));
      await req.response.close();
    });
  });

  tearDown(() => server.close(force: true));

  group('hotspot address', () {
    test(
      'is used when the phone is on the SC-1 Wi-Fi and it answers',
      () async {
        // The fake controller stands in for 192.168.50.1.
        ApiConfig.useHotspotForTesting(
          phoneOnHotspot: true,
          address: '127.0.0.1',
        );
        expect(await ApiConfig.reachableHotspot(), '127.0.0.1');
      },
    );

    test('is not tried when the phone is on another network', () async {
      ApiConfig.useHotspotForTesting(
        phoneOnHotspot: false,
        address: '127.0.0.1',
      );
      expect(await ApiConfig.reachableHotspot(), isNull);
    });

    test('is not used when nothing answers /health there', () async {
      healthy = false;
      ApiConfig.useHotspotForTesting(
        phoneOnHotspot: true,
        address: '127.0.0.1',
      );
      expect(await ApiConfig.reachableHotspot(), isNull);
    });

    test('is 192.168.50.1 unless a test changes it', () {
      expect(ApiConfig.hotspotIp, '192.168.50.1');
    });
  });

  group('reachable controllers', () {
    // 203.0.113.0/24 is reserved for documentation: nothing answers there.
    const nowhere = '203.0.113.7';

    test('lists a controller once, at the address that answers', () async {
      final result = await ApiConfig.reachable([
        _found(nowhere, hostname: 'SC1-2063'),
        _found('127.0.0.1', hostname: 'SC1-2063'),
        _found('169.254.12.9', hostname: 'SC1-2063'),
      ]);
      expect(result.map((c) => c.ip), ['127.0.0.1']);
    });

    test('keeps different controllers apart', () async {
      final result = await ApiConfig.reachable([
        _found('127.0.0.1', hostname: 'SC1-2063'),
        _found('127.0.0.1', hostname: 'SC1-9999'),
      ]);
      expect(result.map((c) => c.hostname), ['SC1-2063', 'SC1-9999']);
    });

    test(
      'returns everything when none answers, so the error can be shown',
      () async {
        healthy = false;
        final announced = [_found('127.0.0.1', hostname: 'SC1-2063')];
        expect(await ApiConfig.reachable(announced), announced);
      },
    );
  });
}
