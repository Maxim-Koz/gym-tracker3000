import 'package:flutter/material.dart';
import 'package:gym_tracker/services/db_helper.dart';
import 'package:gym_tracker/services/exercise_grouping.dart';

/// Creates a new exercise. Deliberately minimal - just a name and whether
/// to include bodyweight - logging an actual session happens afterwards
/// from RecordExerciseScreen, not here.
class NewExerciseScreen extends StatefulWidget {
  const NewExerciseScreen({super.key});

  @override
  State<NewExerciseScreen> createState() => _NewExerciseScreenState();
}

class _NewExerciseScreenState extends State<NewExerciseScreen> {
  final _nameController = TextEditingController();
  bool _includeBodyweight = false;
  bool _isSaving = false;
  List<String> _groupNames = [];
  final Set<String> _selectedGroups = <String>{};

  @override
  void initState() {
    super.initState();
    _loadExistingGroups();
  }

  Future<void> _loadExistingGroups() async {
    final exercises = await DBHelper().getExercises();
    final groupNames = await loadExerciseGroupNames(exercises);
    if (!mounted) return;
    setState(() => _groupNames = groupNames);
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;

    setState(() => _isSaving = true);
    try {
      final exists = await DBHelper().getExerciseByName(name);
      if (exists != null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('An exercise with that name already exists.'),
          ),
        );
        return;
      }

      // Type only matters once the user starts logging sets, so it isn't
      // asked for here - every exercise starts as 'normal' and can be
      // changed later if that ever needs to be exposed.
      final groups = _selectedGroups.toList()..sort();
      await DBHelper().insertExercise(name, 'normal', {
        'groups': groups,
      }, includeBodyweight: _includeBodyweight);

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('New Exercise'),
        actions: [
          IconButton(
            icon: const Icon(Icons.check),
            onPressed: _isSaving ? null : _save,
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _nameController,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Exercise name'),
              onSubmitted: (_) => _isSaving ? null : _save(),
            ),
            const SizedBox(height: 24),
            SwitchListTile(
              value: _includeBodyweight,
              onChanged: (value) {
                setState(() => _includeBodyweight = value);
              },
              contentPadding: EdgeInsets.zero,
              title: const Text('Include bodyweight'),
              subtitle: const Text(
                'Every log for this exercise will show your last recorded '
                'body weight at that time. You can change this later.',
              ),
            ),
            if (_groupNames.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text('Add to groups'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final groupName in _groupNames)
                    FilterChip(
                      label: Text(groupName),
                      selected: _selectedGroups.contains(groupName),
                      onSelected: (selected) {
                        setState(() {
                          if (selected) {
                            _selectedGroups.add(groupName);
                          } else {
                            _selectedGroups.remove(groupName);
                          }
                        });
                      },
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
