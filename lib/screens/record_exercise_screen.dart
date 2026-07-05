import 'package:flutter/material.dart';
import 'package:gym_tracker/services/db_helper.dart';
import 'package:gym_tracker/services/set_entry_utils.dart';

class RecordExerciseScreen extends StatefulWidget {
  const RecordExerciseScreen({super.key});

  @override
  State<RecordExerciseScreen> createState() => _RecordExerciseScreenState();
}

class _RecordExerciseScreenState extends State<RecordExerciseScreen> {
  List<Map<String, dynamic>> _sessions = [];
  Map<String, dynamic>? _exercise;
  final List<Map<String, dynamic>> _normalRows = [];
  final List<DropGroup> _dropGroups = [];
  String _selectedType = 'normal';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is Map<String, dynamic>) {
      final nextExercise = args;
      final nextType = (nextExercise['type'] ?? 'normal') as String;
      if (_exercise?['id'] != nextExercise['id']) {
        _exercise = nextExercise;
        _selectedType = nextType;
        _resetRowsForType(_selectedType);
      }
      _loadSessions();
    }
  }

  @override
  void dispose() {
    for (final row in _normalRows) {
      (row['weight'] as TextEditingController?)?.dispose();
      (row['reps'] as TextEditingController?)?.dispose();
      final restPauses = row['restPauses'] as List<TextEditingController>?;
      if (restPauses != null) {
        for (final pauseController in restPauses) {
          pauseController.dispose();
        }
      }
    }
    for (final group in _dropGroups) {
      for (final row in group.rows) {
        row.dispose();
      }
    }
    super.dispose();
  }

  void _resetRowsForType(String type) {
    setState(() {
      for (final row in _normalRows) {
        (row['weight'] as TextEditingController?)?.dispose();
        (row['reps'] as TextEditingController?)?.dispose();
        final restPauses = row['restPauses'] as List<TextEditingController>?;
        if (restPauses != null) {
          for (final pauseController in restPauses) {
            pauseController.dispose();
          }
        }
      }
      for (final group in _dropGroups) {
        for (final row in group.rows) {
          row.dispose();
        }
      }
      _normalRows.clear();
      _dropGroups.clear();

      if (type == 'drop') {
        _dropGroups.add(DropGroup());
      } else {
        _normalRows.add({
          'weight': TextEditingController(),
          'reps': TextEditingController(),
          'unit': 'kg',
          'restPauses': <TextEditingController>[],
        });
      }
    });
  }

  void _addRestPause(int rowIndex) {
    setState(() {
      final row = _normalRows[rowIndex];
      final restPauses = row['restPauses'] as List<TextEditingController>?;
      restPauses?.add(TextEditingController());
    });
  }

  void _removeRestPause(int rowIndex, int pauseIndex) {
    setState(() {
      final row = _normalRows[rowIndex];
      final restPauses = row['restPauses'] as List<TextEditingController>?;
      if (restPauses == null || pauseIndex >= restPauses.length) return;
      restPauses[pauseIndex].dispose();
      restPauses.removeAt(pauseIndex);
    });
  }

  void _changeSetType(String? value) {
    if (value == null || value == _selectedType) return;
    setState(() {
      _selectedType = value;
    });
    _resetRowsForType(value);
  }

  void _addNormalRow() {
    setState(() {
      _normalRows.add({
        'weight': TextEditingController(),
        'reps': TextEditingController(),
        'unit': 'kg',
        'restPauses': <TextEditingController>[],
      });
    });
  }

  void _addDropRow(int groupIndex) {
    setState(() {
      _dropGroups[groupIndex].rows.add(SetEntryRow());
    });
  }

  void _addDropGroup() {
    setState(() {
      _dropGroups.add(DropGroup());
    });
  }

  bool _hasValidEntries() {
    return hasAnyValidSetEntries(
      type: _selectedType,
      normalRows: _normalRows,
      dropGroups: _dropGroups,
    );
  }

  Future<void> _loadSessions() async {
    final exerciseId = _exercise?['id'] as int?;
    if (exerciseId == null) return;

    final sessions = await DBHelper().getSessionsForExercise(exerciseId);
    final recent = <Map<String, dynamic>>[];

    for (final session in sessions.take(2).toList().reversed.toList()) {
      final sets = await DBHelper().getSetsForSession(session['id'] as int);
      recent.add({'session': session, 'sets': sets});
    }

    if (!mounted) return;
    setState(() => _sessions = recent);
  }

  Future<void> _saveSession() async {
    final exerciseId = _exercise?['id'] as int?;
    if (exerciseId == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('No exercise selected')));
      return;
    }

    if (!_hasValidEntries()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter at least one set.')),
      );
      return;
    }

    final sessionId = await DBHelper().insertSession(
      exerciseId,
      DateTime.now(),
    );

    final setEntries = collectValidSetEntries(
      type: _selectedType,
      normalRows: _normalRows,
      dropGroups: _dropGroups,
    );

    for (final entry in setEntries) {
      final groupIndex = entry['groupIndex'] as int?;
      if (groupIndex != null) {
        await DBHelper().insertSet(
          sessionId,
          entry['weight'] as double,
          entry['reps'] as int,
          entry['unit'] as String,
          groupIndex: groupIndex,
        );
      } else {
        final setId = await DBHelper().insertSet(
          sessionId,
          entry['weight'] as double,
          entry['reps'] as int,
          entry['unit'] as String,
        );
        final restPauses = entry['restPauses'] as List<int>? ?? [];
        for (final pauseReps in restPauses) {
          await DBHelper().insertSet(
            sessionId,
            entry['weight'] as double,
            pauseReps,
            entry['unit'] as String,
            parentSetId: setId,
          );
        }
      }
    }

    if (!mounted) return;
    await _loadSessions();
    if (!mounted) return;
    _resetRowsForType(_selectedType);
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Session saved')));
  }

  @override
  Widget build(BuildContext context) {
    final args =
        ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
    if (args == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Record Exercise')),
        body: const Center(child: Text('No exercise selected')),
      );
    }

    final name = args['name'] ?? 'Exercise';

    return Scaffold(
      appBar: AppBar(title: Text(name)),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Previous sessions',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Expanded(
              flex: 2,
              child: _sessions.isEmpty
                  ? const Center(child: Text('No previous sessions yet.'))
                  : ListView.builder(
                      itemCount: _sessions.length,
                      itemBuilder: (context, index) {
                        final item = _sessions[index];
                        final session = item['session'] as Map<String, dynamic>;
                        final sets = item['sets'] as List<Map<String, dynamic>>;
                        final date = session['timestamp'] as DateTime;
                        return Card(
                          margin: const EdgeInsets.symmetric(vertical: 6.0),
                          child: Padding(
                            padding: const EdgeInsets.all(12.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _formatDate(date),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                ..._buildSetRows(sets),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Log new session',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Expanded(
              flex: 3,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Text('Set type'),
                        const SizedBox(width: 12),
                        DropdownButton<String>(
                          value: _selectedType,
                          items: const [
                            DropdownMenuItem(
                              value: 'normal',
                              child: Text('Normal'),
                            ),
                            DropdownMenuItem(
                              value: 'drop',
                              child: Text('Drop set'),
                            ),
                          ],
                          onChanged: _changeSetType,
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (_selectedType == 'drop')
                      ...List.generate(_dropGroups.length, (groupIndex) {
                        final group = _dropGroups[groupIndex];
                        return Card(
                          margin: const EdgeInsets.symmetric(vertical: 8.0),
                          child: Padding(
                            padding: const EdgeInsets.all(12.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text('Drop set group ${groupIndex + 1}'),
                                    IconButton(
                                      icon: const Icon(Icons.delete),
                                      onPressed: () => setState(
                                        () => _dropGroups.removeAt(groupIndex),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                ...List.generate(group.rows.length, (rowIndex) {
                                  final row = group.rows[rowIndex];
                                  return Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 6.0,
                                    ),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: TextField(
                                            controller: row.weightController,
                                            keyboardType:
                                                const TextInputType.numberWithOptions(
                                                  decimal: true,
                                                ),
                                            decoration: const InputDecoration(
                                              labelText: 'Weight',
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        DropdownButton<String>(
                                          value: row.unit,
                                          items: const [
                                            DropdownMenuItem(
                                              value: 'kg',
                                              child: Text('kg'),
                                            ),
                                            DropdownMenuItem(
                                              value: 'lb',
                                              child: Text('lb'),
                                            ),
                                          ],
                                          onChanged: (value) => setState(() {
                                            if (value != null) row.unit = value;
                                          }),
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: TextField(
                                            controller: row.repsController,
                                            keyboardType: TextInputType.number,
                                            decoration: const InputDecoration(
                                              labelText: 'Reps',
                                            ),
                                          ),
                                        ),
                                        IconButton(
                                          icon: const Icon(Icons.delete),
                                          onPressed: () => setState(
                                            () => group.rows.removeAt(rowIndex),
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                }),
                                const SizedBox(height: 8),
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: TextButton.icon(
                                    icon: const Icon(Icons.add),
                                    label: const Text('Add row'),
                                    onPressed: () => _addDropRow(groupIndex),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      })
                    else
                      ...List.generate(_normalRows.length, (index) {
                        final row = _normalRows[index];
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: TextField(
                                      controller: row['weight'],
                                      keyboardType:
                                          const TextInputType.numberWithOptions(
                                            decimal: true,
                                          ),
                                      decoration: const InputDecoration(
                                        labelText: 'Weight',
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  DropdownButton<String>(
                                    value: row['unit'] as String?,
                                    items: const [
                                      DropdownMenuItem(
                                        value: 'kg',
                                        child: Text('kg'),
                                      ),
                                      DropdownMenuItem(
                                        value: 'lb',
                                        child: Text('lb'),
                                      ),
                                    ],
                                    onChanged: (value) =>
                                        setState(() => row['unit'] = value),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: TextField(
                                      controller: row['reps'],
                                      keyboardType: TextInputType.number,
                                      decoration: const InputDecoration(
                                        labelText: 'Reps',
                                      ),
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.add_reaction),
                                    tooltip: 'Add rest pause',
                                    onPressed: () => _addRestPause(index),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete),
                                    onPressed: () => setState(
                                      () => _normalRows.removeAt(index),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              if ((row['restPauses']
                                          as List<TextEditingController>?)
                                      ?.isNotEmpty ??
                                  false)
                                ...List.generate(
                                  (row['restPauses']
                                          as List<TextEditingController>)
                                      .length,
                                  (pauseIndex) {
                                    final pauseController =
                                        (row['restPauses']
                                            as List<
                                              TextEditingController
                                            >)[pauseIndex];
                                    return Padding(
                                      padding: const EdgeInsets.only(top: 6.0),
                                      child: Row(
                                        children: [
                                          Expanded(
                                            child: TextField(
                                              controller: pauseController,
                                              keyboardType:
                                                  TextInputType.number,
                                              decoration: InputDecoration(
                                                labelText: 'Rest pause reps',
                                                border: OutlineInputBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(8),
                                                ),
                                              ),
                                            ),
                                          ),
                                          IconButton(
                                            icon: const Icon(
                                              Icons.delete_outline,
                                            ),
                                            tooltip: 'Remove rest pause',
                                            onPressed: () => _removeRestPause(
                                              index,
                                              pauseIndex,
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                ),
                            ],
                          ),
                        );
                      }),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          _selectedType == 'drop' ? 'Drop set groups' : 'Sets',
                        ),
                        IconButton(
                          icon: const Icon(Icons.add),
                          onPressed: _selectedType == 'drop'
                              ? _addDropGroup
                              : _addNormalRow,
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _saveSession,
                        child: const Text('Save session'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
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
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text('${weightText} ${unit ?? ''}'.trim()),
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
    return values.join(', ');
  }
}
