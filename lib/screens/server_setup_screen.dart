import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import '../theme/app_theme.dart';
import '../widgets/app_shell.dart';
import '../config/api_config.dart';
import '../services/controller_discovery.dart';
import '../services/network_binding.dart';
import 'sc1_ble_setup_screen.dart';

/// Shown right after login so the client can point the app at their AV
/// controller. Controllers announce themselves on the network, so they are
/// listed here to pick from; typing the IP is the fallback.
class ServerSetupScreen extends StatefulWidget {
  final bool isAdmin;
  const ServerSetupScreen({super.key, required this.isAdmin});

  @override
  State<ServerSetupScreen> createState() => _ServerSetupScreenState();
}

class _ServerSetupScreenState extends State<ServerSetupScreen> {
  late final TextEditingController _ipCtrl;
  String? _error;
  bool _searching = false;
  // checking → straight to the app if an SC-1 answers; otherwise the
  // choice between connecting to an existing SC-1 or setting up a new one.
  _Stage _stage = _Stage.checking;
  List<FoundController> _found = const [];

  static final _ipv4Re = RegExp(
    r'^(25[0-5]|2[0-4][0-9]|1?[0-9]{1,2})(\.(25[0-5]|2[0-4][0-9]|1?[0-9]{1,2})){3}$',
  );

  @override
  void initState() {
    super.initState();
    _ipCtrl = TextEditingController(text: ApiConfig.ip ?? '');
    _start();
  }

  // Day 2: an SC-1 that's already set up should just connect.
  Future<void> _start() async {
    // On the SC-1's hotspot (no internet) Android would otherwise use mobile
    // data for the requests below.
    await NetworkBinding.bindToWifi();
    final saved = ApiConfig.ip;
    if (saved != null && saved.isNotEmpty) {
      // rediscover() also tries the SC-1's hotspot address.
      if (await ApiConfig.responds(saved) || await ApiConfig.rediscover()) {
        return _openApp();
      }
    } else {
      // A phone that has never connected, but is on the SC-1's own Wi-Fi.
      final hotspot = await ApiConfig.reachableHotspot();
      if (hotspot != null) {
        await ApiConfig.setIp(hotspot);
        return _openApp();
      }
    }
    await _search();
    if (!mounted || _stage != _Stage.checking) return;
    if (_found.length == 1) {
      await _connect(_found.single.ip, hostname: _found.single.hostname);
      return;
    }
    setState(() => _stage = _found.isEmpty ? _Stage.choose : _Stage.connect);
  }

