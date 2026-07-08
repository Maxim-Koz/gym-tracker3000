import 'package:supabase_flutter/supabase_flutter.dart';

import 'db_helper.dart';
import 'legacy_local_db.dart';

/// Runs once per account, the first time that account logs in on a device
/// that still has data in the old local SQLite database. It copies every
/// exercise/session/set up to Supabase, then marks the account as migrated
/// (via `profiles.local_data_migrated`) so it never runs again for that
/// account, and other devices won't try to re-import the same data.
///
/// Safe to call on every app start / every login — it's a fast no-op once
/// migration has completed, and skips entirely on a device with no local
/// data (e.g. a second device, or a fresh install).
class DataMigrationService {
  static final DataMigrationService _instance =
      DataMigrationService._internal();
  factory DataMigrationService() => _instance;
  DataMigrationService._internal();

  SupabaseClient get _client => Supabase.instance.client;

  Future<void> migrateIfNeeded() async {
    final user = _client.auth.currentUser;
    if (user == null) return;

    try {
      final profile = await _client
          .from('profiles')
          .select('local_data_migrated')
          .eq('id', user.id)
          .maybeSingle();

      final alreadyMigrated = profile?['local_data_migrated'] == true;
      if (alreadyMigrated) return;

      final legacy = LegacyLocalDb();
      if (!await legacy.hasAnyLocalData()) {
        // Nothing on this device to migrate (fresh install / new device).
        // Still mark the account as migrated so future logins don't keep
        // checking, unless the profile row can't be found for some reason.
        if (profile != null) {
          await _client
              .from('profiles')
              .update({'local_data_migrated': true})
              .eq('id', user.id);
        }
        return;
      }

      final dbHelper = DBHelper();
      final legacyExercises = await legacy.getExercises();

      for (final legacyExercise in legacyExercises) {
        final name = legacyExercise['name'] as String;
        final type = legacyExercise['type'] as String;
        final data = Map<String, dynamic>.from(
          (legacyExercise['data'] as Map?) ?? <String, dynamic>{},
        );

        if (data['_migrated'] == true) continue;

        var remoteExercise = await dbHelper.getExerciseByName(name);
        final int exerciseId;
        if (remoteExercise != null) {
          exerciseId = remoteExercise['id'] as int;
        } else {
          exerciseId = await dbHelper.insertExercise(name, type, data);
        }

        final legacySessions = await legacy.getSessionsForExercise(
          legacyExercise['id'] as int,
        );

        for (final legacySession in legacySessions) {
          final newSessionId = await dbHelper.insertSession(
            exerciseId,
            legacySession['timestamp'] as DateTime,
            note: legacySession['note'] as String?,
          );

          final legacySets = await legacy.getSetsForSession(
            legacySession['id'] as int,
          );

          // Insert parentless sets first so we know each new set's id
          // before inserting the rest-pause children that reference it.
          final parents = legacySets
              .where((s) => s['parent_set_id'] == null)
              .toList();
          final children = legacySets
              .where((s) => s['parent_set_id'] != null)
              .toList();

          final oldIdToNewId = <int, int>{};
          for (final set in parents) {
            final newSetId = await dbHelper.insertSet(
              newSessionId,
              ((set['weight'] as num?) ?? 0).toDouble(),
              (set['reps'] as int?) ?? 0,
              (set['unit'] as String?) ?? 'kg',
              groupIndex: set['group_index'] as int?,
            );
            oldIdToNewId[set['id'] as int] = newSetId;
          }
          for (final set in children) {
            final newParentId = oldIdToNewId[set['parent_set_id'] as int];
            await dbHelper.insertSet(
              newSessionId,
              ((set['weight'] as num?) ?? 0).toDouble(),
              (set['reps'] as int?) ?? 0,
              (set['unit'] as String?) ?? 'kg',
              parentSetId: newParentId,
            );
          }
        }

        // Mark this exercise as fully migrated so a retry after a later
        // failure doesn't duplicate its sessions/sets.
        final updatedData = Map<String, dynamic>.from(data)
          ..['_migrated'] = true;
        await _client
            .from('exercises')
            .update({'data': updatedData})
            .eq('id', exerciseId);
      }

      await _client
          .from('profiles')
          .update({'local_data_migrated': true})
          .eq('id', user.id);
    } catch (e) {
      // Don't block login on a failed migration — the flag is only set on
      // full success, so this will simply be retried next launch.
      // ignore: avoid_print
      print('Local data migration failed, will retry next launch: $e');
    }
  }
}
