import 'dart:convert';

import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

/// This is the old SQLite-backed storage layer, kept around under a new name
/// purely so [DataMigrationService] can read whatever a device already has
/// locally and copy it up to Supabase. New reads/writes should always go
/// through DBHelper (Supabase-backed) instead — nothing in the app should
/// write to this class going forward.
class LegacyLocalDb {
  static final LegacyLocalDb _instance = LegacyLocalDb._internal();
  factory LegacyLocalDb() => _instance;
  LegacyLocalDb._internal();

  static Database? _db;

  Future<Database> get db async {
    if (_db != null) return _db!;
    _db = await _initDb();
    return _db!;
  }

  Future<Database> _initDb() async {
    final databasesPath = await getDatabasesPath();
    final path = join(databasesPath, 'gym_tracker.db');
    return await openDatabase(
      path,
      version: 5,
      onCreate: (db, version) async {
        await db.execute('''
        CREATE TABLE exercises (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL UNIQUE,
          type TEXT NOT NULL,
          data TEXT
        )
      ''');

        await db.execute('''
        CREATE TABLE sessions (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          exercise_id INTEGER NOT NULL,
          timestamp INTEGER NOT NULL,
          note TEXT,
          FOREIGN KEY(exercise_id) REFERENCES exercises(id) ON DELETE CASCADE
        )
      ''');

        await db.execute('''
        CREATE TABLE sets (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          session_id INTEGER NOT NULL,
          weight REAL,
          reps INTEGER,
          unit TEXT,
          group_index INTEGER,
          parent_set_id INTEGER,
          FOREIGN KEY(session_id) REFERENCES sessions(id) ON DELETE CASCADE,
          FOREIGN KEY(parent_set_id) REFERENCES sets(id) ON DELETE CASCADE
        )
      ''');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS sessions (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              exercise_id INTEGER NOT NULL,
              timestamp INTEGER NOT NULL,
              FOREIGN KEY(exercise_id) REFERENCES exercises(id) ON DELETE CASCADE
            )
          ''');

          await db.execute('''
            CREATE TABLE IF NOT EXISTS sets (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              session_id INTEGER NOT NULL,
              weight REAL,
              reps INTEGER,
              unit TEXT,
              FOREIGN KEY(session_id) REFERENCES sessions(id) ON DELETE CASCADE
            )
          ''');

          await db.execute(
            'CREATE UNIQUE INDEX IF NOT EXISTS idx_exercises_name ON exercises(name)',
          );
        }

        if (oldVersion < 3) {
          final columns = await db.rawQuery('PRAGMA table_info(sets)');
          final hasGroupIndex = columns.any(
            (col) => col['name'] == 'group_index',
          );
          if (!hasGroupIndex) {
            await db.execute('ALTER TABLE sets ADD COLUMN group_index INTEGER');
          }
        }

        if (oldVersion < 4) {
          final columns = await db.rawQuery('PRAGMA table_info(sets)');
          final hasParentSetId = columns.any(
            (col) => col['name'] == 'parent_set_id',
          );
          if (!hasParentSetId) {
            await db.execute(
              'ALTER TABLE sets ADD COLUMN parent_set_id INTEGER',
            );
          }
        }

        if (oldVersion < 5) {
          final columns = await db.rawQuery('PRAGMA table_info(sessions)');
          final hasNote = columns.any((col) => col['name'] == 'note');
          if (!hasNote) {
            await db.execute('ALTER TABLE sessions ADD COLUMN note TEXT');
          }
        }
      },
    );
  }

  /// True if a local SQLite database file with at least one exercise exists
  /// on this device. Lets the migration step skip touching the DB entirely
  /// on a fresh install / fresh device where there is nothing to migrate.
  Future<bool> hasAnyLocalData() async {
    try {
      final exercises = await getExercises();
      return exercises.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  Future<List<Map<String, dynamic>>> getExercises() async {
    final database = await db;
    final list = await database.query('exercises', orderBy: 'id ASC');
    return list.map((e) {
      final copy = Map<String, dynamic>.from(e);
      if (copy['data'] != null) {
        try {
          copy['data'] = jsonDecode(copy['data'] as String);
        } catch (_) {
          copy['data'] = <String, dynamic>{};
        }
      }
      return copy;
    }).toList();
  }

  Future<List<Map<String, dynamic>>> getSessionsForExercise(
    int exerciseId,
  ) async {
    final database = await db;
    final sessions = await database.query(
      'sessions',
      where: 'exercise_id = ?',
      whereArgs: [exerciseId],
      orderBy: 'timestamp ASC',
    );
    return sessions.map((s) {
      final copy = Map<String, dynamic>.from(s);
      copy['timestamp'] = DateTime.fromMillisecondsSinceEpoch(
        copy['timestamp'] as int,
      );
      return copy;
    }).toList();
  }

  Future<List<Map<String, dynamic>>> getSetsForSession(int sessionId) async {
    final database = await db;
    return await database.query(
      'sets',
      where: 'session_id = ?',
      whereArgs: [sessionId],
      orderBy: 'id ASC',
    );
  }
}
