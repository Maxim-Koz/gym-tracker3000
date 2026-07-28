import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'local_cache_db.dart';
import 'network_preferences.dart';

/// Cloud-backed, offline-capable replacement for the old SQLite DBHelper.
///
/// The public method names, parameters and return shapes are unchanged, so
/// no screen needs to change. Behaviour:
///  - Before touching the network, every method checks the device's current
///    connectivity state ([_hasNetwork]) - a fast local OS call, not a
///    network request. If there's no connection at all, it skips straight
///    to the cache/queue instead of waiting out a timeout, which is what
///    made things feel slow offline.
///  - When there is a connection, reads try Supabase (bounded by
///    [_networkTimeout] in case the connection is up but not actually
///    reaching the internet), refresh the local cache with whatever came
///    back, then always return from the cache.
///  - Writes try Supabase first when there's a connection; on failure (or
///    when there's none) they write a row into the local cache with a
///    negative "temp" id, queue it for sync, and return that temp id so
///    callers (which chain ids, e.g. insertSession -> insertSet) keep
///    working exactly as if the write had succeeded.
///  - A write whose parent hasn't synced yet (temp exercise/session id) is
///    always queued immediately, since Supabase has no row for that parent
///    yet regardless of connectivity.
class DBHelper {
  static final DBHelper _instance = DBHelper._internal();
  factory DBHelper() => _instance;
  DBHelper._internal();

  /// Sentinel default for `note` params so callers can distinguish "leave
  /// the note unchanged" from "clear the note" (pass note: null).
  static const Object _unset = Object();

  final LocalCacheDb _cache = LocalCacheDb();
  final Connectivity _connectivity = Connectivity();
  static const _networkTimeout = Duration(seconds: 5);

  bool _isSyncing = false;

  /// Number of writes still waiting to reach Supabase. Screens can listen
  /// to this to show a small "syncing" indicator.
  final ValueNotifier<int> pendingSyncCount = ValueNotifier<int>(0);

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

  bool _isTemp(int id) => id < 0;

  /// Fast, local check of whether the device currently has a usable
  /// network interface up. Does not confirm real internet reachability,
  /// but answers in milliseconds rather than seconds, which is what
  /// matters for keeping the app snappy while offline.
  ///
  /// If the only interface up is mobile (cellular) data, this also
  /// consults [NetworkPreferences] - when the user has turned mobile data
  /// off in Settings, a mobile-only connection is treated the same as no
  /// connection at all, so the app falls back to the cache/queue instead
  /// of using cellular data. Wi-Fi/ethernet/etc always count as online
  /// regardless of that setting.
  Future<bool> _hasNetwork() async {
    try {
      final results = await _connectivity.checkConnectivity();
      final usable = results.where((r) => r != ConnectivityResult.none).toSet();
      if (usable.isEmpty) return false;

      final hasNonMobile = usable.any((r) => r != ConnectivityResult.mobile);
      if (hasNonMobile) return true;

      // Only mobile data is available - respect the user's preference.
      return NetworkPreferences().isMobileDataAllowed();
    } catch (_) {
      // Connectivity state unknown - fall through and let the network
      // attempt itself (bounded by _networkTimeout) decide.
      return true;
    }
  }

  bool _looksOffline(Object error) {
    if (error is SocketException) return true;
    if (error is TimeoutException) return true;
    final message = error.toString().toLowerCase();
    return message.contains('socketexception') ||
        message.contains('failed host lookup') ||
        message.contains('network is unreachable') ||
        message.contains('connection refused') ||
        message.contains('connection closed') ||
        message.contains('connection reset') ||
        message.contains('clientexception') ||
        message.contains('timeoutexception') ||
        message.contains('handshakeexception');
  }

  Future<void> refreshPendingSyncCount() async {
    try {
      pendingSyncCount.value = await _cache.pendingOperationsCount(_userId);
    } catch (_) {
      pendingSyncCount.value = 0;
    }
  }

  /// Clears this user's offline cache/queue. Call on logout.
  Future<void> clearLocalDataForCurrentUser() async {
    final user = _client.auth.currentUser;
    if (user == null) return;
    await _cache.clearForUser(user.id);
    pendingSyncCount.value = 0;
  }

