import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import '../config/api_config.dart';
import '../models/device_model.dart';
import '../modules/discovery_module.dart';
import '../services/database_service.dart';
import '../services/device_api_service.dart';
import '../services/snapshot_service.dart';

/// A login account. Only a salted hash of the password is kept.
class UserAccount {
  /// The built-in admin, which can't be deleted or demoted.
  static const String rootAdminId = 'u1';

  /// Out-of-the-box credentials; the password must be changed at first login.
  static const String defaultUsername = 'admin';
  static const String defaultPassword = 'admin';

  static const int minPasswordLength = 6;

  final String id;
  final String username;
  final String role;
  final String passwordHash;
  final String salt;

  /// True for the default account and for accounts an admin created or
  /// reset, so the person sets their own password at their next login.
  final bool mustChangePassword;

  const UserAccount({
    required this.id,
    required this.username,
    required this.role,
    required this.passwordHash,
    required this.salt,
    required this.mustChangePassword,
  });

  factory UserAccount.withPassword({
    required String id,
    required String username,
    required String role,
    required String password,
    required bool mustChangePassword,
  }) {
    final salt = _newSalt();
    return UserAccount(
      id: id,
      username: username,
      role: role,
      passwordHash: hashPassword(password, salt),
      salt: salt,
      mustChangePassword: mustChangePassword,
    );
  }

  bool get isAdmin => role == 'Admin';
  bool get isRootAdmin => id == rootAdminId;

  bool checkPassword(String password) =>
      hashPassword(password, salt) == passwordHash;

  UserAccount copyWith({String? username, String? role}) => UserAccount(
    id: id,
    username: username ?? this.username,
    role: role ?? this.role,
    passwordHash: passwordHash,
    salt: salt,
    mustChangePassword: mustChangePassword,
  );

  /// Salted SHA-256, repeated so guessing passwords from a copied database
  /// is slow.
  static String hashPassword(String password, String salt) {
    List<int> digest = utf8.encode('$salt:$password');
    for (var i = 0; i < 10000; i++) {
      digest = sha256.convert(digest).bytes;
    }
    return base64Encode(digest);
  }

  static String _newSalt() {
    final random = Random.secure();
    return base64Encode(List<int>.generate(16, (_) => random.nextInt(256)));
  }

  /// Why [password] can't be used for [username], or null if it's fine.
  static String? passwordProblem(String username, String password) {
    if (password.length < minPasswordLength) {
      return 'Use at least $minPasswordLength characters.';
    }
    if (password == defaultPassword ||
        password.toLowerCase() == username.toLowerCase()) {
      return "Choose a password that isn't the default or your username.";
    }
    return null;
  }
}

/// Whether this phone can reach the SC-1 right now.
enum ControllerLink { checking, connected, lost }

/// Something the user should be told about, shown by the app shell.
class AppAlert {
  final String title;
  final String? detail;

  /// Red when something went wrong, green when it recovered.
  final bool isError;

  const AppAlert(this.title, {this.detail, this.isError = true});
}

/// Ids of the main menu tabs, used to switch tabs from anywhere.
class AppTabs {
  static const discovery = 'discovery';
  static const configuration = 'configuration';
  static const operate = 'operate';
  static const snapshots = 'snapshots';
  static const users = 'users';
  static const utilities = 'utilities';
  static const help = 'help';
}

class AppState extends ChangeNotifier {
  static final AppState instance = AppState._internal();
  AppState._internal();

  bool isLoaded = false;

  // Active Device Registries
  final List<Device> sources = [];
  final Map<String, List<Device>> destinationsByLocation = {};

  // Security/RBAC Authentication Registry
  final List<UserAccount> users = [];

  // Active Matrix Routing Paths (Destination ID -> Source ID)
  final Map<String, String?> activeRoutes = {};

  // Routing presets, stored on the controller so touch panels share them.
  List<ControllerSnapshot> snapshots = [];
  ControllerApiException? snapshotsError;
  bool snapshotsLoading = false;

