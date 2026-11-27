import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/device_model.dart';
import '../logic/app_state.dart' show UserAccount;

class DatabaseService {
  static final DatabaseService instance = DatabaseService._internal();
  DatabaseService._internal();

  static Database? _db;

  Future<Database> get database async {
    _db ??= await _initDb();
    return _db!;
  }

  Future<Database> _initDb() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'authenticav.db');

    return await openDatabase(
      path,
      version: 2,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    // v2: login accounts are saved (they used to live only in memory).
    if (oldVersion < 2) await _createUsersTable(db);
  }

  Future<void> _createUsersTable(Database db) async {
    await db.execute('''
      CREATE TABLE users (
        id TEXT PRIMARY KEY,
        username TEXT NOT NULL UNIQUE,
        role TEXT NOT NULL,
        password_hash TEXT NOT NULL,
        salt TEXT NOT NULL,
        must_change_password INTEGER NOT NULL DEFAULT 0
      )
    ''');
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE discovered_devices (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        ip TEXT NOT NULL UNIQUE,
        mac TEXT NOT NULL,
        signal INTEGER NOT NULL DEFAULT 100,
        type TEXT NOT NULL,
        last_seen INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE adopted_devices (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        ip TEXT NOT NULL,
        type TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'online',
        location TEXT NOT NULL DEFAULT 'Unassigned',
        preview_url TEXT,
        video_url TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE active_routes (
        destination_id TEXT PRIMARY KEY,
        source_id TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE settings (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');

    await _createUsersTable(db);
  }

  /// Forgets every adopted device, route and saved scan (after an SC-1
  /// factory reset). Login accounts and settings stay.
  Future<void> clearDeviceData() async {
    final db = await database;
    final batch = db.batch();
    batch.delete('adopted_devices');
    batch.delete('active_routes');
    batch.delete('discovered_devices');
    await batch.commit(noResult: true);
  }

  // ── Users ─────────────────────────────────────────────────────────────────

  Future<List<UserAccount>> loadUsers() async {
    final db = await database;
    final rows = await db.query('users');
    return [
      for (final row in rows)
        UserAccount(
          id: row['id'] as String,
          username: row['username'] as String,
          role: row['role'] as String,
          passwordHash: row['password_hash'] as String,
          salt: row['salt'] as String,
          mustChangePassword: (row['must_change_password'] as int) == 1,
        ),
    ];
  }

  Future<void> saveUser(UserAccount user) async {
    final db = await database;
    await db.insert('users', {
      'id': user.id,
      'username': user.username,
      'role': user.role,
      'password_hash': user.passwordHash,
      'salt': user.salt,
      'must_change_password': user.mustChangePassword ? 1 : 0,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> deleteUser(String id) async {
    final db = await database;
    await db.delete('users', where: 'id = ?', whereArgs: [id]);
  }

  // ── Discovered Devices ────────────────────────────────────────────────────

  /// Replaces the saved scan with [devices].
  Future<void> saveDiscoveredDevices(List<Map<String, dynamic>> devices) async {
    final db = await database;
    final batch = db.batch();
    final now = DateTime.now().millisecondsSinceEpoch;
    batch.delete('discovered_devices');

    for (final d in devices) {
      batch.insert(
        'discovered_devices',
        {...d, 'last_seen': now},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<List<Map<String, dynamic>>> loadDiscoveredDevices() async {
    final db = await database;
    return await db.query('discovered_devices', orderBy: 'last_seen DESC');
  }

  // ── Adopted Devices ───────────────────────────────────────────────────────

  Future<void> saveAdoptedDevice(Device device) async {
    final db = await database;
    await db.insert(
      'adopted_devices',
      {
        'id': device.id,
        'name': device.name,
        'ip': device.ip,
        'type': device.type.name,
        'status': device.status.name,
        'location': device.location,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> deleteAdoptedDevice(String deviceId) async {
    final db = await database;
    await db.delete('adopted_devices', where: 'id = ?', whereArgs: [deviceId]);
  }

  Future<List<Device>> loadAdoptedDevices() async {
    final db = await database;
    final rows = await db.query('adopted_devices');
    return rows.map((row) => Device(
      id: row['id'] as String,
      name: row['name'] as String,
      ip: row['ip'] as String,
      type: DeviceType.values.firstWhere((e) => e.name == row['type'], orElse: () => DeviceType.rx),
      status: DeviceStatus.values.firstWhere((e) => e.name == row['status'], orElse: () => DeviceStatus.online),
      location: row['location'] as String? ?? 'Unassigned',
    )).toList();
  }

  // ── Active Routes ─────────────────────────────────────────────────────────

  Future<void> saveActiveRoutes(Map<String, String?> routes) async {
    final db = await database;
    await db.delete('active_routes');
    final batch = db.batch();
    for (final entry in routes.entries) {
      batch.insert('active_routes', {
        'destination_id': entry.key,
        'source_id': entry.value,
      });
    }
    await batch.commit(noResult: true);
  }

  Future<Map<String, String?>> loadActiveRoutes() async {
    final db = await database;
    final rows = await db.query('active_routes');
    return {for (final r in rows) r['destination_id'] as String: r['source_id'] as String?};
  }

  // ── Settings ──────────────────────────────────────────────────────────────

  Future<void> saveSetting(String key, String value) async {
    final db = await database;
    await db.insert(
      'settings',
      {'key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> deleteSetting(String key) async {
    final db = await database;
    await db.delete('settings', where: 'key = ?', whereArgs: [key]);
  }

  Future<String?> loadSetting(String key) async {
    final db = await database;
    final rows = await db.query('settings', where: 'key = ?', whereArgs: [key]);
    if (rows.isEmpty) return null;
    return rows.first['value'] as String?;
  }
}