  /// Proactively fetches and caches the full exercises/sessions/sets lists
  /// whenever there's a connection - not just when a screen that happens to
  /// call getExercises()/getAllSessions()/getAllSets() is opened. Without
  /// this, a user who e.g. only ever used the "record exercise" screen
  /// while online would find the stats page and home calendar empty the
  /// first time they open them offline, since those full-table caches
  /// would never have been warmed. Safe to call often - each call is a
  /// no-op if there's no connection or no signed-in user.
  Future<void> warmCaches() async {
    if (_client.auth.currentUser == null) return;
    if (!await _hasNetwork()) return;
    try {
      await getExercises();
      await getAllSessions();
      await getAllSets();
    } catch (_) {
      // Best-effort - whichever screen is actually opened will retry.
    }
  }

  // -------------------------------------------------------------------
  // Exercises
  // -------------------------------------------------------------------

  Future<int> insertExercise(
    String name,
    String type,
    Map<String, dynamic> data,
  ) async {
    final userId = _userId;
    if (await _hasNetwork()) {
      try {
        final row = await _client
            .from('exercises')
            .insert({
              'user_id': userId,
              'name': name,
              'type': type,
              'data': data,
            })
            .select('id')
            .single()
            .timeout(_networkTimeout);
        final id = row['id'] as int;
        await _cache.upsertExercise(
          userId: userId,
          id: id,
          name: name,
          type: type,
          data: data,
          pending: false,
        );
        return id;
      } catch (e) {
        if (!_looksOffline(e)) rethrow;
      }
    }
    return _queueExerciseInsert(userId, name, type, data);
  }

  Future<int> _queueExerciseInsert(
    String userId,
    String name,
    String type,
    Map<String, dynamic> data,
  ) async {
    final tempId = await _cache.nextTempId(userId);
    await _cache.upsertExercise(
      userId: userId,
      id: tempId,
      name: name,
      type: type,
      data: data,
      pending: true,
    );
    await _cache.enqueueOperation(
      userId: userId,
      opType: 'insert_exercise',
      localId: tempId,
    );
    await refreshPendingSyncCount();
    return tempId;
  }

  Future<Map<String, dynamic>?> getExerciseByName(String name) async {
    final userId = _userId;
    if (await _hasNetwork()) {
      try {
        final rows = await _client
            .from('exercises')
            .select()
            .eq('user_id', userId)
            .eq('name', name)
            .limit(1)
            .timeout(_networkTimeout);
        if (rows.isNotEmpty) {
          final row = Map<String, dynamic>.from(rows.first as Map);
          await _cache.upsertExercise(
            userId: userId,
            id: row['id'] as int,
            name: row['name'] as String,
            type: row['type'] as String,
            data: row['data'] as Map<String, dynamic>?,
            pending: false,
          );
        }
      } catch (_) {
        // Any failure here (not just an obviously network-shaped
        // error) just means we fall back to the cache below - a
        // stale read is always better than crashing the screen.
      }
    }
    return _cache.getExerciseByName(userId, name);
  }

  Future<Map<String, dynamic>?> getExerciseById(int id) async {
    final userId = _userId;
    if (_isTemp(id)) {
      return _cache.getExerciseById(userId, id);
    }
    if (await _hasNetwork()) {
      try {
        final rows = await _client
            .from('exercises')
            .select()
            .eq('user_id', userId)
            .eq('id', id)
            .limit(1)
            .timeout(_networkTimeout);
        if (rows.isNotEmpty) {
          final row = Map<String, dynamic>.from(rows.first as Map);
          await _cache.upsertExercise(
            userId: userId,
            id: row['id'] as int,
            name: row['name'] as String,
            type: row['type'] as String,
            data: row['data'] as Map<String, dynamic>?,
            pending: false,
          );
        }
      } catch (_) {
        // Any failure here (not just an obviously network-shaped
        // error) just means we fall back to the cache below - a
        // stale read is always better than crashing the screen.
      }
    }
    return _cache.getExerciseById(userId, id);
  }

  Future<List<Map<String, dynamic>>> getExercises() async {
    final userId = _userId;
    if (await _hasNetwork()) {
      try {
        final rows = await _client
            .from('exercises')
            .select()
            .eq('user_id', userId)
            .order('id', ascending: false)
            .timeout(_networkTimeout);
        await _cache.refreshExercises(
          userId,
          rows.map((e) => Map<String, dynamic>.from(e as Map)).toList(),
        );
      } catch (_) {
        // Any failure here (not just an obviously network-shaped
        // error) just means we fall back to the cache below - a
        // stale read is always better than crashing the screen.
      }
    }
    return _cache.getExercises(userId);
  }

