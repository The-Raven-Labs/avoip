import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:authenticav/config/api_config.dart';
import 'package:authenticav/services/system_reset_service.dart';

void main() {
  late HttpServer server;
  final requests = <({String path, Object? body})>[];
  late Map<String, (int, Object)> replies;

  setUp(() async {
    requests.clear();
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    ApiConfig.useForTesting('127.0.0.1', testPort: server.port);
    server.listen((req) async {
      final raw = await utf8.decoder.bind(req).join();
      requests.add((path: req.uri.path, body: raw.isEmpty ? null : jsonDecode(raw)));
      final (status, body) = replies[req.uri.path] ?? (404, {'detail': 'Not Found'});
      req.response.statusCode = status;
      req.response.write(jsonEncode(body));
      await req.response.close();
    });
  });

  tearDown(() => server.close(force: true));

  test('prepare returns the one-time code and Wi-Fi capability', () async {
    replies = {
      '/api/v1/system/reset/prepare': (200, {'confirm_code': 'K7Q2', 'expires_in_seconds': 60, 'wifi_can_be_cleared': false}),
    };
    final prep = await SystemResetService.prepare();
    expect(prep.confirmCode, 'K7Q2');
    expect(prep.expiresInSeconds, 60);
    expect(prep.wifiCanBeCleared, isFalse);
  });

  test('reset sends the code and reports what was cleared', () async {
    replies = {
      '/api/v1/system/reset': (200, {'cleared': ['scenes', 'settings', 'devices'], 'wifi': 'scheduled'}),
    };
    final result = await SystemResetService.reset('K7Q2');
    expect(requests.single.path, '/api/v1/system/reset');
    expect(requests.single.body, {'confirm_code': 'K7Q2'});
    expect(result.cleared, ['scenes', 'settings', 'devices']);
    expect(result.leavesWifi, isTrue);
  });

  test('Wi-Fi kept when the unit does not allow clearing it', () async {
    replies = {'/api/v1/system/reset': (200, {'cleared': ['scenes'], 'wifi': 'not_permitted'})};
    final result = await SystemResetService.reset('K7Q2');
    expect(result.leavesWifi, isFalse);
    expect(result.wifi, 'not_permitted');
  });

  test('an expired or used code is recognised so the app can prepare again', () async {
    replies = {'/api/v1/system/reset': (403, {'detail': 'confirm_code_invalid'})};
    await expectLater(
      SystemResetService.reset('OLD1'),
      throwsA(predicate<ControllerApiException>(SystemResetService.isInvalidCode)),
    );
  });

  test('an older controller without reset needs an update', () async {
    replies = {};
    await expectLater(
      SystemResetService.prepare(),
      throwsA(isA<ControllerApiException>()
          .having((e) => e.unsupported, 'unsupported', isTrue)
          .having((e) => e.message, 'message', contains('factory reset'))),
    );
  });
}
