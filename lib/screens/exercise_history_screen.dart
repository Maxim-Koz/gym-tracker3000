import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:gym_tracker/services/db_helper.dart';
import 'package:gym_tracker/widgets/weight_progress_chart.dart';

enum _ViewMode { log, graph }

enum _TimeRange { twoWeeks, oneYear, all }

class ExerciseHistoryScreen extends StatefulWidget {
  const ExerciseHistoryScreen({super.key});

  @override
  State<ExerciseHistoryScreen> createState() => _ExerciseHistoryScreenState();
}

class _ExerciseHistoryScreenState extends State<ExerciseHistoryScreen> {
  List<Map<String, dynamic>> _sessions = [];
  Map<String, dynamic>? _exercise;
  _ViewMode _viewMode = _ViewMode.log;
  _TimeRange _timeRange = _TimeRange.oneYear;

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
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                  child: CupertinoSlidingSegmentedControl<_ViewMode>(
                    groupValue: _viewMode,
                    children: const {
                      _ViewMode.log: Padding(
                        padding: EdgeInsets.symmetric(vertical: 6),
                        child: Text('Log'),
                      ),
                      _ViewMode.graph: Padding(
                        padding: EdgeInsets.symmetric(vertical: 6),
                        child: Text('Graph'),
                      ),
                    },
                    onValueChanged: (value) {
                      if (value == null) return;
                      setState(() => _viewMode = value);
                    },
                  ),
                ),
                if (_viewMode == _ViewMode.graph)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                    child: CupertinoSlidingSegmentedControl<_TimeRange>(
                      groupValue: _timeRange,
                      children: const {
                        _TimeRange.twoWeeks: Padding(
                          padding: EdgeInsets.symmetric(vertical: 4),
                          child: Text(
                            '2 weeks',
                            style: TextStyle(fontSize: 13),
                          ),
                        ),
                        _TimeRange.oneYear: Padding(
                          padding: EdgeInsets.symmetric(vertical: 4),
                          child: Text('1 year', style: TextStyle(fontSize: 13)),
                        ),
                        _TimeRange.all: Padding(
                          padding: EdgeInsets.symmetric(vertical: 4),
                          child: Text(
                            'All time',
                            style: TextStyle(fontSize: 13),
                          ),
                        ),
                      },
                      onValueChanged: (value) {
                        if (value == null) return;
                        setState(() => _timeRange = value);
                      },
                    ),
                  ),
                Expanded(
                  child: _viewMode == _ViewMode.graph
                      ? _buildGraphView()
                      : _buildLogView(),
                ),
              ],
            ),
    );
  }

  Widget _buildLogView() {
    if (_sessions.isEmpty) {
      return const Center(
        child: Text('No sessions recorded for this exercise.'),
      );
    }
    return ListView.builder(
      reverse: true,
      itemCount: _sessions.length,
      itemBuilder: (context, index) {
        final sessionBundle = _sessions[index];
        final session = sessionBundle['session'] as Map<String, dynamic>;
        final sets = sessionBundle['sets'] as List<Map<String, dynamic>>;
        final date = session['timestamp'] as DateTime;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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
                  if ((session['note'] as String?)?.isNotEmpty ?? false) ...[
                    const SizedBox(height: 4),
                    Text(
                      session['note'] as String,
                      style: const TextStyle(
                        fontStyle: FontStyle.italic,
                        color: Colors.grey,
                      ),
                    ),
                  ],
                  const SizedBox(height: 4),
                  Text(
                    '${sets.where((s) => s['parent_set_id'] == null).length} set${sets.where((s) => s['parent_set_id'] == null).length == 1 ? '' : 's'}',
                  ),
                  const Divider(),
                  if (sets.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8.0),
                      child: Text('No sets recorded for this session.'),
                    )
                  else
                    ..._buildSetRows(sets),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildGraphView() {
    final points = _buildWeightPoints();
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 16, 16),
      child: WeightProgressChart(points: points),
    );
  }

  // Converts a weight to kg so sets recorded in different units can be
  // plotted on the same scale (mirrors the approach in WorkoutStatsScreen).
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

  // Builds one point per session: the session's date paired with the
  // heaviest weight (in kg) logged during that session, restricted to the
  // currently selected time range and sorted oldest-to-newest.
  List<WeightPoint> _buildWeightPoints() {
    DateTime? cutoff;
    final now = DateTime.now();
    switch (_timeRange) {
      case _TimeRange.twoWeeks:
        cutoff = now.subtract(const Duration(days: 14));
        break;
      case _TimeRange.oneYear:
        cutoff = now.subtract(const Duration(days: 365));
        break;
      case _TimeRange.all:
        cutoff = null;
        break;
    }

    final points = <WeightPoint>[];
    for (final bundle in _sessions) {
      final session = bundle['session'] as Map<String, dynamic>;
      final sets = bundle['sets'] as List<Map<String, dynamic>>;
      final date = session['timestamp'] as DateTime;
      if (cutoff != null && date.isBefore(cutoff)) continue;

      double? bestKg;
      for (final set in sets) {
        final rawWeight = set['weight'];
        if (rawWeight == null) continue;
        final weight = (rawWeight as num).toDouble();
        final unit = set['unit'] as String? ?? 'kg';
        final kg = _toKg(weight, unit);
        if (bestKg == null || kg > bestKg) bestKg = kg;
      }
      if (bestKg != null) {
        points.add(WeightPoint(date: date, weightKg: bestKg));
      }
    }

    points.sort((a, b) => a.date.compareTo(b.date));
    return points;
  }

  String _formatDate(DateTime date) {
    final local = date.toLocal();
    return '${local.day.toString().padLeft(2, '0')}/${local.month.toString().padLeft(2, '0')}/${local.year}';
  }

  // Builds the widgets for a session's sets. If any set carries a
  // group_index (i.e. it was recorded as part of a drop set), the sets are
  // clustered under a "Drop set group N" header instead of shown flat.
  List<Widget> _buildSetRows(List<Map<String, dynamic>> sets) {
    final childrenByParent = <int, List<Map<String, dynamic>>>{};
    final parentRows = <Map<String, dynamic>>[];

    for (final setRow in sets) {
      final parentId = setRow['parent_set_id'] as int?;
      if (parentId != null) {
        childrenByParent.putIfAbsent(parentId, () => []).add(setRow);
      } else {
        parentRows.add(setRow);
      }
    }

    final hasGroups = parentRows.any((s) => s['group_index'] != null);

    Widget buildRowWithChildren(Map<String, dynamic> row) {
      final id = row['id'] as int?;
      final children = id == null
          ? <Map<String, dynamic>>[]
          : childrenByParent[id] ?? [];
      return _buildSingleSetRow(row, children: children);
    }

    if (!hasGroups) {
      return parentRows.map((setRow) => buildRowWithChildren(setRow)).toList();
    }

    final grouped = <int, List<Map<String, dynamic>>>{};
    for (final setRow in parentRows) {
      final groupIndex = setRow['group_index'] as int? ?? 0;
      grouped.putIfAbsent(groupIndex, () => []).add(setRow);
    }
    final sortedKeys = grouped.keys.toList()..sort();

    final widgets = <Widget>[];
    for (final key in sortedKeys) {
      widgets.add(
        Padding(
          padding: const EdgeInsets.only(top: 6.0, bottom: 2.0),
          child: Text(
            'Drop set group ${key + 1}',
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
          ),
        ),
      );
      widgets.addAll(
        grouped[key]!.map(
          (setRow) => Padding(
            padding: const EdgeInsets.only(left: 8.0),
            child: buildRowWithChildren(setRow),
          ),
        ),
      );
    }
    return widgets;
  }

  Widget _buildSingleSetRow(
    Map<String, dynamic> setRow, {
    List<Map<String, dynamic>> children = const <Map<String, dynamic>>[],
  }) {
    final weight = setRow['weight'];
    final unit = setRow['unit'];
    String weightText;
    if (weight == null) {
      weightText = '-';
    } else if (weight is double) {
      weightText = weight.toStringAsFixed(1);
    } else {
      weightText = weight.toString();
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            '$weightText ${unit ?? ''}'.trim(),
            style: const TextStyle(fontWeight: FontWeight.w500),
          ),
          Text(_formatRepsDisplay(setRow, children)),
        ],
      ),
    );
  }

  String _formatRepsDisplay(
    Map<String, dynamic> setRow,
    List<Map<String, dynamic>> children,
  ) {
    final values = <String>[];
    final mainReps = setRow['reps'];
    if (mainReps != null) {
      values.add(mainReps.toString());
    }
    for (final child in children) {
      final childReps = child['reps'];
      if (childReps != null) {
        values.add(childReps.toString());
      }
    }
    if (values.isEmpty) {
      return '-';
    }
    final isSingleRep = values.length == 1 && values.first == '1';
    return '${values.join(', ')} ${isSingleRep ? 'rep' : 'reps'}';
  }
}