  // -------------------------------------------------------------------
  // Sessions
  // -------------------------------------------------------------------

  Future<int> insertSession(
    int exerciseId,
    DateTime timestamp, {
    String? note,
  }) async {
    final userId = _userId;
    if (_isTemp(exerciseId)) {
      return _queueSessionInsert(userId, exerciseId, timestamp, note);
    }
    if (await _hasNetwork()) {
      try {
        final row = await _client
            .from('sessions')
            .insert({
              'user_id': userId,
              'exercise_id': exerciseId,
              'timestamp': timestamp.toUtc().toIso8601String(),
              'note': note,
            })
            .select('id')
            .single()
            .timeout(_networkTimeout);
        final id = row['id'] as int;
        await _cache.upsertSession(
          userId: userId,
          id: id,
          exerciseId: exerciseId,
          timestampMs: timestamp.millisecondsSinceEpoch,
          note: note,
          pending: false,
        );
        return id;
      } catch (e) {
        if (!_looksOffline(e)) rethrow;
      }
    }
    return _queueSessionInsert(userId, exerciseId, timestamp, note);
  }

  Future<int> _queueSessionInsert(
    String userId,
    int exerciseId,
    DateTime timestamp,
    String? note,
  ) async {
    final tempId = await _cache.nextTempId(userId);
    await _cache.upsertSession(
      userId: userId,
      id: tempId,
      exerciseId: exerciseId,
      timestampMs: timestamp.millisecondsSinceEpoch,
      note: note,
      pending: true,
    );
    await _cache.enqueueOperation(
      userId: userId,
      opType: 'insert_session',
      localId: tempId,
    );
    await refreshPendingSyncCount();
    return tempId;
  }

  Future<List<Map<String, dynamic>>> getSessionsForExercise(
    int exerciseId,
  ) async {
    final userId = _userId;
    if (_isTemp(exerciseId)) {
      return _cache.getSessionsForExercise(userId, exerciseId);
    }
    if (await _hasNetwork()) {
      try {
        final rows = await _client
            .from('sessions')
            .select()
            .eq('user_id', userId)
            .eq('exercise_id', exerciseId)
            .order('timestamp', ascending: false)
            .timeout(_networkTimeout);
        await _cache.refreshSessionsForExercise(
          userId,
          exerciseId,
          rows.map((s) => _withParsedTimestamp(s as Map)).toList(),
        );
      } catch (_) {
        // Any failure here (not just an obviously network-shaped
        // error) just means we fall back to the cache below - a
        // stale read is always better than crashing the screen.
      }
    }
    return _cache.getSessionsForExercise(userId, exerciseId);
  }

  Future<List<Map<String, dynamic>>> getAllSessions() async {
    final userId = _userId;
    if (await _hasNetwork()) {
      try {
        final rows = await _client
            .from('sessions')
            .select()
            .eq('user_id', userId)
            .order('timestamp', ascending: true)
            .timeout(_networkTimeout);
        await _cache.refreshAllSessions(
          userId,
          rows.map((s) => _withParsedTimestamp(s as Map)).toList(),
        );
      } catch (_) {
        // Any failure here (not just an obviously network-shaped
        // error) just means we fall back to the cache below - a
        // stale read is always better than crashing the screen.
      }
    }
    return _cache.getAllSessions(userId);
  }