  void _openApp() {
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => AppShell(isAdmin: widget.isAdmin),
      ),
    );
  }

  @override
  void dispose() {
    _ipCtrl.dispose();
    super.dispose();
  }

  Future<void> _search({bool retryIfEmpty = true}) async {
    setState(() => _searching = true);
    final announced = await ControllerDiscovery.find();
    if (!mounted) return;
    // The first search on iOS can come back empty while the "find devices
    // on your local network" permission prompt is still up, so try once more.
    if (announced.isEmpty && retryIfEmpty) {
      return _search(retryIfEmpty: false);
    }
    // A controller announces all its addresses (cable, hotspot, the one on
    // the AV switch); list it once, at an address this phone can reach.
    final found = await ApiConfig.reachable(announced);
    if (!mounted) return;
    setState(() {
      _searching = false;
      _found = found;
    });
  }

  Future<void> _connect(String ip, {String? hostname}) async {
    setState(() {
      _searching = true;
      _error = null;
    });
    try {
      final response = await http
          .get(Uri.parse('http://$ip:${ApiConfig.port}/health'))
          .timeout(const Duration(seconds: 4));
      if (response.statusCode != 200 ||
          (jsonDecode(response.body) as Map)['status'] != 'ok') {
        throw const FormatException('Controller health check failed');
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _searching = false;
          _stage = _Stage.connect;
          _error =
              'Could not confirm this controller. Check your network and try again.';
        });
      }
      return;
    }
    await ApiConfig.setIp(ip, hostname: hostname);
    _openApp();
  }

  Future<void> _continueWithTypedIp() async {
    final ip = _ipCtrl.text.trim();
    if (!_ipv4Re.hasMatch(ip)) {
      setState(() => _error = 'Enter a valid IP address, e.g. 192.168.22.11');
      return;
    }
    setState(() => _error = null);
    // Keep the hostname if this IP belongs to a controller on the list, or
    // is the one already saved, so a later IP change can still be followed.
    final listed = _found.where((c) => c.ip == ip).firstOrNull;
    final hostname =
        listed?.hostname ?? (ip == ApiConfig.ip ? ApiConfig.hostname : null);
    await _connect(ip, hostname: hostname);
  }

  @override
  Widget build(BuildContext context) {
    if (_stage == _Stage.checking) return _buildChecking();
    if (_stage == _Stage.choose) return _buildSetupPaths();
    return Scaffold(
      backgroundColor: AppTheme.backgroundLight,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.dns_outlined,
                    color: Colors.white70,
                    size: 48,
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Connect to Existing SC-1',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Pick the controller on this network, or enter its IP address.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white70),
                  ),
                  const SizedBox(height: 32),
                  _panel(child: _buildFoundList()),
                  const SizedBox(height: 16),
                  _panel(child: _buildManualEntry()),
                  const SizedBox(height: 16),
                  TextButton.icon(
                    onPressed: _openBluetoothSetup,
                    icon: const Icon(Icons.bluetooth, size: 18),
                    label: const Text('Set Up New SC-1 instead'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildChecking() {
    return Scaffold(
      backgroundColor: AppTheme.backgroundLight,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(color: AppTheme.accentWhite),
                const SizedBox(height: 24),
                Text(
                  'Looking for your SC-1...',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Make sure this phone is on the same Wi-Fi as your SC-1.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white70),
                ),
                const SizedBox(height: 24),
                TextButton(
                  onPressed: () => setState(() => _stage = _Stage.choose),
                  child: const Text('Skip'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _openBluetoothSetup() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Sc1BleSetupScreen(isAdmin: widget.isAdmin),
      ),
    );
  }

  Widget _buildSetupPaths() {
    return Scaffold(
      backgroundColor: AppTheme.backgroundLight,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Column(
                children: [
                  const Icon(
                    Icons.settings_input_antenna,
                    color: Colors.white70,
                    size: 48,
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'No SC-1 found',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    "We couldn't find an SC-1 on this Wi-Fi. Is yours already "
                    'set up, or is it new?',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white70, height: 1.4),
                  ),
                  const SizedBox(height: 28),
                  _setupChoice(
                    icon: Icons.link_rounded,
                    title: 'Connect to Existing SC-1',
                    subtitle:
                        'Already set up, or plugged into your network. Join '
                        'the same Wi-Fi (or the dedicated AV Wi-Fi), then '
                        'search or enter its IP.',
                    onTap: () {
                      setState(() => _stage = _Stage.connect);
                      _search(retryIfEmpty: false);
                    },
                  ),
                  const SizedBox(height: 12),
                  _setupChoice(
                    icon: Icons.bluetooth,
                    title: 'Set Up New SC-1',
                    subtitle:
                        'First time, or after a reset. Send it your Wi-Fi '
                        'over Bluetooth.',
                    onTap: _openBluetoothSetup,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _setupChoice({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Card(
      color: AppTheme.highlightGrey,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ListTile(
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 10,
        ),
        leading: Icon(icon, color: Colors.white70),
        title: Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(subtitle, style: const TextStyle(color: Colors.white70)),
        ),
        trailing: const Icon(Icons.chevron_right, color: Colors.white54),
      ),
    );
  }

  Widget _panel({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white10),
      ),
      child: child,
    );
  }

  Widget _buildFoundList() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Controllers on this network',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            if (_searching)
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white70,
                ),
              )
            else
              IconButton(
                onPressed: () => _search(retryIfEmpty: false),
                icon: const Icon(Icons.refresh_rounded, color: Colors.white70),
                tooltip: 'Search again',
                visualDensity: VisualDensity.compact,
              ),
          ],
        ),
        const SizedBox(height: 8),
        if (_searching && _found.isEmpty)
          const Text('Searching...', style: TextStyle(color: Colors.grey))
        else if (_found.isEmpty)
          const Text(
            'No controller found. Make sure this phone is on the same Wi-Fi as your SC-1 controller, or enter its IP below.',
            style: TextStyle(color: Colors.grey, height: 1.4),
          ),
        for (final controller in _found)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Material(
              color: AppTheme.highlightGrey,
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap:
                    () =>
                        _connect(controller.ip, hostname: controller.hostname),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.router_outlined,
                        color: Colors.greenAccent,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              controller.label,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              controller.ip,
                              style: const TextStyle(
                                color: Colors.grey,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Icon(
                        Icons.chevron_right_rounded,
                        color: Colors.white54,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildManualEntry() {
    return Column(
      children: [
        TextField(
          controller: _ipCtrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
          ],
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            labelText: 'Controller IP address',
            labelStyle: const TextStyle(color: Colors.grey),
            hintText: '192.168.22.11',
            hintStyle: TextStyle(color: Colors.grey.shade700),
            prefixIcon: const Icon(Icons.wifi_tethering, color: Colors.white54),
            border: InputBorder.none,
            errorText: _error,
          ),
          onSubmitted: (_) => _continueWithTypedIp(),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          height: 50,
          child: ElevatedButton(
            onPressed: _continueWithTypedIp,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.accentWhite,
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text(
              'Continue',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ),
        ),
      ],
    );
  }
}

enum _Stage { checking, choose, connect }
