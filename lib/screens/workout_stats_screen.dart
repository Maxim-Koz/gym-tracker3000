import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:gym_tracker/services/db_helper.dart';
import 'package:gym_tracker/services/stats_service.dart';

class MaxWeightEntry {
  final int exerciseId;
  final String name;
  final String type;
  final double weight;
  final String unit;
  final int reps;
  final DateTime date;

  const MaxWeightEntry({
    required this.exerciseId,
    required this.name,
    required this.type,
    required this.weight,
    required this.unit,
    required this.reps,
    required this.date,
  });
}

class WorkoutStatsScreen extends StatefulWidget {
  const WorkoutStatsScreen({super.key});

  @override
  State<WorkoutStatsScreen> createState() => _WorkoutStatsScreenState();
}

class _WorkoutStatsScreenState extends State<WorkoutStatsScreen> {
  bool _isLoading = true;
  int _loggedDays = 0;
  double _yearPercentage = 0.0;
  List<MaxWeightEntry> _maxWeights = const <MaxWeightEntry>[];
  DateTime? _memberSince;

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

    final maxWeights = _calculateMaxWeights(
      exercises: exercises,
      sessions: sessions,
      sets: sets,
    );

    final createdAt = Supabase.instance.client.auth.currentUser?.createdAt;
    final memberSince = createdAt != null ? DateTime.tryParse(createdAt) : null;

    setState(() {
      _loggedDays = stats.loggedDays;
      _yearPercentage = stats.yearPercentage;
      _maxWeights = maxWeights;
      _memberSince = memberSince;
      _isLoading = false;
    });
  }

  // Converts a weight to kg so entries recorded in different units can be
  // compared on equal footing (e.g. 200 lb vs 100 kg).
  static const double _kgPerLb = 0.45359237;

  double _toKg(double weight, String unit) {
    switch (unit.toLowerCase()) {
      case 'lb':
        return weight * _kgPerLb;
      case 'kg':
      default:
        return weight;
    }
  }

  // Session timestamps are normally already converted to DateTime by
  // DBHelper, but this defends against a raw int (millisecondsSinceEpoch)
  // or a missing/null value ever reaching here, instead of throwing.
  DateTime _sessionDate(Map<String, dynamic> session) {
    final raw = session['timestamp'];
    if (raw is DateTime) return raw;
    if (raw is int) return DateTime.fromMillisecondsSinceEpoch(raw);
    return DateTime.now();
  }

  // For each exercise, finds the session in which its heaviest weight was
  // logged, and returns that weight along with the reps done and the date
  // it happened on.
  List<MaxWeightEntry> _calculateMaxWeights({
    required List<Map<String, dynamic>> exercises,
    required List<Map<String, dynamic>> sessions,
    required List<Map<String, dynamic>> sets,
  }) {
    final sessionById = {
      for (final session in sessions) session['id'] as int: session,
    };

    final bestByExercise = <int, Map<String, dynamic>>{};
    for (final set in sets) {
      final rawWeight = set['weight'];
      if (rawWeight == null) continue;

      final session = sessionById[set['session_id'] as int];
      if (session == null) continue;
      final exerciseId = session['exercise_id'] as int;

      final weight = (rawWeight as num).toDouble();
      final unit = set['unit'] as String? ?? 'kg';
      final weightInKg = _toKg(weight, unit);

      final current = bestByExercise[exerciseId];
      if (current == null || weightInKg > (current['weightInKg'] as double)) {
        bestByExercise[exerciseId] = {
          'weight': weight,
          'unit': unit,
          'weightInKg': weightInKg,
          'reps': set['reps'] as int? ?? 0,
          'date': _sessionDate(session),
        };
      }
    }

    final exerciseById = {
      for (final exercise in exercises) exercise['id'] as int: exercise,
    };

    final entries = bestByExercise.entries.map((entry) {
      final exercise = exerciseById[entry.key];
      final best = entry.value;
      return MaxWeightEntry(
        exerciseId: entry.key,
        name: exercise?['name'] as String? ?? 'Unknown exercise',
        type: exercise?['type'] as String? ?? '',
        weight: best['weight'] as double,
        unit: best['unit'] as String,
        reps: best['reps'] as int,
        date: best['date'] as DateTime,
      );
    }).toList();

    entries.sort(
      (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    );
    return entries;
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
                          if (_memberSince != null) ...[
                            const SizedBox(height: 8),
                            _buildStatRow(
                              label: 'Member since',
                              value: _formatDate(_memberSince!),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'Max weight',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  if (_maxWeights.isEmpty)
                    const Text('No exercises with recorded weights yet.')
                  else
                    ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _maxWeights.length,
                      itemBuilder: (context, index) {
                        final entry = _maxWeights[index];
                        return Card(
                          margin: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          child: ListTile(
                            title: Text(entry.name),
                            subtitle: Text(
                              '${_formatDate(entry.date)} • ${entry.reps} reps',
                            ),
                            trailing: Text(
                              '${_formatWeight(entry.weight)} ${entry.unit}'
                                  .trim(),
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
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
