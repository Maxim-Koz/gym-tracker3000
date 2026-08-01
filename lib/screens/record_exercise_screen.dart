import 'package:flutter/material.dart';
import 'package:gym_tracker/services/bodyweight_lookup.dart';
import 'package:gym_tracker/services/db_helper.dart';
import 'package:gym_tracker/services/session_draft_store.dart';
import 'package:gym_tracker/services/set_entry_utils.dart';
import 'package:gym_tracker/services/weight_format.dart';
import 'package:gym_tracker/widgets/edit_log_sheet.dart';

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
  String _selectedUnit = 'kg';
  final TextEditingController _noteController = TextEditingController();
  bool _showNoteField = false;
  List<Map<String, dynamic>> _bodyWeights = [];

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
        _noteController.clear();
        _showNoteField = false;

        final exerciseId = nextExercise['id'] as int?;
        final draft = exerciseId == null
            ? null
            : SessionDraftStore().get(exerciseId);
        if (draft != null) {
          _selectedType = draft.type;
          _selectedUnit = draft.unit;
          _noteController.text = draft.note;
          _showNoteField = draft.note.isNotEmpty;
          _rebuildRows(type: draft.type, draft: draft);
        } else {
          _rebuildRows(type: _selectedType);
        }
      }
      _loadSessions();
    }
  }

  @override
  void dispose() {
    _saveDraft();
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
    _noteController.dispose();
    super.dispose();
  }

  /// Snapshots whatever is currently typed into the log-new-session form
  /// and stashes it so it can be restored if the user comes back to this
  /// exercise after navigating away without saving.
  void _saveDraft() {
    final exerciseId = _exercise?['id'] as int?;
    if (exerciseId == null) return;

    final normalRowDrafts = _normalRows.map((row) {
      final restPauses = row['restPauses'] as List<TextEditingController>?;
      return NormalRowDraft(
        weight: (row['weight'] as TextEditingController?)?.text ?? '',
        reps: (row['reps'] as TextEditingController?)?.text ?? '',
        unit: row['unit'] as String? ?? _selectedUnit,
        restPauses: restPauses?.map((c) => c.text).toList() ?? const [],
      );
    }).toList();

    final dropGroupDrafts = _dropGroups
        .map(
          (group) => group.rows
              .map(
                (row) => DropRowDraft(
                  weight: row.weightController.text,
                  reps: row.repsController.text,
                  unit: row.unit,
                ),
              )
              .toList(),
        )
        .toList();

    SessionDraftStore().save(
      exerciseId,
      SessionDraft(
        type: _selectedType,
        unit: _selectedUnit,
        note: _noteController.text,
        normalRows: normalRowDrafts,
        dropGroups: dropGroupDrafts,
      ),
    );
  }

  void _rebuildRows({required String type, SessionDraft? draft}) {
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
        final groupDrafts = draft?.dropGroups;
        if (groupDrafts != null && groupDrafts.isNotEmpty) {
          for (final rowDrafts in groupDrafts) {
            final group = DropGroup(rows: []);
            for (final rowDraft in rowDrafts) {
              group.rows.add(
                SetEntryRow()
                  ..weightController.text = rowDraft.weight
                  ..repsController.text = rowDraft.reps
                  ..unit = rowDraft.unit,
              );
            }
            if (group.rows.isEmpty) group.rows.add(SetEntryRow());
            _dropGroups.add(group);
          }
        } else {
          final group = DropGroup();
          _applyUnitToGroup(group);
          _dropGroups.add(group);
        }
      } else {
        final rowDrafts = draft?.normalRows;
        if (rowDrafts != null && rowDrafts.isNotEmpty) {
          for (final rowDraft in rowDrafts) {
            _normalRows.add({
              'weight': TextEditingController(text: rowDraft.weight),
              'reps': TextEditingController(text: rowDraft.reps),
              'unit': rowDraft.unit,
              'restPauses': rowDraft.restPauses
                  .map((text) => TextEditingController(text: text))
                  .toList(),
            });
          }
        } else {
          _normalRows.add({
            'weight': TextEditingController(),
            'reps': TextEditingController(),
            'unit': _selectedUnit,
            'restPauses': <TextEditingController>[],
          });
        }
      }
    });
  }

  void _applyUnitToGroup(DropGroup group) {
    for (final row in group.rows) {
      row.unit = _selectedUnit;
    }
  }

  void _changeUnit(String? value) {
    if (value == null || value == _selectedUnit) return;
    setState(() {
      _selectedUnit = value;
      for (final row in _normalRows) {
        row['unit'] = _selectedUnit;
      }
      for (final group in _dropGroups) {
        _applyUnitToGroup(group);
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
    _rebuildRows(type: value);
  }

  void _addNormalRow() {
    setState(() {
      _normalRows.add({
        'weight': TextEditingController(),
        'reps': TextEditingController(),
        'unit': _selectedUnit,
        'restPauses': <TextEditingController>[],
      });
    });
  }

  void _addDropRow(int groupIndex) {
    setState(() {
      _dropGroups[groupIndex].rows.add(SetEntryRow()..unit = _selectedUnit);
    });
  }

  void _addDropGroup() {
    setState(() {
      final group = DropGroup();
      _applyUnitToGroup(group);
      _dropGroups.add(group);
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

    // Bodyweight lookups are a nice-to-have annotation on top of the
    // sessions list, not a hard dependency - if it fails for any reason,
    // fall back to an empty list rather than let it stop the sessions
    // preview (which we already have) from ever rendering.
    List<Map<String, dynamic>> bodyWeights = const [];
    try {
      bodyWeights = await DBHelper().getBodyWeights();
    } catch (e) {
      debugPrint('Failed to load body weights: $e');
    }

    if (!mounted) return;
    setState(() {
      _sessions = recent;
      _bodyWeights = bodyWeights;
    });
  }

  Future<void> _saveSession() async {
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

    if (!_hasValidEntries()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter at least one set.')),
      );
      return;
    }

    final noteText = _noteController.text.trim();
    final sessionId = await DBHelper().insertSession(
      exerciseId,
      DateTime.now(),
      note: noteText.isEmpty ? null : noteText,
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
    SessionDraftStore().clear(exerciseId);
    _rebuildRows(type: _selectedType);
    setState(() {
      _noteController.clear();
      _showNoteField = false;
    });
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Session saved')));
  }

  String get _exerciseInfo {
    final data = _exercise?['data'];
    if (data is Map) {
      return data['metadata'] as String? ?? '';
    }
    return '';
  }

  Future<void> _showExerciseInfoSheet() async {
    if (_exercise == null) return;
    var info = _exerciseInfo;
    var includeBodyweight =
        (_exercise?['include_bodyweight'] as bool?) ?? false;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) {
        // We rename the inner context to 'innerContext' to avoid shadowing and allow proper mounted checks.
        return StatefulBuilder(
          builder: (innerContext, setSheetState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 16,
                bottom: MediaQuery.of(innerContext).viewInsets.bottom + 16,
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
                  info.isEmpty
                      ? const Text(
                          'No info added yet for this exercise.',
                          style: TextStyle(color: Colors.grey),
                        )
                      : Text(info),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () async {
                        final updated = await _showEditInfoDialog(
                          innerContext,
                          info,
                        );
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

                          // 1. Check if the main screen is still mounted
                          if (mounted) {
                            setState(() {
                              _exercise = {..._exercise!, 'data': data};
                            });
                          }
                        }

                        // 2. Check if the bottom sheet is still mounted before setting sheet state
                        if (!innerContext.mounted) return;
                        setSheetState(() => info = updated);
                      },
                      child: const Text('Edit exercise info'),
                    ),
                  ),
                  const Divider(height: 32),
                  SwitchListTile(
                    value: includeBodyweight,
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Include bodyweight'),
                    subtitle: const Text(
                      'Every log for this exercise will show your last '
                      'recorded body weight at that time.',
                    ),
                    onChanged: (value) async {
                      final exerciseId = _exercise?['id'] as int?;
                      if (exerciseId == null) return;
                      setSheetState(() => includeBodyweight = value);
                      try {
                        await DBHelper().setExerciseIncludeBodyweight(
                          exerciseId,
                          value,
                        );
                        if (mounted) {
                          setState(() {
                            _exercise = {
                              ..._exercise!,
                              'include_bodyweight': value,
                            };
                          });
                        }
                      } catch (e) {
                        // Revert the switch and let the user know it didn't
                        // stick, rather than showing a state that wasn't
                        // actually saved.
                        setSheetState(() => includeBodyweight = !value);
                        if (innerContext.mounted) {
                          ScaffoldMessenger.of(
                            innerContext,
                          ).showSnackBar(SnackBar(content: Text('Error: $e')));
                        }
                      }
                    },
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<String?> _showEditInfoDialog(
    BuildContext context,
    String current,
  ) async {
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => _EditInfoDialog(initialText: current),
    );
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
      appBar: AppBar(
        title: Text(name),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            tooltip: 'Exercise info',
            onPressed: _exercise == null ? null : _showExerciseInfoSheet,
          ),
        ],
      ),
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
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      _formatDate(date),
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    InkWell(
                                      borderRadius: BorderRadius.circular(20),
                                      onTap: () => showEditLogSheet(
                                        context: context,
                                        session: session,
                                        sets: sets,
                                        onChanged: _loadSessions,
                                      ),
                                      child: const Padding(
                                        padding: EdgeInsets.all(4.0),
                                        child: Icon(Icons.more_vert, size: 20),
                                      ),
                                    ),
                                  ],
                                ),
                                if ((session['note'] as String?)?.isNotEmpty ??
                                    false) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    session['note'] as String,
                                    style: const TextStyle(
                                      fontStyle: FontStyle.italic,
                                      color: Colors.grey,
                                    ),
                                  ),
                                ],
                                if (_bodyweightLabelFor(session)
                                    case final bwLabel?) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    'Bodyweight: $bwLabel',
                                    style: const TextStyle(
                                      fontSize: 13,
                                      color: Colors.grey,
                                    ),
                                  ),
                                ],
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
                        const SizedBox(width: 20),
                        const Text('Unit'),
                        const SizedBox(width: 12),
                        DropdownButton<String>(
                          value: _selectedUnit,
                          items: const [
                            DropdownMenuItem(value: 'kg', child: Text('kg')),
                            DropdownMenuItem(value: 'lb', child: Text('lb')),
                          ],
                          onChanged: _changeUnit,
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
                                                  signed: true,
                                                ),
                                            decoration: const InputDecoration(
                                              labelText: 'Weight',
                                            ),
                                          ),
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
                                            signed: true,
                                          ),
                                      decoration: const InputDecoration(
                                        labelText: 'Weight',
                                      ),
                                    ),
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
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
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
                    if (!_showNoteField)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          icon: const Icon(Icons.note_add_outlined),
                          label: const Text('Add note'),
                          onPressed: () =>
                              setState(() => _showNoteField = true),
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

  /// If this exercise has bodyweight included, returns the last recorded
  /// body weight at or before [session]'s date (e.g. "75 kg"), or null if
  /// bodyweight isn't enabled for this exercise or nothing had been logged
  /// yet by then.
  String? _bodyweightLabelFor(Map<String, dynamic> session) {
    if (_exercise?['include_bodyweight'] != true) return null;
    final date = session['timestamp'] as DateTime;
    final entry = findBodyWeightAtOrBefore(date, _bodyWeights);
    if (entry == null) return null;
    return formatBodyWeightEntry(entry);
  }

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
      weightText = formatWeight(weight);
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
    final isSingleRep = values.length == 1 && values.first == '1';
    return '${values.join(', ')} ${isSingleRep ? 'rep' : 'reps'}';
  }
}

// 3. New Stateful Widget explicitly to scope the TextEditingController
class _EditInfoDialog extends StatefulWidget {
  final String initialText;

  const _EditInfoDialog({required this.initialText});

  @override
  State<_EditInfoDialog> createState() => _EditInfoDialogState();
}

class _EditInfoDialogState extends State<_EditInfoDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialText);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Edit exercise info'),
      content: TextField(
        controller: _controller,
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
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(_controller.text.trim()),
          child: const Text('Confirm'),
        ),
      ],
    );
  }
}
