import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:authenticav/logic/app_state.dart';
import 'package:authenticav/models/device_model.dart';
import 'package:authenticav/modules/discovery_module.dart';

// Adopted device ids are the MAC without colons.
const _txMac = 'AA:AA:AA:AA:AA:01';
const _rxMac = 'AA:AA:AA:AA:AA:02';
const _txId = 'AAAAAAAAAA01';
const _rxId = 'AAAAAAAAAA02';

Device _device(String id, DeviceType type, String ip, DeviceStatus status) =>
    Device(
      id: id,
      name: id,
      ip: ip,
      type: type,
      status: status,
      location: 'Unassigned',
    );

DiscoveredDevice _listed(
  String mac,
  DeviceType type,
  String ip, {
  bool online = true,
  String? currentTxIp,
  String? selected,
}) => DiscoveredDevice(
  controllerId: 'ctrl-$mac',
  name: mac,
  ip: ip,
  mac: mac,
  signal: online ? 100 : 0,
  type: type,
  currentTxIp: currentTxIp,
  selected: selected,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final state = AppState.instance;
  late Device tx;
  late Device rx;

  setUp(() {
    tx = _device(_txId, DeviceType.tx, '192.168.29.187', DeviceStatus.online);
    rx = _device(_rxId, DeviceType.rx, '192.168.29.213', DeviceStatus.online);
    state.sources.add(tx);
    state.destinationsByLocation['Unassigned'] = [rx];
    state.activeRoutes[_rxId] = _txId;
  });

  tearDown(() {
    state.sources.clear();
    state.destinationsByLocation.clear();
    state.activeRoutes.clear();
  });

  test('status comes only from the list: a missing device is Offline', () {
    state.applyControllerDevices([
      _listed(_txMac, DeviceType.tx, '192.168.29.187'),
    ]);
    expect(tx.status, DeviceStatus.online);
    expect(rx.status, DeviceStatus.offline); // not in the list
  });

  test('a device the controller reports offline is Offline', () {
    state.applyControllerDevices([
      _listed(_txMac, DeviceType.tx, '192.168.29.187', online: false),
      _listed(_rxMac, DeviceType.rx, '192.168.29.213'),
    ]);
    expect(tx.status, DeviceStatus.offline);
    expect(rx.status, DeviceStatus.online);
  });

  test('IPs always come from the latest list, not the saved ones', () {
    state.applyControllerDevices([
      _listed(_txMac, DeviceType.tx, '10.1.1.50'),
      _listed(_rxMac, DeviceType.rx, '10.1.1.60'),
    ]);
    expect(tx.ip, '10.1.1.50');
    expect(rx.ip, '10.1.1.60');
  });

  test('an Rx pointing at an old Tx IP shows No source', () {
    // The Rx was last told to watch .187, which is no longer a Tx.
    state.applyControllerDevices([
      _listed(_txMac, DeviceType.tx, '10.1.1.50'),
      _listed(_rxMac, DeviceType.rx, '10.1.1.60', currentTxIp: '192.168.29.187'),
    ]);
    expect(state.activeRoutes[_rxId], isNull);
  });

  test('an Rx pointing at a Tx in the list shows that source', () {
    state.activeRoutes[_rxId] = null;
    // The Tx moved to a new IP and the Rx points at the new one.
    state.applyControllerDevices([
      _listed(_txMac, DeviceType.tx, '10.1.1.50'),
      _listed(_rxMac, DeviceType.rx, '10.1.1.60', currentTxIp: '10.1.1.50'),
    ]);
    expect(state.activeRoutes[_rxId], _txId);
  });

  test('an unknown current_tx_ip keeps the route set from the app', () {
    state.applyControllerDevices([
      _listed(_txMac, DeviceType.tx, '192.168.29.187'),
      _listed(_rxMac, DeviceType.rx, '192.168.29.213'),
    ]);
    expect(state.activeRoutes[_rxId], _txId);
  });

  group('routing by channel', () {
    test('an Rx routed by channel shows the channel and its source', () {
      state.activeRoutes[_rxId] = null;
      state.applyControllerDevices([
        _listed(_txMac, DeviceType.tx, '169.254.10.20'),
        _listed(
          _rxMac,
          DeviceType.rx,
          '169.254.54.160',
          currentTxIp: '169.254.10.20',
          selected: '0032',
        ),
      ]);
      expect(rx.selected, '0032');
      expect(rx.routeChannel, '0032');
      expect(rx.staleRoute, isFalse);
      expect(state.activeRoutes[_rxId], _txId);
    });

    test('the route follows a Tx whose IP changed between scans', () {
      state.applyControllerDevices([
        _listed(_txMac, DeviceType.tx, '169.254.10.20'),
        _listed(
          _rxMac,
          DeviceType.rx,
          '169.254.54.160',
          currentTxIp: '169.254.10.20',
          selected: '0032',
        ),
      ]);
      // Same boxes, new random 169.254 addresses.
      state.applyControllerDevices([
        _listed(_txMac, DeviceType.tx, '169.254.77.8'),
        _listed(
          _rxMac,
          DeviceType.rx,
          '169.254.12.99',
          currentTxIp: '169.254.77.8',
          selected: '0032',
        ),
      ]);
      expect(tx.ip, '169.254.77.8');
      expect(rx.ip, '169.254.12.99');
      expect(state.activeRoutes[_rxId], _txId);
      expect(rx.staleRoute, isFalse);
    });

    test('a Tx never gets a selected route', () {
      state.applyControllerDevices([
        _listed(_txMac, DeviceType.tx, '169.254.10.20', selected: '0032'),
      ]);
      expect(tx.selected, isNull);
    });

    test('a route by IP to a Tx that is gone is flagged', () {
      // The office case: Rx .115 is still pointed at .209, which is gone.
      state.applyControllerDevices([
        _listed(_txMac, DeviceType.tx, '192.168.168.212'),
        _listed(
          _rxMac,
          DeviceType.rx,
          '192.168.168.115',
          currentTxIp: '192.168.168.209',
          selected: '192.168.168.209',
        ),
      ]);
      expect(rx.staleRoute, isTrue);
      expect(rx.routeChannel, isNull);
      expect(state.activeRoutes[_rxId], isNull);
    });

    test('a route by IP to a Tx that is listed is not stale', () {
      state.applyControllerDevices([
        _listed(_txMac, DeviceType.tx, '192.168.168.209'),
        _listed(
          _rxMac,
          DeviceType.rx,
          '192.168.168.115',
          currentTxIp: '192.168.168.209',
          selected: '192.168.168.209',
        ),
      ]);
      expect(rx.staleRoute, isFalse);
      expect(state.activeRoutes[_rxId], _txId);
    });

    test('a Tx that is listed but not adopted still counts as on the network',
        () {
      state.applyControllerDevices([
        _listed(_txMac, DeviceType.tx, '10.0.0.5'),
        // Not adopted by the app, but the controller lists it.
        _listed('AA:AA:AA:AA:AA:09', DeviceType.tx, '10.0.0.9'),
        _listed(
          _rxMac,
          DeviceType.rx,
          '10.0.0.6',
          currentTxIp: '10.0.0.9',
          selected: '10.0.0.9',
        ),
      ]);
      expect(rx.staleRoute, isFalse);
    });

    test('an Rx with nothing selected is not stale', () {
      state.applyControllerDevices([
        _listed(_txMac, DeviceType.tx, '10.0.0.5'),
        _listed(_rxMac, DeviceType.rx, '10.0.0.6'),
      ]);
      expect(rx.staleRoute, isFalse);
    });

    test('a box missing from the list is Offline, not stale', () {
      rx.selected = '192.168.168.209';
      state.applyControllerDevices([
        _listed(_txMac, DeviceType.tx, '10.0.0.5'),
      ]);
      expect(rx.status, DeviceStatus.offline);
      expect(rx.staleRoute, isFalse);
    });

    test('choosing a source again clears the stale flag on the next list', () {
      state.applyControllerDevices([
        _listed(_txMac, DeviceType.tx, '10.0.0.5'),
        _listed(
          _rxMac,
          DeviceType.rx,
          '10.0.0.6',
          currentTxIp: '10.0.0.99',
          selected: '10.0.0.99',
        ),
      ]);
      expect(rx.staleRoute, isTrue);
      state.applyControllerDevices([
        _listed(_txMac, DeviceType.tx, '10.0.0.5'),
        _listed(
          _rxMac,
          DeviceType.rx,
          '10.0.0.6',
          currentTxIp: '10.0.0.5',
          selected: '0032',
        ),
      ]);
      expect(rx.staleRoute, isFalse);
      expect(rx.routeChannel, '0032');
    });

    test('only 4-digit codes are channels', () {
      expect(isChannelCode('0032'), isTrue);
      expect(isChannelCode('32'), isFalse);
      expect(isChannelCode('00321'), isFalse);
      expect(isChannelCode('192.168.1.1'), isFalse);
      expect(isChannelCode(null), isFalse);
      expect(isIpv4('169.254.54.160'), isTrue);
      expect(isIpv4('0032'), isFalse);
    });
  });

  group('alerts', () {
    late List<AppAlert> alerts;
    late StreamSubscription<AppAlert> sub;

    setUp(() {
      alerts = [];
      sub = state.alerts.listen(alerts.add);
    });
    tearDown(() => sub.cancel());

    // The stream delivers on the next event-loop turn.
    Future<List<AppAlert>> settled() async {
      await Future<void>.delayed(Duration.zero);
      return alerts;
    }

    test('a source dropping off names the screens that lose their picture',
        () async {
      state.applyControllerDevices([
        _listed(_txMac, DeviceType.tx, '192.168.29.187', online: false),
        _listed(_rxMac, DeviceType.rx, '192.168.29.213'),
      ]);
      final got = await settled();
      expect(got, hasLength(1));
      expect(got.single.isError, isTrue);
      expect(got.single.title, contains('Source lost connection'));
      expect(got.single.title, contains(_txId));
      expect(got.single.detail, contains('Screens affected: $_rxId'));
    });

    test('a screen dropping off is reported', () async {
      state.applyControllerDevices([
        _listed(_txMac, DeviceType.tx, '192.168.29.187'),
      ]); // the Rx is missing from the list
      final got = await settled();
      expect(got.single.title, contains('Screen lost connection'));
    });

    test('no alarm for devices that were never confirmed online', () async {
      tx.status = DeviceStatus.pending; // just opened the app
      rx.status = DeviceStatus.pending;
      state.applyControllerDevices([]);
      expect(await settled(), isEmpty);
    });

    test('a box coming back is announced as good news', () async {
      tx.status = DeviceStatus.offline;
      state.applyControllerDevices([
        _listed(_txMac, DeviceType.tx, '192.168.29.187'),
        _listed(_rxMac, DeviceType.rx, '192.168.29.213'),
      ]);
      final got = await settled();
      expect(got.single.isError, isFalse);
      expect(got.single.title, contains('Back online'));
    });
  });
}
