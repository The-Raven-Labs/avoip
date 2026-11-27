import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:authenticav/config/api_config.dart';
import 'package:authenticav/logic/app_state.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final state = AppState.instance;
  late HttpServer server;
  late int status;
  final alerts = <AppAlert>[];
  late StreamSubscription<AppAlert> sub;

  setUp(() async {
    // The test binding answers every HTTP request with 400; use real HTTP
    // to reach the fake controller below.
    HttpOverrides.global = null;
    state.resetControllerLinkForTesting();
    alerts.clear();
    sub = state.alerts.listen(alerts.add);
    status = 200;
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    ApiConfig.useForTesting('127.0.0.1', testPort: server.port);
    server.listen((req) async {
      req.response.statusCode = status;
      req.response.write(jsonEncode([]));
      await req.response.close();
    });
  });

  tearDown(() async {
    await sub.cancel();
    await server.close(force: true);
  });

  Future<void> refresh() async {
    await state.refreshDevices(minInterval: Duration.zero);
    await Future<void>.delayed(Duration.zero);
  }

  test('the SC-1 is "lost" only after two misses, then reconnects', () async {
    await refresh();
    expect(state.controllerLink.value, ControllerLink.connected);
    expect(state.lastControllerContact, isNotNull);

    status = 500; // the SC-1 stops answering
    await refresh();
    // One miss could be a dropped packet: no alarm yet.
    expect(state.controllerLink.value, ControllerLink.connected);
    expect(alerts, isEmpty);

    await refresh();
    expect(state.controllerLink.value, ControllerLink.lost);
    expect(alerts.single.title, 'SC-1 not responding');
    expect(alerts.single.isError, isTrue);

    await refresh(); // still down: no second alarm
    expect(alerts, hasLength(1));

    status = 200; // it's back
    await refresh();
    expect(state.controllerLink.value, ControllerLink.connected);
    expect(alerts.last.title, 'Reconnected to the SC-1');
    expect(alerts.last.isError, isFalse);
  });

  test('a single failed read does not raise an alarm', () async {
    await refresh();
    status = 500;
    await refresh();
    status = 200;
    await refresh();
    expect(state.controllerLink.value, ControllerLink.connected);
    expect(alerts, isEmpty);
  });
}