  // The SC-1 link: "lost" after two failed device-list reads in a row, so
  // one dropped packet doesn't raise an alarm.
  static const int _missesBeforeLost = 2;
  final ValueNotifier<ControllerLink> controllerLink =
      ValueNotifier<ControllerLink>(ControllerLink.checking);
  DateTime? lastControllerContact;
  int _failedRefreshes = 0;
  // After the SC-1 drops, all boxes show Offline; don't also announce each
  // one coming back when it returns.
  bool _quietNextRecovery = false;

  final StreamController<AppAlert> _alerts =
      StreamController<AppAlert>.broadcast();

  /// Alerts for the app shell to show: SC-1 lost/back, a source or screen
  /// that dropped off, or came back.
  Stream<AppAlert> get alerts => _alerts.stream;

  // Global Notifiers for listeners
  final ValueNotifier<int> stateVersionNotifier = ValueNotifier<int>(0);
  // Id of the visible tab (one of AppTabs).
  final ValueNotifier<String> currentTab = ValueNotifier<String>('');

  // Track the most recently adopted device to auto-focus in Configuration
  String? lastAdoptedDeviceId;

  // ── Database Load (called once on app start) ───────────────────────────────

  Future<void> loadFromDatabase() async {
    if (isLoaded) return;

    final db = DatabaseService.instance;

    // Login accounts; a fresh install starts with the default admin.
    users.addAll(await db.loadUsers());
    if (users.isEmpty) {
      final admin = UserAccount.withPassword(
        id: UserAccount.rootAdminId,
        username: UserAccount.defaultUsername,
        role: 'Admin',
        password: UserAccount.defaultPassword,
        mustChangePassword: true,
      );
      await db.saveUser(admin);
      users.add(admin);
    }

    // Load adopted devices
    final devices = await db.loadAdoptedDevices();
    for (final device in devices) {
      // A saved status may be days old or from another network; show
      // "checking" until the controller confirms (see refreshDevices).
      device.status = DeviceStatus.pending;
      if (device.type == DeviceType.tx) {
        if (!sources.any((s) => s.id == device.id)) {
          sources.add(device);
        }
      } else {
        final loc = device.location;
        destinationsByLocation.putIfAbsent(loc, () => []);
        if (!destinationsByLocation[loc]!.any((d) => d.id == device.id)) {
          destinationsByLocation[loc]!.add(device);
        }
      }
    }

    // Load active routes
    final routes = await db.loadActiveRoutes();
    activeRoutes.addAll(routes);
    // Drop routes to devices that no longer exist, such as the old demo
    // devices; notifyListeners() below saves the cleaned routes.
    final knownIds = {
      ...sources.map((d) => d.id),
      ...destinationsByLocation.values.expand((d) => d).map((d) => d.id),
    };
    activeRoutes.removeWhere(
      (dest, src) =>
          !knownIds.contains(dest) || (src != null && !knownIds.contains(src)),
    );

    isLoaded = true;
    notifyListeners();
  }

  // ── Save helpers ───────────────────────────────────────────────────────────

  Future<void> _persistRoutes() async {
    try {
      await DatabaseService.instance.saveActiveRoutes(activeRoutes);
    } catch (e) {
      debugPrint('AppState: could not save routes: $e');
    }
  }

  Future<void> _saveDevice(Device device) async {
    try {
      await DatabaseService.instance.saveAdoptedDevice(device);
    } catch (e) {
      debugPrint('AppState: could not save ${device.name}: $e');
    }
  }

  // ── Overridden notifyListeners — persists routes on every change ───────────

  @override
  void notifyListeners() {
    stateVersionNotifier.value++;
    super.notifyListeners();
    _persistRoutes();
  }

  // ── Device Adoption — saves to DB immediately ──────────────────────────────

