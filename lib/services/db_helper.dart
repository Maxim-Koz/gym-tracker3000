import 'package:supabase_flutter/supabase_flutter.dart';

/// Cloud-backed replacement for the old SQLite DBHelper.
///
/// The public method names, parameters and return shapes are kept identical
/// to the previous SQLite-backed version, so none of the screens that use
/// DBHelper() need to change. Under the hood, every read/write now goes to
/// Supabase (`exercises`, `sessions`, `sets` tables) scoped to the signed-in
/// user via `user_id`, with Row Level Security enforcing that a user can
/// only ever see or modify their own rows. This means a user's workout
/// history now lives in the cloud and is available on any device they log
/// into, instead of being trapped on a single phone's local database.
class DBHelper {
  static final DBHelper _instance = DBHelper._internal();
  factory DBHelper() => _instance;
  DBHelper._internal();

  SupabaseClient get _client => Supabase.instance.client;

  String get _userId {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw StateError(
        'No authenticated user. Please log in before accessing workout data.',
      );
    }
    return user.id;
  }

  Future<int> insertExercise(
    String name,
    String type,
    Map<String, dynamic> data,
  ) async {
    final row = await _client
        .from('exercises')
        .insert({'user_id': _userId, 'name': name, 'type': type, 'data': data})
        .select('id')
        .single();
    return row['id'] as int;
  }

  Future<Map<String, dynamic>?> getExerciseByName(String name) async {
    final rows = await _client
        .from('exercises')
        .select()
        .eq('user_id', _userId)
        .eq('name', name)
        .limit(1);
    if (rows.isEmpty) return null;
    return Map<String, dynamic>.from(rows.first as Map);
  }

  Future<int> insertSession(
    int exerciseId,
    DateTime timestamp, {
    String? note,
  }) async {
    final row = await _client
        .from('sessions')
        .insert({
          'user_id': _userId,
          'exercise_id': exerciseId,
          'timestamp': timestamp.toUtc().toIso8601String(),
          'note': note,
        })
        .select('id')
        .single();
    return row['id'] as int;
  }

  Future<int> insertSet(
    int sessionId,
    double weight,
    int reps,
    String unit, {
    int? groupIndex,
    int? parentSetId,
  }) async {
    final row = await _client
        .from('sets')
        .insert({
          'user_id': _userId,
          'session_id': sessionId,
          'weight': weight,
          'reps': reps,
          'unit': unit,
          'group_index': groupIndex,
          'parent_set_id': parentSetId,
        })
        .select('id')
        .single();
    return row['id'] as int;
  }

  Future<List<Map<String, dynamic>>> getSessionsForExercise(
    int exerciseId,
  ) async {
    final rows = await _client
        .from('sessions')
        .select()
        .eq('user_id', _userId)
        .eq('exercise_id', exerciseId)
        .order('timestamp', ascending: false);
    return rows.map((s) => _withParsedTimestamp(s as Map)).toList();
  }

  Future<List<Map<String, dynamic>>> getSetsForSession(int sessionId) async {
    final rows = await _client
        .from('sets')
        .select()
        .eq('user_id', _userId)
        .eq('session_id', sessionId)
        .order('id', ascending: true);
    return rows.map((r) => Map<String, dynamic>.from(r as Map)).toList();
  }

  Future<List<Map<String, dynamic>>> getAllSessions() async {
    final rows = await _client
        .from('sessions')
        .select()
        .eq('user_id', _userId)
        .order('timestamp', ascending: true);
    return rows.map((s) => _withParsedTimestamp(s as Map)).toList();
  }

  Future<List<Map<String, dynamic>>> getAllSets() async {
    final rows = await _client
        .from('sets')
        .select()
        .eq('user_id', _userId)
        .order('id', ascending: true);
    return rows.map((r) => Map<String, dynamic>.from(r as Map)).toList();
  }

  Future<List<DateTime>> getLoggedDates() async {
    final rows = await _client
        .from('sessions')
        .select('timestamp')
        .eq('user_id', _userId)
        .order('timestamp', ascending: false);

    return rows
        .map((s) {
          final date = DateTime.parse(s['timestamp'] as String).toLocal();
          return DateTime(date.year, date.month, date.day);
        })
        .toSet()
        .toList();
  }

  Future<List<Map<String, dynamic>>> getExercises() async {
    final rows = await _client
        .from('exercises')
        .select()
        .eq('user_id', _userId)
        .order('id', ascending: false);
    return rows.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<Map<String, dynamic>?> getExerciseById(int id) async {
    final rows = await _client
        .from('exercises')
        .select()
        .eq('user_id', _userId)
        .eq('id', id)
        .limit(1);
    if (rows.isEmpty) return null;
    return Map<String, dynamic>.from(rows.first as Map);
  }

  Map<String, dynamic> _withParsedTimestamp(Map row) {
    final copy = Map<String, dynamic>.from(row);
    final raw = copy['timestamp'];
    if (raw is String) {
      copy['timestamp'] = DateTime.parse(raw).toLocal();
    }
    return copy;
  }
}
