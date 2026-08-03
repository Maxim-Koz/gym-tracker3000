import 'package:flutter/material.dart';
import 'package:gym_tracker/services/db_helper.dart';
import 'package:gym_tracker/services/session_note_utils.dart';
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
  final TextEditingController _noteController = TextEditingController();
  bool _showNoteField = false;
  bool _isOneRepMax = false;

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
        _noteController.clear();
        _showNoteField = false;
        _isOneRepMax = false;
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
    _noteController.dispose();
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

    final entryError = findSetEntryError(
      type: _selectedType,
      normalRows: _normalRows,
      dropGroups: _dropGroups,
    );
    if (entryError != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(entryError)));
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

    final noteText = _noteController.text.trim();
    final encodedNote = encodeSessionNote(
      noteText.isEmpty ? null : noteText,
      isOneRepMax: _isOneRepMax,
    );
    final sessionId = await DBHelper().insertSession(
      exerciseId,
      DateTime.now(),
      note: encodedNote.isEmpty ? null : encodedNote,
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
    _noteController.clear();
    _showNoteField = false;
    _isOneRepMax = false;
    Navigator.of(context).pop(true);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Session saved')));
  }

  String get _exerciseMetadata {
    final data = _exercise?['data'];
    if (data is Map) {
      return data['metadata'] as String? ?? '';
    }
    return '';
  }

  Future<void> _showExerciseInfoSheet() async {
    if (_exercise == null) return;
    var metadata = _exerciseMetadata;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 16,
                bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 16,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    (_exercise?['name'] as String?) ?? 'Exercise',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  metadata.isEmpty
                      ? const Text(
                          'No notes yet for this exercise.',
                          style: TextStyle(color: Colors.grey),
                        )
                      : Text(metadata),
                  const SizedBox(height: 20),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      icon: const Icon(Icons.edit_outlined),
                      label: const Text('Edit exercise metadata'),
                      onPressed: () async {
                        final updated = await _showEditMetadataDialog(metadata);
                        if (updated == null) return;

                        final exerciseId = _exercise?['id'] as int?;
                        if (exerciseId != null) {
                          await DBHelper().updateExerciseMetadata(
                            exerciseId,
                            updated,
                          );
                          final data = Map<String, dynamic>.from(
                            (_exercise?['data'] as Map?) ?? <String, dynamic>{},
                          );
                          if (updated.isEmpty) {
                            data.remove('metadata');
                          } else {
                            data['metadata'] = updated;
                          }
                          if (mounted) {
                            setState(() {
                              _exercise = {..._exercise!, 'data': data};
                            });
                          }
                        }

                        setSheetState(() => metadata = updated);
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<String?> _showEditMetadataDialog(String current) async {
    final controller = TextEditingController(text: current);
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Edit exercise metadata'),
        content: TextField(
          controller: controller,
          maxLines: 4,
          autofocus: true,
          decoration: const InputDecoration(
            hintText:
                'Add notes about this exercise (form cues, machine settings, etc.)',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final exerciseName = _exercise?['name'] ?? 'Exercise';

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Flexible(
              child: Text(
                'Record $exerciseName',
                overflow: TextOverflow.ellipsis,
              ),
            ),
            IconButton(
              icon: const Icon(Icons.info_outline),
              tooltip: 'Exercise info',
              onPressed: _showExerciseInfoSheet,
            ),
          ],
        ),
      ),
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
                                                    signed: true,
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
                                        signed: true,
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
            CheckboxListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: const Text('One rep max'),
              value: _isOneRepMax,
              onChanged: (value) =>
                  setState(() => _isOneRepMax = value ?? false),
              controlAffinity: ListTileControlAffinity.leading,
            ),
            if (!_showNoteField)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  icon: const Icon(Icons.note_add_outlined),
                  label: const Text('Add note'),
                  onPressed: () => setState(() => _showNoteField = true),
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.only(bottom: 8.0),
                child: TextField(
                  controller: _noteController,
                  maxLines: 3,
                  decoration: InputDecoration(
                    labelText: 'Note',
                    alignLabelWithHint: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.close),
                      tooltip: 'Remove note',
                      onPressed: () => setState(() {
                        _noteController.clear();
                        _showNoteField = false;
                      }),
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 8),
            ElevatedButton(onPressed: _save, child: const Text('Save session')),
          ],
        ),
      ),
    );
  }
}
