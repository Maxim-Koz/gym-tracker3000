import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'db_helper.dart';
import 'legacy_local_db.dart';

class DataMigrationService {
  static final DataMigrationService _instance =
      DataMigrationService._internal();
  factory DataMigrationService() => _instance;
  DataMigrationService._internal();

  SupabaseClient get _client => Supabase.instance.client;

  static const _networkTimeout = Duration(seconds: 8);

  Future<void> migrateIfNeeded() async {
    final user = _client.auth.currentUser;
    if (user == null) return;

    try {
      final results = await Connectivity().checkConnectivity();
      if (results.every((r) => r == ConnectivityResult.none)) return;
    } catch (_) {}

    try {
      final profile = await _client
          .from('profiles')
          .select('local_data_migrated')
          .eq('id', user.id)
          .maybeSingle()
          .timeout(_networkTimeout);

      final alreadyMigrated = profile?['local_data_migrated'] == true;
      if (alreadyMigrated) return;

      final legacy = LegacyLocalDb();
      if (!await legacy.hasAnyLocalData()) {
        if (profile != null) {
          await _client
              .from('profiles')
              .update({'local_data_migrated': true})
              .eq('id', user.id)
              .timeout(_networkTimeout);
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

        final updatedData = Map<String, dynamic>.from(data)
          ..['_migrated'] = true;
        await _client
            .from('exercises')
            .update({'data': updatedData})
            .eq('id', exerciseId)
            .timeout(_networkTimeout);
      }

      await _client
          .from('profiles')
          .update({'local_data_migrated': true})
          .eq('id', user.id)
          .timeout(_networkTimeout);
    } catch (_) {}
  }
}
