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
    if (!mounted) return;
    setState(() {
      _exercises = list;
      _knownGroupNames = groupNames;
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
    );
    if (query.isEmpty) return sections;
    return sections
        .where((section) => section.name.toLowerCase().contains(query))
        .toList();
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
        // Already on add exercise
        break;
      case 2:
        Navigator.of(context).pushNamed('/weight');
        break;
      case 3:
        Navigator.of(context).pushNamed('/settings');
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
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
        child: ListView(
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
            if (_exercises.isEmpty && _knownGroupNames.isEmpty)
              const Center(child: Text('No exercises yet. Tap + to add.'))
            else if (_filteredSections.isEmpty)
              const Center(child: Text('No groups match your search.'))
            else
              for (final section in _filteredSections)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Card(
                    child: ListTile(
                      title: Text(section.name),
                      subtitle: Text(
                        '${section.exercises.length} exercise${section.exercises.length == 1 ? '' : 's'}',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () async {
                        await Navigator.of(context).pushNamed(
                          '/exercise_groups',
                          arguments: section.name,
                        );
                        if (mounted) _loadExercises();
                      },
                    ),
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
