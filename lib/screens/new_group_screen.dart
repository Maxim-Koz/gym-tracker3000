import 'package:flutter/material.dart';
import 'package:gym_tracker/services/db_helper.dart';
import 'package:gym_tracker/services/exercise_grouping.dart';

class NewGroupScreen extends StatefulWidget {
  const NewGroupScreen({super.key});

  @override
  State<NewGroupScreen> createState() => _NewGroupScreenState();
}

class _NewGroupScreenState extends State<NewGroupScreen> {
  final _nameController = TextEditingController();
  final Set<int> _selectedExerciseIds = <int>{};
  List<Map<String, dynamic>> _exercises = [];
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadExercises();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _loadExercises() async {
    final list = await DBHelper().getExercises();
    if (!mounted) return;
    setState(() => _exercises = list);
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a group name.')),
      );
      return;
    }

    final existingGroupNames = await loadExerciseGroupNames(_exercises);
    if (existingGroupNames.contains(name)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('That group already exists.')),
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      await addExerciseGroupName(name);
      for (final exerciseId in _selectedExerciseIds) {
        final exercise = _exercises.firstWhere(
          (item) => item['id'] == exerciseId,
        );
        final data = Map<String, dynamic>.from(
          (exercise['data'] as Map?) ?? <String, dynamic>{},
        );
        final groups = <String>[];
        final rawGroups = data['groups'];
        if (rawGroups is List) {
          for (final group in rawGroups) {
            final groupName = group?.toString().trim();
            if (groupName != null && groupName.isNotEmpty) {
              groups.add(groupName);
            }
          }
        }
        if (!groups.contains(name)) {
          groups.add(name);
        }
        await DBHelper().setExerciseGroups(exercise['id'] as int, groups);
      }

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
        title: const Text('New Group'),
        actions: [
          IconButton(
            icon: const Icon(Icons.check),
            onPressed: _isSaving ? null : _save,
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: _exercises.isEmpty
            ? const Center(child: Text('No exercises yet. Add one first.'))
            : ListView(
                children: [
                  TextField(
                    controller: _nameController,
                    autofocus: true,
                    decoration: const InputDecoration(labelText: 'Group name'),
                  ),
                  const SizedBox(height: 24),
                  const Text('Choose exercises to add to this group'),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final exercise in _exercises)
                        FilterChip(
                          label: Text(
                            exercise['name'] as String? ?? 'Exercise',
                          ),
                          selected: _selectedExerciseIds.contains(
                            exercise['id'] as int,
                          ),
                          onSelected: (selected) {
                            setState(() {
                              final exerciseId = exercise['id'] as int;
                              if (selected) {
                                _selectedExerciseIds.add(exerciseId);
                              } else {
                                _selectedExerciseIds.remove(exerciseId);
                              }
                            });
                          },
                        ),
                    ],
                  ),
                ],
              ),
      ),
    );
  }
}
