import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/screens/year_history_screen.dart';
import 'package:gym_tracker/widgets/workout_calendar.dart';

void main() {
  testWidgets('calendar shows month title and day cells', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WorkoutCalendar(
            month: DateTime(2024, 5),
            loggedDates: {DateTime(2024, 5, 10)},
          ),
        ),
      ),
    );

    expect(find.text('May 2024'), findsOneWidget);
    expect(find.text('10'), findsWidgets);
  });

  testWidgets('year history screen renders the contribution grid', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: YearHistoryScreen()));
    await tester.pumpAndSettle();

    expect(find.byType(DropdownButton<int>), findsOneWidget);
    expect(find.text('Each block represents a logged day.'), findsOneWidget);
  });

  testWidgets('year history screen spans the full selected year', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: YearHistoryScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Dec'), findsOneWidget);
  });
}
