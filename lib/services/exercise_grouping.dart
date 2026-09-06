import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ExerciseGroupSection {
  const ExerciseGroupSection({required this.name, required this.exercises});

  final String name;
  final List<Map<String, dynamic>> exercises;
}

const String _exerciseGroupNamesStorageKey = 'exercise_group_names';
const String _exerciseGroupOrderStorageKey = 'exercise_group_order';
const String _exerciseGroupNameOrderStorageKey = 'exercise_group_name_order';

String _currentUserScope() {
  try {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    return userId?.trim().isNotEmpty == true ? userId!.trim() : 'anonymous';
  } catch (_) {
    return 'anonymous';
  }
}

String _scopedStorageKey({String? userIdOverride}) {
  final scope = userIdOverride?.trim().isNotEmpty == true
      ? userIdOverride!.trim()
      : _currentUserScope();
  return '$_exerciseGroupNamesStorageKey::$scope';
}

String _scopedGroupOrderStorageKey(String groupName, {String? userIdOverride}) {
  final scope = userIdOverride?.trim().isNotEmpty == true
      ? userIdOverride!.trim()
      : _currentUserScope();
  return '$_exerciseGroupOrderStorageKey::$scope::$groupName';
}

String _scopedGroupNameOrderStorageKey({String? userIdOverride}) {
  final scope = userIdOverride?.trim().isNotEmpty == true
      ? userIdOverride!.trim()
      : _currentUserScope();
  return '$_exerciseGroupNameOrderStorageKey::$scope';
}

int? _toInt(Object? value) {
  if (value is int) return value;
  return int.tryParse(value?.toString() ?? '');
}

List<Map<String, dynamic>> _applyGroupOrder(
  List<Map<String, dynamic>> exercises,
  List<int> orderedIds,
) {
  if (orderedIds.isEmpty || exercises.length < 2) return exercises;

  final byId = <int, Map<String, dynamic>>{};
  for (final exercise in exercises) {
    final id = _toInt(exercise['id']);
    if (id != null) {
      byId[id] = exercise;
    }
  }

  final orderedExercises = <Map<String, dynamic>>[];
  final seenIds = <int>{};
  for (final id in orderedIds) {
    final exercise = byId[id];
    if (exercise == null) continue;
    orderedExercises.add(exercise);
    seenIds.add(id);
  }

  for (final exercise in exercises) {
    final id = _toInt(exercise['id']);
    if (id == null || seenIds.contains(id)) continue;
    orderedExercises.add(exercise);
  }

  return orderedExercises;
}

List<String> collectExerciseGroupNames(
  List<Map<String, dynamic>> exercises, {
  List<String>? extraGroupNames,
}) {
  final groups = <String>{};
  for (final exercise in exercises) {
    final data = exercise['data'];
    if (data is! Map) continue;
    final rawGroups = data['groups'];
    if (rawGroups is! List) continue;
    for (final candidate in rawGroups) {
      final groupName = candidate?.toString().trim();
      if (groupName != null && groupName.isNotEmpty) {
        groups.add(groupName);
      }
    }
  }

  if (extraGroupNames != null) {
    for (final groupName in extraGroupNames) {
      final candidate = groupName.trim();
      if (candidate.isNotEmpty) {
        groups.add(candidate);
      }
    }
  }

  final sorted = groups.toList()..sort();
  return sorted;
}

Future<List<String>> loadExerciseGroupNames(
  List<Map<String, dynamic>> exercises, {
  String? userIdOverride,
}) async {
  final prefs = await SharedPreferences.getInstance();
  final storedNames = prefs.getStringList(
    _scopedStorageKey(userIdOverride: userIdOverride),
  );
  return collectExerciseGroupNames(
    exercises,
    extraGroupNames: storedNames ?? const <String>[],
  );
}

