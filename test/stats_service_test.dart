import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/services/stats_service.dart';

void main() {
  test('calculates logged-day coverage and heaviest weights', () {
    final now = DateTime(2024, 6, 15);
    final exercises = [
      {'id': 1, 'name': 'Bench Press'},
      {'id': 2, 'name': 'Squat'},
    ];
    final sessions = [
      {'id': 1, 'exercise_id': 1, 'timestamp': DateTime(2024, 1, 10)},
      {'id': 2, 'exercise_id': 1, 'timestamp': DateTime(2024, 2, 12)},
      {'id': 3, 'exercise_id': 2, 'timestamp': DateTime(2024, 2, 12)},
    ];
    final sets = [
      {'session_id': 1, 'weight': 100.0, 'reps': 8, 'unit': 'kg'},
      {'session_id': 2, 'weight': 110.0, 'reps': 6, 'unit': 'kg'},
      {'session_id': 3, 'weight': 80.0, 'reps': 10, 'unit': 'kg'},
      {'session_id': 3, 'weight': 85.0, 'reps': 8, 'unit': 'kg'},
    ];

    final stats = calculateWorkoutStats(
      exercises: exercises,
      sessions: sessions,
      sets: sets,
      now: now,
    );

    expect(stats.loggedDays, 2);
    expect(stats.yearPercentage, closeTo((2 / 366) * 100, 0.001));
    expect(stats.logEntries, hasLength(4));
    expect(stats.logEntries.first.exerciseName, 'Bench Press');
    expect(stats.logEntries.first.weight, 110.0);
    expect(stats.logEntries.first.unit, 'kg');
    expect(stats.logEntries.first.reps, 6);
    expect(stats.logEntries.last.exerciseName, 'Bench Press');
  });
}