  Future<void> adoptDevice(
    String id,
    String name,
    String ip,
    DeviceType type, {
    String? previewUrl,
    String? streamUrl,
    String? channel,
    DeviceStatus status = DeviceStatus.pending,
  }) async {
    final newDevice = Device(
      id: id,
      name: name,
      ip: ip,
      type: type,
      status: status,
      location: 'Unassigned',
      tags: ['Newly Adopted'],
      previewUrl: previewUrl,
      streamUrl: streamUrl,
      channel: type == DeviceType.tx ? channel : null,
    );

    if (type == DeviceType.tx) {
      if (!sources.any((s) => s.id == id)) {
        sources.add(newDevice);
      }
    } else {
      const location = 'Unassigned';
      destinationsByLocation.putIfAbsent(location, () => []);
      if (!destinationsByLocation[location]!.any((d) => d.id == id)) {
        destinationsByLocation[location]!.add(newDevice);
      }
    }

    await DatabaseService.instance.saveAdoptedDevice(newDevice);
    lastAdoptedDeviceId = id;
    notifyListeners();
  }

  // ── Controller device list ─────────────────────────────────────────────

  /// Controller device id → name, from the last device list.
  final Map<String, String> controllerDeviceNames = {};

  DateTime? _lastDeviceRefresh;
  Future<void>? _deviceRefresh;

  /// Reloads the controller's device list and applies its preview/stream
  /// URLs. Runs on screen open, periodically, and after any 404, because
  /// device ids (and so the URLs) change when the controller restarts.
  /// Skipped while a reload is running or within [minInterval] of the last
  /// one, so many tiles hitting 404 at once cause a single reload.
  Future<void> refreshDevices({
    Duration minInterval = const Duration(seconds: 3),
  }) {
    if (!ApiConfig.isConfigured) return Future.value();
    final running = _deviceRefresh;
    if (running != null) return running;
    final last = _lastDeviceRefresh;
    if (last != null && DateTime.now().difference(last) < minInterval) {
      return Future.value();
    }
    _lastDeviceRefresh = DateTime.now();
    return _deviceRefresh = DeviceApiService.fetchDevices()
        .then((found) {
          if (found != null) {
            _controllerReached();
            applyControllerDevices(found);
          } else {
            _controllerMissed();
            _markAllOffline();
          }
        })
        .whenComplete(() => _deviceRefresh = null);
  }

  void _controllerReached() {
    _failedRefreshes = 0;
    lastControllerContact = DateTime.now();
    final wasLost = controllerLink.value == ControllerLink.lost;
    controllerLink.value = ControllerLink.connected;
    if (wasLost) {
      _alerts.add(const AppAlert('Reconnected to the SC-1', isError: false));
    }
  }

  void _controllerMissed() {
    _failedRefreshes++;
    _quietNextRecovery = true;
    if (_failedRefreshes < _missesBeforeLost ||
        controllerLink.value == ControllerLink.lost) {
      return;
    }
    controllerLink.value = ControllerLink.lost;
    _alerts.add(
      const AppAlert(
        'SC-1 not responding',
        detail:
            'Check that it has power and this phone is on the same Wi-Fi. '
            'Switching and previews are unavailable until it is back.',
      ),
    );
  }

  /// Puts the link state back to "checking" (tests only).
  @visibleForTesting
  void resetControllerLinkForTesting() {
    controllerLink.value = ControllerLink.checking;
    lastControllerContact = null;
    _failedRefreshes = 0;
    _quietNextRecovery = false;
  }

  // The controller couldn't be reached, so no box can be confirmed online.
  void _markAllOffline() {
    var changed = false;
    for (final device in [
      ...sources,
      ...destinationsByLocation.values.expand((d) => d),
    ]) {
      if (device.status != DeviceStatus.offline) {
        device.status = DeviceStatus.offline;
        changed = true;
      }
    }
    if (changed) notifyListeners();
  }

