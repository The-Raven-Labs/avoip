import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../services/controller_discovery.dart';
import '../services/database_service.dart';

/// Holds the controller's address. The client picks the controller found on
/// the network (or types its IP) after login, see ServerSetupScreen. Both the
/// IP and the controller's hostname are saved, so that when DHCP gives the
/// controller a new IP the app can find it again by hostname.
///
/// The SC-1 can also run its own Wi-Fi hotspot (no router, no DHCP). On that
/// Wi-Fi it is always at [hotspotIp], so when the saved address stops working
/// and the phone is on that network, that address is tried first.
class ApiConfig {
  static const String _ipKey = 'server_ip';
  static const String _hostnameKey = 'server_hostname';
  static const int port = 8000;

  /// The SC-1's address on its own hotspot, and the network it hands out.
  static const String hotspotIp = '192.168.50.1';
  static const String _hotspotPrefix = '192.168.50.';

  static String _hotspotAddress = hotspotIp;
  static Future<bool> Function() _phoneOnHotspot = _isPhoneOnHotspotNetwork;

  // Don't browse the network more often than this when the IP stops working.
  static const Duration _rediscoveryInterval = Duration(seconds: 30);

  static String? _ip;
  static String? _hostname;
  static DateTime? _lastRediscovery;
  static Future<bool>? _rediscovery;

  static String? get ip => _ip;

  /// The controller's hostname (e.g. "SC1-2063") if it was picked from the
  /// network rather than typed in.
  static String? get hostname => _hostname;

  static bool get isConfigured => _ip != null && _ip!.trim().isNotEmpty;

  // Always [port] in the app; tests point at a local fake controller.
  static int _port = port;

  static String get baseUrl => 'http://$_ip:$_port';

  /// Loads the last-saved controller, if any. Call once at startup.
  static Future<void> loadSaved() async {
    _ip = await DatabaseService.instance.loadSetting(_ipKey);
    _hostname = await DatabaseService.instance.loadSetting(_hostnameKey);
  }

  /// Points the app at [ip]:[testPort] without saving it (tests only).
  @visibleForTesting
  static void useForTesting(String ip, {int testPort = port}) {
    _ip = ip;
    _port = testPort;
    _hostname = null;
    _hotspotAddress = hotspotIp;
    _phoneOnHotspot = _isPhoneOnHotspotNetwork;
    _lastRediscovery = null;
  }

  /// Pretends the phone is (or isn't) on the SC-1's hotspot, and that the
  /// hotspot controller lives at [address] (tests only).
  @visibleForTesting
  static void useHotspotForTesting({
    required bool phoneOnHotspot,
    String address = hotspotIp,
  }) {
    _phoneOnHotspot = () async => phoneOnHotspot;
    _hotspotAddress = address;
  }

  /// Saves the controller to use. Pass [hostname] when it came from network
  /// discovery; a typed-in IP has none.
  static Future<void> setIp(String ip, {String? hostname}) async {
    _ip = ip.trim();
    _hostname = hostname;
    await DatabaseService.instance.saveSetting(_ipKey, _ip!);
    if (hostname == null) {
      await DatabaseService.instance.deleteSetting(_hostnameKey);
    } else {
      await DatabaseService.instance.saveSetting(_hostnameKey, hostname);
    }
  }

  /// Looks for the saved controller on the network and switches to its new
  /// IP. Matches by hostname, or takes the only controller found when the IP
  /// was typed in. Returns true if the IP changed.
  static Future<bool> rediscover() {
    final running = _rediscovery;
    if (running != null) return running;
    final last = _lastRediscovery;
    if (last != null &&
        DateTime.now().difference(last) < _rediscoveryInterval) {
      return Future.value(false);
    }
    _lastRediscovery = DateTime.now();
    return _rediscovery = _findAgain().whenComplete(() => _rediscovery = null);
  }

  static Future<bool> _findAgain() async {
    // On the SC-1's own Wi-Fi the address is fixed, so there is nothing to
    // search for: no need to wait for mDNS.
    final hotspot = await reachableHotspot();
    if (hotspot != null) {
      if (hotspot == _ip) return false;
      // Keep the hostname, so the controller can still be followed by name
      // when the phone is back on a normal network.
      await setIp(hotspot, hostname: _hostname);
      return true;
    }

    final found = await ControllerDiscovery.find();
    final candidates =
        _hostname != null
            ? found.where((c) => c.hostname == _hostname).toList()
            : found.length == 1
            ? found
            : <FoundController>[];
    for (final candidate in candidates) {
      if (!await responds(candidate.ip)) continue;
      if (candidate.ip == _ip) return false;
      await setIp(candidate.ip, hostname: candidate.hostname ?? _hostname);
      return true;
    }
    return false;
  }

  /// The hotspot address, if this phone is on the SC-1's Wi-Fi and a
  /// controller answers there. Null otherwise.
  static Future<String?> reachableHotspot() async {
    if (!await _phoneOnHotspot()) return null;
    return await responds(_hotspotAddress) ? _hotspotAddress : null;
  }

  // Other networks use 192.168.50.x too (some routers default to it), which
  // is harmless: only a controller answering /health there is accepted.
  static Future<bool> _isPhoneOnHotspotNetwork() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLinkLocal: false,
      );
      return interfaces.any(
        (i) => i.addresses.any((a) => a.address.startsWith(_hotspotPrefix)),
      );
    } catch (_) {
      return false;
    }
  }

  /// The controllers in [found] that this phone can actually reach, one per
  /// controller. A controller announces every address it has (cable, hotspot,
  /// the link-local one on the AV switch) but a phone usually reaches only
  /// one of them. Falls back to [found] unchanged if none answers, so the
  /// caller can still show them and report the error.
  static Future<List<FoundController>> reachable(
    List<FoundController> found,
  ) async {
    final answers = await Future.wait([for (final c in found) responds(c.ip)]);
    final seen = <String>{};
    final reachable = <FoundController>[
      for (var i = 0; i < found.length; i++)
        if (answers[i] && seen.add(found[i].hostname ?? found[i].name))
          found[i],
    ];
    return reachable.isEmpty ? found : reachable;
  }

  /// True if a controller at [ip] answers `GET /health` with "ok".
  static Future<bool> responds(String ip) async {
    try {
      final response = await http
          .get(Uri.parse('http://$ip:$_port/health'))
          .timeout(const Duration(seconds: 3));
      if (response.statusCode != 200) return false;
      return (jsonDecode(response.body) as Map)['status'] == 'ok';
    } catch (_) {
      return false;
    }
  }
}
