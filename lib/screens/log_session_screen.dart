import 'package:flutter/material.dart';
import 'package:gym_tracker/services/db_helper.dart';
import 'package:gym_tracker/services/set_entry_utils.dart';

class LogSessionScreen extends StatefulWidget {
  const LogSessionScreen({super.key});

  @override
  State<LogSessionScreen> createState() => _LogSessionScreenState();
}

class _LogSessionScreenState extends State<LogSessionScreen> {
  final List<Map<String, dynamic>> _normalRows = [];
  final List<DropGroup> _dropGroups = [];
  Map<String, dynamic>? _exercise;
  String _selectedType = 'normal';
  bool _rowsInitialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is Map<String, dynamic>) {
      final nextExercise = args;
      final nextType = (nextExercise['type'] ?? 'normal') as String;
      if (_exercise?['id'] != nextExercise['id'] || !_rowsInitialized) {
        _exercise = nextExercise;
        _selectedType = nextType;
        _resetRowsForType(_selectedType);
        _rowsInitialized = true;
      }
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
      _dropGroups[groupIndex].rows.add(SetEntryRow());
    });
  }

  void _addDropGroup() {
    setState(() {
      _dropGroups.add(DropGroup());
    });
  }

  Future<void> _save() async {
    final exerciseId = _exercise?['id'] as int?;
    if (exerciseId == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('No exercise selected')));
      return;
    }

    final hasSets = hasAnyValidSetEntries(
      type: _selectedType,
      normalRows: _normalRows,
      dropGroups: _dropGroups,
    );
    if (!hasSets) {
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
        await DBHelper().insertSet(
          sessionId,
          entry['weight'] as double,
          entry['reps'] as int,
          entry['unit'] as String,
        );
      }
    }

    if (!mounted) return;
    Navigator.of(context).pop(true);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Session saved')));
  }

  @override
  Widget build(BuildContext context) {
    final exerciseName = _exercise?['name'] ?? 'Exercise';

    return Scaffold(
      appBar: AppBar(title: Text('Record $exerciseName')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Row(
              children: [
                const Text('Set type'),
                const SizedBox(width: 12),
                DropdownButton<String>(
                  value: _selectedType,
                  items: const [
                    DropdownMenuItem(value: 'normal', child: Text('Normal')),
                    DropdownMenuItem(value: 'drop', child: Text('Drop set')),
                  ],
                  onChanged: _changeSetType,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: _selectedType == 'drop'
                  ? ListView.builder(
                      itemCount: _dropGroups.length,
                      itemBuilder: (context, groupIndex) {
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
                                ListView.builder(
                                  shrinkWrap: true,
                                  physics: const NeverScrollableScrollPhysics(),
                                  itemCount: group.rows.length,
                                  itemBuilder: (context, rowIndex) {
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
                                            onChanged: (v) => setState(() {
                                              if (v != null) row.unit = v;
                                            }),
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: TextField(
                                              controller: row.repsController,
                                              keyboardType:
                                                  TextInputType.number,
                                              decoration: const InputDecoration(
                                                labelText: 'Reps',
                                              ),
                                            ),
                                          ),
                                          IconButton(
                                            icon: const Icon(Icons.delete),
                                            onPressed: () => setState(
                                              () =>
                                                  group.rows.removeAt(rowIndex),
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                ),
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
                      },
                    )
                  : ListView.builder(
                      itemCount: _normalRows.length,
                      itemBuilder: (context, i) {
                        final row = _normalRows[i];
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
                                onChanged: (v) =>
                                    setState(() => row['unit'] = v),
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
                                    setState(() => _normalRows.removeAt(i)),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(_selectedType == 'drop' ? 'Drop set groups' : 'Sets'),
                IconButton(
                  icon: const Icon(Icons.add),
                  onPressed: _selectedType == 'drop'
                      ? _addDropGroup
                      : _addNormalRow,
                ),
              ],
            ),
            const SizedBox(height: 8),
            ElevatedButton(onPressed: _save, child: const Text('Save session')),
          ],
        ),
      ),
    );
  }
}
