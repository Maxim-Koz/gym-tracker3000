class WorkoutStats {
  const WorkoutStats({
    required this.loggedDays,
    required this.yearPercentage,
    required this.logEntries,
  });

  final int loggedDays;
  final double yearPercentage;
  final List<WorkoutLogEntry> logEntries;
}

class WorkoutLogEntry {
  const WorkoutLogEntry({
    required this.exerciseName,
    required this.date,
    required this.weight,
    required this.unit,
    required this.reps,
  });

  final String exerciseName;
  final DateTime date;
  final double weight;
  final String unit;
  final int reps;
}

WorkoutStats calculateWorkoutStats({
  required List<Map<String, dynamic>> exercises,
  required List<Map<String, dynamic>> sessions,
  required List<Map<String, dynamic>> sets,
  required DateTime now,
}) {
  final uniqueLoggedDays = sessions
      .map((session) => session['timestamp'] as DateTime)
      .map(
        (timestamp) => DateTime(timestamp.year, timestamp.month, timestamp.day),
      )
      .toSet()
      .length;

  final totalDaysInYear = _daysInYear(now.year);

  final percentage = totalDaysInYear == 0
      ? 0.0
      : (uniqueLoggedDays / totalDaysInYear) * 100;

  final exerciseById = {
    for (final exercise in exercises) (exercise['id'] as int): exercise['name'] as String,
  };

  final logEntries = <WorkoutLogEntry>[];

  for (final session in sessions) {
    final sessionId = session['id'] as int;
    final sessionDate = session['timestamp'] as DateTime;
    final matchingSets = sets.where(
      (setEntry) => (setEntry['session_id'] as int) == sessionId,
    );

    for (final setEntry in matchingSets) {
      final weight = setEntry['weight'];
      final reps = setEntry['reps'];
      if (weight is! num || reps is! num) {
        continue;
      }

      final exerciseName = exerciseById[(session['exercise_id'] as int)] ?? 'Unknown exercise';
      logEntries.add(
        WorkoutLogEntry(
          exerciseName: exerciseName,
          date: sessionDate,
          weight: weight.toDouble(),
          unit: (setEntry['unit'] as String?) ?? '',
          reps: reps.toInt(),
        ),
      );
    }
  }

  logEntries.sort((a, b) => b.date.compareTo(a.date));

  return WorkoutStats(
    loggedDays: uniqueLoggedDays,
    yearPercentage: percentage,
    logEntries: logEntries,
  );
}

int _daysInYear(int year) {
  final start = DateTime(year, 1, 1);
  final end = DateTime(year + 1, 1, 1);
  return end.difference(start).inDays;
}
