import 'package:flutter/material.dart';
import 'package:gym_tracker/services/db_helper.dart';
import 'package:gym_tracker/services/session_note_utils.dart';

class DailyWorkoutHistoryScreen extends StatefulWidget {
  const DailyWorkoutHistoryScreen({super.key});

  @override
  State<DailyWorkoutHistoryScreen> createState() =>
      _DailyWorkoutHistoryScreenState();
}

class _DailyWorkoutHistoryScreenState extends State<DailyWorkoutHistoryScreen> {
  DateTime? _selectedDate;
  bool _isLoading = true;
  List<Map<String, dynamic>> _sessions = const [];
  Map<int, Map<String, dynamic>> _exerciseById = const {};
  Map<int, List<Map<String, dynamic>>> _setsBySessionId = const {};

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final args = ModalRoute.of(context)?.settings.arguments;
    final date = args is Map<String, dynamic>
        ? args['date'] as DateTime?
        : null;
    if (date != null) {
      _selectedDate = DateTime(date.year, date.month, date.day);
      _loadSessionsForDay(_selectedDate!);
    }
  }

  Future<void> _loadSessionsForDay(DateTime day) async {
    setState(() => _isLoading = true);

    try {
      final sessions = await DBHelper().getSessionsForDate(day);
      final exercises = await DBHelper().getExercises();
      final exerciseMap = {
        for (final exercise in exercises) exercise['id'] as int: exercise,
      };

      if (!mounted) return;
      final setsBySessionId = <int, List<Map<String, dynamic>>>{};
      for (final session in sessions) {
        final sessionId = session['id'] as int;
        setsBySessionId[sessionId] = await DBHelper().getSetsForSession(
          sessionId,
        );
      }

      if (!mounted) return;
      setState(() {
        _selectedDate = DateTime(day.year, day.month, day.day);
        _sessions = sessions;
        _exerciseById = exerciseMap;
        _setsBySessionId = setsBySessionId;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _sessions = const [];
        _exerciseById = const {};
        _setsBySessionId = const {};
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final date = _selectedDate ?? DateTime.now();
    return Scaffold(
      appBar: AppBar(title: Text(_formatDay(date))),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _sessions.isEmpty
          ? const Center(child: Text('No workouts logged for this day.'))
          : ListView(
              padding: const EdgeInsets.all(12),
              children: _buildExerciseSections(),
            ),
    );
  }

  List<Widget> _buildExerciseSections() {
    final grouped = <int, List<Map<String, dynamic>>>{};
    for (final session in _sessions) {
      final exerciseId = session['exercise_id'] as int;
      grouped
          .putIfAbsent(exerciseId, () => <Map<String, dynamic>>[])
          .add(session);
    }

    final orderedKeys = grouped.keys.toList();

    return orderedKeys.map((exerciseId) {
      final exercise = _exerciseById[exerciseId];
      final sessionsForExercise = grouped[exerciseId]!;
      final heading = exercise?['name'] ?? 'Exercise #$exerciseId';

      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                heading,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(height: 8),
            ...sessionsForExercise.map((session) => _buildSessionCard(session)),
          ],
        ),
      );
    }).toList();
  }

  Widget _buildSessionCard(Map<String, dynamic> session) {
    final sets =
        _setsBySessionId[session['id'] as int] ??
        const <Map<String, dynamic>>[];
    final note = (session['note'] as String?)?.trim();
    final isOneRepMax = noteHasOneRepMax(note);
    final cleanNote = stripOneRepMaxMarker(note);
    final ignoredInGraph = noteIsIgnoredInGraph(note);
    final setCount = sets.where((s) => s['parent_set_id'] == null).length;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Card(
        color: ignoredInGraph
            ? Theme.of(context).colorScheme.surfaceContainerHighest
            : null,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: isOneRepMax
                ? Theme.of(context).colorScheme.error
                : Theme.of(context).dividerColor,
            width: isOneRepMax ? 2 : 1,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _formatDate(session['timestamp'] as DateTime),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
              ),
              if (cleanNote.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  cleanNote,
                  style: const TextStyle(
                    fontStyle: FontStyle.italic,
                    color: Colors.grey,
                  ),
                ),
              ],
              if (ignoredInGraph) ...[
                const SizedBox(height: 4),
                Text(
                  'Ignored in graph',
                  style: TextStyle(
                    fontSize: 13,
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              const SizedBox(height: 4),
              Text('$setCount set${setCount == 1 ? '' : 's'}'),
              const Divider(),
              if (sets.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8.0),
                  child: Text('No sets recorded for this session.'),
                )
              else
                ..._buildSetRows(sets, isOneRepMax: isOneRepMax),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildSetRows(
    List<Map<String, dynamic>> sets, {
    bool isOneRepMax = false,
  }) {
    final parentRows = sets
        .where((set) => set['parent_set_id'] == null)
        .toList();
    if (parentRows.isEmpty) return const [];

    return parentRows.map((setRow) {
      final weight = setRow['weight'];
      final unit = setRow['unit'];
      final reps = setRow['reps'];
      final weightText = weight == null
          ? '-'
          : (weight is double
                ? weight.toStringAsFixed(
                    weight.truncateToDouble() == weight ? 0 : 1,
                  )
                : weight.toString());
      final unitText = unit == null ? '' : ' $unit';
      final repsText = reps == null
          ? '-'
          : isOneRepMax
          ? '1 rep max'
          : '$reps reps';

      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '$weightText$unitText',
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
            Text(repsText),
          ],
        ),
      );
    }).toList();
  }

  String _formatDay(DateTime date) {
    final local = date.toLocal();
    final weekday = [
      'Mon',
      'Tue',
      'Wed',
      'Thu',
      'Fri',
      'Sat',
      'Sun',
    ][local.weekday - 1];
    return '$weekday, ${local.day}/${local.month}/${local.year}';
  }

  String _formatDate(DateTime date) {
    final local = date.toLocal();
    return '${local.day.toString().padLeft(2, '0')}/${local.month.toString().padLeft(2, '0')}/${local.year}';
  }
}