  /// Updates a session's note and/or date. Omit a parameter to leave it
  /// unchanged; pass `note: null` explicitly to clear the note.
  Future<void> updateSession(
    int sessionId, {
    Object? note = _unset,
    DateTime? timestamp,
  }) async {
    final userId = _userId;
    final cached = await _cache.getCachedSessionRaw(userId, sessionId);
    if (cached == null) return;
    final exerciseId = cached['exercise_id'] as int;
    final newNote = identical(note, _unset)
        ? cached['note'] as String?
        : note as String?;
    final newTimestampMs =
        timestamp?.millisecondsSinceEpoch ?? cached['timestamp'] as int;

    if (_isTemp(sessionId)) {
      await _cache.upsertSession(
        userId: userId,
        id: sessionId,
        exerciseId: exerciseId,
        timestampMs: newTimestampMs,
        note: newNote,
        pending: true,
      );
      return;
    }

    if (await _hasNetwork()) {
      try {
        await _client
            .from('sessions')
            .update({
              'note': newNote,
              'timestamp': DateTime.fromMillisecondsSinceEpoch(
                newTimestampMs,
              ).toUtc().toIso8601String(),
            })
            .eq('user_id', userId)
            .eq('id', sessionId)
            .timeout(_networkTimeout);
        await _cache.upsertSession(
          userId: userId,
          id: sessionId,
          exerciseId: exerciseId,
          timestampMs: newTimestampMs,
          note: newNote,
          pending: false,
        );
        return;
      } catch (e) {
        if (!_looksOffline(e)) rethrow;
      }
    }

    await _cache.upsertSession(
      userId: userId,
      id: sessionId,
      exerciseId: exerciseId,
      timestampMs: newTimestampMs,
      note: newNote,
      pending: true,
    );
    final alreadyQueued = await _cache.hasPendingOperation(
      userId: userId,
      opType: 'update_session',
      localId: sessionId,
    );
    if (!alreadyQueued) {
      await _cache.enqueueOperation(
        userId: userId,
        opType: 'update_session',
        localId: sessionId,
      );
    }
    await refreshPendingSyncCount();
  }

  /// Deletes a session and every set (including rest-pause children) that
  /// belongs to it. Each set is deleted individually first (so its own
  /// online/offline/temp-id handling runs), then the session itself.
  Future<void> deleteSession(int sessionId) async {
    final userId = _userId;
    final setIds = await _cache.getSetIdsForSession(userId, sessionId);
    for (final setId in setIds) {
      await deleteSet(setId);
    }

    if (_isTemp(sessionId)) {
      await _cache.hardDeleteSession(userId, sessionId);
      return;
    }

    if (await _hasNetwork()) {
      try {
        await _client
            .from('sessions')
            .delete()
            .eq('user_id', userId)
            .eq('id', sessionId)
            .timeout(_networkTimeout);
        await _cache.hardDeleteSession(userId, sessionId);
        await refreshPendingSyncCount();
        return;
      } catch (e) {
        if (!_looksOffline(e)) rethrow;
      }
    }

    await _cache.softDeleteSession(userId, sessionId);
    final alreadyQueued = await _cache.hasPendingOperation(
      userId: userId,
      opType: 'delete_session',
      localId: sessionId,
    );
    if (!alreadyQueued) {
      await _cache.enqueueOperation(
        userId: userId,
        opType: 'delete_session',
        localId: sessionId,
      );
    }
    await refreshPendingSyncCount();
  }

  Future<List<DateTime>> getLoggedDates() async {
    final sessions = await getAllSessions();
    return sessions
        .map((s) {
          final date = s['timestamp'] as DateTime;
          return DateTime(date.year, date.month, date.day);
        })
        .toSet()
        .toList();
  }

  // -------------------------------------------------------------------
  // Sets
  // -------------------------------------------------------------------

  Future<int> insertSet(
    int sessionId,
    double weight,
    int reps,
    String unit, {
    int? groupIndex,
    int? parentSetId,
  }) async {
    final userId = _userId;
    final hasUnsyncedParent =
        _isTemp(sessionId) || (parentSetId != null && _isTemp(parentSetId));
    if (hasUnsyncedParent) {
      return _queueSetInsert(
        userId,
        sessionId,
        weight,
        reps,
        unit,
        groupIndex,
        parentSetId,
      );
    }
    if (await _hasNetwork()) {
      try {
        final row = await _client
            .from('sets')
            .insert({
              'user_id': userId,
              'session_id': sessionId,
              'weight': weight,
              'reps': reps,
              'unit': unit,
              'group_index': groupIndex,
              'parent_set_id': parentSetId,
            })
            .select('id')
            .single()
            .timeout(_networkTimeout);
        final id = row['id'] as int;
        await _cache.upsertSet(
          userId: userId,
          id: id,
          sessionId: sessionId,
          weight: weight,
          reps: reps,
          unit: unit,
          groupIndex: groupIndex,
          parentSetId: parentSetId,
          pending: false,
        );
        return id;
      } catch (e) {
        if (!_looksOffline(e)) rethrow;
      }
    }
    return _queueSetInsert(
      userId,
      sessionId,
      weight,
      reps,
      unit,
      groupIndex,
      parentSetId,
    );
  }