Future<void> saveExerciseGroupNames(
  List<String> groupNames, {
  String? userIdOverride,
}) async {
  final prefs = await SharedPreferences.getInstance();
  final sanitized =
      groupNames
          .map((name) => name.trim())
          .where((name) => name.isNotEmpty)
          .toSet()
          .toList()
        ..sort();
  await prefs.setStringList(
    _scopedStorageKey(userIdOverride: userIdOverride),
    sanitized,
  );
}

Future<void> addExerciseGroupName(
  String groupName, {
  String? userIdOverride,
}) async {
  final trimmed = groupName.trim();
  if (trimmed.isEmpty) return;

  final prefs = await SharedPreferences.getInstance();
  final existing =
      prefs.getStringList(_scopedStorageKey(userIdOverride: userIdOverride)) ??
      const <String>[];
  if (existing.contains(trimmed)) return;

  final updated = [...existing, trimmed]..sort();
  await prefs.setStringList(
    _scopedStorageKey(userIdOverride: userIdOverride),
    updated,
  );
}

Future<void> removeExerciseGroupName(
  String groupName, {
  String? userIdOverride,
}) async {
  final trimmed = groupName.trim();
  if (trimmed.isEmpty) return;

  final prefs = await SharedPreferences.getInstance();
  final existing =
      prefs.getStringList(_scopedStorageKey(userIdOverride: userIdOverride)) ??
      const <String>[];
  final updated = existing.where((name) => name != trimmed).toList()..sort();
  await prefs.setStringList(
    _scopedStorageKey(userIdOverride: userIdOverride),
    updated,
  );
}

Future<void> renameExerciseGroupName(
  String oldName,
  String newName, {
  String? userIdOverride,
}) async {
  final oldTrimmed = oldName.trim();
  final newTrimmed = newName.trim();
  if (oldTrimmed.isEmpty || newTrimmed.isEmpty || oldTrimmed == newTrimmed) {
    return;
  }

  final prefs = await SharedPreferences.getInstance();
  final existing =
      prefs.getStringList(_scopedStorageKey(userIdOverride: userIdOverride)) ??
      const <String>[];
  final updated = existing.where((name) => name != oldTrimmed).toList()
    ..add(newTrimmed)
    ..sort();
  await prefs.setStringList(
    _scopedStorageKey(userIdOverride: userIdOverride),
    updated,
  );
}

Future<List<String>> loadExerciseGroupNameOrder({
  String? userIdOverride,
}) async {
  final prefs = await SharedPreferences.getInstance();
  final stored =
      prefs.getStringList(
        _scopedGroupNameOrderStorageKey(userIdOverride: userIdOverride),
      ) ??
      const <String>[];

  final ordered = <String>[];
  final seen = <String>{};
  for (final value in stored) {
    final name = value.trim();
    if (name.isEmpty || seen.contains(name)) continue;
    seen.add(name);
    ordered.add(name);
  }
  return ordered;
}

Future<void> saveExerciseGroupNameOrder(
  List<String> groupNames, {
  String? userIdOverride,
}) async {
  final prefs = await SharedPreferences.getInstance();
  final unique = <String>[];
  final seen = <String>{};
  for (final name in groupNames) {
    final trimmed = name.trim();
    if (trimmed.isEmpty || seen.contains(trimmed)) continue;
    seen.add(trimmed);
    unique.add(trimmed);
  }

  await prefs.setStringList(
    _scopedGroupNameOrderStorageKey(userIdOverride: userIdOverride),
    unique,
  );
}

Future<void> renameExerciseGroupNameOrder(
  String oldName,
  String newName, {
  String? userIdOverride,
}) async {
  final oldTrimmed = oldName.trim();
  final newTrimmed = newName.trim();
  if (oldTrimmed.isEmpty || newTrimmed.isEmpty || oldTrimmed == newTrimmed) {
    return;
  }

  final currentOrder = await loadExerciseGroupNameOrder(
    userIdOverride: userIdOverride,
  );
  final updated = currentOrder
      .map((name) => name == oldTrimmed ? newTrimmed : name)
      .toList();
  await saveExerciseGroupNameOrder(updated, userIdOverride: userIdOverride);
}

