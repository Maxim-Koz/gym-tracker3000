import 'package:flutter/material.dart';
import 'package:gym_tracker/services/db_helper.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  List<Map<String, dynamic>> _exercises = [];
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadExercises();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadExercises() async {
    final exercises = await DBHelper().getExercises();
    setState(() => _exercises = exercises);
  }

  List<Map<String, dynamic>> get _filteredExercises {
    final query = _searchQuery.trim().toLowerCase();
    if (query.isEmpty) return _exercises;

    return _exercises.where((exercise) {
      final name = (exercise['name'] as String? ?? '').toLowerCase();
      return name.contains(query);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Exercise History')),
      body: _exercises.isEmpty
          ? const Center(
              child: Text('No history yet. Add exercises and record sessions.'),
            )
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
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
                  child: _filteredExercises.isEmpty
                      ? const Center(child: Text('No matching exercises.'))
                      : ListView.builder(
                          itemCount: _filteredExercises.length,
                          itemBuilder: (context, index) {
                            final exercise = _filteredExercises[index];
                            return Card(
                              margin: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              child: ListTile(
                                title: Text(exercise['name'] ?? ''),
                                trailing: const Icon(
                                  Icons.arrow_forward_ios,
                                  size: 16,
                                ),
                                onTap: () async {
                                  await Navigator.of(context).pushNamed(
                                    '/history/exercise',
                                    arguments: exercise,
                                  );
                                  if (mounted) _loadExercises();
                                },
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }
}
