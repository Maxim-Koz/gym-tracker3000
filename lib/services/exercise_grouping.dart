import 'package:shared_preferences/shared_preferences.dart';

class ExerciseGroupSection {
  const ExerciseGroupSection({required this.name, required this.exercises});

  final String name;
  final List<Map<String, dynamic>> exercises;
}

const String _exerciseGroupNamesStorageKey = 'exercise_group_names';

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
  List<Map<String, dynamic>> exercises,
) async {
  final prefs = await SharedPreferences.getInstance();
  final storedNames = prefs.getStringList(_exerciseGroupNamesStorageKey);
  return collectExerciseGroupNames(
    exercises,
    extraGroupNames: storedNames ?? const <String>[],
  );
}

Future<void> saveExerciseGroupNames(List<String> groupNames) async {
  final prefs = await SharedPreferences.getInstance();
  final sanitized =
      groupNames
          .map((name) => name.trim())
          .where((name) => name.isNotEmpty)
          .toSet()
          .toList()
        ..sort();
  await prefs.setStringList(_exerciseGroupNamesStorageKey, sanitized);
}

Future<void> addExerciseGroupName(String groupName) async {
  final trimmed = groupName.trim();
  if (trimmed.isEmpty) return;

  final prefs = await SharedPreferences.getInstance();
  final existing =
      prefs.getStringList(_exerciseGroupNamesStorageKey) ?? const <String>[];
  if (existing.contains(trimmed)) return;

  final updated = [...existing, trimmed]..sort();
  await prefs.setStringList(_exerciseGroupNamesStorageKey, updated);
}

Future<void> removeExerciseGroupName(String groupName) async {
  final trimmed = groupName.trim();
  if (trimmed.isEmpty) return;

  final prefs = await SharedPreferences.getInstance();
  final existing =
      prefs.getStringList(_exerciseGroupNamesStorageKey) ?? const <String>[];
  final updated = existing.where((name) => name != trimmed).toList()..sort();
  await prefs.setStringList(_exerciseGroupNamesStorageKey, updated);
}

Future<void> renameExerciseGroupName(String oldName, String newName) async {
  final oldTrimmed = oldName.trim();
  final newTrimmed = newName.trim();
  if (oldTrimmed.isEmpty || newTrimmed.isEmpty || oldTrimmed == newTrimmed) {
    return;
  }

  final prefs = await SharedPreferences.getInstance();
  final existing =
      prefs.getStringList(_exerciseGroupNamesStorageKey) ?? const <String>[];
  final updated = existing.where((name) => name != oldTrimmed).toList()
    ..add(newTrimmed)
    ..sort();
  await prefs.setStringList(_exerciseGroupNamesStorageKey, updated);
}

List<ExerciseGroupSection> buildExerciseGroupSections(
  List<Map<String, dynamic>> exercises, {
  List<String>? extraGroupNames,
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

  final orderedGroupNames = groups.keys.toList()..sort();
  for (final groupName in orderedGroupNames) {
    sections.add(
      ExerciseGroupSection(name: groupName, exercises: groups[groupName]!),
    );
  }

  return sections;
}
