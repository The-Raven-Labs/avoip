import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

class Sc1WifiNetwork {
  final String ssid;
  final int signal;
  final bool secure;
  const Sc1WifiNetwork(this.ssid, this.signal, this.secure);
}

class Sc1WifiStatus {
  final String state;
  final String? ssid;
  final String? ip;
  final String? error;
  const Sc1WifiStatus(this.state, this.ssid, this.ip, this.error);
}

class Sc1BleWriteException implements Exception {
  final int? code;
  final Object original;
  final Sc1WifiStatus? status;
  final Map<String, dynamic>? info;
  const Sc1BleWriteException(this.code, this.original, this.status, this.info);
}

/// BLE client for the SC-1 provisioning contract. Credentials are encoded and
/// written directly; this service never retains them.
class Sc1BleSetup {
  static const serviceId = '4a7f0000-1c2b-4d3e-8f5a-6b7c8d9e0f10';
  static const infoId = '4a7f0001-1c2b-4d3e-8f5a-6b7c8d9e0f10';
  static const networksId = '4a7f0002-1c2b-4d3e-8f5a-6b7c8d9e0f10';
  static const credentialsId = '4a7f0003-1c2b-4d3e-8f5a-6b7c8d9e0f10';
  static const statusId = '4a7f0004-1c2b-4d3e-8f5a-6b7c8d9e0f10';
  static const setupCodeId = '4a7f0005-1c2b-4d3e-8f5a-6b7c8d9e0f10';

  BluetoothDevice? _device;
  BluetoothCharacteristic? _info, _networks, _credentials, _status, _setupCode;
  StreamSubscription<List<ScanResult>>? _scanSub;
  StreamSubscription<List<int>>? _statusSub;
  StreamSubscription<BluetoothConnectionState>? _connectionSub;
  final _devices = <String, ScanResult>{};
  Map<String, dynamic>? info;
  bool _codeAccepted = false;
  final statusEvents = StreamController<Sc1WifiStatus>.broadcast();

  List<ScanResult> get devices => _devices.values.toList();

  /// "Authentic SC-1 1234", from the advertisement or, if that was empty,
  /// the name the phone cached; a plain label if neither is known yet.
  static String nameOf(ScanResult result) {
    final adv = result.advertisementData.advName;
    if (adv.isNotEmpty) return adv;
    final platform = result.device.platformName;
    return platform.isNotEmpty ? platform : 'Authentic SC-1';
  }
  Stream<Sc1WifiStatus> get statuses => statusEvents.stream;

  Future<void> scan({Duration timeout = const Duration(seconds: 15)}) async {
    _devices.clear();
    await _scanSub?.cancel();
    // The adapter can still be "unknown" right after the screen opens, which
    // made the first scans fail.
    await FlutterBluePlus.adapterState
        .where((s) => s == BluetoothAdapterState.on)
        .first
        .timeout(const Duration(seconds: 5));
    var stopping = false;
    _scanSub = FlutterBluePlus.onScanResults.listen((results) {
      // The scan is already filtered by the setup service id. The name can
      // arrive later in the scan response, so don't drop a result without
      // one; the latest result for a device replaces the earlier one.
      for (final result in results) {
        _devices[result.device.remoteId.str] = result;
      }
      // Found one: give others a moment to show up, then stop early.
      if (_devices.isNotEmpty && !stopping) {
        stopping = true;
        Future<void>.delayed(
          const Duration(seconds: 1),
          () => FlutterBluePlus.stopScan(),
        );
      }
    });
    // startScan returns as soon as the scan has started, so wait for it to
    // finish before reading the results.
    await FlutterBluePlus.startScan(
      withServices: [Guid(serviceId)],
      timeout: timeout,
      androidUsesFineLocation: Platform.isAndroid,
    );
    await FlutterBluePlus.isScanning.where((scanning) => !scanning).first;
    await _scanSub?.cancel();
    _scanSub = null;
  }

  Future<void> connect(ScanResult result) async {
    await disconnect();
    _device = result.device;
    await _device!.connect(
      license: License.commercial,
      timeout: const Duration(seconds: 15),
      mtu: null,
    );
    if (Platform.isAndroid) {
      try {
        await _device!.requestMtu(512);
      } catch (_) {
        /* device may negotiate a smaller MTU */
      }
    } else {
      // Let iOS negotiate its preferred MTU during connection.
    }
    final services = await _device!.discoverServices();
    final service =
        services.where((s) => s.uuid == Guid(serviceId)).firstOrNull;
    if (service == null) throw StateError('SC-1 setup service was not found.');
    BluetoothCharacteristic get(String id) =>
        service.characteristics.where((c) => c.uuid == Guid(id)).firstOrNull ??
        (throw StateError('SC-1 setup characteristic is missing.'));
    _info = get(infoId);
    _networks = get(networksId);
    _credentials = get(credentialsId);
    _status = get(statusId);
    _setupCode =
        service.characteristics
            .where((c) => c.uuid == Guid(setupCodeId))
            .firstOrNull;
    info = Map<String, dynamic>.from(
      jsonDecode(utf8.decode(await _info!.read())) as Map,
    );
    // The screen asks for the code exactly when the SC-1 says it is
    // required, so anything else counts as "nothing to enter". (Treating a
    // missing flag as "not accepted" left such a unit stuck on the
    // enter-the-code screen.)
    _codeAccepted = info?['code_required'] != true;
    _connectionSub = _device!.connectionState.listen((state) {
      if (state == BluetoothConnectionState.disconnected) {
        statusEvents.add(const Sc1WifiStatus('disconnected', null, null, null));
      }
    });
  }

