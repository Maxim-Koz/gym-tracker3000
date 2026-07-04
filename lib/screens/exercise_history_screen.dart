import 'package:flutter/material.dart';
import 'package:gym_tracker/services/db_helper.dart';

class ExerciseHistoryScreen extends StatefulWidget {
  const ExerciseHistoryScreen({super.key});

  @override
  State<ExerciseHistoryScreen> createState() => _ExerciseHistoryScreenState();
}

class _ExerciseHistoryScreenState extends State<ExerciseHistoryScreen> {
  List<Map<String, dynamic>> _sessions = [];
  Map<String, dynamic>? _exercise;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is Map<String, dynamic>) {
      _exercise = args;
      _loadSessions();
    }
  }

  Future<void> _loadSessions() async {
    if (_exercise == null) return;
    final sessions = await DBHelper().getSessionsForExercise(
      _exercise!['id'] as int,
    );
    final enriched = <Map<String, dynamic>>[];
    for (final session in sessions) {
      final sets = await DBHelper().getSetsForSession(session['id'] as int);
      enriched.add({'session': session, 'sets': sets});
    }
    setState(() => _sessions = enriched);
  }

  @override
  Widget build(BuildContext context) {
    final exercise = _exercise;
    return Scaffold(
      appBar: AppBar(title: Text(exercise?['name'] ?? 'Exercise History')),
      body: exercise == null
          ? const Center(child: Text('No exercise selected.'))
          : _sessions.isEmpty
          ? const Center(child: Text('No sessions recorded for this exercise.'))
          : ListView.builder(
              reverse: true,
              itemCount: _sessions.length,
              itemBuilder: (context, index) {
                final sessionBundle = _sessions[index];
                final session =
                    sessionBundle['session'] as Map<String, dynamic>;
                final sets =
                    sessionBundle['sets'] as List<Map<String, dynamic>>;
                final date = session['timestamp'] as DateTime;
                return Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _formatDate(date),
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${sets.length} set${sets.length == 1 ? '' : 's'}',
                          ),
                          const Divider(),
                          if (sets.isEmpty)
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 8.0),
                              child: Text('No sets recorded for this session.'),
                            )
                          else
                            ...sets.map((setRow) {
                              final weight = setRow['weight'];
                              final reps = setRow['reps'];
                              final unit = setRow['unit'];
                              String weightText;
                              if (weight == null) {
                                weightText = '-';
                              } else if (weight is double) {
                                weightText = weight.toStringAsFixed(1);
                              } else {
                                weightText = weight.toString();
                              }
                              final repsText = reps == null
                                  ? '-'
                                  : reps.toString();
                              return Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 4.0,
                                ),
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      '$weightText ${unit ?? ''}',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    Text('$repsText reps'),
                                  ],
                                ),
                              );
                            }),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }

  String _formatDate(DateTime date) {
    final local = date.toLocal();
    return '${local.day.toString().padLeft(2, '0')}/${local.month.toString().padLeft(2, '0')}/${local.year}';
  }
}
