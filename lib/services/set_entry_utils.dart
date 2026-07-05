import 'package:flutter/material.dart';

class SetEntryRow {
  final TextEditingController weightController = TextEditingController();
  final TextEditingController repsController = TextEditingController();
  String unit = 'kg';

  void dispose() {
    weightController.dispose();
    repsController.dispose();
  }

  Map<String, dynamic> toMap() {
    return {
      'weight': double.tryParse(weightController.text.trim()) ?? 0.0,
      'reps': int.tryParse(repsController.text.trim()) ?? 0,
      'unit': unit,
    };
  }
}

class DropGroup {
  final List<SetEntryRow> rows;

  DropGroup({List<SetEntryRow>? rows}) : rows = rows ?? [SetEntryRow()];
}

List<Map<String, dynamic>> collectValidSetEntries({
  required String type,
  required List<Map<String, dynamic>> normalRows,
  required List<DropGroup> dropGroups,
}) {
  if (type == 'drop') {
    final entries = <Map<String, dynamic>>[];
    for (var groupIndex = 0; groupIndex < dropGroups.length; groupIndex++) {
      final group = dropGroups[groupIndex];
      for (final row in group.rows) {
        final values = row.toMap();
        final weight = values['weight'] as double;
        final reps = values['reps'] as int;
        if (weight > 0 && reps > 0) {
          entries.add({
            'weight': weight,
            'reps': reps,
            'unit': values['unit'] as String,
            'groupIndex': groupIndex,
          });
        }
      }
    }
    return entries;
  }

  final entries = <Map<String, dynamic>>[];
  for (final row in normalRows) {
    final weightController = row['weight'] as TextEditingController?;
    final repsController = row['reps'] as TextEditingController?;
    final restPauseControllers =
        row['restPauses'] as List<TextEditingController>?;
    final weight = double.tryParse(weightController?.text.trim() ?? '') ?? 0.0;
    final reps = int.tryParse(repsController?.text.trim() ?? '') ?? 0;
    final unit = row['unit'] as String? ?? 'kg';
    if (weight > 0 && reps > 0) {
      final restPauses = <int>[];
      if (restPauseControllers != null) {
        for (final pauseController in restPauseControllers) {
          final pauseReps = int.tryParse(pauseController.text.trim()) ?? 0;
          if (pauseReps > 0) {
            restPauses.add(pauseReps);
          }
        }
      }
      entries.add({
        'weight': weight,
        'reps': reps,
        'unit': unit,
        'restPauses': restPauses,
      });
    }
  }
  return entries;
}

bool hasAnyValidSetEntries({
  required String type,
  required List<Map<String, dynamic>> normalRows,
  required List<DropGroup> dropGroups,
}) {
  return collectValidSetEntries(
    type: type,
    normalRows: normalRows,
    dropGroups: dropGroups,
  ).isNotEmpty;
}

// Checks a single weight/reps pair. A blank field is fine (the row is just
// left unfilled and will be skipped), but a field that has text in it that
// isn't a real number is a mistake the user should be told about, rather
// than being silently discarded like an empty row.
String? _checkWeightAndReps({
  required String weightText,
  required String repsText,
  required String label,
}) {
  final trimmedWeight = weightText.trim();
  if (trimmedWeight.isNotEmpty && double.tryParse(trimmedWeight) == null) {
    return '$label: "$trimmedWeight" is not a valid weight.';
  }
  final trimmedReps = repsText.trim();
  if (trimmedReps.isNotEmpty && int.tryParse(trimmedReps) == null) {
    return '$label: "$trimmedReps" is not a valid number of reps.';
  }
  return null;
}

/// Scans every row (normal sets, drop-set groups, and rest pauses) for a
/// weight or reps field that was actually typed into but doesn't parse as a
/// real number (e.g. "12kg" or "n/a"). Blank fields are not an error - they
/// are treated as an unfilled row and simply skipped elsewhere.
///
/// Returns a user-facing message describing the first problem found, or
/// null if everything present is a valid number.
String? findSetEntryError({
  required String type,
  required List<Map<String, dynamic>> normalRows,
  required List<DropGroup> dropGroups,
}) {
  if (type == 'drop') {
    for (var groupIndex = 0; groupIndex < dropGroups.length; groupIndex++) {
      final group = dropGroups[groupIndex];
      for (var rowIndex = 0; rowIndex < group.rows.length; rowIndex++) {
        final row = group.rows[rowIndex];
        final error = _checkWeightAndReps(
          weightText: row.weightController.text,
          repsText: row.repsController.text,
          label: 'Drop set group ${groupIndex + 1}, row ${rowIndex + 1}',
        );
        if (error != null) return error;
      }
    }
    return null;
  }

  for (var rowIndex = 0; rowIndex < normalRows.length; rowIndex++) {
    final row = normalRows[rowIndex];
    final weightController = row['weight'] as TextEditingController?;
    final repsController = row['reps'] as TextEditingController?;
    final error = _checkWeightAndReps(
      weightText: weightController?.text ?? '',
      repsText: repsController?.text ?? '',
      label: 'Set ${rowIndex + 1}',
    );
    if (error != null) return error;

    final restPauseControllers =
        row['restPauses'] as List<TextEditingController>?;
    if (restPauseControllers != null) {
      for (
        var pauseIndex = 0;
        pauseIndex < restPauseControllers.length;
        pauseIndex++
      ) {
        final pauseText = restPauseControllers[pauseIndex].text.trim();
        if (pauseText.isNotEmpty && int.tryParse(pauseText) == null) {
          return 'Set ${rowIndex + 1}, rest pause ${pauseIndex + 1}: '
              '"$pauseText" is not a valid number of reps.';
        }
      }
    }
  }
  return null;
}
