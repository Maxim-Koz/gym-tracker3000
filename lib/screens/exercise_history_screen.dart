import 'package:flutter/material.dart';
import 'package:gym_tracker/services/db_helper.dart';

class ExerciseHistoryScreen extends StatefulWidget {
  const ExerciseHistoryScreen({super.key});

  @override
  State<ExerciseHistoryScreen> createState() => _ExerciseHistoryScreenState();
}

class _ExerciseHistoryScreenState extends State<ExerciseHistoryScreen> {
  List<Map<String, dynamic>> _sessions = [];
  Map<String, dynamic>? _exercise;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is Map<String, dynamic>) {
      _exercise = args;
      _loadSessions();
    }
  }

  Future<void> _loadSessions() async {
    if (_exercise == null) return;
    final sessions = await DBHelper().getSessionsForExercise(
      _exercise!['id'] as int,
    );
    final enriched = <Map<String, dynamic>>[];
    for (final session in sessions) {
      final sets = await DBHelper().getSetsForSession(session['id'] as int);
      enriched.add({'session': session, 'sets': sets});
    }
    setState(() => _sessions = enriched);
  }

  @override
  Widget build(BuildContext context) {
    final exercise = _exercise;
    return Scaffold(
      appBar: AppBar(title: Text(exercise?['name'] ?? 'Exercise History')),
      body: exercise == null
          ? const Center(child: Text('No exercise selected.'))
          : _sessions.isEmpty
          ? const Center(child: Text('No sessions recorded for this exercise.'))
          : ListView.builder(
              reverse: true,
              itemCount: _sessions.length,
              itemBuilder: (context, index) {
                final sessionBundle = _sessions[index];
                final session =
                    sessionBundle['session'] as Map<String, dynamic>;
                final sets =
                    sessionBundle['sets'] as List<Map<String, dynamic>>;
                final date = session['timestamp'] as DateTime;
                return Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _formatDate(date),
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${sets.where((s) => s['parent_set_id'] == null).length} set${sets.where((s) => s['parent_set_id'] == null).length == 1 ? '' : 's'}',
                          ),
                          const Divider(),
                          if (sets.isEmpty)
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 8.0),
                              child: Text('No sets recorded for this session.'),
                            )
                          else
                            ..._buildSetRows(sets),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }

  String _formatDate(DateTime date) {
    final local = date.toLocal();
    return '${local.day.toString().padLeft(2, '0')}/${local.month.toString().padLeft(2, '0')}/${local.year}';
  }

  // Builds the widgets for a session's sets. If any set carries a
  // group_index (i.e. it was recorded as part of a drop set), the sets are
  // clustered under a "Drop set group N" header instead of shown flat.
  List<Widget> _buildSetRows(List<Map<String, dynamic>> sets) {
    final childrenByParent = <int, List<Map<String, dynamic>>>{};
    final parentRows = <Map<String, dynamic>>[];

    for (final setRow in sets) {
      final parentId = setRow['parent_set_id'] as int?;
      if (parentId != null) {
        childrenByParent.putIfAbsent(parentId, () => []).add(setRow);
      } else {
        parentRows.add(setRow);
      }
    }

    final hasGroups = parentRows.any((s) => s['group_index'] != null);

    Widget buildRowWithChildren(Map<String, dynamic> row) {
      final id = row['id'] as int?;
      final children = id == null
          ? <Map<String, dynamic>>[]
          : childrenByParent[id] ?? [];
      return _buildSingleSetRow(row, children: children);
    }

    if (!hasGroups) {
      return parentRows.map((setRow) => buildRowWithChildren(setRow)).toList();
    }

    final grouped = <int, List<Map<String, dynamic>>>{};
    for (final setRow in parentRows) {
      final groupIndex = setRow['group_index'] as int? ?? 0;
      grouped.putIfAbsent(groupIndex, () => []).add(setRow);
    }
    final sortedKeys = grouped.keys.toList()..sort();

    final widgets = <Widget>[];
    for (final key in sortedKeys) {
      widgets.add(
        Padding(
          padding: const EdgeInsets.only(top: 6.0, bottom: 2.0),
          child: Text(
            'Drop set group ${key + 1}',
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
          ),
        ),
      );
      widgets.addAll(
        grouped[key]!.map(
          (setRow) => Padding(
            padding: const EdgeInsets.only(left: 8.0),
            child: buildRowWithChildren(setRow),
          ),
        ),
      );
    }
    return widgets;
  }

  Widget _buildSingleSetRow(
    Map<String, dynamic> setRow, {
    List<Map<String, dynamic>> children = const <Map<String, dynamic>>[],
  }) {
    final weight = setRow['weight'];
    final unit = setRow['unit'];
    String weightText;
    if (weight == null) {
      weightText = '-';
    } else if (weight is double) {
      weightText = weight.toStringAsFixed(1);
    } else {
      weightText = weight.toString();
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            '$weightText ${unit ?? ''}'.trim(),
            style: const TextStyle(fontWeight: FontWeight.w500),
          ),
          Text(_formatRepsDisplay(setRow, children)),
        ],
      ),
    );
  }

  String _formatRepsDisplay(
    Map<String, dynamic> setRow,
    List<Map<String, dynamic>> children,
  ) {
    final values = <String>[];
    final mainReps = setRow['reps'];
    if (mainReps != null) {
      values.add(mainReps.toString());
    }
    for (final child in children) {
      final childReps = child['reps'];
      if (childReps != null) {
        values.add(childReps.toString());
      }
    }
    if (values.isEmpty) {
      return '-';
    }
    return '${values.join(', ')} reps';
  }
}
