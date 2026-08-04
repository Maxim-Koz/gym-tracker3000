import 'package:flutter/material.dart';
import 'package:gym_tracker/services/db_helper.dart';
import 'package:gym_tracker/services/exercise_grouping.dart';

class ExerciseGroupsScreen extends StatefulWidget {
  const ExerciseGroupsScreen({super.key, this.initialGroupName});

  final String? initialGroupName;

  @override
  State<ExerciseGroupsScreen> createState() => _ExerciseGroupsScreenState();
}

class _ExerciseGroupsScreenState extends State<ExerciseGroupsScreen> {
  final TextEditingController _searchController = TextEditingController();
  List<Map<String, dynamic>> _exercises = [];
  List<String> _knownGroupNames = const <String>[];
  Map<String, List<int>> _groupExerciseOrder = const <String, List<int>>{};
  String? _selectedGroupName;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _selectedGroupName = widget.initialGroupName;
    _loadExercises();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadExercises() async {
    final list = await DBHelper().getExercises();
    final groupNames = await loadExerciseGroupNames(list);
    final groupExerciseOrder = await loadExerciseGroupOrders(groupNames);
    if (!mounted) return;
    setState(() {
      _exercises = list;
      _knownGroupNames = groupNames;
      _groupExerciseOrder = groupExerciseOrder;
    });
  }

  List<ExerciseGroupSection> get _sections {
    return buildExerciseGroupSections(
      _exercises,
      extraGroupNames: _knownGroupNames,
      groupExerciseOrder: _groupExerciseOrder,
    );
  }