  // One alert for sources that dropped, one for screens, one for boxes that
  // came back, so a bad moment doesn't stack a dozen messages.
  void _announceDeviceChanges(
    List<Device> dropped,
    List<Device> returned,
    List<Device> displays,
  ) {
    final quiet = _quietNextRecovery;
    _quietNextRecovery = false;

    String names(List<Device> devices) => devices.map((d) => d.name).join(', ');
    final lostSources = dropped.where((d) => d.type == DeviceType.tx).toList();
    final lostScreens = dropped.where((d) => d.type != DeviceType.tx).toList();

    if (lostSources.isNotEmpty) {
      // Screens still pointed at a source that just dropped.
      final affected = [
        for (final display in displays)
          if (lostSources.any((s) => s.id == activeRoutes[display.id]))
            display.name,
      ];
      _alerts.add(
        AppAlert(
          lostSources.length == 1
              ? 'Source lost connection: ${lostSources.single.name}'
              : 'Sources lost connection: ${names(lostSources)}',
          detail:
              affected.isEmpty
                  ? 'No screen was showing it.'
                  : 'Screens affected: ${affected.join(', ')}.',
        ),
      );
    }
    if (lostScreens.isNotEmpty) {
      _alerts.add(
        AppAlert(
          lostScreens.length == 1
              ? 'Screen lost connection: ${lostScreens.single.name}'
              : 'Screens lost connection: ${names(lostScreens)}',
        ),
      );
    }
    if (returned.isNotEmpty && !quiet) {
      _alerts.add(AppAlert('Back online: ${names(returned)}', isError: false));
    }
  }

  /// Applies the controller's latest device list to the adopted devices
  /// (matched by id: the MAC without colons). The list is the only truth:
  ///  - status is Online only if the controller says "online"; a device
  ///    missing from the list is Offline,
  ///  - IPs are replaced by the list's (DHCP can change them),
  ///  - an Rx whose `current_tx_ip` matches no Tx in the list shows
  ///    "No source" (it points at an old address),
  ///  - preview/stream URLs and controller ids are refreshed.
  void applyControllerDevices(List<DiscoveredDevice> found) {
    // Names of every box the controller knows, adopted or not, so snapshots
    // can show them.
    controllerDeviceNames
      ..clear()
      ..addAll({
        for (final d in found)
          if (d.controllerId != null) d.controllerId!: d.name,
      });
    final byId = {for (final d in found) d.mac.replaceAll(':', ''): d};
    final displays = destinationsByLocation.values.expand((d) => d).toList();
    var changed = false;
    // Boxes that were Online and dropped off, and ones that came back.
    final dropped = <Device>[];
    final returned = <Device>[];

    // Pass 1: status, addresses and URLs (sources first, so pass 2 sees
    // their new IPs).
    for (final device in [...sources, ...displays]) {
      final match = byId[device.id];
      if (match == null) {
        // The controller doesn't know this box (unplugged, other site).
        if (device.status != DeviceStatus.offline) {
          if (device.status == DeviceStatus.online) dropped.add(device);
          device.status = DeviceStatus.offline;
          changed = true;
        }
        continue;
      }
      if (device.ip != match.ip) {
        device.ip = match.ip;
        changed = true;
        unawaited(_saveDevice(device));
      }
      if (device.controllerId != match.controllerId) {
        device.controllerId = match.controllerId;
        changed = true;
      }
      final status =
          match.signal > 0 ? DeviceStatus.online : DeviceStatus.offline;
      if (device.status != status) {
        if (device.status == DeviceStatus.online) dropped.add(device);
        if (device.status == DeviceStatus.offline) returned.add(device);
        device.status = status;
        changed = true;
      }
      if (device.previewUrl != match.previewUrl ||
          device.streamUrl != match.streamUrl) {
        device.previewUrl = match.previewUrl;
        device.streamUrl = match.streamUrl;
        changed = true;
      }
      if (device.type == DeviceType.tx && device.channel != match.channel) {
        device.channel = match.channel;
        changed = true;
      }
      if (device.type != DeviceType.tx &&
          device.currentTxIp != match.currentTxIp) {
        device.currentTxIp = match.currentTxIp;
        changed = true;
      }
      if (device.type != DeviceType.tx && device.selected != match.selected) {
        device.selected = match.selected;
        changed = true;
      }
    }

    _announceDeviceChanges(dropped, returned, displays);

    // Pass 2: what each screen shows. A null current_tx_ip means the
    // controller doesn't know, so the route set from this app stays.
    final sourceByIp = {for (final s in sources) s.ip: s};
    for (final display in displays) {
      final txIp = byId[display.id]?.currentTxIp;
      if (txIp == null) continue;
      // A Tx IP that matches no source is an old address: no source.
      final sourceId = sourceByIp[txIp]?.id;
      if (activeRoutes[display.id] != sourceId) {
        activeRoutes[display.id] = sourceId;
        changed = true;
      }
    }

    // An Rx still routed the old way (by IP) to a Tx that isn't in the
    // controller's list any more can't show anything: say so. Judged against
    // every Tx the controller lists, adopted or not, because an unadopted
    // Tx is still on the network.
    final txIps = {
      for (final d in found)
        if (d.type == DeviceType.tx) d.ip,
    };
    for (final display in displays) {
      final selected = display.selected;
      final stale =
          byId[display.id] != null &&
          isIpv4(selected) &&
          !txIps.contains(selected);
      if (display.staleRoute != stale) {
        display.staleRoute = stale;
        changed = true;
      }
    }
    if (changed) notifyListeners();
  }

