import 'package:flutter/material.dart';
import 'package:gym_tracker/services/db_helper.dart';
import 'package:gym_tracker/services/session_note_utils.dart';
import 'package:gym_tracker/services/set_entry_utils.dart';
import 'package:gym_tracker/services/weight_format.dart';

/// Opens the edit sheet for a single logged session (its date, note, and
/// sets). Call this from the "..." menu wherever a session/log is shown.
///
/// [onChanged] is invoked after any edit that should cause the caller to
/// reload its session list (including when the whole log is deleted).
Future<void> showEditLogSheet({
  required BuildContext context,
  required Map<String, dynamic> session,
  required List<Map<String, dynamic>> sets,
  required VoidCallback onChanged,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) {
      return Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: EditLogSheet(session: session, sets: sets, onChanged: onChanged),
      );
    },
  );
}

class EditLogSheet extends StatefulWidget {
  const EditLogSheet({
    super.key,
    required this.session,
    required this.sets,
    required this.onChanged,
  });

  final Map<String, dynamic> session;
  final List<Map<String, dynamic>> sets;
  final VoidCallback onChanged;

  @override
  State<EditLogSheet> createState() => _EditLogSheetState();
}

class _EditLogSheetState extends State<EditLogSheet> {
  late final TextEditingController _noteController;
  late DateTime _date;
  late bool _isOneRepMax;
  late final List<int> _originalTopLevelSetIds;