  Future<int> _queueSetInsert(
    String userId,
    int sessionId,
    double weight,
    int reps,
    String unit,
    int? groupIndex,
    int? parentSetId,
  ) async {
    final tempId = await _cache.nextTempId(userId);
    await _cache.upsertSet(
      userId: userId,
      id: tempId,
      sessionId: sessionId,
      weight: weight,
      reps: reps,
      unit: unit,
      groupIndex: groupIndex,
      parentSetId: parentSetId,
      pending: true,
    );
    await _cache.enqueueOperation(
      userId: userId,
      opType: 'insert_set',
      localId: tempId,
    );
    await refreshPendingSyncCount();
    return tempId;
  }

  Future<List<Map<String, dynamic>>> getSetsForSession(int sessionId) async {
    final userId = _userId;
    if (_isTemp(sessionId)) {
      return _cache.getSetsForSession(userId, sessionId);
    }
    if (await _hasNetwork()) {
      try {
        final rows = await _client
            .from('sets')
            .select()
            .eq('user_id', userId)
            .eq('session_id', sessionId)
            .order('id', ascending: true)
            .timeout(_networkTimeout);
        await _cache.refreshSetsForSession(
          userId,
          sessionId,
          rows.map((r) => Map<String, dynamic>.from(r as Map)).toList(),
        );
      } catch (_) {
        // Any failure here (not just an obviously network-shaped
        // error) just means we fall back to the cache below - a
        // stale read is always better than crashing the screen.
      }
    }
    return _cache.getSetsForSession(userId, sessionId);
  }

  Future<List<Map<String, dynamic>>> getAllSets() async {
    final userId = _userId;
    if (await _hasNetwork()) {
      try {
        final rows = await _client
            .from('sets')
            .select()
            .eq('user_id', userId)
            .order('id', ascending: true)
            .timeout(_networkTimeout);
        await _cache.refreshAllSets(
          userId,
          rows.map((r) => Map<String, dynamic>.from(r as Map)).toList(),
        );
      } catch (_) {
        // Any failure here (not just an obviously network-shaped
        // error) just means we fall back to the cache below - a
        // stale read is always better than crashing the screen.
      }
    }
    return _cache.getAllSets(userId);
  }

  /// Updates a set's weight, reps, unit, and/or drop-set group index. Pass
  /// [clearGroupIndex] to turn a drop-set row back into a normal set;
  /// otherwise omitted fields keep their current value.
  Future<void> updateSet(
    int setId, {
    double? weight,
    int? reps,
    String? unit,
    int? groupIndex,
    bool clearGroupIndex = false,
  }) async {
    final userId = _userId;
    final cached = await _cache.getCachedSetRaw(userId, setId);
    if (cached == null) return;

    final newWeight = weight ?? (cached['weight'] as num?)?.toDouble();
    final newReps = reps ?? cached['reps'] as int?;
    final newUnit = unit ?? cached['unit'] as String?;
    final newGroupIndex = clearGroupIndex
        ? null
        : (groupIndex ?? cached['group_index'] as int?);
    final sessionId = cached['session_id'] as int;
    final parentSetId = cached['parent_set_id'] as int?;

    if (_isTemp(setId)) {
      await _cache.upsertSet(
        userId: userId,
        id: setId,
        sessionId: sessionId,
        weight: newWeight,
        reps: newReps,
        unit: newUnit,
        groupIndex: newGroupIndex,
        parentSetId: parentSetId,
        pending: true,
      );
      return;
    }

    if (await _hasNetwork()) {
      try {
        await _client
            .from('sets')
            .update({
              'weight': newWeight,
              'reps': newReps,
              'unit': newUnit,
              'group_index': newGroupIndex,
            })
            .eq('user_id', userId)
            .eq('id', setId)
            .timeout(_networkTimeout);
        await _cache.upsertSet(
          userId: userId,
          id: setId,
          sessionId: sessionId,
          weight: newWeight,
          reps: newReps,
          unit: newUnit,
          groupIndex: newGroupIndex,
          parentSetId: parentSetId,
          pending: false,
        );
        return;
      } catch (e) {
        if (!_looksOffline(e)) rethrow;
      }
    }

    await _cache.upsertSet(
      userId: userId,
      id: setId,
      sessionId: sessionId,
      weight: newWeight,
      reps: newReps,
      unit: newUnit,
      groupIndex: newGroupIndex,
      parentSetId: parentSetId,
      pending: true,
    );
    final alreadyQueued = await _cache.hasPendingOperation(
      userId: userId,
      opType: 'update_set',
      localId: setId,
    );
    if (!alreadyQueued) {
      await _cache.enqueueOperation(
        userId: userId,
        opType: 'update_set',
        localId: setId,
      );
    }
    await refreshPendingSyncCount();
  }