Future<void> removeExerciseGroupNameOrder(
  String groupName, {
  String? userIdOverride,
}) async {
  final trimmed = groupName.trim();
  if (trimmed.isEmpty) return;

  final currentOrder = await loadExerciseGroupNameOrder(
    userIdOverride: userIdOverride,
  );
  final updated = currentOrder.where((name) => name != trimmed).toList();
  await saveExerciseGroupNameOrder(updated, userIdOverride: userIdOverride);
}

Future<List<int>> loadExerciseGroupOrder(
  String groupName, {
  String? userIdOverride,
}) async {
  final trimmed = groupName.trim();
  if (trimmed.isEmpty) return const <int>[];

  final prefs = await SharedPreferences.getInstance();
  final stored =
      prefs.getStringList(
        _scopedGroupOrderStorageKey(trimmed, userIdOverride: userIdOverride),
      ) ??
      const <String>[];

  final parsed = <int>[];
  for (final value in stored) {
    final id = int.tryParse(value);
    if (id != null) {
      parsed.add(id);
    }
  }
  return parsed;
}

Future<Map<String, List<int>>> loadExerciseGroupOrders(
  List<String> groupNames, {
  String? userIdOverride,
}) async {
  final prefs = await SharedPreferences.getInstance();
  final result = <String, List<int>>{};

  for (final groupName in groupNames) {
    final trimmed = groupName.trim();
    if (trimmed.isEmpty) continue;
    final stored =
        prefs.getStringList(
          _scopedGroupOrderStorageKey(trimmed, userIdOverride: userIdOverride),
        ) ??
        const <String>[];

    final parsed = <int>[];
    for (final value in stored) {
      final id = int.tryParse(value);
      if (id != null) {
        parsed.add(id);
      }
    }
    if (parsed.isNotEmpty) {
      result[trimmed] = parsed;
    }
  }

  return result;
}

Future<void> saveExerciseGroupOrder(
  String groupName,
  List<int> exerciseIds, {
  String? userIdOverride,
}) async {
  final trimmed = groupName.trim();
  if (trimmed.isEmpty) return;

  final prefs = await SharedPreferences.getInstance();
  final uniqueIds = <int>{};
  final serialized = <String>[];
  for (final id in exerciseIds) {
    if (uniqueIds.add(id)) {
      serialized.add(id.toString());
    }
  }

  await prefs.setStringList(
    _scopedGroupOrderStorageKey(trimmed, userIdOverride: userIdOverride),
    serialized,
  );
}

Future<void> removeExerciseGroupOrder(
  String groupName, {
  String? userIdOverride,
}) async {
  final trimmed = groupName.trim();
  if (trimmed.isEmpty) return;

  final prefs = await SharedPreferences.getInstance();
  await prefs.remove(
    _scopedGroupOrderStorageKey(trimmed, userIdOverride: userIdOverride),
  );
}

Future<void> clearExerciseGroupingForUser(String userId) async {
  final scope = userId.trim();
  if (scope.isEmpty) return;

  final prefs = await SharedPreferences.getInstance();
  final namesKey = _scopedStorageKey(userIdOverride: scope);
  final storedGroupNames = prefs.getStringList(namesKey) ?? const <String>[];

  for (final groupName in storedGroupNames) {
    await prefs.remove(
      _scopedGroupOrderStorageKey(groupName, userIdOverride: scope),
    );
  }

  await prefs.remove(namesKey);
  await prefs.remove(_scopedGroupNameOrderStorageKey(userIdOverride: scope));
}

