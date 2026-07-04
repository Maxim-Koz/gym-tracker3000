import 'package:flutter/material.dart';
import 'package:gym_tracker/services/db_helper.dart';

class SetRow {
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
  final List<SetRow> rows = [SetRow()];
}

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
        });
      }
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
      });
    });
  }

  void _addDropRow(int groupIndex) {
    setState(() {
      _dropGroups[groupIndex].rows.add(SetRow());
    });
  }

  void _addDropGroup() {
    setState(() {
      _dropGroups.add(DropGroup());
    });
  }

  bool _hasValidEntries() {
    if (_selectedType == 'drop') {
      return _dropGroups.any((group) {
        return group.rows.any((row) {
          final values = row.toMap();
          return (values['weight'] as double) > 0 &&
              (values['reps'] as int) > 0;
        });
      });
    }

    return _normalRows.any((row) {
      final weightController = row['weight'] as TextEditingController?;
      final repsController = row['reps'] as TextEditingController?;
      final w = double.tryParse(weightController?.text.trim() ?? '') ?? 0.0;
      final r = int.tryParse(repsController?.text.trim() ?? '') ?? 0;
      return w > 0 && r > 0;
    });
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

    if (_selectedType == 'drop') {
      for (final group in _dropGroups) {
        for (final row in group.rows) {
          final values = row.toMap();
          if ((values['weight'] as double) > 0 && (values['reps'] as int) > 0) {
            await DBHelper().insertSet(
              sessionId,
              values['weight'] as double,
              values['reps'] as int,
              values['unit'] as String,
            );
          }
        }
      }
    } else {
      for (final row in _normalRows) {
        final weightController = row['weight'] as TextEditingController?;
        final repsController = row['reps'] as TextEditingController?;
        final w = double.tryParse(weightController?.text.trim() ?? '') ?? 0.0;
        final r = int.tryParse(repsController?.text.trim() ?? '') ?? 0;
        final u = row['unit'] as String? ?? 'kg';
        if (w > 0 && r > 0) {
          await DBHelper().insertSet(sessionId, w, r, u);
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
                                ...sets.map((setRow) {
                                  final weight = setRow['weight'];
                                  final reps = setRow['reps'];
                                  final unit = setRow['unit'];
                                  return Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        '${weight ?? '-'} ${unit ?? ''}'.trim(),
                                      ),
                                      Text('$reps reps'),
                                    ],
                                  );
                                }),
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
                          child: Row(
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
                                icon: const Icon(Icons.delete),
                                onPressed: () =>
                                    setState(() => _normalRows.removeAt(index)),
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
}