  /// Deletes a set and, recursively, any rest-pause child sets that point
  /// at it via parent_set_id.
  Future<void> deleteSet(int setId) async {
    final userId = _userId;
    final childIds = await _cache.getChildSetIds(userId, setId);
    for (final childId in childIds) {
      await deleteSet(childId);
    }

    if (_isTemp(setId)) {
      await _cache.hardDeleteSet(userId, setId);
      return;
    }

    if (await _hasNetwork()) {
      try {
        await _client
            .from('sets')
            .delete()
            .eq('user_id', userId)
            .eq('id', setId)
            .timeout(_networkTimeout);
        await _cache.hardDeleteSet(userId, setId);
        await refreshPendingSyncCount();
        return;
      } catch (e) {
        if (!_looksOffline(e)) rethrow;
      }
    }

    await _cache.softDeleteSet(userId, setId);
    final alreadyQueued = await _cache.hasPendingOperation(
      userId: userId,
      opType: 'delete_set',
      localId: setId,
    );
    if (!alreadyQueued) {
      await _cache.enqueueOperation(
        userId: userId,
        opType: 'delete_set',
        localId: setId,
      );
    }
    await refreshPendingSyncCount();
  }

  Map<String, dynamic> _withParsedTimestamp(Map row) {
    final copy = Map<String, dynamic>.from(row);
    final raw = copy['timestamp'];
    if (raw is String) {
      copy['timestamp'] = DateTime.parse(raw).toLocal();
    }
    return copy;
  }

  // -------------------------------------------------------------------
  // Sync - replays the pending_operations queue against Supabase, in the
  // order they were created, resolving temp ids to real ones as it goes.
  // -------------------------------------------------------------------

  Future<void> syncPendingOperations() async {
    if (_isSyncing) return;
    final String userId;
    try {
      userId = _userId;
    } catch (_) {
      return; // Not logged in - nothing to sync yet.
    }
    if (!await _hasNetwork()) return;

    _isSyncing = true;
    try {
      final ops = await _cache.getPendingOperations(userId);
      for (final op in ops) {
        final seq = op['seq'] as int;
        final opType = op['op_type'] as String;
        final localId = op['local_id'] as int;

        try {
          switch (opType) {
            case 'insert_exercise':
              await _syncExercise(userId, seq, localId);
              break;
            case 'insert_session':
              final resolved = await _syncSession(userId, seq, localId);
              if (!resolved) return; // parent not synced yet, retry later
              break;
            case 'insert_set':
              final resolved = await _syncSet(userId, seq, localId);
              if (!resolved) return; // parent not synced yet, retry later
              break;
            case 'update_session':
              await _syncUpdateSession(userId, seq, localId);
              break;
            case 'delete_session':
              await _syncDeleteSession(userId, seq, localId);
              break;
            case 'update_set':
              await _syncUpdateSet(userId, seq, localId);
              break;
            case 'delete_set':
              await _syncDeleteSet(userId, seq, localId);
              break;
          }
        } catch (e) {
          // Whether it's a network error mid-sync or something else, stop
          // here rather than risk dropping the user's data - everything
          // from this point stays queued and will be retried later.
          return;
        }
      }
    } finally {
      _isSyncing = false;
      await refreshPendingSyncCount();
    }
  }

  Future<void> _syncExercise(String userId, int seq, int localId) async {
    final cached = await _cache.getCachedExerciseRaw(userId, localId);
    if (cached == null) {
      await _cache.deletePendingOperation(seq);
      return;
    }
    final rawData = cached['data'];
    final data = rawData == null
        ? <String, dynamic>{}
        : jsonDecode(rawData as String) as Map<String, dynamic>;
    final row = await _client
        .from('exercises')
        .insert({
          'user_id': userId,
          'name': cached['name'],
          'type': cached['type'],
          'data': data,
        })
        .select('id')
        .single()
        .timeout(_networkTimeout);
    final realId = row['id'] as int;
    await _cache.replaceExerciseId(userId, localId, realId);
    await _cache.deletePendingOperation(seq);
  }

