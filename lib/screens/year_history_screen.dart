import 'package:flutter/material.dart';
import 'package:gym_tracker/services/db_helper.dart';

class YearHistoryScreen extends StatefulWidget {
  const YearHistoryScreen({super.key});

  @override
  State<YearHistoryScreen> createState() => _YearHistoryScreenState();
}

class _YearHistoryScreenState extends State<YearHistoryScreen> {
  int _selectedYear = DateTime.now().year;
  Set<DateTime> _loggedDates = <DateTime>{};
  bool _isLoading = true;
  List<int> _availableYears = <int>[];

  @override
  void initState() {
    super.initState();
    _loadDates();
  }

  Future<void> _loadDates() async {
    try {
      final dates = await DBHelper().getLoggedDates();
      final years = dates.map((date) => date.year).toSet().toList()..sort();
      if (years.isEmpty) {
        years.add(DateTime.now().year);
      }

      final resolvedYear = years.contains(_selectedYear)
          ? _selectedYear
          : years.last;

      if (!mounted) return;
      setState(() {
        _loggedDates = dates.toSet();
        _availableYears = years;
        _selectedYear = resolvedYear;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loggedDates = <DateTime>{};
        _availableYears = <int>[DateTime.now().year];
        _selectedYear = DateTime.now().year;
        _isLoading = false;
      });
    }
  }

  static const double _weekdayLabelHeight = 14.0;
  static const double _monthLabelWidth = 26.0;
  static const double _blockGap = 16.0;
  static const double _gapAfterLabels = 6.0;
  static const double _rowBottomPadding = 2.0;

  @override
  Widget build(BuildContext context) {
    final firstHalfStart = DateTime(_selectedYear, 1, 1);
    final firstHalfEnd = DateTime(_selectedYear, 6, 30);
    final secondHalfStart = DateTime(_selectedYear, 7, 1);
    final secondHalfEnd = DateTime(_selectedYear, 12, 31);

    final firstHalfWeeks = _weeksInRange(firstHalfStart, firstHalfEnd);
    final secondHalfWeeks = _weeksInRange(secondHalfStart, secondHalfEnd);
    final maxWeeks = firstHalfWeeks > secondHalfWeeks
        ? firstHalfWeeks
        : secondHalfWeeks;

    return Scaffold(
      appBar: AppBar(title: const Text('Workout History')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DropdownButton<int>(
                    value: _selectedYear,
                    isExpanded: true,
                    items: _availableYears
                        .map(
                          (year) => DropdownMenuItem<int>(
                            value: year,
                            child: Text('$year'),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() => _selectedYear = value);
                    },
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Each block represents a logged day.',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final perBlockWidth =
                            (constraints.maxWidth - _blockGap) / 2;
                        final widthForCells = perBlockWidth - _monthLabelWidth;
                        final cellSizeByWidth = widthForCells / 7;

                        final heightForRows =
                            constraints.maxHeight -
                            _weekdayLabelHeight -
                            _gapAfterLabels -
                            (maxWeeks * _rowBottomPadding);
                        final cellSizeByHeight = heightForRows / maxWeeks;

                        final cellSize = cellSizeByWidth < cellSizeByHeight
                            ? cellSizeByWidth
                            : cellSizeByHeight;

                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: _buildHalfYearBlock(
                                firstHalfStart,
                                firstHalfEnd,
                                firstHalfWeeks,
                                cellSize,
                              ),
                            ),
                            const SizedBox(width: _blockGap),
                            Expanded(
                              child: _buildHalfYearBlock(
                                secondHalfStart,
                                secondHalfEnd,
                                secondHalfWeeks,
                                cellSize,
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildHalfYearBlock(
    DateTime firstDay,
    DateTime lastDay,
    int totalWeeks,
    double cellSize,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildWeekdayLabels(),
        const SizedBox(height: _gapAfterLabels),
        _buildContributionGrid(firstDay, lastDay, totalWeeks, cellSize),
      ],
    );
  }

  Widget _buildWeekdayLabels() {
    const weekdayLabels = ['Mon', 'Wed', 'Fri'];
    return SizedBox(
      height: _weekdayLabelHeight,
      child: Row(
        children: [
          const SizedBox(width: _monthLabelWidth),
          ...List.generate(7, (dayIndex) {
            final label = dayIndex == 0 || dayIndex == 2 || dayIndex == 4
                ? weekdayLabels[(dayIndex / 2).floor()]
                : '';

            return Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  label,
                  style: const TextStyle(fontSize: 10, color: Colors.grey),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  int _weeksInRange(DateTime firstDay, DateTime lastDay) {
    final daysInRange = lastDay.difference(firstDay).inDays + 1;
    final startOffset = firstDay.weekday - 1;
    return ((startOffset + daysInRange) / 7).ceil();
  }

  Widget _buildContributionGrid(
    DateTime firstDay,
    DateTime lastDay,
    int totalWeeks,
    double cellSize,
  ) {
    final startOffset = firstDay.weekday - 1;
    final safeCellSize = cellSize < 2 ? 2.0 : cellSize;
    final margin = safeCellSize < 6 ? 0.5 : 1.2;

    final rows = <Widget>[];
    int? previousMonth;

    for (var weekIndex = 0; weekIndex < totalWeeks; weekIndex++) {
      final weekStart = firstDay.add(
        Duration(days: weekIndex * 7 - startOffset),
      );
      final monthLabel = weekIndex == 0 || weekStart.month != previousMonth
          ? _monthLabel(weekStart.month)
          : '';
      previousMonth = weekStart.month;

      rows.add(
        Padding(
          padding: const EdgeInsets.only(bottom: _rowBottomPadding),
          child: SizedBox(
            height: safeCellSize,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SizedBox(
                  width: _monthLabelWidth,
                  height: safeCellSize,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      monthLabel,
                      style: const TextStyle(fontSize: 9, color: Colors.grey),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                ...List.generate(7, (dayIndex) {
                  final date = weekStart.add(Duration(days: dayIndex));
                  final isInRange =
                      !date.isBefore(firstDay) && !date.isAfter(lastDay);
                  final isLogged =
                      isInRange &&
                      _loggedDates.contains(
                        DateTime(date.year, date.month, date.day),
                      );

                  final cell = SizedBox(
                    width: safeCellSize,
                    height: safeCellSize,
                    child: Container(
                      margin: EdgeInsets.all(margin),
                      decoration: BoxDecoration(
                        color: isLogged
                            ? Theme.of(context).colorScheme.primary
                            : isInRange
                            ? Theme.of(
                                context,
                              ).colorScheme.surfaceContainerHighest
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(
                          safeCellSize < 6 ? 1 : 3,
                        ),
                      ),
                    ),
                  );

                  if (!isInRange) return cell;

                  return Tooltip(
                    message: _formatDate(date),
                    triggerMode: TooltipTriggerMode.longPress,
                    child: cell,
                  );
                }),
              ],
            ),
          ),
        ),
      );
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: rows);
  }

  String _formatDate(DateTime date) {
    return '${_monthLabel(date.month)} ${date.day}, ${date.year}';
  }

  String _monthLabel(int month) {
    const months = <String>[
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return months[month - 1];
  }
}
