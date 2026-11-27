import 'dart:async';

import 'package:flutter/material.dart';

import '../config/api_config.dart';
import '../logic/app_state.dart';
import '../models/device_model.dart';
import '../services/switch_service.dart';
import '../services/unit_status_service.dart';
import '../services/system_reset_service.dart';
import '../screens/sc1_ble_setup_screen.dart';
import '../theme/app_theme.dart';
import '../widgets/switch_status_card.dart';

/// Live status of every box: is a monitor connected, is video coming in,
/// at what resolution and refresh rate, and which firmware it runs. Also the
/// network switch's multicast (IGMP) status, and the factory reset.
class UtilitiesModule extends StatefulWidget {
  const UtilitiesModule({super.key});

  @override
  State<UtilitiesModule> createState() => _UtilitiesModuleState();
}

class _UtilitiesModuleState extends State<UtilitiesModule> {
  // While the SC-1 is still looking at the switch ("pending"), ask again
  // every few seconds, up to about two minutes.
  static const Duration _pendingPollEvery = Duration(seconds: 5);
  static const int _pendingPollLimit = 24;

  List<UnitStatus> _units = const [];
  ControllerApiException? _error;
  bool _loading = false;
  DateTime? _updatedAt;

  SwitchStatus? _switch;
  ControllerApiException? _switchError;
  bool _checkingSwitch = false;
  Timer? _pendingPoll;
  int _pendingPolls = 0;

  @override
  void initState() {
    super.initState();
    AppState.instance.currentTab.addListener(_onTabChanged);
    if (AppState.instance.currentTab.value == AppTabs.utilities) _load();
  }

  @override
  void dispose() {
    AppState.instance.currentTab.removeListener(_onTabChanged);
    _pendingPoll?.cancel();
    super.dispose();
  }

  // ── Network switch ──────────────────────────────────────────────────────

  Future<void> _loadSwitch() async {
    _pendingPoll?.cancel();
    try {
      final status = await SwitchService.fetch();
      if (!mounted) return;
      setState(() {
        _switch = status;
        _switchError = null;
      });
      _pollWhilePending(status);
    } on ControllerApiException catch (e) {
      if (mounted) setState(() => _switchError = e);
    }
  }

  void _pollWhilePending(SwitchStatus status) {
    if (status.state != SwitchState.pending) {
      _pendingPolls = 0;
      return;
    }
    if (_pendingPolls >= _pendingPollLimit) return;
    _pendingPolls++;
    _pendingPoll = Timer(_pendingPollEvery, () {
      // Only while the tab is showing.
      if (mounted && AppState.instance.currentTab.value == AppTabs.utilities) {
        _loadSwitch();
      }
    });
  }

  Future<void> _checkSwitchNow() async {
    if (_checkingSwitch) return;
    _pendingPoll?.cancel();
    setState(() => _checkingSwitch = true);
    try {
      final status = await SwitchService.checkNow();
      if (!mounted) return;
      setState(() {
        _switch = status;
        _switchError = null;
      });
    } on ControllerApiException catch (e) {
      _toast(e.message, error: true);
    } finally {
      if (mounted) setState(() => _checkingSwitch = false);
    }
  }

  // Nothing at all for a controller without a managed switch, or an older
  // controller that has no switch API.
  Widget? _buildSwitchCard() {
    final error = _switchError;
    if (error != null) {
      // If the boxes didn't load either, that message already says the
      // controller can't be reached.
      if (error.unsupported || _error != null) return null;
      return _message(
        Icons.hub_outlined,
        "Couldn't load the switch status",
        error.message,
        onRetry: _loadSwitch,
      );
    }
    final status = _switch;
    if (status == null || !SwitchStatusCard.shouldShow(status)) return null;
    return SwitchStatusCard(
      status: status,
      checking: _checkingSwitch,
      onCheckNow: _checkSwitchNow,
    );
  }

  // Reading every box takes a few seconds, so only load when shown.
  void _onTabChanged() {
    if (AppState.instance.currentTab.value == AppTabs.utilities) _load();
  }