  Future<bool> _syncSession(String userId, int seq, int localId) async {
    final cached = await _cache.getCachedSessionRaw(userId, localId);
    if (cached == null) {
      await _cache.deletePendingOperation(seq);
      return true;
    }
    final exerciseId = cached['exercise_id'] as int;
    if (_isTemp(exerciseId)) return false;

    final row = await _client
        .from('sessions')
        .insert({
          'user_id': userId,
          'exercise_id': exerciseId,
          'timestamp': DateTime.fromMillisecondsSinceEpoch(
            cached['timestamp'] as int,
          ).toUtc().toIso8601String(),
          'note': cached['note'],
        })
        .select('id')
        .single()
        .timeout(_networkTimeout);
    final realId = row['id'] as int;
    await _cache.replaceSessionId(userId, localId, realId);
    await _cache.deletePendingOperation(seq);
    return true;
  }

  Future<bool> _syncSet(String userId, int seq, int localId) async {
    final cached = await _cache.getCachedSetRaw(userId, localId);
    if (cached == null) {
      await _cache.deletePendingOperation(seq);
      return true;
    }
    final sessionId = cached['session_id'] as int;
    final parentSetId = cached['parent_set_id'] as int?;
    if (_isTemp(sessionId) || (parentSetId != null && _isTemp(parentSetId))) {
      return false;
    }

    final row = await _client
        .from('sets')
        .insert({
          'user_id': userId,
          'session_id': sessionId,
          'weight': cached['weight'],
          'reps': cached['reps'],
          'unit': cached['unit'],
          'group_index': cached['group_index'],
          'parent_set_id': parentSetId,
        })
        .select('id')
        .single()
        .timeout(_networkTimeout);
    final realId = row['id'] as int;
    await _cache.replaceSetId(userId, localId, realId);
    await _cache.deletePendingOperation(seq);
    return true;
  }

  Future<void> _syncUpdateSession(String userId, int seq, int localId) async {
    final cached = await _cache.getCachedSessionRaw(userId, localId);
    if (cached == null) {
      await _cache.deletePendingOperation(seq);
      return;
    }
    final timestampMs = cached['timestamp'] as int;
    await _client
        .from('sessions')
        .update({
          'note': cached['note'],
          'timestamp': DateTime.fromMillisecondsSinceEpoch(
            timestampMs,
          ).toUtc().toIso8601String(),
        })
        .eq('user_id', userId)
        .eq('id', localId)
        .timeout(_networkTimeout);
    await _cache.upsertSession(
      userId: userId,
      id: localId,
      exerciseId: cached['exercise_id'] as int,
      timestampMs: timestampMs,
      note: cached['note'] as String?,
      pending: false,
      deleted: (cached['deleted'] as int? ?? 0) == 1,
    );
    await _cache.deletePendingOperation(seq);
  }

  Future<void> _syncDeleteSession(String userId, int seq, int localId) async {
    await _client
        .from('sessions')
        .delete()
        .eq('user_id', userId)
        .eq('id', localId)
        .timeout(_networkTimeout);
    await _cache.hardDeleteSession(userId, localId);
    await _cache.deletePendingOperation(seq);
  }

  Future<void> _syncUpdateSet(String userId, int seq, int localId) async {
    final cached = await _cache.getCachedSetRaw(userId, localId);
    if (cached == null) {
      await _cache.deletePendingOperation(seq);
      return;
    }
    await _client
        .from('sets')
        .update({
          'weight': cached['weight'],
          'reps': cached['reps'],
          'unit': cached['unit'],
          'group_index': cached['group_index'],
        })
        .eq('user_id', userId)
        .eq('id', localId)
        .timeout(_networkTimeout);
    await _cache.upsertSet(
      userId: userId,
      id: localId,
      sessionId: cached['session_id'] as int,
      weight: (cached['weight'] as num?)?.toDouble(),
      reps: cached['reps'] as int?,
      unit: cached['unit'] as String?,
      groupIndex: cached['group_index'] as int?,
      parentSetId: cached['parent_set_id'] as int?,
      pending: false,
      deleted: (cached['deleted'] as int? ?? 0) == 1,
    );
    await _cache.deletePendingOperation(seq);
  }

  Future<void> _syncDeleteSet(String userId, int seq, int localId) async {
    await _client
        .from('sets')
        .delete()
        .eq('user_id', userId)
        .eq('id', localId)
        .timeout(_networkTimeout);
    await _cache.hardDeleteSet(userId, localId);
    await _cache.deletePendingOperation(seq);
  }
}