Future<void> renameExerciseGroupOrder(
  String oldName,
  String newName, {
  String? userIdOverride,
}) async {
  final oldTrimmed = oldName.trim();
  final newTrimmed = newName.trim();
  if (oldTrimmed.isEmpty || newTrimmed.isEmpty || oldTrimmed == newTrimmed) {
    return;
  }

  final currentOrder = await loadExerciseGroupOrder(
    oldTrimmed,
    userIdOverride: userIdOverride,
  );
  await saveExerciseGroupOrder(
    newTrimmed,
    currentOrder,
    userIdOverride: userIdOverride,
  );
  await removeExerciseGroupOrder(oldTrimmed, userIdOverride: userIdOverride);
}

List<String> reorderExerciseGroupNames(
  List<String> groupNames,
  int oldIndex,
  int newIndex,
) {
  if (groupNames.isEmpty ||
      oldIndex < 0 ||
      oldIndex >= groupNames.length ||
      newIndex < 0 ||
      newIndex >= groupNames.length) {
    return List<String>.from(groupNames);
  }

  final updated = List<String>.from(groupNames);
  final item = updated.removeAt(oldIndex);
  var insertIndex = newIndex;
  if (oldIndex < insertIndex) {
    insertIndex -= 1;
  }
  updated.insert(insertIndex, item);
  return updated;
}

List<String> _applyGroupNameOrder(
  List<String> groupNames, [
  List<String>? explicitOrder,
]) {
  final names = groupNames.toSet().toList();
  if (explicitOrder == null || explicitOrder.isEmpty) {
    final sorted = List<String>.from(names)..sort();
    return sorted;
  }

  final ordered = <String>[];
  final seen = <String>{};
  for (final candidate in explicitOrder) {
    final trimmed = candidate.trim();
    if (trimmed.isEmpty || !names.contains(trimmed) || !seen.add(trimmed)) {
      continue;
    }
    ordered.add(trimmed);
  }

  for (final candidate in names) {
    if (seen.add(candidate)) {
      ordered.add(candidate);
    }
  }

  return ordered;
}

List<ExerciseGroupSection> buildExerciseGroupSections(
  List<Map<String, dynamic>> exercises, {
  List<String>? extraGroupNames,
  Map<String, List<int>>? groupExerciseOrder,
  List<String>? groupNameOrder,
}) {
  final sortedExercises = List<Map<String, dynamic>>.from(exercises);
  sortedExercises.sort((a, b) {
    final left = (a['name'] ?? '').toString().toLowerCase();
    final right = (b['name'] ?? '').toString().toLowerCase();
    return left.compareTo(right);
  });

  final sections = <ExerciseGroupSection>[];
  sections.add(
    ExerciseGroupSection(name: 'All Exercises', exercises: sortedExercises),
  );

  final groups = <String, List<Map<String, dynamic>>>{};
  if (extraGroupNames != null) {
    for (final groupName in extraGroupNames) {
      final candidate = groupName.trim();
      if (candidate.isEmpty) continue;
      groups.putIfAbsent(candidate, () => <Map<String, dynamic>>[]);
    }
  }

  for (final exercise in sortedExercises) {
    final data = exercise['data'];
    if (data is! Map) continue;
    final rawGroups = data['groups'];
    if (rawGroups is! List) continue;
    for (final candidate in rawGroups) {
      final groupName = candidate?.toString().trim();
      if (groupName == null || groupName.isEmpty) continue;
      groups.putIfAbsent(groupName, () => <Map<String, dynamic>>[]);
      groups[groupName]!.add(exercise);
    }
  }

  final orderedGroupNames = _applyGroupNameOrder(
    groups.keys.toList(),
    groupNameOrder,
  );
  for (final groupName in orderedGroupNames) {
    final orderedExercises = _applyGroupOrder(
      groups[groupName]!,
      groupExerciseOrder?[groupName] ?? const <int>[],
    );
    sections.add(
      ExerciseGroupSection(name: groupName, exercises: orderedExercises),
    );
  }

  return sections;
}