  Future<void> _load() async {
    if (_loading) return;
    setState(() => _loading = true);
    // The switch is asked separately: reading the boxes takes a few seconds,
    // and neither should hold up (or fail) the other.
    unawaited(_loadSwitch());
    try {
      await AppState.instance.refreshDevices(minInterval: Duration.zero);
      final units = await UnitStatusService.fetchAll();
      if (!mounted) return;
      setState(() {
        _units = units;
        _error = null;
        _updatedAt = DateTime.now();
      });
    } on ControllerApiException catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _nameOf(UnitStatus unit) {
    final state = AppState.instance;
    for (final d in [
      ...state.sources,
      ...state.destinationsByLocation.values.expand((d) => d),
    ]) {
      if (d.controllerId == unit.id) return d.name;
    }
    return state.controllerDeviceNames[unit.id] ?? unit.ip;
  }

  Device? _deviceOf(UnitStatus unit) {
    final state = AppState.instance;
    for (final d in [
      ...state.sources,
      ...state.destinationsByLocation.values.expand((d) => d),
    ]) {
      if (d.controllerId == unit.id) return d;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 700;
    return RefreshIndicator(
      onRefresh: _load,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.all(isMobile ? 16.0 : 24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Utilities',
                      maxLines: 1,
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textMain,
                      ),
                    ),
                  ),
                ),
                if (_loading)
                  const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppTheme.accentWhite,
                      ),
                    ),
                  )
                else
                  IconButton(
                    onPressed: _load,
                    icon: const Icon(
                      Icons.refresh_rounded,
                      color: Colors.white70,
                    ),
                    tooltip: 'Refresh',
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              _updatedAt == null
                  ? 'Live status read from each box.'
                  : 'Live status read from each box. Updated '
                      '${_updatedAt!.hour.toString().padLeft(2, '0')}:'
                      '${_updatedAt!.minute.toString().padLeft(2, '0')}:'
                      '${_updatedAt!.second.toString().padLeft(2, '0')}.',
              style: const TextStyle(color: AppTheme.textMuted),
            ),
            const SizedBox(height: 24),
            if (_buildSwitchCard() case final card?) ...[
              card,
              const SizedBox(height: 24),
            ],
            _buildBody(isMobile ? 12.0 : 16.0),
            const SizedBox(height: 32),
            _buildResetSection(),
          ],
        ),
      ),
    );
  }

  // ── Factory reset ───────────────────────────────────────────────────────

  bool _resetting = false;

  Widget _buildResetSection() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.redAccent.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.redAccent.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Factory reset',
            style: TextStyle(
              color: Colors.redAccent,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Returns the SC-1 to a clean slate: clears saved scenes, settings, '
            'devices and its saved Wi-Fi. The Tx/Rx boxes are not changed.',
            style: TextStyle(color: AppTheme.textMuted, height: 1.4),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _resetting ? null : _factoryReset,
            icon:
                _resetting
                    ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.redAccent,
                      ),
                    )
                    : const Icon(Icons.restart_alt_rounded),
            label: const Text('Full Reset'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.redAccent,
              side: const BorderSide(color: Colors.redAccent),
            ),
          ),
        ],
      ),
    );
  }

  void _toast(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? Colors.redAccent : null,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<bool> _confirmReset(ResetPreparation prep) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            backgroundColor: AppTheme.backgroundLight,
            title: const Text(
              'Factory reset the SC-1?',
              style: TextStyle(color: AppTheme.accentWhite),
            ),
            content: Text(
              'This clears saved scenes, settings, devices and the SC-1\'s '
              'saved Wi-Fi. This cannot be undone.'
              '${prep.wifiCanBeCleared ? '' : '\n\nThe saved Wi-Fi cannot be cleared on this unit.'}',
              style: const TextStyle(color: AppTheme.textMuted, height: 1.4),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text(
                  'Cancel',
                  style: TextStyle(color: Colors.grey),
                ),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text(
                  'Reset',
                  style: TextStyle(
                    color: Colors.redAccent,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
    );
    return confirmed == true;
  }

  Future<void> _factoryReset() async {
    setState(() => _resetting = true);
    try {
      // A code that expired while the dialog was open is refused with 403:
      // get a new one and ask again.
      for (var attempt = 0; attempt < 3; attempt++) {
        final prep = await SystemResetService.prepare();
        if (!mounted || !await _confirmReset(prep)) return;
        final ResetResult result;
        try {
          result = await SystemResetService.reset(prep.confirmCode);
        } on ControllerApiException catch (e) {
          if (SystemResetService.isInvalidCode(e)) {
            _toast(e.message, error: true);
            continue;
          }
          rethrow;
        }
        // Only now that the SC-1 confirmed is the app's own data cleared.
        await AppState.instance.clearLocalDeviceData();
        if (!mounted) return;
        setState(() => _units = const []);
        await _afterReset(result);
        return;
      }
    } on ControllerApiException catch (e) {
      _toast(e.message, error: true);
    } finally {
      if (mounted) setState(() => _resetting = false);
    }
  }

  Future<void> _afterReset(ResetResult result) async {
    await showDialog<void>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            backgroundColor: AppTheme.backgroundLight,
            title: const Text(
              'SC-1 reset',
              style: TextStyle(color: AppTheme.accentWhite),
            ),
            content: Text(
              result.leavesWifi
                  ? 'The SC-1 will forget its Wi-Fi in a few seconds. If it is '
                      'connected by cable it stays reachable; otherwise you '
                      'will set it up again with Bluetooth.'
                  : result.wifi == 'not_permitted'
                  ? 'Scenes, settings and devices were cleared. The SC-1 kept '
                      'its saved Wi-Fi, so it stays on this network.'
                  : 'Scenes, settings and devices were cleared.',
              style: const TextStyle(color: AppTheme.textMuted, height: 1.4),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('OK'),
              ),
            ],
          ),
    );
    if (!mounted) return;
    if (result.leavesWifi && !await _stillReachableAfterWifiLoss()) {
      if (!mounted) return;
      // The SC-1 is off this network now: start the new-SC-1 setup.
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) => const Sc1BleSetupScreen(isAdmin: true),
        ),
        (_) => false,
      );
      return;
    }
    if (result.leavesWifi) {
      _toast('The SC-1 is on a cable, so it is still connected.');
    }
    // Still reachable: the boxes reappear on the next scan.
    AppState.instance.currentTab.value = AppTabs.discovery;
  }

  // Waits for the SC-1 to drop its Wi-Fi, then checks whether it can still
  // be reached (cable), at its old address or a new one.
  Future<bool> _stillReachableAfterWifiLoss() async {
    final navigator = Navigator.of(context, rootNavigator: true);
    unawaited(
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder:
            (_) => const PopScope(
              canPop: false,
              child: AlertDialog(
                backgroundColor: AppTheme.backgroundLight,
                content: Row(
                  children: [
                    SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    SizedBox(width: 16),
                    Expanded(
                      child: Text(
                        'Checking the SC-1 connection...',
                        style: TextStyle(color: AppTheme.textMuted),
                      ),
                    ),
                  ],
                ),
              ),
            ),
      ),
    );
    await Future<void>.delayed(const Duration(seconds: 8));
    final ip = ApiConfig.ip;
    final reachable =
        (ip != null && await ApiConfig.responds(ip)) ||
        await ApiConfig.rediscover();
    navigator.pop();
    return reachable;
  }

  Widget _buildBody(double spacing) {
    if (_loading && _units.isEmpty) {
      return _message(
        null,
        'Reading the boxes...',
        'This takes a few seconds.',
      );
    }
    final error = _error;
    if (error != null) {
      return _message(
        error.unsupported
            ? Icons.system_update_alt_rounded
            : Icons.cloud_off_rounded,
        error.unsupported ? 'Controller update needed' : "Couldn't load status",
        error.message,
        onRetry: _load,
      );
    }
    if (_units.isEmpty) {
      return _message(
        Icons.devices_other_rounded,
        'No boxes yet',
        'Boxes the controller finds appear here.',
      );
    }

    final sources = _units.where((u) => u.isTx).toList();
    final screens = _units.where((u) => !u.isTx).toList();
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = (constraints.maxWidth / 420).ceil().clamp(1, 3);
        final width =
            (constraints.maxWidth - spacing * (columns - 1)) / columns;
        Widget group(String title, List<UnitStatus> units) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(
                title,
                style: TextStyle(
                  color: Colors.grey.shade500,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                ),
              ),
            ),
            Wrap(
              spacing: spacing,
              runSpacing: spacing,
              children: [
                for (final unit in units)
                  SizedBox(width: width, child: _buildCard(unit)),
              ],
            ),
            const SizedBox(height: 24),
          ],
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (sources.isNotEmpty) group('SOURCES (TX)', sources),
            if (screens.isNotEmpty) group('SCREENS (RX)', screens),
          ],
        );
      },
    );
  }

  Widget _message(
    IconData? icon,
    String title,
    String detail, {
    VoidCallback? onRetry,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Center(
        child: Column(
          children: [
            if (icon != null)
              Icon(icon, size: 48, color: Colors.grey.shade700)
            else
              const CircularProgressIndicator(color: AppTheme.accentWhite),
            const SizedBox(height: 12),
            Text(
              title,
              style: const TextStyle(color: Colors.white, fontSize: 16),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              detail,
              style: const TextStyle(color: Colors.grey, fontSize: 13),
              textAlign: TextAlign.center,
            ),
            if (onRetry != null)
              TextButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }

  static String? _video(String? resolution, num? hz) {
    if (resolution == null) return null;
    return hz == null ? resolution : '$resolution @ ${_hz(hz)} Hz';
  }

  static String _hz(num hz) =>
      hz == hz.roundToDouble() ? hz.round().toString() : hz.toStringAsFixed(2);

  Widget _buildCard(UnitStatus unit) {
    final reachable = unit.reachable;
    final firmware =
        unit.firmwareVersion == null
            ? null
            : unit.firmwareBuild == null
            ? unit.firmwareVersion
            : '${unit.firmwareVersion} (build ${unit.firmwareBuild})';

    final rows = <Widget>[
      if (unit.isTx) ...[
        if (_deviceOf(unit)?.channel case final channel?)
          _row('Channel', channel),
        _flagRow('Video in', unit.videoDetected, 'Detected', 'No video'),
        _row('Input', _video(unit.sourceResolution, unit.sourceRefreshHz)),
        _row('Signal', unit.signalType),
      ] else ...[
        if (_deviceOf(unit)?.currentTxIp case final txIp?)
          _row('Showing', 'TX $txIp'),
        _flagRow(
          'Monitor',
          unit.monitorConnected,
          'Connected',
          'Not connected',
        ),
        _flagRow('Video', unit.videoDetected, 'Receiving', 'No video'),
        _row('Source', _video(unit.sourceResolution, unit.sourceRefreshHz)),
        _row('Output', _video(unit.outputResolution, unit.outputRefreshHz)),
      ],
      _row('Firmware', firmware),
    ];

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.highlightGrey,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color:
              reachable
                  ? Colors.white.withValues(alpha: 0.1)
                  : Colors.redAccent,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                unit.isTx ? Icons.play_arrow_rounded : Icons.monitor,
                color: unit.isTx ? Colors.purpleAccent : Colors.blueAccent,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _nameOf(unit),
                      style: const TextStyle(
                        color: AppTheme.accentWhite,
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      unit.ip,
                      style: TextStyle(
                        color: Colors.grey.shade500,
                        fontSize: 12,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _chip(
                reachable ? 'ONLINE' : 'NOT RESPONDING',
                reachable ? Colors.greenAccent : Colors.redAccent,
              ),
            ],
          ),
          const SizedBox(height: 12),
          // A box that doesn't answer has no live values to show.
          Opacity(opacity: reachable ? 1 : 0.4, child: Column(children: rows)),
        ],
      ),
    );
  }

  Widget _row(String label, String? value, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 96,
            child: Text(
              label,
              style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
            ),
          ),
          Expanded(
            child: Text(
              value ?? '—',
              style: TextStyle(color: color ?? Colors.white, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  // A yes/no reading; "no" is a warning worth noticing.
  Widget _flagRow(String label, bool? value, String yes, String no) {
    return _row(
      label,
      value == null ? null : (value ? yes : no),
      color:
          value == null
              ? null
              : (value ? Colors.greenAccent : Colors.orangeAccent),
    );
  }

  Widget _chip(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 9,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
