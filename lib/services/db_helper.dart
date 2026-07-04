import 'dart:convert';

import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

class DBHelper {
  static final DBHelper _instance = DBHelper._internal();
  factory DBHelper() => _instance;
  DBHelper._internal();

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
      version: 2,
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
          FOREIGN KEY(session_id) REFERENCES sessions(id) ON DELETE CASCADE
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
      },
    );
  }

  Future<int> insertExercise(
    String name,
    String type,
    Map<String, dynamic> data,
  ) async {
    final database = await db;
    return await database.insert('exercises', {
      'name': name,
      'type': type,
      'data': jsonEncode(data),
    });
  }

  Future<Map<String, dynamic>?> getExerciseByName(String name) async {
    final database = await db;
    final rows = await database.query(
      'exercises',
      where: 'name = ?',
      whereArgs: [name],
    );
    if (rows.isEmpty) return null;
    final copy = Map<String, dynamic>.from(rows.first);
    if (copy['data'] != null) {
      copy['data'] = jsonDecode(copy['data'] as String);
    }
    return copy;
  }

  Future<int> insertSession(int exerciseId, DateTime timestamp) async {
    final database = await db;
    return await database.insert('sessions', {
      'exercise_id': exerciseId,
      'timestamp': timestamp.millisecondsSinceEpoch,
    });
  }

  Future<int> insertSet(
    int sessionId,
    double weight,
    int reps,
    String unit,
  ) async {
    final database = await db;
    return await database.insert('sets', {
      'session_id': sessionId,
      'weight': weight,
      'reps': reps,
      'unit': unit,
    });
  }

  Future<List<Map<String, dynamic>>> getSessionsForExercise(
    int exerciseId,
  ) async {
    final database = await db;
    final sessions = await database.query(
      'sessions',
      where: 'exercise_id = ?',
      whereArgs: [exerciseId],
      orderBy: 'timestamp DESC',
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
    final rows = await database.query(
      'sets',
      where: 'session_id = ?',
      whereArgs: [sessionId],
    );
    return rows;
  }

  Future<List<Map<String, dynamic>>> getExercises() async {
    final database = await db;
    final list = await database.query('exercises', orderBy: 'id DESC');
    return list.map((e) {
      final copy = Map<String, dynamic>.from(e);
      if (copy['data'] != null) {
        try {
          copy['data'] = jsonDecode(copy['data'] as String);
        } catch (_) {
          copy['data'] = null;
        }
      }
      return copy;
    }).toList();
  }

  Future<Map<String, dynamic>?> getExerciseById(int id) async {
    final database = await db;
    final rows = await database.query(
      'exercises',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (rows.isEmpty) return null;
    final copy = Map<String, dynamic>.from(rows.first);
    if (copy['data'] != null) {
      copy['data'] = jsonDecode(copy['data'] as String);
    }
    return copy;
  }
}