  Future<void> _reorderExercisesInGroup(
    ExerciseGroupSection section,
    int oldIndex,
    int newIndex,
  ) async {
    if (section.name == 'All Exercises') return;
    if (oldIndex < 0 || oldIndex >= section.exercises.length) return;
    if (newIndex < 0 || newIndex > section.exercises.length) return;

    final updated = List<Map<String, dynamic>>.from(section.exercises);
    if (newIndex > oldIndex) {
      newIndex -= 1;
    }
    final moved = updated.removeAt(oldIndex);
    updated.insert(newIndex, moved);

    final orderedIds = <int>[];
    for (final exercise in updated) {
      final id = exercise['id'];
      if (id is int) {
        orderedIds.add(id);
      }
    }

    setState(() {
      _groupExerciseOrder = <String, List<int>>{
        ..._groupExerciseOrder,
        section.name: orderedIds,
      };
    });

    try {
      await saveExerciseGroupOrder(section.name, orderedIds);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save exercise order: $e')),
      );
    }
  }

  ExerciseGroupSection? get _selectedSection {
    if (_selectedGroupName == null) return null;
    return _sections.firstWhere(
      (section) => section.name == _selectedGroupName,
      orElse: () => _sections.first,
    );
  }

  List<Map<String, dynamic>> _getFilteredExercises(
    ExerciseGroupSection section,
  ) {
    final query = _searchQuery.trim().toLowerCase();
    if (query.isEmpty) {
      return section.exercises;
    }

    return section.exercises.where((exercise) {
      final name = (exercise['name'] ?? '').toString().toLowerCase();
      return name.contains(query);
    }).toList();
  }

  Future<void> _renameGroup() async {
    final oldGroupName = _selectedGroupName;
    if (oldGroupName == null || oldGroupName == 'All Exercises') return;

    final nameController = TextEditingController(text: oldGroupName);
    final newName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename group'),
        content: TextField(
          controller: nameController,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Group name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () =>
                Navigator.of(context).pop(nameController.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (newName == null || newName.isEmpty) return;
    if (newName == oldGroupName) return;

    final existingGroupNames = await loadExerciseGroupNames(_exercises);
    if (existingGroupNames.contains(newName)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('That group already exists.')),
      );
      return;
    }

    try {
      for (final exercise in _exercises) {
        final data = Map<String, dynamic>.from(
          (exercise['data'] as Map?) ?? <String, dynamic>{},
        );
        final groups = <String>[];
        final rawGroups = data['groups'];
        if (rawGroups is List) {
          for (final group in rawGroups) {
            final candidate = group?.toString().trim();
            if (candidate != null && candidate.isNotEmpty) {
              groups.add(candidate == oldGroupName ? newName : candidate);
            }
          }
        }
        await DBHelper().setExerciseGroups(exercise['id'] as int, groups);
      }
      await renameExerciseGroupName(oldGroupName, newName);
      await renameExerciseGroupOrder(oldGroupName, newName);
      if (!mounted) return;
      await _loadExercises();
      if (!mounted) return;
      setState(() => _selectedGroupName = newName);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  Future<void> _deleteGroup() async {
    final groupName = _selectedGroupName;
    if (groupName == null || groupName == 'All Exercises') return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete group?'),
        content: Text('Remove "$groupName" from every exercise?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      for (final exercise in _exercises) {
        final data = Map<String, dynamic>.from(
          (exercise['data'] as Map?) ?? <String, dynamic>{},
        );
        final groups = <String>[];
        final rawGroups = data['groups'];
        if (rawGroups is List) {
          for (final group in rawGroups) {
            final candidate = group?.toString().trim();
            if (candidate != null &&
                candidate.isNotEmpty &&
                candidate != groupName) {
              groups.add(candidate);
            }
          }
        }
        await DBHelper().setExerciseGroups(exercise['id'] as int, groups);
      }
      await removeExerciseGroupName(groupName);
      await removeExerciseGroupOrder(groupName);
      if (!mounted) return;
      await _loadExercises();
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  Future<void> _addExercisesToGroup() async {
    final groupName = _selectedGroupName;
    if (groupName == null) return;

    final availableExercises = _exercises.where((exercise) {
      final data = exercise['data'];
      if (data is! Map) return true;
      final rawGroups = data['groups'];
      if (rawGroups is! List) return true;
      return !rawGroups.any((candidate) => candidate?.toString() == groupName);
    }).toList();

    if (availableExercises.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('All exercises are already in this group.'),
        ),
      );
      return;
    }

    final selectedIds = <int>{};
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          final maxContentHeight = MediaQuery.of(context).size.height * 0.55;
          return AlertDialog(
            title: const Text('Add exercises'),
            content: SizedBox(
              width: double.maxFinite,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: maxContentHeight),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Choose exercises to add to this group'),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final exercise in availableExercises)
                            FilterChip(
                              label: Text(
                                exercise['name'] as String? ?? 'Exercise',
                              ),
                              selected: selectedIds.contains(
                                exercise['id'] as int,
                              ),
                              onSelected: (selected) {
                                setState(() {
                                  final id = exercise['id'] as int;
                                  if (selected) {
                                    selectedIds.add(id);
                                  } else {
                                    selectedIds.remove(id);
                                  }
                                });
                              },
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Add'),
              ),
            ],
          );
        },
      ),
    );

    if (confirmed != true || selectedIds.isEmpty) return;

    try {
      for (final exercise in availableExercises) {
        final id = exercise['id'] as int;
        if (!selectedIds.contains(id)) continue;

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
        if (!groups.contains(groupName)) {
          groups.add(groupName);
        }
        await DBHelper().setExerciseGroups(id, groups);
      }
      if (!mounted) return;
      await _loadExercises();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  Future<void> _renameExercise(Map<String, dynamic> exercise) async {
    final nameController = TextEditingController(
      text: exercise['name'] as String? ?? '',
    );
    final newName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename exercise'),
        content: TextField(
          controller: nameController,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Exercise name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () =>
                Navigator.of(context).pop(nameController.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (newName == null || newName.isEmpty) return;

    try {
      await DBHelper().renameExercise(exercise['id'] as int, newName);
      if (!mounted) return;
      await _loadExercises();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  Future<void> _removeExerciseFromGroup(Map<String, dynamic> exercise) async {
    final groupName = _selectedGroupName;
    if (groupName == null) return;

    try {
      final data = Map<String, dynamic>.from(
        (exercise['data'] as Map?) ?? <String, dynamic>{},
      );
      final groups = <String>[];
      final rawGroups = data['groups'];
      if (rawGroups is List) {
        for (final group in rawGroups) {
          final candidate = group?.toString().trim();
          if (candidate != null &&
              candidate.isNotEmpty &&
              candidate != groupName) {
            groups.add(candidate);
          }
        }
      }
      await DBHelper().setExerciseGroups(exercise['id'] as int, groups);
      if (!mounted) return;
      await _loadExercises();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  Future<void> _deleteExercise(Map<String, dynamic> exercise) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete exercise?'),
        content: Text(
          'This will permanently delete ${exercise['name'] as String? ?? 'this exercise'} and all of its logs.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await DBHelper().deleteExercise(exercise['id'] as int);
      if (!mounted) return;
      await _loadExercises();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  Future<void> _createGroup() async {
    final nameController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    int? selectedExerciseId;

    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New group'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: nameController,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Group name'),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter a name';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<int>(
                decoration: const InputDecoration(
                  labelText: 'Add an existing exercise to the group',
                ),
                items: [
                  for (final exercise in _exercises)
                    DropdownMenuItem<int>(
                      value: exercise['id'] as int,
                      child: Text(exercise['name'] as String? ?? 'Exercise'),
                    ),
                ],
                onChanged: (value) => selectedExerciseId = value,
                validator: (value) {
                  if (value == null) {
                    return 'Pick an exercise';
                  }
                  return null;
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              if (formKey.currentState!.validate()) {
                Navigator.of(context).pop(nameController.text.trim());
              }
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );

    if (name == null || selectedExerciseId == null) return;

    final existingGroupNames = await loadExerciseGroupNames(_exercises);
    if (existingGroupNames.contains(name)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('That group already exists.')),
      );
      return;
    }

    try {
      final exercise = _exercises.firstWhere(
        (item) => item['id'] == selectedExerciseId,
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
      await addExerciseGroupName(name);
      await DBHelper().setExerciseGroups(exercise['id'] as int, groups);
      if (!mounted) return;
      await _loadExercises();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final selectedSection = _selectedSection;
    final isInGroup =
        selectedSection != null && selectedSection.name != 'All Exercises';
    final filteredExercises = selectedSection == null
        ? const <Map<String, dynamic>>[]
        : _getFilteredExercises(selectedSection);
    final canReorder = isInGroup && _searchQuery.trim().isEmpty;

    return Scaffold(
      appBar: AppBar(
        title: Text(selectedSection == null ? 'Groups' : selectedSection.name),
        leading: selectedSection == null
            ? null
            : IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => Navigator.of(context).pop(),
              ),
        actions: [
          if (selectedSection != null &&
              selectedSection.name != 'All Exercises')
            IconButton(
              icon: const Icon(Icons.add),
              tooltip: 'Add exercises to group',
              onPressed: _addExercisesToGroup,
            ),
          if (selectedSection != null &&
              selectedSection.name != 'All Exercises')
            PopupMenuButton<String>(
              tooltip: 'Group actions',
              onSelected: (value) async {
                switch (value) {
                  case 'rename_group':
                    await _renameGroup();
                    break;
                  case 'delete_group':
                    await _deleteGroup();
                    break;
                }
              },
              itemBuilder: (context) => const [
                PopupMenuItem(
                  value: 'rename_group',
                  child: Text('Rename group'),
                ),
                PopupMenuItem(
                  value: 'delete_group',
                  child: Text('Delete group'),
                ),
              ],
            ),
          if (selectedSection == null)
            IconButton(
              icon: const Icon(Icons.add),
              tooltip: 'Add group',
              onPressed: _createGroup,
            ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: selectedSection == null
            ? ListView(
                children: [
                  for (final section in _sections)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Card(
                        child: ListTile(
                          title: Text(section.name),
                          subtitle: Text(
                            '${section.exercises.length} exercise${section.exercises.length == 1 ? '' : 's'}',
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () {
                            setState(() => _selectedGroupName = section.name);
                          },
                        ),
                      ),
                    ),
                  if (_sections.isEmpty)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.only(top: 16),
                        child: Text('No groups yet.'),
                      ),
                    ),
                ],
              )
            : Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: TextField(
                      controller: _searchController,
                      decoration: const InputDecoration(
                        hintText: 'Search exercises',
                        prefixIcon: Icon(Icons.search),
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (value) {
                        setState(() => _searchQuery = value);
                      },
                    ),
                  ),
                  Expanded(
                    child: canReorder
                        ? ReorderableListView.builder(
                            itemCount: filteredExercises.length,
                            onReorder: (oldIndex, newIndex) async {
                              await _reorderExercisesInGroup(
                                selectedSection,
                                oldIndex,
                                newIndex,
                              );
                            },
                            itemBuilder: (context, index) {
                              final ex = filteredExercises[index];
                              return Card(
                                key: ValueKey(ex['id']),
                                margin: const EdgeInsets.only(bottom: 8),
                                child: ListTile(
                                  title: Text(ex['name'] ?? ''),
                                  onTap: () async {
                                    await Navigator.of(context).pushNamed(
                                      '/record_exercise',
                                      arguments: ex,
                                    );
                                    if (mounted) _loadExercises();
                                  },
                                  trailing: PopupMenuButton<String>(
                                    tooltip: 'Exercise actions',
                                    onSelected: (value) async {
                                      switch (value) {
                                        case 'rename':
                                          await _renameExercise(ex);
                                          break;
                                        case 'remove_from_group':
                                          await _removeExerciseFromGroup(ex);
                                          break;
                                        case 'delete':
                                          await _deleteExercise(ex);
                                          break;
                                      }
                                    },
                                    itemBuilder: (context) {
                                      final items = <PopupMenuEntry<String>>[
                                        const PopupMenuItem(
                                          value: 'rename',
                                          child: Text('Rename exercise'),
                                        ),
                                        if (selectedSection.name !=
                                            'All Exercises')
                                          const PopupMenuItem(
                                            value: 'remove_from_group',
                                            child: Text('Remove from group'),
                                          ),
                                        const PopupMenuItem(
                                          value: 'delete',
                                          child: Text('Delete exercise'),
                                        ),
                                      ];
                                      return items;
                                    },
                                  ),
                                ),
                              );
                            },
                          )
                        : filteredExercises.isEmpty
                        ? const Center(
                            child: Padding(
                              padding: EdgeInsets.only(top: 16),
                              child: Text('No matching exercises found.'),
                            ),
                          )
                        : ListView.builder(
                            itemCount: filteredExercises.length,
                            itemBuilder: (context, index) {
                              final ex = filteredExercises[index];
                              return Card(
                                margin: const EdgeInsets.only(bottom: 8),
                                child: ListTile(
                                  title: Text(ex['name'] ?? ''),
                                  onTap: () async {
                                    await Navigator.of(context).pushNamed(
                                      '/record_exercise',
                                      arguments: ex,
                                    );
                                    if (mounted) _loadExercises();
                                  },
                                  trailing: PopupMenuButton<String>(
                                    tooltip: 'Exercise actions',
                                    onSelected: (value) async {
                                      switch (value) {
                                        case 'rename':
                                          await _renameExercise(ex);
                                          break;
                                        case 'remove_from_group':
                                          await _removeExerciseFromGroup(ex);
                                          break;
                                        case 'delete':
                                          await _deleteExercise(ex);
                                          break;
                                      }
                                    },
                                    itemBuilder: (context) {
                                      final items = <PopupMenuEntry<String>>[
                                        const PopupMenuItem(
                                          value: 'rename',
                                          child: Text('Rename exercise'),
                                        ),
                                        if (selectedSection.name !=
                                            'All Exercises')
                                          const PopupMenuItem(
                                            value: 'remove_from_group',
                                            child: Text('Remove from group'),
                                          ),
                                        const PopupMenuItem(
                                          value: 'delete',
                                          child: Text('Delete exercise'),
                                        ),
                                      ];
                                      return items;
                                    },
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
      ),
    );
  }
}
