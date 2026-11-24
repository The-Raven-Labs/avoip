import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:authenticav/config/api_config.dart';
import 'package:authenticav/services/av_command_service.dart';

void main() {
  group('acked', () {
    test('needs success true in the body, not just HTTP 200', () {
      // What the controller returns when the box didn't respond.
      expect(
        AVCommandService.acked(
          http.Response(
            '{"success":false,"ack":"ConnectError: All connection attempts failed","duration_ms":30}',
            200,
          ),
        ),
        isFalse,
      );
      expect(
        AVCommandService.acked(
          http.Response('{"success":true,"ack":"","duration_ms":120}', 200),
        ),
        isTrue,
      );
    });

    test('fails on error statuses and unreadable bodies', () {
      expect(AVCommandService.acked(http.Response('{"success":true}', 500)), isFalse);
      expect(AVCommandService.acked(http.Response('not json', 200)), isFalse);
    });
  });

  group('failedReceivers', () {
    const rxIps = {'192.168.29.200', '192.168.29.213'};

    test('returns only the receivers the controller did not confirm', () {
      final response = http.Response('''{
        "results": [
          {"success": true, "ack": "", "duration_ms": 90, "device_ip": "192.168.29.200", "tx_ip": "192.168.29.187"},
          {"success": false, "ack": "ConnectError", "duration_ms": 30, "device_ip": "192.168.29.213", "tx_ip": "192.168.29.187"}
        ],
        "succeeded": 1,
        "failed": 1
      }''', 200);
      expect(AVCommandService.failedReceivers(rxIps, response), {'192.168.29.213'});
    });

    test('counts receivers missing from the results as failed', () {
      final response = http.Response(
        '{"results": [{"success": true, "device_ip": "192.168.29.200"}], "succeeded": 1, "failed": 0}',
        200,
      );
      expect(AVCommandService.failedReceivers(rxIps, response), {'192.168.29.213'});
    });

    test('treats a failed request as all receivers failing', () {
      expect(
        AVCommandService.failedReceivers(rxIps, http.Response('{"detail":"bad"}', 422)),
        rxIps,
      );
    });
  });

  group('target (what the receiver was pointed at)', () {
    test('is a channel, or the Tx IP when the channel could not be used', () {
      expect(
        AVCommandService.targetOf(
          http.Response('{"success":true,"ack":"OK","duration_ms":120,"target":"0032"}', 200),
        ),
        '0032',
      );
      expect(
        AVCommandService.targetOf(
          http.Response('{"success":true,"target":"169.254.10.20"}', 200),
        ),
        '169.254.10.20',
      );
    });

    test('is null from an older controller, or when empty', () {
      expect(
        AVCommandService.targetOf(http.Response('{"success":true,"ack":""}', 200)),
        isNull,
      );
      expect(
        AVCommandService.targetOf(http.Response('{"success":true,"target":""}', 200)),
        isNull,
      );
      expect(AVCommandService.targetOf(http.Response('not json', 200)), isNull);
    });

    test('is read per receiver from a batch, only for those that worked', () {
      final response = http.Response('''{
        "results": [
          {"success": true, "device_ip": "169.254.1.1", "tx_ip": "169.254.9.9", "target": "0032"},
          {"success": true, "device_ip": "169.254.1.2", "tx_ip": "169.254.9.9"},
          {"success": false, "device_ip": "169.254.1.3", "tx_ip": "169.254.9.9", "target": "0032"}
        ],
        "succeeded": 2, "failed": 1
      }''', 200);
      expect(AVCommandService.targetsByReceiver(response), {'169.254.1.1': '0032'});
      expect(
        AVCommandService.targetsByReceiver(http.Response('{"results": []}', 500)),
        isEmpty,
      );
    });
  });

  group('against a fake controller', () {
    late HttpServer server;
    final requests = <({String path, Object? body})>[];
    late Object reply;

    setUp(() async {
      HttpOverrides.global = null;
      requests.clear();
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      ApiConfig.useForTesting('127.0.0.1', testPort: server.port);
      server.listen((req) async {
        final raw = await utf8.decoder.bind(req).join();
        requests.add((path: req.uri.path, body: raw.isEmpty ? null : jsonDecode(raw)));
        req.response.write(jsonEncode(reply));
        await req.response.close();
      });
    });

    tearDown(() => server.close(force: true));

    test('routeVideo still sends the Tx IP and reports the channel', () async {
      reply = {'success': true, 'ack': 'OK', 'duration_ms': 120, 'target': '0032'};
      final result = await AVCommandService.routeVideo(
        txIp: '169.254.10.20',
        rxIp: '169.254.54.160',
      );
      expect(result.success, isTrue);
      expect(result.target, '0032');
      expect(requests.single.path, '/api/v1/commands/set');
      expect(requests.single.body, {
        'device_ip': '169.254.54.160',
        'tx_ip': '169.254.10.20',
      });
    });

    test('a failed route has no target', () async {
      reply = {'success': false, 'ack': 'ConnectError', 'target': '0032'};
      final result = await AVCommandService.routeVideo(txIp: '1.1.1.1', rxIp: '2.2.2.2');
      expect(result.success, isFalse);
      expect(result.target, isNull);
    });

    test('routeBatch reports failures and the target of each that worked', () async {
      reply = {
        'results': [
          {'success': true, 'device_ip': '10.0.0.1', 'target': '0032'},
          {'success': false, 'device_ip': '10.0.0.2'},
        ],
        'succeeded': 1,
        'failed': 1,
      };
      final result = await AVCommandService.routeBatch({
        '10.0.0.1': '10.0.0.9',
        '10.0.0.2': '10.0.0.9',
      });
      expect(result.failed, {'10.0.0.2'});
      expect(result.targets, {'10.0.0.1': '0032'});
      expect(requests.single.path, '/api/v1/commands/set/batch');
    });

    test('an unreachable controller fails every receiver', () async {
      await server.close(force: true);
      final single = await AVCommandService.routeVideo(txIp: '1.1.1.1', rxIp: '2.2.2.2');
      expect(single.success, isFalse);
      final batch = await AVCommandService.routeBatch({'2.2.2.2': '1.1.1.1'});
      expect(batch.failed, {'2.2.2.2'});
      expect(batch.targets, isEmpty);
    });
  });
}
