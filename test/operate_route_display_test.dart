import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:authenticav/logic/app_state.dart';
import 'package:authenticav/models/device_model.dart';
import 'package:authenticav/modules/operate_module.dart';

const _stale =
    "Routed to a source that's no longer on the network – choose a source "
    'again';

Device _device(String id, String name, DeviceType type, String ip) => Device(
  id: id,
  name: name,
  ip: ip,
  type: type,
  status: DeviceStatus.online,
  location: 'Lobby',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final state = AppState.instance;
  late Device tx;
  late Device rx;

  setUp(() {
    tx = _device('TX1', 'Lobby Source', DeviceType.tx, '169.254.10.20');
    rx = _device('RX1', 'Lobby Screen', DeviceType.rx, '169.254.54.160');
    state.sources.add(tx);
    state.destinationsByLocation['Lobby'] = [rx];
  });

  tearDown(() {
    state.sources.clear();
    state.destinationsByLocation.clear();
    state.activeRoutes.clear();
  });

  // The test font draws every letter as a wide square, so the existing Operate
  // header needs a roomy screen to fit; real fonts are much narrower.
  Future<void> show(WidgetTester tester) {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(1600, 1200);
    addTearDown(tester.view.reset);
    return tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: OperateModule())),
    );
  }

  testWidgets('a screen routed by channel says so, next to its source', (
    tester,
  ) async {
    state.activeRoutes['RX1'] = 'TX1';
    rx.selected = '0032';
    await show(tester);
    expect(find.text('Lobby Screen'), findsOneWidget);
    expect(find.text('Lobby Source'), findsWidgets);
    expect(find.text('by channel 0032'), findsOneWidget);
    expect(find.text(_stale), findsNothing);
  });

  testWidgets('a screen routed the old way (by IP) shows no channel', (
    tester,
  ) async {
    state.activeRoutes['RX1'] = 'TX1';
    rx.selected = '169.254.10.20';
    await show(tester);
    expect(find.text('Lobby Source'), findsWidgets);
    expect(find.textContaining('by channel'), findsNothing);
  });

  testWidgets('a route to a source that is gone asks for a new source', (
    tester,
  ) async {
    // The app may still remember the old source; the box says otherwise.
    state.activeRoutes['RX1'] = 'TX1';
    rx
      ..selected = '192.168.168.209'
      ..staleRoute = true;
    await show(tester);
    expect(find.text(_stale), findsOneWidget);
    expect(find.text('None'), findsOneWidget);
    // Nothing is shown as the source it is "routed" to.
    expect(find.text('Lobby Source'), findsNothing);
    expect(find.textContaining('by channel'), findsNothing);
  });

  testWidgets('a screen with no route shows neither note', (tester) async {
    await show(tester);
    expect(find.text('None'), findsOneWidget);
    expect(find.text(_stale), findsNothing);
    expect(find.textContaining('by channel'), findsNothing);
  });
}