  Future<List<Sc1WifiNetwork>> readNetworks() async {
    final json =
        jsonDecode(utf8.decode(await _networks!.read(timeout: 25))) as List;
    return json
        .map(
          (e) => Sc1WifiNetwork(
            e['ssid'] as String,
            (e['signal'] as num).toInt(),
            e['secure'] as bool,
          ),
        )
        .toList();
  }

  Future<Sc1WifiStatus> readStatus() async =>
      _parseStatus(await _status!.read());

  Future<void> subscribeStatus() async {
    if (_statusSub != null) return;
    _statusSub = _status!.onValueReceived.listen((value) {
      if (value.isNotEmpty) statusEvents.add(_parseStatus(value));
    });
    try {
      await _status!.setNotifyValue(true);
    } catch (_) {
      await _statusSub?.cancel();
      _statusSub = null;
      rethrow;
    }
  }

  bool get supportsContractVersion {
    final version = info?['version'];
    if (version is! String) return false;
    final parsed = RegExp(r'^(\d+)\.(\d+)(?:\.(\d+))?$').firstMatch(version);
    if (parsed == null) return false;
    final major = int.parse(parsed.group(1)!);
    final minor = int.parse(parsed.group(2)!);
    // This app implements contract 1.0. Permit older contract versions, but
    // never send credentials to a newer major or minor contract.
    return major < 1 || (major == 1 && minor <= 0);
  }

  bool get codeAccepted => _codeAccepted;

  /// The code as the SC-1 expects it: the label may print it as "1234 5678"
  /// or "1234-5678", but only the characters themselves are sent.
  static String normalizeSetupCode(String typed) =>
      typed.replaceAll(RegExp(r'[\s\-]'), '');

  /// Sends the setup code from the SC-1's label. The code is never logged
  /// or kept.
  Future<void> writeSetupCode(String code) async {
    final characteristic = _setupCode;
    if (characteristic == null) {
      // An SC-1 without the setup-code characteristic can't be unlocked.
      throw Sc1BleWriteException(
        null,
        StateError('SC-1 setup code characteristic is missing.'),
        null,
        info,
      );
    }
    try {
      await characteristic.write(
        utf8.encode(jsonEncode({'code': normalizeSetupCode(code)})),
        withoutResponse: false,
      );
      _codeAccepted = true;
      return;
    } catch (error) {
      final diagnostic = await _readDiagnostic();
      throw Sc1BleWriteException(
        _attCode(error),
        error,
        diagnostic.$1,
        diagnostic.$2,
      );
    }
  }

  Future<(Sc1WifiStatus?, Map<String, dynamic>?)> _readDiagnostic() async {
    Sc1WifiStatus? status;
    Map<String, dynamic>? latestInfo;
    try {
      status = await readStatus();
    } catch (_) {}
    try {
      latestInfo = Map<String, dynamic>.from(
        jsonDecode(utf8.decode(await _info!.read())) as Map,
      );
      info = latestInfo;
    } catch (_) {}
    return (status, latestInfo);
  }

  int? _attCode(Object error) =>
      error is FlutterBluePlusException ? error.code : null;

  Future<void> provision(String ssid, String password) async {
    if (!supportsContractVersion)
      throw StateError('Unsupported SC-1 contract version.');
    if (!_codeAccepted) throw StateError('The SC-1 setup code is required.');
    await subscribeStatus();
    final payload = utf8.encode(
      jsonEncode({'ssid': ssid, 'password': password}),
    );
    password = '';
    try {
      await _credentials!.write(
        payload,
        withoutResponse: false,
        allowLongWrite: true,
      );
    } catch (error) {
      final diagnostic = await _readDiagnostic();
      throw Sc1BleWriteException(
        _attCode(error),
        error,
        diagnostic.$1,
        diagnostic.$2,
      );
    }
  }

  Sc1WifiStatus _parseStatus(List<int> value) {
    final map = jsonDecode(utf8.decode(value)) as Map;
    return Sc1WifiStatus(
      map['state'] as String,
      map['ssid'] as String?,
      map['ip'] as String?,
      map['error'] as String?,
    );
  }

  Future<void> disconnect() async {
    await _statusSub?.cancel();
    _statusSub = null;
    await _connectionSub?.cancel();
    _connectionSub = null;
    final device = _device;
    _device = null;
    if (device != null) {
      try {
        await device.disconnect();
      } catch (_) {}
    }
  }

  Future<void> dispose() async {
    await FlutterBluePlus.stopScan();
    await _scanSub?.cancel();
    await disconnect();
    await statusEvents.close();
  }
}
