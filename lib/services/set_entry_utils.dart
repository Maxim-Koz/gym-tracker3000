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
    final weight = double.tryParse(weightController?.text.trim() ?? '') ?? 0.0;
    final reps = int.tryParse(repsController?.text.trim() ?? '') ?? 0;
    final unit = row['unit'] as String? ?? 'kg';
    if (weight > 0 && reps > 0) {
      entries.add({'weight': weight, 'reps': reps, 'unit': unit});
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
