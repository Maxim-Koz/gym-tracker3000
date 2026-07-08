import 'dart:convert';

import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

/// Local SQLite cache that backs offline reads and queues offline writes.
///
/// Every row carries the id it will ultimately have in Supabase. Rows that
/// haven't been synced yet (created while offline) get a negative "temp" id
/// and `pending = 1`; once [DBHelper]'s sync step successfully inserts them
/// into Supabase, [replaceExerciseId]/[replaceSessionId]/[replaceSetId]
/// rewrite that row's id to the real one (and cascade the change into any
/// already-cached child rows that referenced the temp id), and flip
/// `pending` to 0.
///
/// Everything is scoped by `user_id` so switching accounts on the same
/// device never leaks one user's cached/queued data into another's.
class LocalCacheDb {
  static final LocalCacheDb _instance = LocalCacheDb._internal();
  factory LocalCacheDb() => _instance;
  LocalCacheDb._internal();

  static Database? _db;

  Future<Database> get db async {
    if (_db != null) return _db!;
    _db = await _initDb();
    return _db!;
  }

  Future<Database> _initDb() async {
    final databasesPath = await getDatabasesPath();
    final path = join(databasesPath, 'gym_tracker_cache.db');
    return await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE cached_exercises (
            id INTEGER NOT NULL,
            user_id TEXT NOT NULL,
            name TEXT NOT NULL,
            type TEXT NOT NULL,
            data TEXT,
            pending INTEGER NOT NULL DEFAULT 0,
            PRIMARY KEY (id, user_id)
          )
        ''');
        await db.execute('''
          CREATE TABLE cached_sessions (
            id INTEGER NOT NULL,
            user_id TEXT NOT NULL,
            exercise_id INTEGER NOT NULL,
            timestamp INTEGER NOT NULL,
            note TEXT,
            pending INTEGER NOT NULL DEFAULT 0,
            PRIMARY KEY (id, user_id)
          )
        ''');
        await db.execute('''
          CREATE TABLE cached_sets (
            id INTEGER NOT NULL,
            user_id TEXT NOT NULL,
            session_id INTEGER NOT NULL,
            weight REAL,
            reps INTEGER,
            unit TEXT,
            group_index INTEGER,
            parent_set_id INTEGER,
            pending INTEGER NOT NULL DEFAULT 0,
            PRIMARY KEY (id, user_id)
          )
        ''');
        await db.execute('''
          CREATE TABLE pending_operations (
            seq INTEGER PRIMARY KEY AUTOINCREMENT,
            user_id TEXT NOT NULL,
            op_type TEXT NOT NULL,
            local_id INTEGER NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE local_meta (
            user_id TEXT NOT NULL,
            key TEXT NOT NULL,
            value INTEGER NOT NULL,
            PRIMARY KEY (user_id, key)
          )
        ''');
      },
    );
  }

  // ---------------------------------------------------------------------
  // Temp id allocation - a monotonically decreasing counter per user,
  // persisted so ids stay unique even across app restarts.
  // ---------------------------------------------------------------------

  Future<int> nextTempId(String userId) async {
    final database = await db;
    return database.transaction((txn) async {
      final rows = await txn.query(
        'local_meta',
        where: 'user_id = ? AND key = ?',
        whereArgs: [userId, 'next_temp_id'],
      );
      final idToUse = rows.isEmpty ? -1 : rows.first['value'] as int;
      await txn.insert('local_meta', {
        'user_id': userId,
        'key': 'next_temp_id',
        'value': idToUse - 1,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      return idToUse;
    });
  }

  // ---------------------------------------------------------------------
  // Upserts (used both to cache fresh remote rows and to store local
  // pending rows created while offline)
  // ---------------------------------------------------------------------

  Future<void> upsertExercise({
    required String userId,
    required int id,
    required String name,
    required String type,
    Map<String, dynamic>? data,
    required bool pending,
  }) async {
    final database = await db;
    await database.insert('cached_exercises', {
      'id': id,
      'user_id': userId,
      'name': name,
      'type': type,
      'data': data == null ? null : jsonEncode(data),
      'pending': pending ? 1 : 0,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> upsertSession({
    required String userId,
    required int id,
    required int exerciseId,
    required int timestampMs,
    String? note,
    required bool pending,
  }) async {
    final database = await db;
    await database.insert('cached_sessions', {
      'id': id,
      'user_id': userId,
      'exercise_id': exerciseId,
      'timestamp': timestampMs,
      'note': note,
      'pending': pending ? 1 : 0,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> upsertSet({
    required String userId,
    required int id,
    required int sessionId,
    double? weight,
    int? reps,
    String? unit,
    int? groupIndex,
    int? parentSetId,
    required bool pending,
  }) async {
    final database = await db;
    await database.insert('cached_sets', {
      'id': id,
      'user_id': userId,
      'session_id': sessionId,
      'weight': weight,
      'reps': reps,
      'unit': unit,
      'group_index': groupIndex,
      'parent_set_id': parentSetId,
      'pending': pending ? 1 : 0,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  // ---------------------------------------------------------------------
  // Reads (decoded to match the shape DBHelper hands back to screens)
  // ---------------------------------------------------------------------

  Map<String, dynamic> _decodeExercise(Map<String, dynamic> row) {
    final copy = Map<String, dynamic>.from(row);
    copy.remove('user_id');
    copy.remove('pending');
    if (copy['data'] != null) {
      try {
        copy['data'] = jsonDecode(copy['data'] as String);
      } catch (_) {
        copy['data'] = <String, dynamic>{};
      }
    }
    return copy;
  }

  Map<String, dynamic> _decodeSession(Map<String, dynamic> row) {
    final copy = Map<String, dynamic>.from(row);
    copy.remove('user_id');
    copy.remove('pending');
    copy['timestamp'] = DateTime.fromMillisecondsSinceEpoch(
      copy['timestamp'] as int,
    );
    return copy;
  }

  Map<String, dynamic> _decodeSet(Map<String, dynamic> row) {
    final copy = Map<String, dynamic>.from(row);
    copy.remove('user_id');
    copy.remove('pending');
    return copy;
  }

  Future<List<Map<String, dynamic>>> getExercises(String userId) async {
    final database = await db;
    final rows = await database.query(
      'cached_exercises',
      where: 'user_id = ?',
      whereArgs: [userId],
      orderBy: 'pending DESC, id DESC',
    );
    return rows.map(_decodeExercise).toList();
  }

  Future<Map<String, dynamic>?> getExerciseById(String userId, int id) async {
    final database = await db;
    final rows = await database.query(
      'cached_exercises',
      where: 'user_id = ? AND id = ?',
      whereArgs: [userId, id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _decodeExercise(rows.first);
  }

  Future<Map<String, dynamic>?> getExerciseByName(
    String userId,
    String name,
  ) async {
    final database = await db;
    final rows = await database.query(
      'cached_exercises',
      where: 'user_id = ? AND name = ?',
      whereArgs: [userId, name],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _decodeExercise(rows.first);
  }

  Future<List<Map<String, dynamic>>> getSessionsForExercise(
    String userId,
    int exerciseId,
  ) async {
    final database = await db;
    final rows = await database.query(
      'cached_sessions',
      where: 'user_id = ? AND exercise_id = ?',
      whereArgs: [userId, exerciseId],
      orderBy: 'timestamp DESC',
    );
    return rows.map(_decodeSession).toList();
  }

  Future<List<Map<String, dynamic>>> getAllSessions(String userId) async {
    final database = await db;
    final rows = await database.query(
      'cached_sessions',
      where: 'user_id = ?',
      whereArgs: [userId],
      orderBy: 'timestamp ASC',
    );
    return rows.map(_decodeSession).toList();
  }

  Future<List<Map<String, dynamic>>> getSetsForSession(
    String userId,
    int sessionId,
  ) async {
    final database = await db;
    final rows = await database.query(
      'cached_sets',
      where: 'user_id = ? AND session_id = ?',
      whereArgs: [userId, sessionId],
      orderBy: 'id ASC',
    );
    return rows.map(_decodeSet).toList();
  }

  Future<List<Map<String, dynamic>>> getAllSets(String userId) async {
    final database = await db;
    final rows = await database.query(
      'cached_sets',
      where: 'user_id = ?',
      whereArgs: [userId],
      orderBy: 'id ASC',
    );
    return rows.map(_decodeSet).toList();
  }

  // ---------------------------------------------------------------------
  // Refresh helpers - replace the "already synced" slice of the cache
  // with a fresh fetch from Supabase, leaving any still-pending local rows
  // untouched (so an offline write made after these rows synced isn't
  // wiped out by a refresh of the already-synced portion).
  // ---------------------------------------------------------------------

  Future<void> refreshExercises(
    String userId,
    List<Map<String, dynamic>> remoteRows,
  ) async {
    final database = await db;
    await database.transaction((txn) async {
      await txn.delete(
        'cached_exercises',
        where: 'user_id = ? AND pending = 0',
        whereArgs: [userId],
      );
      for (final row in remoteRows) {
        await txn.insert('cached_exercises', {
          'id': row['id'],
          'user_id': userId,
          'name': row['name'],
          'type': row['type'],
          'data': row['data'] == null ? null : jsonEncode(row['data']),
          'pending': 0,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
  }

  Future<void> refreshSessionsForExercise(
    String userId,
    int exerciseId,
    List<Map<String, dynamic>> remoteRows,
  ) async {
    final database = await db;
    await database.transaction((txn) async {
      await txn.delete(
        'cached_sessions',
        where: 'user_id = ? AND exercise_id = ? AND pending = 0',
        whereArgs: [userId, exerciseId],
      );
      for (final row in remoteRows) {
        await txn.insert('cached_sessions', {
          'id': row['id'],
          'user_id': userId,
          'exercise_id': row['exercise_id'],
          'timestamp': (row['timestamp'] as DateTime).millisecondsSinceEpoch,
          'note': row['note'],
          'pending': 0,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
  }

  Future<void> refreshAllSessions(
    String userId,
    List<Map<String, dynamic>> remoteRows,
  ) async {
    final database = await db;
    await database.transaction((txn) async {
      await txn.delete(
        'cached_sessions',
        where: 'user_id = ? AND pending = 0',
        whereArgs: [userId],
      );
      for (final row in remoteRows) {
        await txn.insert('cached_sessions', {
          'id': row['id'],
          'user_id': userId,
          'exercise_id': row['exercise_id'],
          'timestamp': (row['timestamp'] as DateTime).millisecondsSinceEpoch,
          'note': row['note'],
          'pending': 0,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
  }

  Future<void> refreshSetsForSession(
    String userId,
    int sessionId,
    List<Map<String, dynamic>> remoteRows,
  ) async {
    final database = await db;
    await database.transaction((txn) async {
      await txn.delete(
        'cached_sets',
        where: 'user_id = ? AND session_id = ? AND pending = 0',
        whereArgs: [userId, sessionId],
      );
      for (final row in remoteRows) {
        await txn.insert('cached_sets', {
          'id': row['id'],
          'user_id': userId,
          'session_id': row['session_id'],
          'weight': row['weight'],
          'reps': row['reps'],
          'unit': row['unit'],
          'group_index': row['group_index'],
          'parent_set_id': row['parent_set_id'],
          'pending': 0,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
  }

  Future<void> refreshAllSets(
    String userId,
    List<Map<String, dynamic>> remoteRows,
  ) async {
    final database = await db;
    await database.transaction((txn) async {
      await txn.delete(
        'cached_sets',
        where: 'user_id = ? AND pending = 0',
        whereArgs: [userId],
      );
      for (final row in remoteRows) {
        await txn.insert('cached_sets', {
          'id': row['id'],
          'user_id': userId,
          'session_id': row['session_id'],
          'weight': row['weight'],
          'reps': row['reps'],
          'unit': row['unit'],
          'group_index': row['group_index'],
          'parent_set_id': row['parent_set_id'],
          'pending': 0,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
  }

  // ---------------------------------------------------------------------
  // Resolving temp ids to real ids once a queued row has synced, cascading
  // the change into any already-cached child rows that pointed at it.
  // ---------------------------------------------------------------------

  Future<void> replaceExerciseId(String userId, int tempId, int realId) async {
    final database = await db;
    await database.transaction((txn) async {
      await txn.update(
        'cached_exercises',
        {'id': realId, 'pending': 0},
        where: 'user_id = ? AND id = ?',
        whereArgs: [userId, tempId],
      );
      await txn.update(
        'cached_sessions',
        {'exercise_id': realId},
        where: 'user_id = ? AND exercise_id = ?',
        whereArgs: [userId, tempId],
      );
    });
  }

  Future<void> replaceSessionId(String userId, int tempId, int realId) async {
    final database = await db;
    await database.transaction((txn) async {
      await txn.update(
        'cached_sessions',
        {'id': realId, 'pending': 0},
        where: 'user_id = ? AND id = ?',
        whereArgs: [userId, tempId],
      );
      await txn.update(
        'cached_sets',
        {'session_id': realId},
        where: 'user_id = ? AND session_id = ?',
        whereArgs: [userId, tempId],
      );
    });
  }

  Future<void> replaceSetId(String userId, int tempId, int realId) async {
    final database = await db;
    await database.transaction((txn) async {
      await txn.update(
        'cached_sets',
        {'id': realId, 'pending': 0},
        where: 'user_id = ? AND id = ?',
        whereArgs: [userId, tempId],
      );
      await txn.update(
        'cached_sets',
        {'parent_set_id': realId},
        where: 'user_id = ? AND parent_set_id = ?',
        whereArgs: [userId, tempId],
      );
    });
  }

  // ---------------------------------------------------------------------
  // Raw (undecoded) single-row lookups used by the sync step - it reads
  // the row's *current* field values, which reflect any earlier id
  // replacements from ancestors that synced earlier in the same run.
  // ---------------------------------------------------------------------

  Future<Map<String, dynamic>?> getCachedExerciseRaw(
    String userId,
    int id,
  ) async {
    final database = await db;
    final rows = await database.query(
      'cached_exercises',
      where: 'user_id = ? AND id = ?',
      whereArgs: [userId, id],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  Future<Map<String, dynamic>?> getCachedSessionRaw(
    String userId,
    int id,
  ) async {
    final database = await db;
    final rows = await database.query(
      'cached_sessions',
      where: 'user_id = ? AND id = ?',
      whereArgs: [userId, id],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  Future<Map<String, dynamic>?> getCachedSetRaw(String userId, int id) async {
    final database = await db;
    final rows = await database.query(
      'cached_sets',
      where: 'user_id = ? AND id = ?',
      whereArgs: [userId, id],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  // ---------------------------------------------------------------------
  // Pending operations queue
  // ---------------------------------------------------------------------

  Future<void> enqueueOperation({
    required String userId,
    required String opType,
    required int localId,
  }) async {
    final database = await db;
    await database.insert('pending_operations', {
      'user_id': userId,
      'op_type': opType,
      'local_id': localId,
    });
  }

  Future<List<Map<String, dynamic>>> getPendingOperations(String userId) async {
    final database = await db;
    return database.query(
      'pending_operations',
      where: 'user_id = ?',
      whereArgs: [userId],
      orderBy: 'seq ASC',
    );
  }

  Future<void> deletePendingOperation(int seq) async {
    final database = await db;
    await database.delete(
      'pending_operations',
      where: 'seq = ?',
      whereArgs: [seq],
    );
  }

  Future<int> pendingOperationsCount(String userId) async {
    final database = await db;
    final result = await database.rawQuery(
      'SELECT COUNT(*) AS count FROM pending_operations WHERE user_id = ?',
      [userId],
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  /// Wipes this user's cache and queue. Intended to be called on logout so
  /// a different account signing in on the same device never sees stale
  /// data left behind while offline.
  Future<void> clearForUser(String userId) async {
    final database = await db;
    await database.transaction((txn) async {
      await txn.delete(
        'cached_exercises',
        where: 'user_id = ?',
        whereArgs: [userId],
      );
      await txn.delete(
        'cached_sessions',
        where: 'user_id = ?',
        whereArgs: [userId],
      );
      await txn.delete(
        'cached_sets',
        where: 'user_id = ?',
        whereArgs: [userId],
      );
      await txn.delete(
        'pending_operations',
        where: 'user_id = ?',
        whereArgs: [userId],
      );
      await txn.delete('local_meta', where: 'user_id = ?', whereArgs: [userId]);
    });
  }
}