  // ── Device Removal — deletes from DB immediately ───────────────────────────

  Future<void> removeDevice(String deviceId, String location) async {
    sources.removeWhere((d) => d.id == deviceId);
    destinationsByLocation[location]?.removeWhere((d) => d.id == deviceId);
    if (destinationsByLocation[location]?.isEmpty ?? false) {
      destinationsByLocation.remove(location);
    }
    // Forget routes to or from it; notifyListeners() saves the change.
    activeRoutes.remove(deviceId);
    activeRoutes.removeWhere((_, sourceId) => sourceId == deviceId);
    await DatabaseService.instance.deleteAdoptedDevice(deviceId);
    notifyListeners();
  }

  // ── Snapshots — stored on the controller ──────────────────────────────────

  // Rebuilds listeners without re-saving routes.
  void _refreshListeners() {
    stateVersionNotifier.value++;
    super.notifyListeners();
  }

  /// Reloads the controller's snapshots. Failures land in [snapshotsError].
  Future<void> loadSnapshots() async {
    if (!ApiConfig.isConfigured) return;
    snapshotsLoading = true;
    _refreshListeners();
    try {
      snapshots = await SnapshotService.list();
      snapshotsError = null;
    } on ControllerApiException catch (e) {
      snapshotsError = e;
    } finally {
      snapshotsLoading = false;
      _refreshListeners();
    }
  }

  /// What [displays] show right now, as controller ids. Displays without a
  /// source, or not yet matched to the controller's list, are left out.
  List<SnapshotRoute> currentSnapshotRoutes(Iterable<Device> displays) {
    final sourcesById = {for (final s in sources) s.id: s};
    return [
      for (final display in displays)
        if (display.controllerId != null &&
            sourcesById[activeRoutes[display.id]]?.controllerId != null)
          SnapshotRoute(
            rxId: display.controllerId!,
            txId: sourcesById[activeRoutes[display.id]]!.controllerId!,
          ),
    ];
  }

  /// These throw [ControllerApiException] with a message to show the user.
  Future<void> createSnapshot({
    required String name,
    required String scope,
    required List<SnapshotRoute> routes,
  }) async {
    await SnapshotService.create(name: name, scope: scope, routes: routes);
    await loadSnapshots();
  }

