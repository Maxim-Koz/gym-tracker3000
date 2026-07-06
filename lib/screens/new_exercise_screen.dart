import 'package:flutter/material.dart';
import 'package:gym_tracker/services/db_helper.dart';
import 'package:gym_tracker/services/set_entry_utils.dart';

class NewExerciseScreen extends StatefulWidget {
  const NewExerciseScreen({super.key});

  @override
  State<NewExerciseScreen> createState() => _NewExerciseScreenState();
}

class _NewExerciseScreenState extends State<NewExerciseScreen> {
  final _nameController = TextEditingController();
  String _type = 'normal';

  final List<Map<String, dynamic>> _normalRows = [];
  final List<DropGroup> _dropGroups = [];

  @override
  void dispose() {
    _nameController.dispose();
    for (final row in _normalRows) {
      row['weight']!.dispose();
      row['reps']!.dispose();
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

  @override
  void initState() {
    super.initState();
    _addNormalRow();
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

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;

    final exists = await DBHelper().getExerciseByName(name);
    if (exists != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('An exercise with that name already exists.'),
        ),
      );
      return;
    }

    final entryError = findSetEntryError(
      type: _type,
      normalRows: _normalRows,
      dropGroups: _dropGroups,
    );
    if (entryError != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(entryError)));
      return;
    }

    final validSets = collectValidSetEntries(
      type: _type,
      normalRows: _normalRows,
      dropGroups: _dropGroups,
    );

    final exerciseId = await DBHelper().insertExercise(name, _type, {});

    // If the user entered any sets while creating the exercise, record them
    // as a real session/sets entry, just like RecordExerciseScreen does.
    if (validSets.isNotEmpty) {
      final sessionId = await DBHelper().insertSession(
        exerciseId,
        DateTime.now(),
      );
      for (final values in validSets) {
        final groupIndex = values['groupIndex'] as int?;
        if (groupIndex != null) {
          await DBHelper().insertSet(
            sessionId,
            values['weight'] as double,
            values['reps'] as int,
            values['unit'] as String,
            groupIndex: groupIndex,
          );
        } else {
          final setId = await DBHelper().insertSet(
            sessionId,
            values['weight'] as double,
            values['reps'] as int,
            values['unit'] as String,
          );
          final restPauses = values['restPauses'] as List<int>? ?? [];
          for (final pauseReps in restPauses) {
            await DBHelper().insertSet(
              sessionId,
              values['weight'] as double,
              pauseReps,
              values['unit'] as String,
              parentSetId: setId,
            );
          }
        }
      }
    }

    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('New Exercise'),
        actions: [IconButton(icon: const Icon(Icons.check), onPressed: _save)],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'Exercise name'),
            ),
            const SizedBox(height: 12),
            DropdownButton<String>(
              value: _type,
              items: const [
                DropdownMenuItem(value: 'normal', child: Text('Normal')),
                DropdownMenuItem(value: 'drop', child: Text('Drop set')),
              ],
              onChanged: (v) => setState(() => _type = v!),
            ),
            const SizedBox(height: 12),
            if (_type == 'normal') ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Sets'),
                  IconButton(
                    icon: const Icon(Icons.add),
                    onPressed: _addNormalRow,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Expanded(
                child: ListView.builder(
                  itemCount: _normalRows.length,
                  itemBuilder: (context, i) {
                    final row = _normalRows[i];
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
                                icon: const Text(
                                  'RP',
                                  style: TextStyle(fontWeight: FontWeight.bold),
                                ),
                                tooltip: 'Add rest pause',
                                onPressed: () => _addRestPause(i),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete),
                                onPressed: () =>
                                    setState(() => _normalRows.removeAt(i)),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          if ((row['restPauses']
                                      as List<TextEditingController>?)
                                  ?.isNotEmpty ??
                              false)
                            ...List.generate(
                              (row['restPauses'] as List<TextEditingController>)
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
                                          keyboardType: TextInputType.number,
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
                                        icon: const Icon(Icons.delete_outline),
                                        tooltip: 'Remove rest pause',
                                        onPressed: () =>
                                            _removeRestPause(i, pauseIndex),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ] else ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Drop set groups'),
                  IconButton(
                    icon: const Icon(Icons.add),
                    onPressed: _addDropGroup,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Expanded(
                child: ListView.builder(
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
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
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
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
