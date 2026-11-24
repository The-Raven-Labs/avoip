import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:authenticav/config/api_config.dart';
import 'package:authenticav/services/switch_service.dart';
import 'package:authenticav/widgets/switch_status_card.dart';

// A real reply from the office SC-1 (2026-11-18).
const _officeReply = '''{
  "configured": true, "driver": "netgear_m4250", "host": "192.168.168.86",
  "vlan": 1, "state": "ok", "message": null,
  "igmp": {"snooping": true, "vlan_snooping": true, "querier": true,
           "vlan_querier": true, "querier_role": "Non-Querier"},
  "checked_at": "2026-11-18T09:51:07+00:00", "changed_at": null
}''';

String _reply(String state, {String? message, bool configured = true}) =>
    jsonEncode({
      'configured': configured,
      'driver': 'netgear_m4250',
      'host': '192.168.168.86',
      'state': state,
      'message': message,
    });

Widget _card(
  SwitchStatus status, {
  bool checking = false,
  VoidCallback? onCheck,
}) => MaterialApp(
  home: Scaffold(
    body: SingleChildScrollView(
      child: SwitchStatusCard(
        status: status,
        checking: checking,
        onCheckNow: onCheck,
      ),
    ),
  ),
);

void main() {
  group('parsing', () {
    test('reads the office reply', () {
      final s = SwitchService.parse(_officeReply);
      expect(s.configured, isTrue);
      expect(s.state, SwitchState.ok);
      expect(s.displayName, 'Netgear M4250');
      expect(s.host, '192.168.168.86');
      expect(s.vlan, 1);
      expect(s.message, isNull);
      expect(s.igmp!.snooping, isTrue);
      expect(s.igmp!.vlanSnooping, isTrue);
      expect(s.igmp!.querier, isTrue);
      expect(s.igmp!.vlanQuerier, isTrue);
      expect(s.igmp!.querierRole, 'Non-Querier');
      // Shown to the installer in local time; it's the same instant.
      expect(s.checkedAt!.toUtc(), DateTime.utc(2026, 11, 18, 9, 51, 7));
      expect(s.checkedAt!.isUtc, isFalse);
      expect(s.changedAt, isNull);
    });

    test('maps every documented state', () {
      const expected = {
        'not_configured': SwitchState.notConfigured,
        'pending': SwitchState.pending,
        'ok': SwitchState.ok,
        'enabled': SwitchState.enabled,
        'unsaved': SwitchState.unsaved,
        'unverified': SwitchState.unverified,
        'failed': SwitchState.failed,
        'unreachable': SwitchState.unreachable,
        'auth_failed': SwitchState.authFailed,
        'needs_password': SwitchState.needsPassword,
      };
      expected.forEach((raw, state) {
        expect(SwitchService.parse(_reply(raw)).state, state, reason: raw);
      });
    });

    test('a state from a newer controller is unknown, not a crash', () {
      expect(
        SwitchService.parse(_reply('rebooting')).state,
        SwitchState.unknown,
      );
    });

    test('a unit with no switch is "not configured"', () {
      final s = SwitchService.parse('{"configured": false}');
      expect(s.state, SwitchState.notConfigured);
      expect(SwitchStatusCard.shouldShow(s), isFalse);
    });

    test('tolerates missing optional fields', () {
      final s = SwitchService.parse('{"configured": true, "state": "pending"}');
      expect(s.displayName, 'Network switch');
      expect(s.igmp, isNull);
      expect(s.checkedAt, isNull);
    });

    test('unreadable replies become a clear error', () {
      for (final body in ['not json', '[1, 2]']) {
        expect(
          () => SwitchService.parse(body),
          throwsA(isA<ControllerApiException>()),
          reason: body,
        );
      }
    });

    test('only good states count as good', () {
      expect(SwitchState.ok.isGood, isTrue);
      expect(SwitchState.enabled.isGood, isTrue);
      expect(SwitchState.unsaved.isGood, isFalse);
      expect(SwitchState.pending.isGood, isFalse);
    });
  });

  group('against a fake controller', () {
    late HttpServer server;
    late int status;
    late String body;
    final requests = <String>[];

    setUp(() async {
      HttpOverrides.global = null;
      requests.clear();
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      ApiConfig.useForTesting('127.0.0.1', testPort: server.port);
      server.listen((req) async {
        requests.add('${req.method} ${req.uri.path}');
        req.response.statusCode = status;
        req.response.write(body);
        await req.response.close();
      });
    });

    tearDown(() => server.close(force: true));

    test('fetch reads GET /api/v1/switch', () async {
      status = 200;
      body = _officeReply;
      final s = await SwitchService.fetch();
      expect(s.state, SwitchState.ok);
      expect(requests, ['GET /api/v1/switch']);
    });

    test(
      'checkNow posts to /api/v1/switch/igmp and returns its result',
      () async {
        status = 200;
        body = _reply('enabled');
        final s = await SwitchService.checkNow();
        expect(s.state, SwitchState.enabled);
        expect(requests, ['POST /api/v1/switch/igmp']);
      },
    );

    test(
      'checkNow falls back to the stored result if the reply has none',
      () async {
        status = 200;
        body = '{}';
        await SwitchService.checkNow();
        expect(requests, ['POST /api/v1/switch/igmp', 'GET /api/v1/switch']);
      },
    );

    test(
      'an older controller without the switch API is reported as such',
      () async {
        status = 404;
        body = '{"detail": "Not Found"}';
        await expectLater(
          SwitchService.fetch(),
          throwsA(
            isA<ControllerApiException>()
                .having((e) => e.unsupported, 'unsupported', isTrue)
                .having(
                  (e) => e.message,
                  'message',
                  contains('network switch'),
                ),
          ),
        );
      },
    );

    test("the controller's own error is shown", () async {
      status = 500;
      body = '{"detail": "switch driver crashed"}';
      await expectLater(
        SwitchService.fetch(),
        throwsA(
          isA<ControllerApiException>().having(
            (e) => e.message,
            'message',
            'switch driver crashed',
          ),
        ),
      );
    });

    test('an unreachable controller gives a clear message', () async {
      await server.close(force: true);
      await expectLater(
        SwitchService.fetch(),
        throwsA(
          isA<ControllerApiException>().having(
            (e) => e.message,
            'message',
            contains("Couldn't reach the controller"),
          ),
        ),
      );
    });
  });

  group('the card', () {
    testWidgets('ok: good news, with the IGMP settings, and no message', (
      tester,
    ) async {
      await tester.pumpWidget(_card(SwitchService.parse(_officeReply)));
      expect(find.text('Network switch'), findsOneWidget);
      expect(find.text('Netgear M4250 · 192.168.168.86'), findsOneWidget);
      expect(find.text('Multicast (IGMP) is set up correctly'), findsOneWidget);
      expect(find.text('IGMP snooping'), findsOneWidget);
      expect(find.text('On'), findsOneWidget);
      expect(find.text('On · Non-Querier'), findsOneWidget);
    });

    testWidgets('every state except ok shows the controller message', (
      tester,
    ) async {
      const headlines = {
        'enabled': 'The SC-1 just turned IGMP on',
        'unsaved': 'On, but not saved on the switch yet; will retry',
        'unverified': "Couldn't read every setting",
        'failed': "Couldn't set up the switch",
        'unreachable': "Can't reach the switch",
        'auth_failed': 'The switch rejected the password',
        'needs_password': 'The switch wants a new password',
      };
      for (final entry in headlines.entries) {
        await tester.pumpWidget(
          _card(
            SwitchService.parse(
              _reply(entry.key, message: 'detail for ${entry.key}'),
            ),
          ),
        );
        expect(
          find.textContaining(entry.value),
          findsOneWidget,
          reason: entry.key,
        );
        expect(
          find.text('detail for ${entry.key}'),
          findsOneWidget,
          reason: entry.key,
        );
      }
    });

    testWidgets('ok never shows a message, even if the controller sends one', (
      tester,
    ) async {
      await tester.pumpWidget(
        _card(SwitchService.parse(_reply('ok', message: 'ignore me'))),
      );
      expect(find.text('ignore me'), findsNothing);
    });

    testWidgets('pending says it is checking', (tester) async {
      await tester.pumpWidget(_card(SwitchService.parse(_reply('pending'))));
      expect(find.text('Checking the switch...'), findsOneWidget);
    });

    testWidgets('not configured: nothing is drawn', (tester) async {
      await tester.pumpWidget(
        _card(SwitchService.parse(_reply('not_configured', configured: false))),
      );
      expect(find.text('Network switch'), findsNothing);
    });

    testWidgets('Check now calls back, and is disabled while checking', (
      tester,
    ) async {
      var taps = 0;
      final status = SwitchService.parse(_officeReply);
      await tester.pumpWidget(_card(status, onCheck: () => taps++));
      await tester.tap(find.text('Check now'));
      expect(taps, 1);

      await tester.pumpWidget(
        _card(status, checking: true, onCheck: () => taps++),
      );
      expect(find.text('Checking...'), findsOneWidget);
      await tester.tap(find.text('Checking...'), warnIfMissed: false);
      expect(taps, 1);
    });

    testWidgets('there is no password field', (tester) async {
      await tester.pumpWidget(
        _card(SwitchService.parse(_reply('needs_password'))),
      );
      expect(find.byType(TextField), findsNothing);
    });

    testWidgets('querier reported off while snooping is on', (tester) async {
      final status = SwitchService.parse(
        jsonEncode({
          'configured': true,
          'state': 'unverified',
          'igmp': {'snooping': true, 'vlan_snooping': false, 'querier': false},
        }),
      );
      await tester.pumpWidget(_card(status));
      expect(find.text('Partly on'), findsOneWidget);
      expect(find.text('Off'), findsOneWidget);
    });
  });
}