  Future<void> updateSnapshot(
    String id, {
    required String name,
    required String scope,
    required List<SnapshotRoute> routes,
  }) async {
    await SnapshotService.update(id, name: name, scope: scope, routes: routes);
    await loadSnapshots();
  }

  Future<void> deleteSnapshot(String id) async {
    await SnapshotService.delete(id);
    await loadSnapshots();
  }

  // ── Factory reset ─────────────────────────────────────────────────────────

  /// Forgets the app's own device data (adopted devices with their names
  /// and locations, routes) once the SC-1 has confirmed a factory reset.
  Future<void> clearLocalDeviceData() async {
    await DatabaseService.instance.clearDeviceData();
    sources.clear();
    destinationsByLocation.clear();
    activeRoutes.clear();
    controllerDeviceNames.clear();
    snapshots = [];
    lastAdoptedDeviceId = null;
    notifyListeners();
  }

  // ── Users — saved to the database ─────────────────────────────────────────

  UserAccount? userNamed(String username) {
    final name = username.trim().toLowerCase();
    for (final user in users) {
      if (user.username.toLowerCase() == name) return user;
    }
    return null;
  }

  /// These return a message to show when the change isn't allowed.
  Future<String?> addUser({
    required String username,
    required String password,
    required String role,
  }) async {
    username = username.trim();
    if (username.isEmpty) return 'Enter a username.';
    if (userNamed(username) != null) return '$username already exists.';
    final problem = UserAccount.passwordProblem(username, password);
    if (problem != null) return problem;
    // A temporary password: they choose their own at first login.
    final user = UserAccount.withPassword(
      id: 'u_${DateTime.now().microsecondsSinceEpoch}',
      username: username,
      role: role,
      password: password,
      mustChangePassword: true,
    );
    await DatabaseService.instance.saveUser(user);
    users.add(user);
    _refreshListeners();
    return null;
  }

  Future<String?> updateUser(
    UserAccount user, {
    required String username,
    required String role,
    String? newPassword,
  }) async {
    username = username.trim();
    if (username.isEmpty) return 'Enter a username.';
    final existing = userNamed(username);
    if (existing != null && existing.id != user.id) {
      return '$username already exists.';
    }
    if (user.isRootAdmin && role != 'Admin') {
      return 'The main admin account must stay an admin.';
    }
    var updated = user.copyWith(username: username, role: role);
    if (newPassword != null && newPassword.isNotEmpty) {
      final problem = UserAccount.passwordProblem(username, newPassword);
      if (problem != null) return problem;
      // Reset by an admin: the user picks their own at next login.
      updated = UserAccount.withPassword(
        id: user.id,
        username: username,
        role: role,
        password: newPassword,
        mustChangePassword: true,
      );
    }
    await DatabaseService.instance.saveUser(updated);
    users[users.indexWhere((u) => u.id == user.id)] = updated;
    _refreshListeners();
    return null;
  }

  /// The signed-in user sets their own password.
  Future<String?> changeOwnPassword(
    UserAccount user,
    String newPassword,
  ) async {
    final problem = UserAccount.passwordProblem(user.username, newPassword);
    if (problem != null) return problem;
    if (user.checkPassword(newPassword)) {
      return 'Choose a different password from the current one.';
    }
    final updated = UserAccount.withPassword(
      id: user.id,
      username: user.username,
      role: user.role,
      password: newPassword,
      mustChangePassword: false,
    );
    await DatabaseService.instance.saveUser(updated);
    users[users.indexWhere((u) => u.id == user.id)] = updated;
    _refreshListeners();
    return null;
  }

  Future<String?> deleteUser(UserAccount user) async {
    if (user.isRootAdmin) return "The main admin account can't be deleted.";
    await DatabaseService.instance.deleteUser(user.id);
    users.removeWhere((u) => u.id == user.id);
    _refreshListeners();
    return null;
  }
}
