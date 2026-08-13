import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// Stockage local (SQLite) pour la résilience hors-ligne (Point 12).
/// - trip_locations : cache des positions GPS avec suivi de synchronisation
/// - sync_queue : file d'attente des opérations API en attente d'envoi
class DatabaseService {
  static const _dbName = 'saferide.db';
  static const _dbVersion = 1;

  static Database? _db;

  static Future<Database> get database async {
    _db ??= await _init();
    return _db!;
  }

  static Future<Database> _init() async {
    final path = p.join(await getDatabasesPath(), _dbName);
    return openDatabase(
      path,
      version: _dbVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  static Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE trip_locations (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        trip_id INTEGER NOT NULL,
        latitude REAL NOT NULL,
        longitude REAL NOT NULL,
        vitesse_km_h REAL,
        captured_at TEXT NOT NULL,
        synced_at TEXT,
        retry_count INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE sync_queue (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        endpoint TEXT NOT NULL,
        method TEXT NOT NULL,
        payload TEXT NOT NULL,
        created_at TEXT NOT NULL,
        retry_count INTEGER NOT NULL DEFAULT 0,
        last_error TEXT
      )
    ''');
  }

  static Future<void> _onUpgrade(Database db, int oldV, int newV) async {
    if (oldV < 2) {
      // futures évolutions de schéma
    }
  }

  static Future<void> close() async {
    await _db?.close();
    _db = null;
  }
}
