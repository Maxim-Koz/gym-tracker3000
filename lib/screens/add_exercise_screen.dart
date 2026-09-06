import 'package:flutter/material.dart';
import 'package:gym_tracker/widgets/bottom_nav_bar.dart';
import 'package:gym_tracker/services/db_helper.dart';
import 'package:gym_tracker/services/exercise_grouping.dart';

class AddExerciseScreen extends StatefulWidget {
  const AddExerciseScreen({super.key});

  @override
  State<AddExerciseScreen> createState() => _AddExerciseScreenState();
}

class _AddExerciseScreenState extends State<AddExerciseScreen> {
  int _selectedIndex = 1;
  List<Map<String, dynamic>> _exercises = [];
  List<String> _knownGroupNames = const <String>[];
  List<String> _groupNameOrder = const <String>[];
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadExercises();
  }

  Future<void> _loadExercises() async {
    final list = await DBHelper().getExercises();
    final groupNames = await loadExerciseGroupNames(list);
    final groupNameOrder = await loadExerciseGroupNameOrder();
    if (!mounted) return;
    setState(() {
      _exercises = list;
      _knownGroupNames = groupNames;
      _groupNameOrder = groupNameOrder.isNotEmpty ? groupNameOrder : groupNames;
    });
  }

  Future<void> _openNewGroupScreen() async {
    final result = await Navigator.of(context).pushNamed('/new_group');
    if (result == true && mounted) {
      await _loadExercises();
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<ExerciseGroupSection> get _filteredSections {
    final query = _searchQuery.trim().toLowerCase();
    final sections = buildExerciseGroupSections(
      _exercises,
      extraGroupNames: _knownGroupNames,
      groupNameOrder: _groupNameOrder,
    );
    if (query.isEmpty) return sections;
    return sections
        .where((section) => section.name.toLowerCase().contains(query))
        .toList();
  }

  Future<void> _reorderGroupNamesByIndex(int oldIndex, int newIndex) async {
    final orderedNames = List<String>.from(
      _groupNameOrder.isNotEmpty ? _groupNameOrder : _knownGroupNames,
    );
    if (oldIndex < 0 || oldIndex >= orderedNames.length) return;
    if (newIndex < 0 || newIndex > orderedNames.length) return;

    final moved = orderedNames.removeAt(oldIndex);
    if (newIndex > orderedNames.length) {
      orderedNames.add(moved);
    } else {
      orderedNames.insert(newIndex, moved);
    }

    setState(() {
      _knownGroupNames = orderedNames;
      _groupNameOrder = orderedNames;
    });

    try {
      await saveExerciseGroupNameOrder(orderedNames);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not save group order: $e')));
    }
  }

  void _onNavTap(int index) {
    setState(() {
      _selectedIndex = index;
    });

    switch (index) {
      case 0:
        Navigator.of(context).pushNamed('/home');
        break;
      case 1:
        break;
      case 2:
        Navigator.of(context).pushNamed('/weight');
        break;
      case 3:
        Navigator.of(context).pushNamed('/settings');
        break;
    }
  }

  Widget _buildGroupCard(ExerciseGroupSection section) {
    return Padding(
      key: ValueKey(section.name),
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        child: ListTile(
          title: Text(section.name),
          subtitle: Text(
            '${section.exercises.length} exercise${section.exercises.length == 1 ? '' : 's'}',
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: () async {
            await Navigator.of(
              context,
            ).pushNamed('/exercise_groups', arguments: section.name);
            if (mounted) _loadExercises();
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sections = _filteredSections;
    final customSections = sections
        .where((section) => section.name != 'All Exercises')
        .toList();
    final allExercisesSection = sections
        .where((section) => section.name == 'All Exercises')
        .toList();
    final canReorder = _searchQuery.trim().isEmpty;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Groups'),
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            tooltip: 'Add group',
            icon: const Icon(Icons.grid_view),
            onPressed: _openNewGroupScreen,
          ),
          IconButton(
            tooltip: 'Add exercise',
            icon: const Icon(Icons.add_circle_outline),
            onPressed: () async {
              final res = await Navigator.of(
                context,
              ).pushNamed('/new_exercise');
              if (res == true) _loadExercises();
            },
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          children: [
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4.0),
              child: TextField(
                controller: _searchController,
                decoration: const InputDecoration(
                  hintText: 'Search groups',
                  prefixIcon: Icon(Icons.search),
                  border: OutlineInputBorder(),
                ),
                onChanged: (value) {
                  setState(() {
                    _searchQuery = value;
                  });
                },
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: _exercises.isEmpty && _knownGroupNames.isEmpty
                  ? const Center(child: Text('No exercises yet. Tap + to add.'))
                  : sections.isEmpty
                  ? const Center(child: Text('No groups match your search.'))
                  : Column(
                      children: [
                        for (final section in allExercisesSection)
                          _buildGroupCard(section),
                        Expanded(
                          child: customSections.isEmpty
                              ? const SizedBox.shrink()
                              : canReorder
                              ? ReorderableListView.builder(
                                  itemCount: customSections.length,
                                  onReorderItem: (oldIndex, newIndex) async {
                                    if (oldIndex < 0 ||
                                        oldIndex >= customSections.length ||
                                        newIndex < 0 ||
                                        newIndex > customSections.length) {
                                      return;
                                    }
                                    await _reorderGroupNamesByIndex(
                                      oldIndex,
                                      newIndex,
                                    );
                                  },
                                  itemBuilder: (context, index) =>
                                      _buildGroupCard(customSections[index]),
                                )
                              : ListView.builder(
                                  itemCount: customSections.length,
                                  itemBuilder: (context, index) =>
                                      _buildGroupCard(customSections[index]),
                                ),
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: BottomNavBar(
        currentIndex: _selectedIndex,
        onTap: _onNavTap,
      ),
    );
  }
}
