import 'package:flutter/material.dart';
import 'package:gym_tracker/services/db_helper.dart';
import 'package:gym_tracker/services/stats_service.dart';

class WorkoutStatsScreen extends StatefulWidget {
  const WorkoutStatsScreen({super.key});

  @override
  State<WorkoutStatsScreen> createState() => _WorkoutStatsScreenState();
}

class _WorkoutStatsScreenState extends State<WorkoutStatsScreen> {
  bool _isLoading = true;
  int _loggedDays = 0;
  double _yearPercentage = 0.0;
  List<WorkoutLogEntry> _logEntries = const <WorkoutLogEntry>[];

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    final exercises = await DBHelper().getExercises();
    final sessions = await DBHelper().getAllSessions();
    final sets = await DBHelper().getAllSets();

    if (!mounted) return;

    final stats = calculateWorkoutStats(
      exercises: exercises,
      sessions: sessions,
      sets: sets,
      now: DateTime.now(),
    );

    setState(() {
      _loggedDays = stats.loggedDays;
      _yearPercentage = stats.yearPercentage;
      _logEntries = stats.logEntries;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Workout stats')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Overview',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 12),
                          _buildStatRow(
                            label: 'Days logged',
                            value: '$_loggedDays',
                          ),
                          const SizedBox(height: 8),
                          _buildStatRow(
                            label: 'Year coverage',
                            value: '${_yearPercentage.toStringAsFixed(1)}%',
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'Full workout log',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  if (_logEntries.isEmpty)
                    const Text('No workout entries yet.')
                  else
                    ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _logEntries.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final entry = _logEntries[index];
                        return ListTile(
                          title: Text(entry.exerciseName),
                          subtitle: Text(
                            '${_formatDate(entry.date)} • ${entry.reps} reps',
                          ),
                          trailing: Text(
                            '${_formatWeight(entry.weight)} ${entry.unit}'.trim(),
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        );
                      },
                    ),
                ],
              ),
            ),
    );
  }

  Widget _buildStatRow({required String label, required String value}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(fontSize: 16)),
        Text(
          value,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }

  String _formatWeight(double weight) {
    if (weight == weight.toInt()) {
      return weight.toInt().toString();
    }
    return weight.toStringAsFixed(1);
  }

  String _formatDate(DateTime date) {
    final local = date.toLocal();
    return '${local.day.toString().padLeft(2, '0')}/${local.month.toString().padLeft(2, '0')}/${local.year}';
  }
}
