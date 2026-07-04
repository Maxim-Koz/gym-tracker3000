import 'package:flutter/material.dart';
import 'package:gym_tracker/services/db_helper.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  List<Map<String, dynamic>> _exercises = [];

  @override
  void initState() {
    super.initState();
    _loadExercises();
  }

  Future<void> _loadExercises() async {
    final exercises = await DBHelper().getExercises();
    setState(() => _exercises = exercises);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Exercise History')),
      body: _exercises.isEmpty
          ? const Center(
              child: Text('No history yet. Add exercises and record sessions.'),
            )
          : ListView.builder(
              itemCount: _exercises.length,
              itemBuilder: (context, index) {
                final exercise = _exercises[index];
                return Card(
                  margin: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  child: ListTile(
                    title: Text(exercise['name'] ?? ''),
                    subtitle: Text(exercise['type'] ?? ''),
                    trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                    onTap: () => Navigator.of(
                      context,
                    ).pushNamed('/history/exercise', arguments: exercise),
                  ),
                );
              },
            ),
    );
  }
}
