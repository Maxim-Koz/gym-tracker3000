import 'package:flutter/material.dart';

class WorkoutCalendar extends StatefulWidget {
  const WorkoutCalendar({
    super.key,
    required this.month,
    required this.loggedDates,
    this.compact = false,
  });

  final DateTime month;
  final Set<DateTime> loggedDates;
  final bool compact;

  @override
  State<WorkoutCalendar> createState() => _WorkoutCalendarState();
}

class _WorkoutCalendarState extends State<WorkoutCalendar> {
  DateTime? _activeDate;
  Offset? _tooltipOffset;
  final GlobalKey _calendarKey = GlobalKey();

  bool _isLogged(DateTime date) {
    final normalized = DateTime(date.year, date.month, date.day);
    return widget.loggedDates.any(
      (loggedDate) =>
          loggedDate.year == normalized.year &&
          loggedDate.month == normalized.month &&
          loggedDate.day == normalized.day,
    );
  }

  String _monthName(int month) {
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    return months[month - 1];
  }

  String _formatDate(DateTime date) {
    const months = [
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
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    final firstDayOfMonth = DateTime(widget.month.year, widget.month.month, 1);
    final leadingDays = firstDayOfMonth.weekday % 7;
    final daysInMonth = DateTime(
      widget.month.year,
      widget.month.month + 1,
      0,
    ).day;
    final totalCells = ((leadingDays + daysInMonth) / 7).ceil() * 7;
    final dayNames = ['S', 'M', 'T', 'W', 'T', 'F', 'S'];
    final cellSize = widget.compact ? 28.0 : 36.0;
    final spacing = widget.compact ? 4.0 : 6.0;

    return LayoutBuilder(
      builder: (context, constraints) {
        return Stack(
          key: _calendarKey,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.08),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '${_monthName(widget.month.month)} ${widget.month.year}',
                          style: TextStyle(
                            fontSize: widget.compact ? 14 : 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (!widget.compact)
                          Text(
                            'Hold to view date',
                            style: TextStyle(
                              fontSize: 11,
                              color: Theme.of(context).hintColor,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: dayNames
                          .map(
                            (day) => Expanded(
                              child: Center(
                                child: Text(
                                  day,
                                  style: TextStyle(
                                    fontSize: widget.compact ? 10 : 11,
                                    color: Theme.of(context).hintColor,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                          )
                          .toList(),
                    ),
                    const SizedBox(height: 6),
                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 7,
                        mainAxisSpacing: spacing,
                        crossAxisSpacing: spacing,
                        childAspectRatio: 1,
                      ),
                      itemCount: totalCells,
                      itemBuilder: (context, index) {
                        final dayNumber = index - leadingDays + 1;
                        final isCurrentMonth =
                            index >= leadingDays && dayNumber <= daysInMonth;

                        if (!isCurrentMonth) {
                          return const SizedBox.shrink();
                        }

                        final date = DateTime(
                          widget.month.year,
                          widget.month.month,
                          dayNumber,
                        );
                        final isLogged = _isLogged(date);
                        final isToday =
                            date.year == DateTime.now().year &&
                            date.month == DateTime.now().month &&
                            date.day == DateTime.now().day;

                        return GestureDetector(
                          onLongPressStart: (details) {
                            final renderBox =
                                _calendarKey.currentContext?.findRenderObject()
                                    as RenderBox?;
                            final localOffset = renderBox == null
                                ? details.globalPosition
                                : renderBox.globalToLocal(
                                    details.globalPosition,
                                  );
                            setState(() {
                              _activeDate = date;
                              _tooltipOffset = localOffset;
                            });
                          },
                          onLongPressEnd: (_) {
                            setState(() {
                              _activeDate = null;
                              _tooltipOffset = null;
                            });
                          },
                          onLongPressCancel: () {
                            setState(() {
                              _activeDate = null;
                              _tooltipOffset = null;
                            });
                          },
                          child: Container(
                            width: cellSize,
                            height: cellSize,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: isLogged
                                  ? Theme.of(context).colorScheme.primary
                                  : Theme.of(
                                      context,
                                    ).colorScheme.surfaceVariant,
                              borderRadius: BorderRadius.circular(12),
                              border: isToday
                                  ? Border.all(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.secondary,
                                      width: 1.6,
                                    )
                                  : null,
                            ),
                            child: Text(
                              '$dayNumber',
                              style: TextStyle(
                                color: isLogged
                                    ? Colors.white
                                    : Theme.of(
                                        context,
                                      ).textTheme.bodyMedium?.color,
                                fontSize: widget.compact ? 10 : 12,
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
            ),
            if (_activeDate != null && _tooltipOffset != null)
              Positioned(
                left: (_tooltipOffset!.dx - 46).clamp(
                  8.0,
                  constraints.maxWidth - 120.0,
                ),
                top: (_tooltipOffset!.dy - 38).clamp(
                  8.0,
                  constraints.maxHeight - 44.0,
                ),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black87,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    _formatDate(_activeDate!),
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