  final List<Map<String, dynamic>> _normalRows = [];
  final List<DropGroup> _dropGroups = [];
  String _selectedType = 'normal';

  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _noteController = TextEditingController(
      text: stripOneRepMaxMarker(widget.session['note'] as String?),
    );
    _date = widget.session['timestamp'] as DateTime;
    _isOneRepMax = noteHasOneRepMax(widget.session['note'] as String?);
    _originalTopLevelSetIds = widget.sets
        .where((s) => s['parent_set_id'] == null)
        .map((s) => s['id'] as int)
        .toList();
    _initRowsFromExisting();
  }

  @override
  void dispose() {
    _noteController.dispose();
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

  int get _sessionId => widget.session['id'] as int;

  String _weightText(dynamic weight) {
    if (weight == null) return '';
    if (weight is double) {
      return formatWeight(weight);
    }
    return weight.toString();
  }

  Map<String, dynamic> _blankNormalRow() => {
    'weight': TextEditingController(),
    'reps': TextEditingController(),
    'unit': 'kg',
    'restPauses': <TextEditingController>[],
  };

  /// Populates _normalRows / _dropGroups (and _selectedType) from the sets
  /// this log already has, so the composer opens pre-filled with the
  /// existing data instead of blank.
  void _initRowsFromExisting() {
    final parentRows =
        widget.sets.where((s) => s['parent_set_id'] == null).toList()
          ..sort((a, b) => (a['id'] as int).compareTo(b['id'] as int));
    final hasGroups = parentRows.any((s) => s['group_index'] != null);
    _selectedType = hasGroups ? 'drop' : 'normal';

    if (hasGroups) {
      final grouped = <int, List<Map<String, dynamic>>>{};
      for (final row in parentRows.where((r) => r['group_index'] != null)) {
        grouped.putIfAbsent(row['group_index'] as int, () => []).add(row);
      }
      final sortedKeys = grouped.keys.toList()..sort();
      for (final key in sortedKeys) {
        final group = DropGroup(rows: <SetEntryRow>[]);
        for (final row in grouped[key]!) {
          final entryRow = SetEntryRow();
          entryRow.weightController.text = _weightText(row['weight']);
          entryRow.repsController.text = (row['reps'] ?? '').toString();
          entryRow.unit = (row['unit'] as String?) ?? 'kg';
          group.rows.add(entryRow);
        }
        _dropGroups.add(group);
      }
      if (_dropGroups.isEmpty) _dropGroups.add(DropGroup());
    } else {
      final normalTop = parentRows
          .where((r) => r['group_index'] == null)
          .toList();
      if (normalTop.isEmpty) {
        _normalRows.add(_blankNormalRow());
      } else {
        for (final row in normalTop) {
          final id = row['id'] as int;
          final children =
              widget.sets.where((s) => s['parent_set_id'] == id).toList()
                ..sort((a, b) => (a['id'] as int).compareTo(b['id'] as int));
          _normalRows.add({
            'weight': TextEditingController(text: _weightText(row['weight'])),
            'reps': TextEditingController(text: (row['reps'] ?? '').toString()),
            'unit': (row['unit'] as String?) ?? 'kg',
            'restPauses': children
                .map(
                  (c) =>
                      TextEditingController(text: (c['reps'] ?? '').toString()),
                )
                .toList(),
          });
        }
      }
    }
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
        _normalRows.add(_blankNormalRow());
      }
    });
  }

  void _changeSetType(String? value) {
    if (value == null || value == _selectedType) return;
    setState(() => _selectedType = value);
    _resetRowsForType(value);
  }

  void _addNormalRow() {
    setState(() => _normalRows.add(_blankNormalRow()));
  }

  void _ensureOrmRow() {
    if (_normalRows.isEmpty) {
      _normalRows.add(_blankNormalRow());
    }
    final repsController = _normalRows.first['reps'] as TextEditingController?;
    repsController?.text = '1';
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

  void _addDropRow(int groupIndex) {
    setState(() => _dropGroups[groupIndex].rows.add(SetEntryRow()));
  }

  void _addDropGroup() {
    setState(() => _dropGroups.add(DropGroup()));
  }

  Future<void> _editDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked == null) return;
    setState(() {
      _date = DateTime(
        picked.year,
        picked.month,
        picked.day,
        _date.hour,
        _date.minute,
        _date.second,
      );
    });
  }

  Future<void> _deleteLog() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this log?'),
        content: const Text(
          "This removes the whole session and all its sets. This can't be undone.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _busy = true);
    try {
      await DBHelper().deleteSession(_sessionId);
      widget.onChanged();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Something went wrong: $e')));
      }
    }
  }

  Future<void> _save() async {
    final entryError = findSetEntryError(
      type: _selectedType,
      normalRows: _normalRows,
      dropGroups: _dropGroups,
      isOneRepMax: _isOneRepMax,
    );
    if (entryError != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(entryError)));
      return;
    }

    final hasEntries = hasAnyValidSetEntries(
      type: _selectedType,
      normalRows: _normalRows,
      dropGroups: _dropGroups,
      isOneRepMax: _isOneRepMax,
    );
    if (!hasEntries) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter at least one set.')),
      );
      return;
    }

    setState(() => _busy = true);
    try {
      final noteText = _noteController.text.trim();
      final encodedNote = encodeSessionNote(
        noteText.isEmpty ? null : noteText,
        isOneRepMax: _isOneRepMax,
      );
      await DBHelper().updateSession(
        _sessionId,
        note: encodedNote.isEmpty ? null : encodedNote,
        timestamp: _date,
      );

      // Simplest, most reliable way to reconcile arbitrary edits (type
      // changes, reordering, added/removed rows and groups) is to replace
      // this session's sets outright, the same way a brand new session is
      // saved from scratch.
      for (final setId in _originalTopLevelSetIds) {
        await DBHelper().deleteSet(setId);
      }

      final setEntries = collectValidSetEntries(
        type: _selectedType,
        normalRows: _normalRows,
        dropGroups: _dropGroups,
        isOneRepMax: _isOneRepMax,
      );

      for (final entry in setEntries) {
        final groupIndex = entry['groupIndex'] as int?;
        if (groupIndex != null) {
          await DBHelper().insertSet(
            _sessionId,
            entry['weight'] as double,
            entry['reps'] as int,
            entry['unit'] as String,
            groupIndex: groupIndex,
          );
        } else {
          final setId = await DBHelper().insertSet(
            _sessionId,
            entry['weight'] as double,
            entry['reps'] as int,
            entry['unit'] as String,
          );
          final restPauses = entry['restPauses'] as List<int>? ?? [];
          for (final pauseReps in restPauses) {
            await DBHelper().insertSet(
              _sessionId,
              entry['weight'] as double,
              pauseReps,
              entry['unit'] as String,
              parentSetId: setId,
            );
          }
        }
      }

      widget.onChanged();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Something went wrong: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return AbsorbPointer(
          absorbing: _busy,
          child: Opacity(
            opacity: _busy ? 0.6 : 1.0,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: _editDate,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            vertical: 4,
                            horizontal: 2,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _formatDate(_date),
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(width: 6),
                              const Icon(
                                Icons.edit_calendar_outlined,
                                size: 18,
                              ),
                            ],
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(
                          Icons.delete_outline,
                          color: Colors.red,
                        ),
                        tooltip: 'Delete entire log',
                        onPressed: _deleteLog,
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView(
                    controller: scrollController,
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    children: [
                      TextField(
                        controller: _noteController,
                        maxLines: 2,
                        decoration: const InputDecoration(
                          labelText: 'Note',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      CheckboxListTile.adaptive(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('One rep max'),
                        value: _isOneRepMax,
                        onChanged: (value) {
                          setState(() {
                            _isOneRepMax = value ?? false;
                            if (_isOneRepMax) {
                              _selectedType = 'normal';
                              _resetRowsForType('normal');
                              _ensureOrmRow();
                            }
                          });
                        },
                        controlAffinity: ListTileControlAffinity.leading,
                      ),
                      const SizedBox(height: 16),
                      if (!_isOneRepMax)
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
                        ..._buildDropGroups()
                      else if (_isOneRepMax)
                        _buildOrmEntry()
                      else
                        ..._buildNormalRows(),
                      const SizedBox(height: 8),
                      if (!_isOneRepMax)
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              _selectedType == 'drop'
                                  ? 'Drop set groups'
                                  : 'Sets',
                            ),
                            IconButton(
                              icon: const Icon(Icons.add),
                              onPressed: _selectedType == 'drop'
                                  ? _addDropGroup
                                  : _addNormalRow,
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _save,
                        child: const Text('Save'),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildOrmEntry() {
    _ensureOrmRow();
    final row = _normalRows.first;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Enter a single weight for this 1RM.',
            style: TextStyle(
              fontSize: 13,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: row['weight'] as TextEditingController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                    signed: true,
                  ),
                  decoration: const InputDecoration(labelText: 'Weight'),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 92,
                child: TextField(
                  controller: row['reps'] as TextEditingController,
                  keyboardType: TextInputType.number,
                  readOnly: true,
                  decoration: const InputDecoration(labelText: 'Reps'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  List<Widget> _buildDropGroups() {
    return List.generate(_dropGroups.length, (groupIndex) {
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
                    onPressed: () =>
                        setState(() => _dropGroups.removeAt(groupIndex)),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ...List.generate(group.rows.length, (rowIndex) {
                final row = group.rows[rowIndex];
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6.0),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: row.weightController,
                          keyboardType: const TextInputType.numberWithOptions(
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
                          DropdownMenuItem(value: 'kg', child: Text('kg')),
                          DropdownMenuItem(value: 'lb', child: Text('lb')),
                        ],
                        onChanged: (value) =>
                            setState(() => row.unit = value ?? row.unit),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: row.repsController,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(labelText: 'Reps'),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete),
                        onPressed: () =>
                            setState(() => group.rows.removeAt(rowIndex)),
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
    });
  }

  List<Widget> _buildNormalRows() {
    return List.generate(_normalRows.length, (index) {
      final row = _normalRows[index];
      final restPauses = row['restPauses'] as List<TextEditingController>;
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: row['weight'] as TextEditingController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(labelText: 'Weight'),
                  ),
                ),
                const SizedBox(width: 8),
                DropdownButton<String>(
                  value: row['unit'] as String?,
                  items: const [
                    DropdownMenuItem(value: 'kg', child: Text('kg')),
                    DropdownMenuItem(value: 'lb', child: Text('lb')),
                  ],
                  onChanged: (value) => setState(() => row['unit'] = value),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: row['reps'] as TextEditingController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Reps'),
                  ),
                ),
                SizedBox(
                  height: 40,
                  child: FilledButton.tonal(
                    onPressed: () => _addRestPause(index),
                    child: const Text('RP'),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.delete),
                  onPressed: () => setState(() {
                    (row['weight'] as TextEditingController).dispose();
                    (row['reps'] as TextEditingController).dispose();
                    for (final c in restPauses) {
                      c.dispose();
                    }
                    _normalRows.removeAt(index);
                  }),
                ),
              ],
            ),
            const SizedBox(height: 4),
            if (restPauses.isNotEmpty)
              ...List.generate(restPauses.length, (pauseIndex) {
                final pauseController = restPauses[pauseIndex];
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
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline),
                        tooltip: 'Remove rest pause',
                        onPressed: () => _removeRestPause(index, pauseIndex),
                      ),
                    ],
                  ),
                );
              }),
          ],
        ),
      );
    });
  }

  String _formatDate(DateTime date) {
    final local = date.toLocal();
    return '${local.day.toString().padLeft(2, '0')}/${local.month.toString().padLeft(2, '0')}/${local.year}';
  }
}
